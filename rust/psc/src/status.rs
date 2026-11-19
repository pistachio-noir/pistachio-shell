//! `psc status`: is the shell running, for how long, how much memory, which helpers.
use std::path::Path;

#[derive(Debug, PartialEq)]
pub struct Helper { pub name: String, pub pid: u32, pub rss_kib: u64 }

#[derive(Debug, PartialEq)]
pub struct Shell { pub pid: u32, pub uptime_s: u64, pub rss_kib: u64, pub helpers: Vec<Helper> }

fn rss_kib(status: &str) -> u64 {
    status.lines().find_map(|l| l.strip_prefix("VmRSS:")).and_then(|v| v.split_whitespace().next()?.parse().ok()).unwrap_or(0)
}

fn ticks_per_second() -> f64 {
    let t = unsafe { libc::sysconf(libc::_SC_CLK_TCK) };
    if t > 0 { t as f64 } else { 100.0 }
}

/// The shell `pid` as /proc (or a stand-in laid out like it) describes it; None when it's gone.
pub fn read(pid: u32, proc: &Path) -> Option<Shell> {
    let dir = proc.join(pid.to_string());
    let stat = std::fs::read_to_string(dir.join("stat")).ok()?;
    // fields after "(comm)": state is field 3, starttime field 22, so index 19 here
    let start: f64 = stat.rsplit_once(')')?.1.split_whitespace().nth(19)?.parse().ok()?;
    let up: f64 = std::fs::read_to_string(proc.join("uptime")).ok()?.split_whitespace().next()?.parse().ok()?;
    let uptime_s = (up - start / ticks_per_second()).max(0.0).round() as u64;
    let rss = rss_kib(&std::fs::read_to_string(dir.join("status")).unwrap_or_default());
    let mut kids: Vec<u32> = vec![];
    if let Ok(tasks) = std::fs::read_dir(dir.join("task")) {
        for task in tasks.flatten() {
            if let Ok(text) = std::fs::read_to_string(task.path().join("children")) {
                kids.extend(text.split_whitespace().filter_map(|c| c.parse::<u32>().ok()));
            }
        }
    }
    kids.sort_unstable();
    kids.dedup();
    let helpers = kids.into_iter().filter_map(|k| {
        let d = proc.join(k.to_string());
        let comm = std::fs::read_to_string(d.join("comm")).ok()?.trim().to_string();
        let name = helper_name(&std::fs::read(d.join("cmdline")).unwrap_or_default()).unwrap_or(comm);
        Some(Helper { name, pid: k, rss_kib: rss_kib(&std::fs::read_to_string(d.join("status")).unwrap_or_default()) })
    }).collect();
    Some(Shell { pid, uptime_s, rss_kib: rss, helpers })
}

/// A helper's readable name from its command line: the program's file name (comm is cut to 15
/// characters), or for a Python helper the script's.
fn helper_name(cmdline: &[u8]) -> Option<String> {
    let args: Vec<String> = cmdline.split(|b| *b == 0).filter(|a| !a.is_empty()).map(|a| String::from_utf8_lossy(a).into_owned()).collect();
    let base = |a: &str| a.rsplit('/').next().unwrap_or(a).to_string();
    let program = base(args.first()?);
    if program.starts_with("python") {
        if let Some(script) = args.iter().skip(1).find(|a| a.ends_with(".py")) {
            return Some(base(script));
        }
    }
    Some(program)
}

pub fn duration(s: u64) -> String {
    let (d, h, m) = (s / 86400, s % 86400 / 3600, s % 3600 / 60);
    if d > 0 { format!("{d} d {h} h") } else if h > 0 { format!("{h} h {m} min") } else if m > 0 { format!("{m} min") } else { format!("{s} s") }
}

pub fn mib(kib: u64) -> String {
    format!("{} MiB", (kib + 512) / 1024)
}

pub fn json(shells: &[Shell]) -> serde_json::Value {
    serde_json::json!({
        "running": !shells.is_empty(),
        "shells": shells.iter().map(|s| serde_json::json!({
            "pid": s.pid, "uptime_s": s.uptime_s, "rss_kib": s.rss_kib,
            "helpers": s.helpers.iter().map(|h| serde_json::json!({"name": h.name, "pid": h.pid, "rss_kib": h.rss_kib})).collect::<Vec<_>>(),
        })).collect::<Vec<_>>(),
    })
}

pub fn text(shells: &[Shell]) -> String {
    if shells.is_empty() {
        return "The shell isn't running. Start it with: psc start".into();
    }
    let mut out = String::new();
    for s in shells {
        let helpers: u64 = s.helpers.iter().map(|h| h.rss_kib).sum();
        out += &format!("Running · PID {} · up {} · {} (helpers {})\n", s.pid, duration(s.uptime_s), mib(s.rss_kib), mib(helpers));
        for h in &s.helpers {
            out += &format!("  {:<22} PID {:<8} {}\n", h.name, h.pid, mib(h.rss_kib));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fake_proc() -> std::path::PathBuf {
        let root = std::env::temp_dir().join(format!("psc-proc-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let put = |p: &str, text: &str| { let f = root.join(p); std::fs::create_dir_all(f.parent().unwrap()).unwrap(); std::fs::write(f, text).unwrap(); };
        put("uptime", "10000.50 1.00\n");
        // field 22 (starttime) in clock ticks: 100 ticks/s → started at 7000 s, so up 3000 s
        put("100/stat", "100 (qs) S 1 100 100 0 -1 4194560 0 0 0 0 0 0 0 0 20 0 9 0 700000 0 0\n");
        put("100/status", "Name:\tqs\nVmRSS:\t  512000 kB\n");
        put("100/task/100/children", "101 102 ");
        put("101/comm", "pistachio-local\n"); put("101/status", "VmRSS:\t 4000 kB\n");
        put("101/cmdline", "/home/x/.local/bin/pistachio-localsend\0--serve\0");
        put("102/comm", "python3\n"); put("102/status", "VmRSS:\t 20000 kB\n");
        put("102/cmdline", "python3\0-I\0/home/x/src/services/phone-timer.py\0");
        root
    }

    #[test]
    fn status_reads_fake_proc() {
        let root = fake_proc();
        let shell = read(100, &root).unwrap();
        assert_eq!(shell.pid, 100);
        assert_eq!(shell.rss_kib, 512000);
        assert!((2999..=3001).contains(&shell.uptime_s), "{}", shell.uptime_s);
        assert_eq!(shell.helpers, vec![
            Helper { name: "pistachio-localsend".into(), pid: 101, rss_kib: 4000 },
            Helper { name: "phone-timer.py".into(), pid: 102, rss_kib: 20000 }]);
        assert_eq!(read(999, &root), None);
        let _ = std::fs::remove_dir_all(root);
    }
}
