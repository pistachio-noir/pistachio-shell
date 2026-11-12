//! PAM, through polkit's own helper, as libpolkit-agent's PolkitAgentSession does it (read from
//! polkit 128's polkitagentsession.c and polkitagenthelper-pam.c). No PAM library is linked: the
//! helper runs PAM and tells polkitd itself when the user is who they say.
//!
//! Reaching the helper:
//!   - `/run/polkit/agent-helper.socket` when it exists (polkit 127 and later; systemd starts a
//!     helper per connection): connect, send "<user>\n", then "<cookie>\n";
//!   - else run the setuid `/usr/lib/polkit-1/polkit-agent-helper-1 <user>` and send "<cookie>\n"
//!     on its stdin (so other processes can't see the cookie).
//!
//! The helper then writes lines, escaped as by g_strescape:
//!   PAM_PROMPT_ECHO_OFF <text>   a question whose answer is hidden (the password)
//!   PAM_PROMPT_ECHO_ON <text>    a question whose answer may show
//!   PAM_ERROR_MSG <text>
//!   PAM_TEXT_INFO <text>
//!   SUCCESS                      authorised; it has told polkitd
//!   FAILURE
//! and reads one line, "<answer>\n", after each question. The answer is not escaped.

use std::io::{self, BufRead, BufReader, Read, Write};
use std::net::Shutdown;
use std::os::unix::net::UnixStream;
use std::path::Path;
use std::process::{Child, Command, Stdio};

pub const SOCKET: &str = "/run/polkit/agent-helper.socket";
pub const HELPER: &str = "/usr/lib/polkit-1/polkit-agent-helper-1";

/// What the helper says before it's done.
#[derive(Debug, PartialEq, Eq)]
pub enum Event {
    Prompt { text: String, echo: bool },
    Error(String),
    Info(String),
}

/// One authentication, from the cookie to SUCCESS or FAILURE.
pub struct Session {
    reader: BufReader<Box<dyn Read + Send>>,
    writer: Box<dyn Write + Send>,
    child: Option<Child>,
}

/// Ends a [`Session`] from another thread, wherever it's waiting.
pub enum Canceller {
    Socket(UnixStream),
    Process(u32),
}

impl Canceller {
    pub fn cancel(&self) {
        match self {
            Canceller::Socket(stream) => {
                let _ = stream.shutdown(Shutdown::Both);
            }
            // SAFETY: kill takes a pid and a signal; the pid is our own child's, not yet reaped
            // (Session::run reaps it only after its output has ended)
            Canceller::Process(pid) => unsafe {
                libc::kill(*pid as libc::pid_t, libc::SIGTERM);
            },
        }
    }
}

impl Session {
    /// Starts authenticating `user` for polkit's `cookie`: over `socket` if it's there, else by
    /// running `helper`.
    pub fn start(user: &str, cookie: &str, socket: &Path, helper: &Path) -> io::Result<(Session, Canceller)> {
        if user.contains('\n') || cookie.contains('\n') {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "a line break in the user name or cookie"));
        }
        if socket.exists() {
            match UnixStream::connect(socket) {
                Ok(mut stream) => {
                    stream.write_all(format!("{user}\n{cookie}\n").as_bytes())?;
                    let canceller = Canceller::Socket(stream.try_clone()?);
                    let reader: Box<dyn Read + Send> = Box::new(stream.try_clone()?);
                    return Ok((Session { reader: BufReader::new(reader), writer: Box::new(stream), child: None }, canceller));
                }
                Err(e) => pistachio_lines::log(&format!("could not reach polkit's helper socket, running the helper instead: {e}")),
            }
        }
        let mut child = Command::new(helper).arg(user).stdin(Stdio::piped()).stdout(Stdio::piped()).spawn()?;
        let mut stdin = child.stdin.take().expect("piped");
        let stdout = child.stdout.take().expect("piped");
        stdin.write_all(format!("{cookie}\n").as_bytes())?;
        let canceller = Canceller::Process(child.id());
        let reader: Box<dyn Read + Send> = Box::new(stdout);
        Ok((Session { reader: BufReader::new(reader), writer: Box::new(stdin), child: Some(child) }, canceller))
    }

    /// Runs to the end. `on` hears each event; for a prompt it returns the answer, or `None` to
    /// give up (what it returns for the other events is ignored). True when polkit was told yes.
    pub fn run(mut self, mut on: impl FnMut(Event) -> Option<String>) -> bool {
        let gained = self.converse(&mut on);
        drop(self.writer);
        if let Some(mut child) = self.child.take() {
            if !gained {
                let _ = child.kill();
            }
            let _ = child.wait();
        }
        gained
    }

    fn converse(&mut self, on: &mut impl FnMut(Event) -> Option<String>) -> bool {
        let mut line = Vec::new();
        loop {
            line.clear();
            match self.reader.read_until(b'\n', &mut line) {
                Ok(0) | Err(_) => return false, // the helper went away
                Ok(_) => {}
            }
            let text = unescape(String::from_utf8_lossy(&line).trim_end_matches('\n'));
            let prompt = |rest: &str, echo| Event::Prompt { text: rest.to_string(), echo };
            let question = if let Some(rest) = text.strip_prefix("PAM_PROMPT_ECHO_OFF ") {
                prompt(rest, false)
            } else if let Some(rest) = text.strip_prefix("PAM_PROMPT_ECHO_ON ") {
                prompt(rest, true)
            } else if let Some(rest) = text.strip_prefix("PAM_ERROR_MSG ") {
                on(Event::Error(rest.to_string()));
                continue;
            } else if let Some(rest) = text.strip_prefix("PAM_TEXT_INFO ") {
                on(Event::Info(rest.to_string()));
                continue;
            } else if text.starts_with("SUCCESS") {
                return true;
            } else if text.starts_with("FAILURE") {
                return false;
            } else {
                pistachio_lines::log("polkit's helper said something unknown");
                continue;
            };
            let Some(mut answer) = on(question) else { return false };
            if !answer.ends_with('\n') {
                answer.push('\n');
            }
            let sent = self.writer.write_all(answer.as_bytes()).and_then(|()| self.writer.flush());
            // the password doesn't stay in memory longer than it must
            // SAFETY: zeroes are valid UTF-8, and the string is dropped right after
            unsafe { answer.as_bytes_mut() }.fill(0);
            if sent.is_err() {
                return false;
            }
        }
    }
}

/// Undoes g_strescape, as g_strcompress does: \b \f \n \r \t \v, up to three octal digits, and any
/// other escaped character as itself.
pub fn unescape(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] != b'\\' || i + 1 == bytes.len() {
            out.push(bytes[i]);
            i += 1;
            continue;
        }
        i += 1;
        match bytes[i] {
            b'b' => out.push(8),
            b'f' => out.push(12),
            b'n' => out.push(b'\n'),
            b'r' => out.push(b'\r'),
            b't' => out.push(b'\t'),
            b'v' => out.push(11),
            b'0'..=b'7' => {
                let mut value = 0u32;
                let mut digits = 0;
                while digits < 3 && i < bytes.len() && (b'0'..=b'7').contains(&bytes[i]) {
                    value = value * 8 + u32::from(bytes[i] - b'0');
                    i += 1;
                    digits += 1;
                }
                out.push(value as u8);
                continue;
            }
            other => out.push(other),
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}
