//! The running shell, through `qs` itself: find it, start it, stop it carefully, pass calls on.
use std::ffi::OsString;
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

pub const CONFIG: &str = "pistachio";

/// `qs -c pistachio`, or the program in `$QS` (tests use a stand-in).
pub fn qs() -> Command {
    let mut command = Command::new(std::env::var_os("QS").unwrap_or_else(|| "qs".into()));
    command.args(["-c", CONFIG]);
    command
}

/// Replace psc with `qs -c pistachio <args>`, so its exit status and output are qs's own.
pub fn exec_qs(args: &[OsString]) -> ! {
    let error = qs().args(args).exec();
    eprintln!("psc: couldn't run qs: {error}");
    std::process::exit(127)
}

/// The process ids in `qs list` output (`  Process ID: 5769` under each instance).
pub fn parse_pids(list: &str) -> Vec<u32> {
    list.lines().filter_map(|l| l.trim().strip_prefix("Process ID:")).filter_map(|p| p.trim().parse().ok()).collect()
}

pub fn pids() -> Vec<u32> {
    let out = qs().arg("list").stderr(Stdio::null()).output();
    out.map(|o| parse_pids(&String::from_utf8_lossy(&o.stdout))).unwrap_or_default()
}

fn alive(pid: u32) -> bool {
    unsafe { libc::kill(pid as libc::pid_t, 0) == 0 }
}

fn signal(pid: u32, signal: libc::c_int) {
    unsafe { libc::kill(pid as libc::pid_t, signal) };
}

/// Waits until the process is gone, for at most `seconds`.
fn gone(pid: u32, seconds: f64) -> bool {
    let until = Instant::now() + Duration::from_secs_f64(seconds);
    while alive(pid) {
        if Instant::now() >= until {
            return false;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    true
}

/// Direct children of a process (of every thread), from /proc.
pub fn children(pid: u32) -> Vec<u32> {
    let mut out = vec![];
    if let Ok(tasks) = std::fs::read_dir(format!("/proc/{pid}/task")) {
        for task in tasks.flatten() {
            if let Ok(text) = std::fs::read_to_string(task.path().join("children")) {
                out.extend(text.split_whitespace().filter_map(|c| c.parse::<u32>().ok()));
            }
        }
    }
    out.sort_unstable();
    out.dedup();
    out
}

/// `qs kill` returns at once, and a shell can hang while exiting, so wait until each process is
/// really gone: 5 s for a clean exit, then SIGTERM (2 s), then SIGKILL (2 s). Only then can a new
/// copy take over the notification service.
pub fn stop() -> Result<(), String> {
    let old = pids();
    if old.is_empty() {
        return Ok(());
    }
    if let Ok(mut child) = qs().arg("kill").stdout(Stdio::null()).stderr(Stdio::null()).spawn() {
        let until = Instant::now() + Duration::from_secs(3);
        while child.try_wait().ok().flatten().is_none() && Instant::now() < until {
            std::thread::sleep(Duration::from_millis(50));
        }
        let _ = child.kill();
        let _ = child.wait();
    }
    for pid in old {
        if gone(pid, 5.0) {
            continue;
        }
        eprintln!("psc: shell {pid} didn't exit, terminating it");
        signal(pid, libc::SIGTERM);
        if gone(pid, 2.0) {
            continue;
        }
        signal(pid, libc::SIGKILL);
        if !gone(pid, 2.0) {
            return Err(format!("couldn't stop shell {pid}"));
        }
    }
    Ok(())
}

/// SIGKILL each shell's direct children (never psc itself) and the shell, then wait for it.
pub fn force_stop() -> Result<(), String> {
    let me = std::process::id();
    let old = pids();
    for &pid in &old {
        for child in children(pid) {
            if child != me {
                signal(child, libc::SIGKILL);
            }
        }
        signal(pid, libc::SIGKILL);
    }
    for pid in old {
        if !gone(pid, 5.0) {
            return Err(format!("couldn't stop shell {pid}"));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pids_from_qs_list() {
        let live = "Instance 9g4bvxqot:\n  Process ID: 5769\n  Shell ID: 6145\n  Config path: /x/shell.qml\n\
                    Instance abc:\n  Process ID: 7000\n";
        assert_eq!(parse_pids(live), vec![5769, 7000]);
        assert_eq!(parse_pids(""), Vec::<u32>::new());
    }
}
