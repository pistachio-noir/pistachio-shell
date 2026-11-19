//! Process and archive primitives shared by the two read-only AI helpers.
use gio::glib;
use serde_json::Value;
use std::fs::{self, DirBuilder, File};
use std::io::{self, BufRead, Read, Write};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::os::unix::{
    ffi::{OsStrExt, OsStringExt},
    fs::DirBuilderExt,
    process::CommandExt,
};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::sync::{mpsc, Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant, SystemTime};

pub const TIMEOUT: Duration = Duration::from_secs(180);

#[derive(Debug)]
pub struct AgentError {
    pub message: String,
    pub unavailable: bool,
}

impl std::fmt::Display for AgentError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.message.fmt(f)
    }
}

impl From<io::Error> for AgentError {
    fn from(error: io::Error) -> Self {
        Self::new(error.to_string(), false)
    }
}

impl AgentError {
    pub fn new(message: impl Into<String>, unavailable: bool) -> Self {
        Self {
            message: message.into(),
            unavailable,
        }
    }

    pub fn from_response(problem: String, stderr: &str, empty: &str) -> Self {
        let message = if !problem.is_empty() {
            problem
        } else if !stderr.trim().is_empty() {
            let stderr = stderr.trim();
            let from = stderr
                .char_indices()
                .rev()
                .nth(1199)
                .map_or(0, |(index, _)| index);
            stderr[from..].to_owned()
        } else {
            empty.to_owned()
        };
        let unavailable = message.split('\0').any(|part| {
            glib::Regex::match_simple(
                r"rate.?limit|usage.?limit|limit reached|quota|overloaded|unavailable|not.?found|does not exist|not supported|unsupported model|not logged|log.?in|authentication|unauthori[sz]ed|expired|connection|network|timed? ?out|timeout|ECONN|ENOTFOUND|service error|server error|\b(?:401|403|429|50[0234])\b",
                part,
                glib::RegexCompileFlags::CASELESS,
                glib::RegexMatchFlags::empty(),
            )
        });
        Self {
            message,
            unavailable,
        }
    }
}

pub fn emit(event: Value) {
    let mut out = io::stdout().lock();
    let _ = writeln!(out, "{event}");
    let _ = out.flush();
}

pub fn string(value: &Value) -> &str {
    value.as_str().unwrap_or_default()
}

pub fn list(value: &Value) -> &[Value] {
    value.as_array().map(Vec::as_slice).unwrap_or_default()
}

pub fn split_lines(text: &str, keep_ends: bool) -> impl Iterator<Item = &str> {
    let mut text = text;
    std::iter::from_fn(move || {
        if text.is_empty() {
            return None;
        }
        let boundary = text.char_indices().find(|(_, c)| {
            matches!(
                c,
                '\n' | '\r'
                    | '\x0b'
                    | '\x0c'
                    | '\x1c'
                    | '\x1d'
                    | '\x1e'
                    | '\u{85}'
                    | '\u{2028}'
                    | '\u{2029}'
            )
        });
        let (line, rest) = match boundary {
            Some((index, c)) => {
                let end = index
                    + c.len_utf8()
                    + usize::from(c == '\r' && text[index + 1..].starts_with('\n'));
                (&text[..if keep_ends { end } else { index }], &text[end..])
            }
            None => (text, ""),
        };
        text = rest;
        Some(line)
    })
}

pub fn alternate(provider: &str) -> &'static str {
    if provider == "claude" {
        "codex"
    } else {
        "claude"
    }
}

pub fn codex(model: &str, effort: &str, session: Option<&str>, schema: Option<&Path>) -> Command {
    let mut command = Command::new("codex");
    command.args(["-a", "never", "-s", "read-only", "exec"]);
    if let Some(session) = session {
        command.args(["resume", session]);
    }
    command.args([
        "--ignore-user-config",
        "--skip-git-repo-check",
        "--json",
        "--model",
        model,
    ]);
    if let Some(schema) = schema {
        command.arg("--output-schema").arg(schema);
    }
    command.args([
        "-c",
        &format!("model_reasoning_effort=\"{effort}\""),
        "-c",
        "features.shell_tool=false",
        "-c",
        "features.hooks=false",
        "-c",
        "features.plugins=false",
        "-c",
        "features.multi_agent=false",
        "-c",
        "features.memories=false",
        "-c",
        "apps._default.enabled=false",
        "-c",
        "web_search=\"disabled\"",
        "-c",
        "project_doc_max_bytes=0",
    ]);
    command
}

pub struct Output {
    pub status: ExitStatus,
    pub stderr: String,
    pub timed_out: bool,
}

pub fn run(
    mut command: Command,
    cwd: &Path,
    stop: &AtomicBool,
    kill_on_timeout: bool,
    mut line: impl FnMut(&str),
) -> io::Result<Option<Output>> {
    if stop.load(Ordering::Relaxed) {
        return Ok(None);
    }
    command
        .current_dir(cwd)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    // A session of its own lets cancellation reach the CLI and its children.
    unsafe {
        command.pre_exec(|| {
            if libc::setsid() == -1 {
                Err(io::Error::last_os_error())
            } else {
                Ok(())
            }
        });
    }
    let mut child = command.spawn()?;
    let pid = child.id() as libc::pid_t;
    let signal = |signal| unsafe { libc::killpg(pid, signal) };
    let mut pipes = [
        File::from(OwnedFd::from(child.stdout.take().unwrap())),
        File::from(OwnedFd::from(child.stderr.take().unwrap())),
    ];
    let mut fds = pipes.each_ref().map(|pipe| libc::pollfd {
        fd: pipe.as_raw_fd(),
        events: libc::POLLIN,
        revents: 0,
    });
    let deadline = Instant::now() + TIMEOUT;
    let mut timed_out = false;
    let mut terminating = None;
    let mut pending = Vec::new();
    let mut stderr = Vec::new();
    let mut buffer = [0; 8192];
    let result = (|| loop {
        let now = Instant::now();
        if terminating.is_none() && (now >= deadline || stop.load(Ordering::Relaxed)) {
            timed_out = now >= deadline;
            if timed_out && kill_on_timeout {
                signal(libc::SIGKILL);
                terminating = Some(now + Duration::from_millis(100));
            } else {
                signal(libc::SIGTERM);
                terminating = Some(now + Duration::from_secs(2));
            }
        }
        if terminating.is_some_and(|until| now >= until) {
            signal(libc::SIGKILL);
            break child.wait();
        }
        if fds.iter().all(|fd| fd.fd < 0) {
            if let Some(status) = child.try_wait()? {
                break Ok(status);
            }
        }
        // Poll each pipe before a single read. A quiet CLI or a descendant holding a pipe
        // can never hold up cancellation, and stderr cannot fill up while stdout streams.
        if unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, 20) } < 0 {
            let error = io::Error::last_os_error();
            if error.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            break Err(error);
        }
        for (index, fd) in fds.iter_mut().enumerate() {
            if fd.revents == 0 {
                continue;
            }
            let count = match pipes[index].read(&mut buffer) {
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                read => read?,
            };
            if count == 0 {
                fd.fd = -1;
            }
            if index == 1 {
                stderr.extend_from_slice(&buffer[..count]);
                continue;
            }
            for chunk in buffer[..count].split_inclusive(|&byte| byte == b'\n') {
                pending.extend_from_slice(chunk);
                if chunk.ends_with(b"\n") {
                    line(&String::from_utf8_lossy(&pending));
                    pending.clear();
                }
            }
        }
    })();
    if !pending.is_empty() {
        line(&String::from_utf8_lossy(&pending));
    }
    if result.is_err() {
        signal(libc::SIGKILL);
        let _ = child.wait();
    }
    result.map(|status| {
        Some(Output {
            status,
            stderr: String::from_utf8_lossy(&stderr).into_owned(),
            timed_out,
        })
    })
}

pub struct Worker<T> {
    state: Arc<Mutex<T>>,
    job: Option<JoinHandle<()>>,
    busy: Arc<AtomicBool>,
    stop: Arc<AtomicBool>,
}

impl<T> Worker<T> {
    pub fn new(state: T) -> Self {
        Self {
            state: Arc::new(Mutex::new(state)),
            job: None,
            busy: Arc::new(AtomicBool::new(false)),
            stop: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn idle(&mut self) -> bool {
        if self.busy.load(Ordering::Acquire) {
            return false;
        }
        self.wait();
        true
    }

    pub fn state(&self) -> std::sync::MutexGuard<'_, T> {
        self.state.lock().unwrap()
    }

    pub fn start(&mut self, job: impl FnOnce(&mut T, &AtomicBool) -> Option<Value> + Send + 'static)
    where
        T: Send + 'static,
    {
        let (state, busy, stop) = (self.state.clone(), self.busy.clone(), self.stop.clone());
        busy.store(true, Ordering::Relaxed);
        stop.store(false, Ordering::Relaxed);
        self.job = Some(thread::spawn(move || {
            let event = job(&mut state.lock().unwrap(), &stop);
            busy.store(false, Ordering::Release);
            if let Some(event) = event {
                emit(event);
            }
        }));
    }

    pub fn stop(&self) {
        self.stop.store(true, Ordering::Relaxed);
    }

    pub fn wait(&mut self) {
        if let Some(job) = self.job.take() {
            let _ = job.join();
        }
    }
}

impl<T> Drop for Worker<T> {
    fn drop(&mut self) {
        self.stop();
        self.wait();
    }
}

static SIGNAL_WRITE: AtomicI32 = AtomicI32::new(-1);

extern "C" fn signal(_: libc::c_int) {
    let fd = SIGNAL_WRITE.load(Ordering::Relaxed);
    unsafe {
        let errno = libc::__errno_location();
        let previous = *errno;
        libc::write(fd, b"x".as_ptr().cast(), 1);
        *errno = previous;
    }
}

pub fn input() -> io::Result<mpsc::Receiver<String>> {
    let mut fds = [0; 2];
    unsafe {
        if libc::pipe2(fds.as_mut_ptr(), libc::O_CLOEXEC) < 0 {
            return Err(io::Error::last_os_error());
        }
        let write = OwnedFd::from_raw_fd(fds[1]);
        if libc::fcntl(write.as_raw_fd(), libc::F_SETFL, libc::O_NONBLOCK) < 0 {
            drop(OwnedFd::from_raw_fd(fds[0]));
            return Err(io::Error::last_os_error());
        }
        // Kept open for the helper's lifetime. The signal handler does only a nonblocking write.
        SIGNAL_WRITE.store(write.as_raw_fd(), Ordering::Relaxed);
        std::mem::forget(write);
        for sig in [libc::SIGTERM, libc::SIGINT] {
            libc::signal(sig, signal as *const () as libc::sighandler_t);
        }
    }
    let (send, receive) = mpsc::channel();
    let mut read = unsafe { File::from_raw_fd(fds[0]) };
    let got_signal = send.clone();
    thread::spawn(move || {
        let _ = read.read_exact(&mut [0]);
        // Another signal can arrive while the CLI is being reaped. Keep the pipe readable until exit.
        std::mem::forget(read);
        // The empty string is a shutdown sentinel; a blank input line still contains a newline.
        let _ = got_signal.send(String::new());
    });
    thread::spawn(move || {
        let mut stdin = io::stdin().lock();
        loop {
            let mut line = String::new();
            if !matches!(stdin.read_line(&mut line), Ok(count) if count > 0) {
                let _ = send.send(String::new());
                break;
            }
            if send.send(line).is_err() {
                break;
            }
        }
    });
    Ok(receive)
}

pub fn home() -> PathBuf {
    std::env::home_dir().unwrap_or_else(|| PathBuf::from("."))
}

pub fn private_dir(path: &Path, recursive: bool) -> io::Result<()> {
    DirBuilder::new()
        .mode(0o700)
        .recursive(recursive)
        .create(path)
}

pub fn local_stamp(time: SystemTime, format: &str) -> String {
    let secs = match time.duration_since(SystemTime::UNIX_EPOCH) {
        Ok(span) => span.as_secs() as i64,
        Err(error) => {
            -(error.duration().as_secs() as i64) - i64::from(error.duration().subsec_nanos() != 0)
        }
    };
    glib::DateTime::from_unix_local(secs)
        .and_then(|time| time.format(format))
        .map(|stamp| stamp.to_string())
        .unwrap_or_default()
}

pub fn archive(base: &Path, question: &str, fallback: &str) -> io::Result<PathBuf> {
    private_dir(base, true)?;
    let mut slug = String::new();
    let mut separator = false;
    for ch in question
        .chars()
        .filter(|ch| ch.is_alphanumeric() || " _-".contains(*ch))
    {
        if ch == ' ' || ch == '_' {
            separator = true;
            continue;
        }
        if separator {
            slug.push('-');
            separator = false;
        }
        slug.push(ch);
    }
    let slug: String = slug.trim_matches('-').chars().take(60).collect();
    let slug = if slug.is_empty() { fallback } else { &slug };
    let name = format!(
        "{} {slug}",
        local_stamp(SystemTime::now(), "%Y-%m-%d %H-%M-%S")
    );
    for number in 1.. {
        let path = base.join(if number == 1 {
            name.clone()
        } else {
            format!("{name}-{number}")
        });
        match private_dir(&path, false) {
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            result => return result.map(|()| path),
        }
    }
    unreachable!()
}

pub struct TempFile {
    pub file: File,
    path: PathBuf,
}

impl TempFile {
    pub fn new(path: &Path, prefix: &str) -> io::Result<Self> {
        let template = path.with_file_name(format!("{prefix}XXXXXX"));
        let template = std::ffi::CString::new(template.as_os_str().as_bytes())?;
        let mut bytes = template.into_bytes_with_nul();
        let fd = unsafe { libc::mkostemp(bytes.as_mut_ptr().cast(), libc::O_CLOEXEC) };
        if fd < 0 {
            return Err(io::Error::last_os_error());
        }
        bytes.pop();
        Ok(Self {
            path: std::ffi::OsString::from_vec(bytes).into(),
            file: unsafe { File::from_raw_fd(fd) },
        })
    }

    pub fn commit(mut self, path: &Path) -> io::Result<()> {
        fs::rename(&self.path, path)?;
        self.path.clear();
        Ok(())
    }
}

impl Drop for TempFile {
    fn drop(&mut self) {
        if !self.path.as_os_str().is_empty() {
            let _ = fs::remove_file(&self.path);
        }
    }
}

pub fn replace(path: &Path, prefix: &str, content: &str) -> io::Result<()> {
    let mut temporary = TempFile::new(path, prefix)?;
    temporary.file.write_all(content.as_bytes())?;
    temporary.commit(path)
}
