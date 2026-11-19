//! `psc capture probe PATH | trim PATH START END`: recording length, and a precise trim to a new
//! sibling file, never the input (services/Screenshots.qml). Python's capture.py until 19 November
//! 2026; same arguments and JSON ({"duration"}, {"path"} or {"error"} with exit 1). SIGTERM/SIGINT end
//! the encoder (terminate, 3 s, kill), remove the partial and the reserved name, exit 128 + signal.
use serde_json::json;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicI32, Ordering};
use std::time::{Duration, Instant};

static SIGNAL: AtomicI32 = AtomicI32::new(0);

extern "C" fn caught(signal: libc::c_int) {
    SIGNAL.store(signal, Ordering::SeqCst);
}

enum Stop { Error(String), Signal(i32) }

/// Runs a video tool; while it runs, a SIGTERM/SIGINT ends it (terminate, then kill after 3 s).
fn run(command: &[&str]) -> Result<String, Stop> {
    let mut child: Child = Command::new(command[0]).args(&command[1..]).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped())
        .spawn().map_err(|e| Stop::Error(e.to_string()))?;
    let (mut out, mut err) = (child.stdout.take().unwrap(), child.stderr.take().unwrap());
    let outs = std::thread::spawn(move || { let mut s = String::new(); let _ = std::io::Read::read_to_string(&mut out, &mut s); s });
    let errs = std::thread::spawn(move || { let mut s = String::new(); let _ = std::io::Read::read_to_string(&mut err, &mut s); s });
    loop {
        let signal = SIGNAL.load(Ordering::SeqCst);
        if signal != 0 {
            unsafe { libc::kill(child.id() as i32, libc::SIGTERM) };
            let until = Instant::now() + Duration::from_secs(3);
            while child.try_wait().ok().flatten().is_none() && Instant::now() < until { std::thread::sleep(Duration::from_millis(20)); }
            let _ = child.kill();
            let _ = child.wait();
            return Err(Stop::Signal(signal));
        }
        match child.try_wait() {
            Ok(Some(status)) => {
                let (out, err) = (outs.join().unwrap_or_default(), errs.join().unwrap_or_default());
                if status.success() { return Ok(out); }
                let err = err.trim();
                let tail: String = err.chars().rev().take(600).collect::<Vec<_>>().into_iter().rev().collect();
                return Err(Stop::Error(if tail.is_empty() { "Video tool failed".into() } else { tail }));
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(20)),
            Err(e) => return Err(Stop::Error(e.to_string())),
        }
    }
}

fn probe(source: &Path) -> Result<f64, Stop> {
    if !source.is_file() { return Err(Stop::Error("Recording no longer exists".into())); }
    let out = run(&["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", &source.to_string_lossy()])?;
    let duration = serde_json::from_str::<serde_json::Value>(&out).ok()
        .and_then(|v| v["format"]["duration"].as_str().and_then(|d| d.parse::<f64>().ok()).or_else(|| v["format"]["duration"].as_f64()))
        .ok_or_else(|| Stop::Error("'duration'".into()))?;
    if !duration.is_finite() || duration <= 0.0 { return Err(Stop::Error("Recording has no usable duration".into())); }
    Ok(duration)
}

/// Python's float(): "1", "0.4", "nan", "inf", " 2 "
fn number(s: &str) -> Result<f64, Stop> {
    s.trim().parse::<f64>().map_err(|_| Stop::Error(format!("could not convert string to float: '{s}'")))
}

fn trim(source: &Path, start: &str, end: &str) -> Result<PathBuf, Stop> {
    let source = std::path::absolute(source).map_err(|e| Stop::Error(e.to_string()))?;
    let duration = probe(&source)?;
    let (start, end) = (number(start)?, number(end)?);
    if !start.is_finite() || !end.is_finite() || start < 0.0 || end <= start || end > duration + 0.01 {
        return Err(Stop::Error("Choose a start before the end, within the recording".into()));
    }
    // reserve the target exclusively, even for simultaneous trims or Unicode/spaced paths
    let stem = source.file_stem().unwrap_or_default().to_string_lossy().into_owned();
    let dir = source.parent().unwrap_or(Path::new("/")).to_path_buf();
    let mut target = dir.join(format!("{stem}_trimmed.mp4"));
    let mut serial = 2;
    loop {
        match std::fs::OpenOptions::new().write(true).create_new(true).open(&target) {
            Ok(_) => break,
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
                target = dir.join(format!("{stem}_trimmed_{serial}.mp4"));
                serial += 1;
            }
            Err(e) => return Err(Stop::Error(e.to_string())),
        }
    }
    // an exclusive, unpredictable name, as mkstemp gave: never through a planted symlink
    let mut temporary = PathBuf::new();
    for n in 0..100u32 {
        let stamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.subsec_nanos()).unwrap_or(0);
        let candidate = dir.join(format!(".pistachio-trim-{}-{:08x}.part.mp4", std::process::id(), stamp.wrapping_mul(2654435761).wrapping_add(n)));
        match std::fs::OpenOptions::new().write(true).create_new(true).open(&candidate) {
            Ok(_) => { temporary = candidate; break; }
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => { let _ = std::fs::remove_file(&target); return Err(Stop::Error(e.to_string())); }
        }
    }
    if temporary.as_os_str().is_empty() { let _ = std::fs::remove_file(&target); return Err(Stop::Error("no temporary file".into())); }
    let result = (|| {
        // re-encode to avoid keyframe snapping; optional audio keeps silent recordings working too
        run(&["ffmpeg", "-v", "error", "-nostdin", "-y", "-ss", &format_float(start), "-i", &source.to_string_lossy(), "-t", &format_float(end - start),
            "-map", "0:v:0", "-map", "0:a?", "-c:v", "libx264", "-preset", "fast", "-crf", "20", "-c:a", "aac",
            "-movflags", "+faststart", &temporary.to_string_lossy()])?;
        std::fs::rename(&temporary, &target).map_err(|e| Stop::Error(e.to_string()))
    })();
    let _ = std::fs::remove_file(&temporary);
    match result {
        Ok(()) => Ok(target),
        Err(e) => { let _ = std::fs::remove_file(&target); Err(e) }
    }
}

/// Like Python's str(float): 1.0 → "1.0", 0.4 → "0.4"
fn format_float(f: f64) -> String {
    if f.fract() == 0.0 { format!("{f:.1}") } else { format!("{f}") }
}

pub fn main(args: &[String]) -> i32 {
    unsafe {
        libc::signal(libc::SIGTERM, caught as extern "C" fn(libc::c_int) as libc::sighandler_t);
        libc::signal(libc::SIGINT, caught as extern "C" fn(libc::c_int) as libc::sighandler_t);
    }
    let a: Vec<&str> = args.iter().map(String::as_str).collect();
    let result = match a.as_slice() {
        ["probe", path] => probe(Path::new(path)).map(|d| json!({"duration": d})),
        ["trim", path, start, end] => trim(Path::new(path), start, end).map(|p| json!({"path": p.to_string_lossy()})),
        _ => Err(Stop::Error("Invalid capture command".into())),
    };
    match result {
        Ok(v) => { println!("{v}"); 0 }
        Err(Stop::Error(e)) => { println!("{}", json!({"error": e})); 1 }
        Err(Stop::Signal(s)) => 128 + s,
    }
}
