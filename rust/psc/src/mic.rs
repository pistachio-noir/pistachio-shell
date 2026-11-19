//! `psc mic-check TARGET`: Settings → Sound's explicit microphone check (services/MicCheck.qml).
//! Python's mic-check.py until 19 November 2026; same JSON lines both ways.
//!
//! Raw audio is kept only in a private temporary folder. No automatic recording or playback.
//! Commands on stdin ({"command": "meter"|"record"|"play"|"stop"}); events on stdout (ready, state,
//! level, error). SIGTERM or EOF closes and reaps the owned audio processes and deletes the sample.
use serde_json::json;
use std::io::{Read, Write};
use std::os::unix::io::AsRawFd;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

const RATE: usize = 16000;
const LIMIT: usize = RATE * 2 * 5; // five seconds of 16-bit mono

static TERM: AtomicBool = AtomicBool::new(false);

extern "C" fn term(_: libc::c_int) {
    TERM.store(true, Ordering::SeqCst);
}

/// The loudest sample in a chunk of signed 16-bit little-endian audio, from 0 to 1.
pub fn peak(data: &[u8]) -> f64 {
    data.chunks_exact(2).map(|b| (i16::from_le_bytes([b[0], b[1]]) as f64).abs() / 32768.0).fold(0.0, f64::max).min(1.0)
}

pub struct Sample {
    pub path: PathBuf,
    file: Option<std::fs::File>,
    pub written: usize,
    pub ready: bool,
}

impl Sample {
    pub fn new(path: PathBuf) -> Sample {
        Sample { path, file: None, written: 0, ready: false }
    }
    pub fn clear(&mut self) {
        self.file = None;
        self.ready = false;
        self.written = 0;
        let _ = std::fs::remove_file(&self.path);
    }
    pub fn start(&mut self) {
        self.clear();
        self.file = std::fs::File::create(&self.path).ok();
    }
    /// Keeps exactly five seconds, then closes the file and is ready to play.
    pub fn feed(&mut self, data: &[u8]) {
        let Some(file) = self.file.as_mut() else { return };
        let part = &data[..data.len().min(LIMIT - self.written)];
        let _ = file.write_all(part);
        self.written += part.len();
        if self.written >= LIMIT {
            self.file = None;
            self.ready = true;
        }
    }
}

fn emit(value: serde_json::Value) {
    let mut out = std::io::stdout().lock();
    let _ = writeln!(out, "{value}");
    let _ = out.flush();
}

fn stop(process: &mut Option<Child>) {
    if let Some(mut child) = process.take() {
        if child.try_wait().ok().flatten().is_none() {
            unsafe { libc::kill(child.id() as i32, libc::SIGTERM) };
            let until = Instant::now() + Duration::from_secs(2);
            while child.try_wait().ok().flatten().is_none() && Instant::now() < until {
                std::thread::sleep(Duration::from_millis(20));
            }
            let _ = child.kill();
        }
        let _ = child.wait();
    }
}

/// A private folder like tempfile.TemporaryDirectory(prefix="pistachio-mic-"), in $TMPDIR.
fn private_folder() -> std::io::Result<PathBuf> {
    let base = std::env::temp_dir();
    for n in 0..100u32 {
        let stamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.subsec_nanos()).unwrap_or(0);
        let dir = base.join(format!("pistachio-mic-{}{:08x}", std::process::id(), stamp.wrapping_add(n)));
        match std::fs::DirBuilder::new().mode(0o700).create(&dir) {
            Ok(()) => return Ok(dir),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e),
        }
    }
    Err(std::io::Error::other("no private folder"))
}

use std::os::unix::fs::DirBuilderExt;

pub fn main(args: &[String]) -> i32 {
    let Some(target) = args.first() else { eprintln!("usage: psc mic-check TARGET"); return 1 };
    unsafe { libc::signal(libc::SIGTERM, term as extern "C" fn(libc::c_int) as libc::sighandler_t) };
    let Ok(folder) = private_folder() else {
        emit(json!({"event": "error", "message": "Audio check could not start. Check PipeWire tools and your input."}));
        return 0;
    };
    let mut sample = Sample::new(folder.join("sample.raw"));
    let mut mic: Option<Child> = None;
    let mut player: Option<Child> = None;
    let mut pending: Vec<u8> = vec![]; // what came on stdin, not yet a whole line
    let mut eof = false;
    emit(json!({"event": "ready"}));
    let mut buffer = [0u8; 3200];
    let result: Result<(), ()> = loop {
        if TERM.load(Ordering::SeqCst) {
            break Ok(());
        }
        let mut fds = vec![libc::pollfd { fd: 0, events: libc::POLLIN, revents: 0 }];
        let mic_fd = mic.as_ref().and_then(|c| c.stdout.as_ref()).map(|o| o.as_raw_fd());
        if let Some(fd) = mic_fd {
            fds.push(libc::pollfd { fd, events: libc::POLLIN, revents: 0 });
        }
        // a whole command already read comes first; otherwise wait (150 ms) for input or audio
        let line_ready = pending.contains(&b'\n');
        if !line_ready && eof {
            break Ok(()); // the shell went away
        }
        let ready = if line_ready { 1 } else { unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, 150) } };
        if ready > 0 {
            if !line_ready && fds[0].revents != 0 {
                let mut chunk = [0u8; 4096];
                let n = unsafe { libc::read(0, chunk.as_mut_ptr() as *mut libc::c_void, chunk.len()) };
                if n <= 0 { eof = true; } else { pending.extend_from_slice(&chunk[..n as usize]); }
                continue;
            }
            if line_ready {
                let at = pending.iter().position(|b| *b == b'\n').unwrap();
                let line = String::from_utf8_lossy(&pending[..at]).into_owned();
                pending.drain(..=at);
                let command = serde_json::from_str::<serde_json::Value>(&line).ok().and_then(|v| v["command"].as_str().map(str::to_string));
                match command.as_deref() {
                    Some(c @ ("meter" | "record")) => {
                        stop(&mut player);
                        if c == "record" { sample.start(); } else { sample.clear(); }
                        stop(&mut mic);
                        let spawned = Command::new("pw-record").args(["--raw", "--format", "s16", "--rate", &RATE.to_string(), "--channels", "1", "--target", target, "-"])
                            .stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn();
                        match spawned {
                            Ok(child) => mic = Some(child),
                            Err(_) => break Err(()),
                        }
                        emit(json!({"event": "state", "state": if c == "record" { "recording" } else { "metering" }}));
                    }
                    Some("play") if sample.ready && mic.is_none() => {
                        stop(&mut player);
                        let spawned = Command::new("pw-play").args(["--raw", "--format", "s16", "--rate", &RATE.to_string(), "--channels", "1"]).arg(&sample.path)
                            .stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn();
                        match spawned {
                            Ok(child) => player = Some(child),
                            Err(_) => break Err(()),
                        }
                        emit(json!({"event": "state", "state": "playing"}));
                    }
                    Some("stop") => break Ok(()),
                    _ => {}
                }
                continue;
            }
            if fds.len() > 1 && fds[1].revents != 0 {
                let n = mic.as_mut().and_then(|c| c.stdout.as_mut()).map(|o| o.read(&mut buffer).unwrap_or(0)).unwrap_or(0);
                if n == 0 {
                    stop(&mut mic);
                    sample.clear();
                    emit(json!({"event": "error", "message": "Microphone unavailable or disconnected."}));
                    continue;
                }
                sample.feed(&buffer[..n]);
                emit(json!({"event": "level", "value": peak(&buffer[..n]), "seconds": sample.written as f64 / (RATE * 2) as f64}));
                if sample.ready {
                    stop(&mut mic);
                    emit(json!({"event": "state", "state": "recorded"}));
                }
            }
        }
        if player.as_mut().is_some_and(|p| p.try_wait().ok().flatten().is_some()) {
            player = None;
            emit(json!({"event": "state", "state": "recorded"}));
        }
    };
    if result.is_err() {
        emit(json!({"event": "error", "message": "Audio check could not start. Check PipeWire tools and your input."}));
    }
    stop(&mut mic);
    stop(&mut player);
    sample.clear();
    let _ = std::fs::remove_dir_all(&folder);
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_explicit_record_keeps_exactly_five_seconds() {
        let dir = std::env::temp_dir().join(format!("psc-mic-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let mut sample = Sample::new(dir.join("sample.raw"));
        sample.feed(&[0x00, 0x40].repeat(1600));
        assert!(!sample.path.exists(), "nothing is kept before Record");
        sample.start();
        sample.feed(&[0x00, 0x40].repeat(90000));
        assert!(sample.ready);
        assert_eq!(std::fs::metadata(&sample.path).unwrap().len(), (16000 * 2 * 5) as u64);
        assert!((peak(&[0x00, 0x40].repeat(10)) - 0.5).abs() < 0.01);
        sample.clear();
        assert!(!sample.path.exists());
        let _ = std::fs::remove_dir_all(dir);
    }
}
