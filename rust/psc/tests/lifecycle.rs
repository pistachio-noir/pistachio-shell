//! The built `psc` against a stand-in `qs` (tests/fake-qs.sh): pass-through, stop's escalation,
//! restart order, force-restart. Never touches a real shell.
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

struct Fake { dir: PathBuf }

impl Fake {
    fn new(name: &str) -> Fake {
        let dir = std::env::temp_dir().join(format!("psc-test-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("state")).unwrap();
        Fake { dir }
    }
    fn psc(&self, args: &[&str]) -> std::process::Output {
        Command::new(env!("CARGO_BIN_EXE_psc"))
            .args(args)
            .env("QS", concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fake-qs.sh"))
            .env("FAKE_LOG", self.dir.join("log"))
            .env("FAKE_STATE", self.dir.join("state"))
            .stdin(Stdio::null())
            .output()
            .unwrap()
    }
    fn calls(&self) -> Vec<Vec<String>> {
        let text = std::fs::read_to_string(self.dir.join("log")).unwrap_or_default();
        let mut out = vec![];
        let mut cur = vec![];
        for line in text.lines() {
            if line == "<end of call>" { out.push(std::mem::take(&mut cur)); } else { cur.push(line.to_string()); }
        }
        out
    }
    fn shells(&self) -> Vec<u32> {
        std::fs::read_dir(self.dir.join("state")).unwrap()
            .filter_map(|e| std::fs::read_to_string(e.unwrap().path()).ok())
            .filter_map(|s| s.trim().parse().ok())
            .filter(|pid: &u32| unsafe { libc::kill(*pid as i32, 0) } == 0)
            .collect()
    }
}

impl Drop for Fake {
    fn drop(&mut self) {
        for pid in self.shells() { unsafe { libc::kill(pid as i32, libc::SIGKILL); } }
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

#[test]
fn passthrough_without_tty() {
    let fake = Fake::new("pass");
    let out = fake.psc(&["launcher", "toggle", "a b", "--", "-x"]);
    assert!(out.status.success(), "{out:?}");
    assert_eq!(fake.calls().last().unwrap(), &["-c", "pistachio", "ipc", "call", "launcher", "toggle", "a b", "--", "-x"]);
    fake.psc(&["log", "-f"]);
    assert_eq!(fake.calls().last().unwrap(), &["-c", "pistachio", "log", "-f"]);
    fake.psc(&["setup"]);
    assert_eq!(fake.calls().last().unwrap(), &["-c", "pistachio", "ipc", "call", "setup", "open"]);
    fake.psc(&["setup", "status"]);
    assert_eq!(fake.calls().last().unwrap(), &["-c", "pistachio", "ipc", "call", "setup", "status"]);
}

#[test]
fn stop_escalates() {
    let fake = Fake::new("stop");
    fake.psc(&["start"]);
    std::thread::sleep(Duration::from_millis(300));
    let pid = fake.shells()[0];
    let began = Instant::now();
    let out = fake.psc(&["stop"]);
    assert!(out.status.success(), "{out:?}");
    assert!(began.elapsed() >= Duration::from_secs(5), "stop gave up waiting too early");
    assert!(unsafe { libc::kill(pid as i32, 0) } != 0, "the stuck shell is gone");
    assert!(String::from_utf8_lossy(&out.stderr).contains("didn't exit"));
}

#[test]
fn restart_starts_after_stop() {
    let fake = Fake::new("restart");
    fake.psc(&["start"]);
    std::thread::sleep(Duration::from_millis(300));
    let out = Command::new(env!("CARGO_BIN_EXE_psc")).arg("restart")
        .env("QS", concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fake-qs.sh"))
        .env("FAKE_LOG", fake.dir.join("log")).env("FAKE_STATE", fake.dir.join("state")).env("FAKE_KILL_WORKS", "1")
        .output().unwrap();
    assert!(out.status.success(), "{out:?}");
    let calls = fake.calls();
    let kill = calls.iter().rposition(|c| c.ends_with(&["kill".to_string()])).unwrap();
    let start = calls.iter().rposition(|c| c.ends_with(&["-n".to_string(), "-d".to_string()])).unwrap();
    assert!(kill < start, "{calls:?}");
}

#[test]
fn force_restart_kills_children() {
    let fake = Fake::new("force");
    fake.psc(&["start"]);
    std::thread::sleep(Duration::from_millis(300));
    let pid = fake.shells()[0];
    // task/*/children needs CONFIG_PROC_CHILDREN (off on the owner's Gentoo kernel): else the parents in /proc/*/stat
    let children = std::fs::read_to_string(format!("/proc/{pid}/task/{pid}/children")).unwrap_or_else(|_| {
        std::fs::read_dir("/proc").unwrap().flatten().filter_map(|e| {
            let stat = std::fs::read_to_string(e.path().join("stat")).ok()?;
            let parent: u32 = stat[stat.rfind(')')? + 1..].split_whitespace().nth(1)?.parse().ok()?;
            (parent == pid).then(|| e.file_name().to_string_lossy().into_owned())
        }).collect::<Vec<_>>().join(" ")
    });
    let child: u32 = children.split_whitespace().next().unwrap().parse().unwrap();
    let out = fake.psc(&["force-restart"]);
    assert!(out.status.success(), "{out:?}");
    std::thread::sleep(Duration::from_millis(200));
    assert!(unsafe { libc::kill(pid as i32, 0) } != 0 && unsafe { libc::kill(child as i32, 0) } != 0);
    assert_eq!(fake.shells().len(), 1, "a new shell started");
}

#[test]
fn broken_pipe_is_quiet() {
    // `psc doctor --json | head -c1`: the reader goes away before psc writes
    let mut child = Command::new(env!("CARGO_BIN_EXE_psc")).args(["doctor", "--json"])
        .stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().unwrap();
    drop(child.stdout.take());
    let out = child.wait_with_output().unwrap();
    let err = String::from_utf8_lossy(&out.stderr);
    assert!(!err.contains("panicked") && out.status.code() != Some(134) && out.status.code() != Some(101), "{err} {:?}", out.status);
}
