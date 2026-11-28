//! `psc launcher-tools`: read-only file tools and volatile, reload-safe background jobs for the
//! launcher (services/LauncherTools.qml). Python's launcher-tools.py until 19 November 2026; the same
//! JSON lines both ways and the same job folders.
//!
//! In: {"action": "preview"|"cancel-preview"|"handlers"|"open"|"run"|"cancel"|"launch", ...}
//! Out: ready, jobs (when they change, polled every 0.7 s), preview, handlers, opened, launched,
//! launch-failed, error. A job runs as `psc launcher-tools --job FOLDER COMMAND` in its own session
//! and process group, writes state.json and a bounded output, ends on a `cancel` file (TERM, then KILL
//! after 2 s), keeps the 20 newest finished jobs, and notifies when done. A running emerge shows as a
//! job too, view only (emerge.rs, 28 November 2026).
use gio::glib;
use gio::prelude::*;
use serde_json::{json, Value};
use std::io::{BufRead, Read, Seek, SeekFrom, Write};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const LIMIT: usize = 262_144;

#[derive(Default)]
pub struct Previews {
    request: Option<i64>,
    children: Vec<u32>,
    closing: bool,
}

fn now_ms() -> f64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs_f64() * 1000.0).unwrap_or(0.0)
}

fn strftime(fmt: &std::ffi::CStr, secs: i64) -> String {
    let mut buf = [0u8; 128];
    unsafe {
        let t = secs as libc::time_t;
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&t, &mut tm);
        let n = libc::strftime(buf.as_mut_ptr() as *mut libc::c_char, buf.len(), fmt.as_ptr(), &tm);
        String::from_utf8_lossy(&buf[..n]).into_owned()
    }
}

fn random_hex() -> String {
    let mut bytes = [0u8; 16];
    if let Ok(mut f) = std::fs::File::open("/dev/urandom") { let _ = f.read_exact(&mut bytes); }
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn uri(path: &Path) -> String {
    glib::filename_to_uri(path, None).map(|u| u.to_string()).unwrap_or_else(|_| format!("file://{}", path.display()))
}

/// The bytes as text: invalid UTF-8 is no text; an unfinished character at a cut is dropped.
fn decode(data: &[u8], last: bool) -> Option<String> {
    match std::str::from_utf8(data) {
        Ok(t) => Some(t.to_string()),
        Err(e) if !last && e.error_len().is_none() => Some(String::from_utf8_lossy(&data[..e.valid_up_to()]).into_owned()),
        Err(_) => None,
    }
}

pub fn preview(name: &str, cache: &Path, request: Option<i64>, previews: &Mutex<Previews>) -> Result<Value, String> {
    let p = Path::new(name);
    let meta = std::fs::metadata(p).map_err(|e| format!("[Errno {}] {}: '{}'", e.raw_os_error().unwrap_or(0), describe(&e), name))?;
    let file_name = p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    // GLib reads an empty sample as an empty file (application/x-zerosize): give it the file's start
    let mut head = Vec::with_capacity(4096);
    if meta.is_file() { let _ = std::fs::File::open(p).and_then(|f| f.take(4096).read_to_end(&mut head)); }
    let (guess, _) = gio::content_type_guess(Some(&file_name), &head);
    let mime = gio::content_type_get_mime_type(&guess).map(|m| m.to_string()).filter(|m| !m.is_empty()).unwrap_or_else(|| "application/octet-stream".into());
    let modified = meta.modified().ok().and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).map(|d| d.as_secs() as i64).unwrap_or(0);
    let mut result = json!({"path": name, "name": file_name, "size": meta.len(), "modified": strftime(c"%d %B %Y %H:%M", modified), "mime": mime, "kind": "metadata"});
    if !meta.is_file() { return Ok(result); }
    if mime.starts_with("image/") && meta.len() <= 67_108_864 {
        result["kind"] = json!("image");
        result["image"] = json!(uri(p));
        return Ok(result);
    }
    if mime == "application/pdf" {
        let dest = cache.join(format!("pdf-{}", random_hex()));
        let rendered = (|| -> Result<(), ()> {
            let mut child = {
                let mut state = previews.lock().unwrap();
                if state.closing || request.is_some() && request != state.request { return Err(()); }
                let child = Command::new("pdftoppm").args(["-f", "1", "-l", "1", "-singlefile", "-scale-to", "1600", "-png"]).arg(p).arg(&dest)
                    .stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn().map_err(|_| ())?;
                state.children.push(child.id());
                child
            };
            let until = Instant::now() + Duration::from_secs(10);
            let status = loop {
                match child.try_wait() {
                    Ok(Some(s)) => break Some(s),
                    Ok(None) if Instant::now() < until => std::thread::sleep(Duration::from_millis(20)),
                    _ => break None,
                }
            };
            if status.is_none() { let _ = child.kill(); }
            let _ = child.wait();
            previews.lock().unwrap().children.retain(|c| *c != child.id());
            if status.is_some_and(|s| s.success()) { Ok(()) } else { Err(()) }
        })();
        match rendered {
            Ok(()) => { result["kind"] = json!("image"); result["image"] = json!(uri(&dest.with_extension("png"))); }
            Err(()) => {
                let state = previews.lock().unwrap();
                // cancelled (or replaced) requests come back as plain metadata, as before
                if !(state.closing || request.is_some() && request != state.request) {
                    result["note"] = json!("PDF preview needs pdftoppm and a readable PDF.");
                }
            }
        }
        return Ok(result);
    }
    let mut data = Vec::with_capacity(LIMIT + 1);
    std::fs::File::open(p).and_then(|f| f.take(LIMIT as u64 + 1).read_to_end(&mut data)).map_err(|e| describe(&e))?;
    if !data.contains(&0) {
        let last = data.len() <= LIMIT;
        if let Some(text) = decode(&data[..data.len().min(LIMIT)], last) {
            result["kind"] = json!("text");
            result["text"] = json!(text);
            result["truncated"] = json!(!last);
        }
    }
    Ok(result)
}

fn describe(e: &std::io::Error) -> String {
    let t = e.to_string();
    t.split(" (os error").next().unwrap_or(&t).to_string()
}

pub fn read_jobs(base: &Path) -> Vec<Value> {
    let mut rows: Vec<Value> = std::fs::read_dir(base).map(|d| d.flatten().filter_map(|e| {
        let folder = e.path();
        let mut row: Value = serde_json::from_str(&std::fs::read_to_string(folder.join("state.json")).ok()?).ok()?;
        let output = std::fs::read(folder.join("output")).unwrap_or_default();
        row["output"] = json!(String::from_utf8_lossy(&output[output.len().saturating_sub(65536)..]));
        Some(row)
    }).collect()).unwrap_or_default();
    rows.sort_by(|a, b| b["started"].as_f64().unwrap_or(0.0).partial_cmp(&a["started"].as_f64().unwrap_or(0.0)).unwrap_or(std::cmp::Ordering::Equal));
    rows
}

fn atomic(path: &Path, data: &Value) {
    let tmp = path.with_extension("tmp");
    if std::fs::write(&tmp, data.to_string()).is_ok() { let _ = std::fs::rename(&tmp, path); }
}

#[cfg(test)]
thread_local! {
    /// tests: make the job's output reading fail on this thread only (other tests run in parallel)
    pub static FAIL_READ: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

fn killpg(pid: u32, signal: libc::c_int) {
    unsafe { libc::killpg(pid as libc::pid_t, signal) };
}

pub fn run_job(folder: &Path, command: &str) {
    let _ = std::fs::create_dir_all(folder);
    let id = folder.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let mut row = json!({"id": id, "command": command, "started": now_ms(), "state": "running", "code": null});
    atomic(&folder.join("state.json"), &row);
    let outcome = (|| -> Result<(i32, bool), (String, Option<u32>)> {
        let mut log = std::fs::OpenOptions::new().read(true).write(true).create(true).truncate(true).open(folder.join("output")).map_err(|e| (describe(&e), None))?;
        let mut child = Command::new("sh").args(["-c", command]).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()).process_group(0)
            .spawn().map_err(|e| (describe(&e), None))?;
        let pid = child.id();
        // stderr into the same output, as STDOUT redirection did: one reader thread per pipe, joined on a channel
        let (send, receive) = std::sync::mpsc::channel::<Option<Vec<u8>>>();
        for pipe in [child.stdout.take().map(|p| Box::new(p) as Box<dyn Read + Send>), child.stderr.take().map(|p| Box::new(p) as Box<dyn Read + Send>)].into_iter().flatten() {
            let send = send.clone();
            std::thread::spawn(move || {
                let mut pipe = pipe;
                let mut chunk = [0u8; 8192];
                loop {
                    match pipe.read(&mut chunk) {
                        Ok(0) | Err(_) => { let _ = send.send(None); break; }
                        Ok(n) => { if send.send(Some(chunk[..n].to_vec())).is_err() { break; } }
                    }
                }
            });
        }
        drop(send);
        let (mut cancelled, mut killed_at, mut open) = (false, Instant::now(), 2);
        loop {
            if folder.join("cancel").exists() && !cancelled {
                cancelled = true;
                killed_at = Instant::now();
                killpg(pid, libc::SIGTERM);
            }
            if cancelled && killed_at.elapsed() > Duration::from_secs(2) { killpg(pid, libc::SIGKILL); }
            #[cfg(test)]
            if FAIL_READ.with(|f| f.get()) {
                return Err(("fixture output failure".into(), Some(pid)));
            }
            match receive.recv_timeout(Duration::from_millis(100)) {
                Ok(Some(bytes)) => {
                    log.write_all(&bytes).map_err(|e| (describe(&e), Some(pid)))?;
                    let size = log.stream_position().unwrap_or(0);
                    if size > 131_072 {
                        // the UI tail is bounded; cap the file too without touching the running command
                        let mut tail = vec![0u8; 65536];
                        log.seek(SeekFrom::End(-65536)).map_err(|e| (describe(&e), Some(pid)))?;
                        log.read_exact(&mut tail).map_err(|e| (describe(&e), Some(pid)))?;
                        log.set_len(0).map_err(|e| (describe(&e), Some(pid)))?;
                        log.seek(SeekFrom::Start(0)).map_err(|e| (describe(&e), Some(pid)))?;
                        log.write_all(&tail).map_err(|e| (describe(&e), Some(pid)))?;
                    }
                }
                Ok(None) => open -= 1,
                Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => open = 0,
                Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {}
            }
            if open == 0 {
                if let Ok(Some(status)) = child.try_wait() {
                    return Ok((status.code().unwrap_or(-1), cancelled));
                }
                if let Ok(status) = child.wait() { return Ok((status.code().unwrap_or(-1), cancelled)); }
            }
        }
    })();
    match outcome {
        Ok((code, cancelled)) => {
            row["code"] = json!(code);
            row["state"] = json!(if cancelled { "cancelled" } else if code == 0 { "finished" } else { "failed" });
        }
        Err((error, pid)) => {
            if let Some(pid) = pid { killpg(pid, libc::SIGKILL); unsafe { libc::waitpid(pid as i32, std::ptr::null_mut(), 0) }; }
            row["state"] = json!("failed");
            row["error"] = json!(error);
        }
    }
    row["ended"] = json!(now_ms());
    atomic(&folder.join("state.json"), &row);
    if let Some(base) = folder.parent() { trim_jobs(base); }
}

/// Volatile session history: keep the twenty newest finished jobs (emerges too), never remove a running one.
pub fn trim_jobs(base: &Path) {
    let finished: Vec<Value> = read_jobs(base).into_iter().filter(|r| r["state"] != "running").collect();
    for old in finished.iter().skip(20) {
        if let Some(id) = old["id"].as_str() { let _ = std::fs::remove_dir_all(base.join(id)); }
    }
}

/// An app that can open a file: gio's AppInfo, or a stand-in in tests.
pub trait OpenApp {
    fn id(&self) -> String;
    fn launch_file(&self, path: &str) -> bool;
    fn make_default(&self, mime: &str);
}

impl OpenApp for gio::AppInfo {
    fn id(&self) -> String { AppInfoExt::id(self).map(|s| s.to_string()).unwrap_or_default() }
    fn launch_file(&self, path: &str) -> bool { self.launch(&[gio::File::for_path(path)], gio::AppLaunchContext::NONE).is_ok() }
    fn make_default(&self, mime: &str) { let _ = self.set_as_default_for_type(mime); }
}

fn content_type(path: &str) -> Result<String, String> {
    let info = gio::File::for_path(path).query_info("standard::content-type", gio::FileQueryInfoFlags::NONE, gio::Cancellable::NONE).map_err(|e| e.to_string())?;
    Ok(info.content_type().map(|c| c.to_string()).unwrap_or_default())
}

pub fn handlers(path: &str) -> Result<(String, Vec<Value>), String> {
    let mime = content_type(path)?;
    let apps = gio::AppInfo::all_for_type(&mime).into_iter().filter_map(|a| {
        let id = AppInfoExt::id(&a)?.to_string();
        if id.is_empty() { return None; }
        let icon = a.icon().and_then(|i| IconExt::to_string(&i)).map(|s| s.to_string()).unwrap_or_default();
        Some(json!({"id": id, "name": a.display_name().to_string(), "icon": icon}))
    }).collect();
    Ok((mime, apps))
}

/// Opens the file with that app; only an explicit `remember` changes the default for its type.
pub fn open_with<A: OpenApp>(path: &str, appid: &str, remember: bool, mime: &str, apps: &[A]) -> Result<(), String> {
    let app = apps.iter().find(|a| a.id() == appid).ok_or("That application is no longer available for this file.")?;
    if !app.launch_file(path) { return Err("Application could not open this file.".into()); }
    if remember { app.make_default(mime); }
    Ok(())
}

fn job_main(folder: &str, command: &str) -> i32 {
    let folder = Path::new(folder);
    run_job(folder, command);
    let row: Value = std::fs::read_to_string(folder.join("state.json")).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or(Value::Null);
    let output = std::fs::read(folder.join("output")).unwrap_or_default();
    let text = String::from_utf8_lossy(&output[output.len().saturating_sub(65536)..]).into_owned();
    let last = text.lines().rev().find(|l| !l.trim().is_empty()).unwrap_or("No output");
    let last: String = last.chars().rev().take(300).collect::<Vec<_>>().into_iter().rev().collect();
    let state = row["state"].as_str().unwrap_or("");
    let title = format!("{}{}: {}", state.get(..1).unwrap_or("").to_uppercase(), state.get(1..).unwrap_or(""), row["command"].as_str().unwrap_or(""));
    let code = match &row["code"] { Value::Null => "None".to_string(), v => v.to_string() };
    let mut notify = Command::new("notify-send");
    notify.args(["--app-name=Command", "--icon=utilities-terminal", &title, &format!("Exit {code} · {last}\nOpen Background jobs for output.")]).stdout(Stdio::null()).stderr(Stdio::null());
    if let Ok(mut child) = notify.spawn() {
        let until = Instant::now() + Duration::from_secs(3);
        while child.try_wait().ok().flatten().is_none() && Instant::now() < until { std::thread::sleep(Duration::from_millis(20)); }
        let _ = child.kill();
        let _ = child.wait();
    }
    0
}

pub fn main(args: &[String]) -> i32 {
    if let [flag, folder, command] = args { if flag == "--job" { return job_main(folder, command); } }
    // SIGTERM (a live reload): the handler only writes a byte to a pipe; a thread does the clean-up as
    // ordinary code. Not sigwait: a blocked SIGTERM is inherited by every child (job commands, apps).
    let mut pipe = [0; 2];
    unsafe {
        libc::pipe2(pipe.as_mut_ptr(), libc::O_CLOEXEC);
        TERM_PIPE.store(pipe[1], std::sync::atomic::Ordering::SeqCst);
        libc::signal(libc::SIGTERM, term as extern "C" fn(libc::c_int) as libc::sighandler_t);
    }
    let runtime = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    let base = runtime.join(format!("pistachio-jobs-{}", unsafe { libc::getuid() }));
    let _ = std::fs::DirBuilder::new().mode(0o700).create(&base);
    let out = Arc::new(Mutex::new(()));
    let emit = { let out = out.clone(); move |v: Value| { let _g = out.lock().unwrap(); let mut o = std::io::stdout().lock(); let _ = writeln!(o, "{v}"); let _ = o.flush(); } };
    emit(json!({"event": "ready"}));
    { let base = base.clone(); let emit = emit.clone(); std::thread::spawn(move || {
        let mut previous: Option<Vec<Value>> = None;
        let mut tick = 0u32;
        loop {
            // a running emerge (emerge.rs), every third look: a scan of /proc
            if tick % 3 == 0 {
                let at = crate::emerge::Places { jobs: &base, proc: Path::new("/proc"), log: Path::new("/var/log/emerge.log") };
                crate::emerge::watch(&at, &|title, body| {
                    let (title, body) = (title.to_string(), body.to_string());
                    std::thread::spawn(move || {
                        if let Ok(mut child) = Command::new("notify-send").args(["--app-name=Portage", "--icon=system-software-update", &title, &body]).stdout(Stdio::null()).stderr(Stdio::null()).spawn() {
                            let until = Instant::now() + Duration::from_secs(3);
                            while child.try_wait().ok().flatten().is_none() && Instant::now() < until { std::thread::sleep(Duration::from_millis(50)); }
                            let _ = child.kill();
                            let _ = child.wait();
                        }
                    });
                });
            }
            tick = tick.wrapping_add(1);
            let rows = read_jobs(&base);
            if previous.as_ref() != Some(&rows) { emit(json!({"event": "jobs", "jobs": rows})); previous = Some(rows); }
            std::thread::sleep(Duration::from_millis(700));
        }
    }); }
    let cache = std::env::temp_dir().join(format!("pistachio-preview-{}-{}", std::process::id(), random_hex().get(..8).unwrap_or("x")));
    let _ = std::fs::DirBuilder::new().mode(0o700).create(&cache);
    let previews = Arc::new(Mutex::new(Previews::default()));
    { let (previews, cache) = (previews.clone(), cache.clone()); std::thread::spawn(move || {
        let mut byte = 0u8;
        if unsafe { libc::read(pipe[0], &mut byte as *mut u8 as *mut libc::c_void, 1) } == 1 {
            // ends like Python's SystemExit: owned PDF renders die, the preview cache goes
            close(&previews, &cache);
            unsafe { libc::_exit(0) };
        }
    }); }
    // two previews at a time, the rest queued, as the old thread pool: reading stdin never waits
    let (queue, queued) = std::sync::mpsc::channel::<(String, i64)>();
    let queued = Arc::new(Mutex::new(queued));
    for _ in 0..2 {
        let (queued, previews, cache, emit) = (queued.clone(), previews.clone(), cache.clone(), emit.clone());
        std::thread::spawn(move || loop {
            let next = queued.lock().unwrap().recv();
            let Ok((path, request)) = next else { break };
            match preview(&path, &cache, Some(request), &previews) {
                Ok(data) => emit(json!({"event": "preview", "id": request, "data": data})),
                Err(e) => emit(json!({"event": "error", "id": request, "error": e})),
            }
        });
    }
    let me = std::env::current_exe().unwrap_or_else(|_| PathBuf::from("psc"));
    for line in std::io::stdin().lock().lines().map_while(Result::ok) {
        let Ok(m) = serde_json::from_str::<Value>(&line) else { emit(json!({"event": "error", "id": 0, "error": "Expecting value"})); continue };
        let action = m["action"].as_str().unwrap_or("");
        let ident = m.get("id").cloned().unwrap_or(json!(0));
        let fail = |e: String| emit(json!({"event": "error", "id": ident, "error": e}));
        match action {
            "preview" | "cancel-preview" => {
                {
                    let mut state = previews.lock().unwrap();
                    state.request = if action == "preview" { Some(ident.as_i64().unwrap_or(0)) } else { None };
                    for child in &state.children { unsafe { libc::kill(*child as i32, libc::SIGKILL) }; }
                }
                if action == "preview" {
                    let Some(path) = m["path"].as_str().map(str::to_string) else { fail("'path'".into()); continue };
                    let _ = queue.send((path, ident.as_i64().unwrap_or(0)));
                }
            }
            "handlers" => match m["path"].as_str().ok_or("'path'".to_string()).and_then(handlers) {
                Ok((mime, apps)) => emit(json!({"event": "handlers", "id": ident, "mime": mime, "apps": apps})),
                Err(e) => fail(e),
            },
            "open" => {
                let (Some(path), Some(app)) = (m["path"].as_str(), m["app"].as_str()) else { fail("'path'".into()); continue };
                match content_type(path).and_then(|mime| open_with(path, app, m["remember"] == true, &mime, &gio::AppInfo::all_for_type(&mime))) {
                    Ok(()) => emit(json!({"event": "opened", "id": ident})),
                    Err(e) => fail(e),
                }
            }
            "run" => {
                let Some(command) = m["command"].as_str() else { fail("'command'".into()); continue };
                let folder = base.join(random_hex());
                match Command::new(&me).arg("launcher-tools").arg("--job").arg(&folder).arg(command)
                    .stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).process_group(0).spawn() {
                    // reaped when it ends, so finished runners don't stay as zombies all session
                    Ok(mut runner) => { std::thread::spawn(move || { let _ = runner.wait(); }); }
                    Err(e) => fail(describe(&e)),
                }
            }
            "cancel" => {
                let job = m["job"].as_str().unwrap_or("");
                if job.len() == 32 && job.chars().all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()) { let _ = std::fs::File::create(base.join(job).join("cancel")); }
            }
            "launch" => {
                let argv: Vec<String> = m["argv"].as_array().map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_string)).collect()).unwrap_or_default();
                let (app, request) = (m["app"].clone(), m["request"].clone());
                let Some((program, rest)) = argv.split_first() else { fail("'argv'".into()); continue };
                let mut command = Command::new(program);
                command.args(rest).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).process_group(0);
                if let Some(cwd) = m["cwd"].as_str().filter(|c| !c.is_empty()) { command.current_dir(cwd); }
                match command.spawn() {
                    Ok(mut child) => {
                        emit(json!({"event": "launched", "app": app}));
                        let emit = emit.clone();
                        std::thread::spawn(move || {
                            if let Ok(status) = child.wait() {
                                if !status.success() {
                                    let code = status.code().unwrap_or(-1);
                                    emit(json!({"event": "launch-failed", "app": app, "request": request, "error": format!("Application exited with status {code}")}));
                                }
                            }
                        });
                    }
                    Err(e) => emit(json!({"event": "launch-failed", "app": app, "request": request, "error": describe(&e)})),
                }
            }
            _ => {}
        }
    }
    close(&previews, &cache);
    0
}

static TERM_PIPE: std::sync::atomic::AtomicI32 = std::sync::atomic::AtomicI32::new(-1);

extern "C" fn term(_: libc::c_int) {
    let fd = TERM_PIPE.load(std::sync::atomic::Ordering::SeqCst);
    unsafe { libc::write(fd, b"x".as_ptr() as *const libc::c_void, 1) };
}

fn close(previews: &Mutex<Previews>, cache: &Path) {
    if let Ok(mut state) = previews.lock() {
        state.closing = true;
        for child in &state.children { unsafe { libc::kill(*child as i32, libc::SIGKILL) }; }
    }
    let _ = std::fs::remove_dir_all(cache);
}

use std::os::unix::fs::DirBuilderExt;

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;

    fn dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("psc-tools-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn preview_is_bounded_and_binary_safe() {
        let d = dir("bounded");
        let previews = Mutex::new(Previews::default());
        let p = d.join("żółć $() file.txt");
        std::fs::write(&p, "hello\n".repeat(60000)).unwrap();
        let r = preview(p.to_str().unwrap(), &d, None, &previews).unwrap();
        assert!(r["kind"] == "text" && r["truncated"] == true && r["text"].as_str().unwrap().len() <= 262144);
        std::fs::write(&p, b"\x00binary").unwrap();
        assert_eq!(preview(p.to_str().unwrap(), &d, None, &previews).unwrap()["kind"], "metadata");
        assert!(preview(d.join("missing").to_str().unwrap(), &d, None, &previews).is_err(), "a missing file is reported");
        let _ = std::fs::remove_dir_all(d);
    }

    #[test]
    fn utf8_preview_truncates_on_a_character_boundary() {
        let d = dir("utf8");
        let p = d.join("unicode.txt");
        std::fs::write(&p, "€".repeat(90000)).unwrap();
        let r = preview(p.to_str().unwrap(), &d, None, &Mutex::new(Previews::default())).unwrap();
        assert!(r["kind"] == "text" && r["truncated"] == true && r["text"].as_str().unwrap().chars().all(|c| c == '€'));
        let _ = std::fs::remove_dir_all(d);
    }

    #[test]
    fn real_pdf_first_page() {
        if !std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default()).any(|p| p.join("pdftoppm").is_file()) { return; } // Poppler is optional
        let d = dir("pdf");
        let stream = b"BT /F1 12 Tf 20 50 Td (Pistachio) Tj ET";
        let objects: Vec<Vec<u8>> = vec![b"<< /Type /Catalog /Pages 2 0 R >>".to_vec(), b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>".to_vec(),
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>".to_vec(),
            [format!("<< /Length {} >>\nstream\n", stream.len()).as_bytes(), stream, b"\nendstream"].concat(),
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>".to_vec()];
        let mut pdf = b"%PDF-1.4\n".to_vec();
        let mut offsets = vec![];
        for (n, obj) in objects.iter().enumerate() {
            offsets.push(pdf.len());
            pdf.extend(format!("{} 0 obj\n", n + 1).as_bytes()); pdf.extend(obj); pdf.extend(b"\nendobj\n");
        }
        let xref = pdf.len();
        pdf.extend(b"xref\n0 6\n0000000000 65535 f \n");
        for o in offsets { pdf.extend(format!("{o:010} 00000 n \n").as_bytes()); }
        pdf.extend(format!("trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF").as_bytes());
        let p = d.join("first page.pdf");
        std::fs::write(&p, pdf).unwrap();
        let r = preview(p.to_str().unwrap(), &d, None, &Mutex::new(Previews::default())).unwrap();
        assert_eq!(r["kind"], "image", "{r}");
        let image = glib::filename_from_uri(r["image"].as_str().unwrap()).unwrap().0;
        assert!(std::fs::read(image).unwrap().starts_with(b"\x89PNG"));
        let _ = std::fs::remove_dir_all(d);
    }

    #[test]
    fn jobs_preserve_output_and_exit_code() {
        let d = dir("jobs");
        run_job(&d.join("one"), "printf 'hello'; exit 7");
        let state = &read_jobs(&d)[0];
        assert!(state["code"] == 7 && state["output"] == "hello" && state["state"] == "failed", "{state}");
        let _ = std::fs::remove_dir_all(d);
    }

    #[test]
    fn cancel_reaps_running_command() {
        let d = dir("cancel");
        let folder = d.join("cancelled");
        let f = folder.clone();
        let worker = std::thread::spawn(move || run_job(&f, "sleep 30"));
        let until = Instant::now() + Duration::from_secs(2);
        while !folder.join("state.json").exists() && Instant::now() < until { std::thread::sleep(Duration::from_millis(10)); }
        std::fs::File::create(folder.join("cancel")).unwrap();
        let began = Instant::now();
        worker.join().unwrap();
        assert!(began.elapsed() < Duration::from_secs(4));
        assert_eq!(read_jobs(&d)[0]["state"], "cancelled");
        let _ = std::fs::remove_dir_all(d);
    }

    #[test]
    fn job_output_error_reaps_child() {
        let d = dir("ioerror");
        FAIL_READ.with(|f| f.set(true));
        let began = Instant::now();
        run_job(&d.join("io-error"), "printf ready; sleep 30");
        FAIL_READ.with(|f| f.set(false));
        assert!(began.elapsed() < Duration::from_secs(5), "the child was killed, not waited for");
        assert_eq!(read_jobs(&d)[0]["state"], "failed");
        let _ = std::fs::remove_dir_all(d);
    }

    #[test]
    fn output_tail_stays_bounded() {
        let d = dir("long");
        run_job(&d.join("long"), "head -c 300000 /dev/zero | tr '\\0' a; echo");
        let row = &read_jobs(&d)[0];
        assert!(row["output"].as_str().unwrap().len() <= 65536);
        assert!(std::fs::metadata(d.join("long/output")).unwrap().len() <= 131072);
        let _ = std::fs::remove_dir_all(d);
    }

    struct Fake { id: &'static str, launched: Cell<u32>, defaulted: Cell<u32>, works: bool }
    impl OpenApp for Fake {
        fn id(&self) -> String { self.id.into() }
        fn launch_file(&self, _: &str) -> bool { self.launched.set(self.launched.get() + 1); self.works }
        fn make_default(&self, _: &str) { self.defaulted.set(self.defaulted.get() + 1); }
    }

    #[test]
    fn open_with_remember_is_explicit() {
        let apps = [Fake { id: "fixture.desktop", launched: Cell::new(0), defaulted: Cell::new(0), works: true }];
        open_with("/tmp/a name.txt", "fixture.desktop", false, "text/plain", &apps).unwrap();
        assert_eq!((apps[0].launched.get(), apps[0].defaulted.get()), (1, 0));
        open_with("/tmp/a name.txt", "fixture.desktop", true, "text/plain", &apps).unwrap();
        assert_eq!(apps[0].defaulted.get(), 1);
        let broken = [Fake { id: "fixture.desktop", launched: Cell::new(0), defaulted: Cell::new(0), works: false }];
        assert!(open_with("/tmp/a name.txt", "fixture.desktop", true, "text/plain", &broken).is_err());
        assert_eq!(broken[0].defaulted.get(), 0, "a failed launch never changes the default");
        assert!(open_with("/tmp/a name.txt", "unknown.desktop", true, "text/plain", &apps).is_err());
    }
}
