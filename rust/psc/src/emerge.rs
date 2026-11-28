//! A running `emerge` in the launcher's Background jobs (owner's call, 28 November 2026: "emerge
//! background jobs inside launcher"), watched by `psc launcher-tools` (tools.rs) every few seconds. View
//! only: it isn't the shell's process, so there's no Cancel or Run again.
//!
//! Each look reads every /proc/PID/cmdline and stat (a few hundred small files, about every 2 s while
//! the shell runs); emerge.log only while an emerge is running or just ended.
//! From /proc, readable by anyone: the emerge itself (python running …/emerge, the first of its forks)
//! and what it builds now: Portage names each ebuild process `[category/package-version] sandbox` (or
//! `bash`, `fakeroot`; portage/package/ebuild/doebuild.py), with the phase after `ebuild.sh`.
//! From /var/log/emerge.log, only for the portage group (root:portage 0660): "3 of 12" and how it
//! ended (`*** exiting successfully.`, `… unsuccessfully with status 'N'.`, `*** terminating.`); without
//! it the job says it ended, not how.
//!
//! It's a job folder like the others (`emerge-PID-START/state.json` and `output`), so read_jobs lists it, a
//! live reload keeps it, and the twenty-newest trim applies; a notification says when it ends.
use serde_json::{json, Value};
use std::os::unix::fs::DirBuilderExt;
use std::path::{Path, PathBuf};

pub struct Proc {
    pub pid: u32,
    pub ppid: u32,
    pub start: u64, // clock ticks after boot (/proc/PID/stat, field 22)
    pub argv: Vec<String>,
}

/// Every process /proc shows: its arguments and, from stat, its parent and start.
pub fn processes(proc: &Path) -> Vec<Proc> {
    let Ok(dir) = std::fs::read_dir(proc) else { return vec![] };
    dir.flatten().filter_map(|e| {
        let pid: u32 = e.file_name().to_str()?.parse().ok()?;
        let raw = std::fs::read(e.path().join("cmdline")).ok()?;
        let argv: Vec<String> = raw.split(|b| *b == 0).filter(|a| !a.is_empty()).map(|a| String::from_utf8_lossy(a).into_owned()).collect();
        let stat = std::fs::read_to_string(e.path().join("stat")).ok()?;
        // the name in brackets may hold spaces: the fields after its last ')'
        let fields: Vec<&str> = stat.rsplit_once(')')?.1.split_whitespace().collect();
        Some(Proc { pid, ppid: fields.get(1)?.parse().ok()?, start: fields.get(19)?.parse().ok()?, argv })
    }).collect()
}

fn base(arg: &str) -> &str {
    arg.rsplit('/').next().unwrap_or(arg)
}

/// emerge's own arguments, if this is an emerge: `python3.14 /usr/lib/python-exec/python3.14/emerge -avuDN
/// @world` (Gentoo's wrapper execs python) or a plain `emerge …`; never sudo's `sudo emerge …`.
fn emerge_args(argv: &[String]) -> Option<&[String]> {
    let first = base(argv.first()?);
    if first == "emerge" {
        return Some(&argv[1..]);
    }
    (first.starts_with("python") && argv.get(1).is_some_and(|a| base(a) == "emerge")).then(|| &argv[2..])
}

/// Quick questions aren't jobs: searches, --info, --pretend and the like end at once.
fn quick(args: &[String]) -> bool {
    args.iter().any(|a| matches!(a.as_str(), "-p" | "--pretend" | "-s" | "--search" | "-S" | "--searchdesc" | "--info" | "--version" | "-V" | "-h" | "--help")
        || a.starts_with('-') && !a.starts_with("--") && a[1..].contains(['p', 's', 'S', 'h']))
}

/// `[dev-libs/foo-1.2] sandbox …/ebuild.sh compile`: the package and its phase.
fn building(argv: &[String]) -> Option<(String, String)> {
    let name = argv.first()?.strip_prefix('[')?;
    let (cpv, rest) = name.split_once(']')?;
    if !matches!(rest.trim(), "sandbox" | "bash" | "fakeroot") || !cpv.contains('/') {
        return None;
    }
    let words: Vec<&str> = argv[1..].iter().flat_map(|a| a.split_whitespace()).collect();
    let phase = words.iter().position(|w| base(w) == "ebuild.sh").and_then(|i| words.get(i + 1)).map(|p| p.to_string()).unwrap_or_default();
    Some((cpv.to_string(), phase))
}

pub struct Running {
    pub pid: u32,
    pub start: u64,
    pub command: String,
    pub packages: Vec<(String, String)>,
}

/// The emerges running now (the first of each one's forks), with what each builds.
pub fn running(procs: &[Proc]) -> Vec<Running> {
    let is_emerge = |p: &Proc| emerge_args(&p.argv).is_some_and(|a| !quick(a));
    let ancestor = |mut pid: u32, of: u32| {
        for _ in 0..64 {
            if pid == of { return true; }
            match procs.iter().find(|p| p.pid == pid) { Some(p) if p.ppid != pid => pid = p.ppid, _ => return false }
        }
        false
    };
    procs.iter().filter(|p| is_emerge(p) && !procs.iter().any(|q| q.pid == p.ppid && is_emerge(q))).map(|p| {
        let args = emerge_args(&p.argv).unwrap_or_default();
        let mut packages: Vec<(String, String)> = procs.iter().filter(|q| ancestor(q.ppid, p.pid)).filter_map(|q| building(&q.argv)).collect();
        packages.sort();
        packages.dedup_by(|a, b| a.0 == b.0);
        Running { pid: p.pid, start: p.start, command: std::iter::once("emerge".to_string()).chain(args.iter().cloned()).collect::<Vec<_>>().join(" "), packages }
    }).collect()
}

#[derive(Debug, PartialEq)]
pub enum End { Success, Failed(i64), Terminated }

#[derive(Debug, Default, PartialEq)]
pub struct Log {
    pub step: String,          // "3 of 12", the last package started
    pub lines: Vec<String>,    // this emerge's lines, without their times
    pub end: Option<End>,
}

/// emerge.log since `since` (seconds since the epoch): `1732790000:  >>> emerge (3 of 12) cat/pkg-1 to /`.
pub fn read_log(text: &str, since: u64) -> Log {
    let mut log = Log::default();
    for line in text.lines() {
        let Some((time, what)) = line.split_once(':') else { continue };
        if time.trim().parse::<u64>().map_or(true, |t| t < since) { continue; }
        let what = what.trim();
        if let Some(rest) = what.strip_prefix(">>> emerge (") {
            log.step = rest.split(')').next().unwrap_or("").to_string();
        }
        if what == "*** exiting successfully." {
            log.end = Some(End::Success);
        } else if let Some(rest) = what.strip_prefix("*** exiting unsuccessfully with status '") {
            log.end = Some(End::Failed(rest.trim_end_matches("'.").parse().unwrap_or(1)));
        } else if what == "*** terminating." {
            log.end = Some(End::Terminated);
        }
        log.lines.push(what.to_string());
    }
    log
}

fn boot_seconds(proc: &Path) -> u64 {
    std::fs::read_to_string(proc.join("stat")).ok().and_then(|s| s.lines().find_map(|l| l.strip_prefix("btime ")?.trim().parse().ok())).unwrap_or(0)
}

fn ticks() -> u64 {
    let t = unsafe { libc::sysconf(libc::_SC_CLK_TCK) };
    if t > 0 { t as u64 } else { 100 }
}

pub struct Places<'a> {
    pub jobs: &'a Path,
    pub proc: &'a Path,
    pub log: &'a Path,
}

fn write(folder: &Path, row: &Value, output: &str) {
    let _ = std::fs::DirBuilder::new().mode(0o700).create(folder);
    let _ = std::fs::write(folder.join("output"), output);
    let tmp = folder.join("state.tmp");
    if std::fs::write(&tmp, row.to_string()).is_ok() { let _ = std::fs::rename(&tmp, folder.join("state.json")); }
}

/// The job's output: this emerge's last 300 log lines (a whole @world can be thousands).
fn last_lines(lines: &[String]) -> String {
    lines[lines.len().saturating_sub(300)..].join("\n")
}

fn now_ms() -> f64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis() as f64).unwrap_or(0.0)
}

/// One look: each running emerge's folder brought up to date, and an emerge that's gone written as
/// ended (`notify(title, body)` once). Returns the folders it wrote.
pub fn watch(at: &Places, notify: &dyn Fn(&str, &str)) -> Vec<PathBuf> {
    let procs = processes(at.proc);
    let now = running(&procs);
    let boot = boot_seconds(at.proc);
    // the folders still marked running (one may have ended)
    let folders: Vec<(PathBuf, Value)> = std::fs::read_dir(at.jobs).into_iter().flatten().flatten()
        .filter(|e| e.file_name().to_string_lossy().starts_with("emerge-"))
        .filter_map(|e| Some((e.path(), serde_json::from_str::<Value>(&std::fs::read_to_string(e.path().join("state.json")).ok()?).ok()?)))
        .filter(|(_, row)| row["state"] == "running").collect();
    // emerge.log grows for good: read only while there's an emerge to tell about
    let log_text = if now.is_empty() && folders.is_empty() { None } else { std::fs::read_to_string(at.log).ok() };
    let mut wrote = vec![];
    let mut ended = false;
    for e in &now {
        let started = boot * 1000 + e.start * 1000 / ticks();
        let log = log_text.as_deref().map(|t| read_log(t, started / 1000));
        let packages: Vec<&str> = e.packages.iter().map(|p| p.0.as_str()).collect();
        let phase = e.packages.first().map(|p| p.1.as_str()).unwrap_or("");
        let output = match &log {
            Some(l) if !l.lines.is_empty() => last_lines(&l.lines),
            Some(_) => "Nothing in emerge.log yet.".to_string(),
            None => format!("{}\n(\"3 of 12\" and how it ends are in /var/log/emerge.log, which needs the portage group: sudo gpasswd -a $USER portage, then log in again.)",
                if packages.is_empty() { "Working out what to build, or waiting for an answer.".to_string() } else { format!("Building {}", packages.join(", ")) }),
        };
        let id = format!("emerge-{}-{}", e.pid, e.start);
        let row = json!({"id": id, "kind": "emerge", "command": e.command, "started": started as f64,
            "state": "running", "code": null, "pid": e.pid, "tick": e.start, "packages": packages, "phase": phase,
            "step": log.as_ref().map(|l| l.step.clone()).unwrap_or_default()});
        let folder = at.jobs.join(&id);
        write(&folder, &row, &output);
        wrote.push(folder);
    }
    // the ones that were running and are gone (or whose pid now belongs to another process)
    for (folder, mut row) in folders {
        if wrote.contains(&folder) { continue; }
        let still = now.iter().any(|e| Some(e.pid as u64) == row["pid"].as_u64() && Some(e.start) == row["tick"].as_u64());
        if still { continue; }
        let since = row["started"].as_f64().unwrap_or(0.0) as u64 / 1000;
        let log = log_text.as_deref().map(|t| read_log(t, since));
        let (state, code) = match log.as_ref().and_then(|l| l.end.as_ref()) {
            Some(End::Success) => ("finished", json!(0)),
            Some(End::Failed(c)) => ("failed", json!(c)),
            Some(End::Terminated) => ("cancelled", Value::Null),
            None => ("ended", Value::Null),
        };
        row["state"] = json!(state);
        row["code"] = code;
        row["ended"] = json!(now_ms());
        row["packages"] = json!([]);
        let output = match &log {
            Some(l) if !l.lines.is_empty() => last_lines(&l.lines),
            _ => std::fs::read_to_string(folder.join("output")).unwrap_or_default(),
        };
        write(&folder, &row, &output);
        let command = row["command"].as_str().unwrap_or("emerge");
        let (title, body) = match state {
            "finished" => (format!("Finished: {command}"), "Open Background jobs for the log.".to_string()),
            "failed" => (format!("Failed: {command}"), format!("Exit {} · Open Background jobs for the log.", row["code"])),
            "cancelled" => (format!("Stopped: {command}"), "Open Background jobs for the log.".to_string()),
            _ => (format!("Ended: {command}"), "Without the portage group the shell can't tell how it ended.".to_string()),
        };
        notify(&title, &body);
        wrote.push(folder);
        ended = true;
    }
    if ended { crate::tools::trim_jobs(at.jobs); }
    wrote
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fake_proc(dir: &Path, pid: u32, ppid: u32, start: u64, argv: &[&str]) {
        let p = dir.join(pid.to_string());
        std::fs::create_dir_all(&p).unwrap();
        std::fs::write(p.join("cmdline"), argv.iter().map(|a| format!("{a}\0")).collect::<String>()).unwrap();
        // pid (comm) state ppid … field 22 is starttime; comm may hold spaces and brackets
        let mut fields = vec!["S".to_string(), ppid.to_string()];
        fields.extend((0..17).map(|_| "0".to_string()));
        fields.push(start.to_string());
        std::fs::write(p.join("stat"), format!("{pid} ({}) {}\n", argv[0], fields.join(" "))).unwrap();
    }

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("psc-emerge-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(d.join("proc")).unwrap();
        std::fs::create_dir_all(d.join("jobs")).unwrap();
        std::fs::write(d.join("proc/stat"), "cpu 0 0\nbtime 1764000000\n").unwrap();
        d
    }

    fn world(proc: &Path) {
        fake_proc(proc, 1, 1, 1, &["/sbin/init"]);
        fake_proc(proc, 100, 1, 500, &["sudo", "emerge", "-avuDN", "@world"]);
        fake_proc(proc, 101, 100, 600, &["/usr/bin/python3.14", "/usr/lib/python-exec/python3.14/emerge", "-avuDN", "@world"]);
        fake_proc(proc, 102, 101, 700, &["/usr/bin/python3.14", "/usr/lib/python-exec/python3.14/emerge", "-avuDN", "@world"]); // a fork
        fake_proc(proc, 103, 102, 800, &["[dev-libs/glib-2.84.1] sandbox", "/usr/lib/portage/python3.14/ebuild.sh compile"]);
        fake_proc(proc, 104, 103, 810, &["make", "-j16"]);
        fake_proc(proc, 200, 1, 900, &["/usr/bin/python3.14", "/usr/lib/python-exec/python3.14/emerge", "--search", "glib"]);
    }

    #[test]
    fn finds_the_emerge_and_what_it_builds() {
        let d = tmp("find");
        world(&d.join("proc"));
        let now = running(&processes(&d.join("proc")));
        assert_eq!(now.len(), 1, "sudo, the fork and the search aren't jobs");
        assert_eq!(now[0].pid, 101);
        assert_eq!(now[0].command, "emerge -avuDN @world");
        assert_eq!(now[0].packages, [("dev-libs/glib-2.84.1".to_string(), "compile".to_string())]);
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn reads_its_part_of_the_log() {
        let text = "1764000000:  >>> emerge (1 of 2) old/thing-1 to /\n1764000000:  *** exiting successfully.\n\
                    1764000010: Started emerge on: Nov 28, 2026 14:00:00\n1764000011:  >>> emerge (1 of 3) dev-libs/glib-2.84.1 to /\n\
                    1764000300:  ::: completed emerge (1 of 3) dev-libs/glib-2.84.1 to /\n1764000301:  >>> emerge (2 of 3) dev-libs/foo-1 to /\n";
        let log = read_log(text, 1764000010);
        assert_eq!(log.step, "2 of 3");
        assert_eq!(log.end, None, "an older emerge's ending isn't this one's");
        assert_eq!(log.lines.len(), 4);
        assert_eq!(read_log(&(text.to_string() + "1764000400:  *** exiting unsuccessfully with status '1'.\n"), 1764000010).end, Some(End::Failed(1)));
        assert_eq!(read_log(&(text.to_string() + "1764000400:  *** terminating.\n"), 1764000010).end, Some(End::Terminated));
    }

    #[test]
    fn a_job_while_it_runs_and_once_it_ends() {
        let d = tmp("watch");
        let (proc, jobs, log) = (d.join("proc"), d.join("jobs"), d.join("emerge.log"));
        world(&proc);
        let at = Places { jobs: &jobs, proc: &proc, log: &log };
        let told = std::cell::RefCell::new(vec![]);
        let notify = |t: &str, b: &str| told.borrow_mut().push(format!("{t} | {b}"));
        // no log (no portage group): the package, and how to get the rest
        watch(&at, &notify);
        let rows = crate::tools::read_jobs(&jobs);
        assert_eq!(rows.len(), 1);
        let r = &rows[0];
        assert!(r["id"] == "emerge-101-600" && r["state"] == "running" && r["packages"][0] == "dev-libs/glib-2.84.1" && r["phase"] == "compile" && r["step"] == "", "{r}");
        assert!(r["output"].as_str().unwrap().contains("portage group"), "{r}");
        let started = r["started"].as_f64().unwrap() / 1000.0;
        // with the log: the step, and then how it ended
        std::fs::write(&log, format!("{}:  >>> emerge (3 of 12) dev-libs/glib-2.84.1 to /\n", started as u64 + 1)).unwrap();
        watch(&at, &notify);
        assert_eq!(crate::tools::read_jobs(&jobs)[0]["step"], "3 of 12");
        assert!(told.borrow().is_empty());
        std::fs::remove_dir_all(proc.join("101")).unwrap();
        std::fs::remove_dir_all(proc.join("102")).unwrap();
        std::fs::remove_dir_all(proc.join("103")).unwrap();
        std::fs::write(&log, format!("{}:  >>> emerge (3 of 12) dev-libs/glib-2.84.1 to /\n{}:  *** exiting unsuccessfully with status '1'.\n", started as u64 + 1, started as u64 + 9)).unwrap();
        watch(&at, &notify);
        let r = &crate::tools::read_jobs(&jobs)[0];
        assert!(r["state"] == "failed" && r["code"] == 1 && r["ended"].is_number(), "{r}");
        assert_eq!(told.borrow().len(), 1);
        assert!(told.borrow()[0].starts_with("Failed: emerge -avuDN @world"), "{:?}", told.borrow());
        watch(&at, &notify);
        assert_eq!(told.borrow().len(), 1, "told once");
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn without_the_log_it_only_says_it_ended() {
        let d = tmp("nolog");
        let (proc, jobs, log) = (d.join("proc"), d.join("jobs"), d.join("emerge.log"));
        world(&proc);
        let at = Places { jobs: &jobs, proc: &proc, log: &log };
        watch(&at, &|_, _| {});
        // the pid comes back as another process: still the old emerge's end
        std::fs::remove_dir_all(proc.join("101")).unwrap();
        fake_proc(&proc, 101, 1, 99999, &["/usr/bin/python3.14", "/usr/lib/python-exec/python3.14/emerge", "-av", "foo"]);
        let told = std::cell::RefCell::new(0);
        watch(&at, &|t, _| { assert!(t.starts_with("Ended")); *told.borrow_mut() += 1; });
        let rows = crate::tools::read_jobs(&jobs);
        assert_eq!(*told.borrow(), 1);
        assert!(rows.iter().any(|r| r["state"] == "ended" && r["command"] == "emerge -avuDN @world"), "{rows:?}");
        assert!(rows.iter().any(|r| r["state"] == "running" && r["command"] == "emerge -av foo"), "the new one is its own job: {rows:?}");
        let _ = std::fs::remove_dir_all(&d);
    }
}
