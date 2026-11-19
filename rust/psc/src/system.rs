//! `psc system …`: read-only system details and an explicitly requested safe UDisks eject, for
//! Settings (services/Network.qml, Bluetooth.qml, Drives.qml, SystemHealth.qml). Python's
//! system-tools.py until 19 November 2026; same arguments and JSON.
//!
//!   psc system network IFACE                         {ipv4, ipv6, gateways, dns}
//!   psc system bluetooth                             {ADDRESS: {profile, codec, rate}}
//!   psc system health [--auth] [--pid N] [--sources DIR]   [{id, title, detail, status}]
//!   psc system eject DEVICE DISK NAME MOUNTPOINT     {ok, name, holders, message}
//!
//! Only allowlisted summaries cross into diagnostics: never raw auth output, environment, user paths,
//! device names, network addresses, logs or tokens. Eject uses no shell strings, no force flags and
//! never stops applications.
use serde_json::{json, Map, Value};
use std::net::IpAddr;
use std::path::{Path, PathBuf};

/// A command's exit code (-1 when it couldn't run or took too long), stdout and stderr.
pub type Run<'a> = &'a dyn Fn(&[&str]) -> (i32, String, String);

pub struct Sys<'a> {
    pub run: Run<'a>,
    pub proc: PathBuf,
}

fn read_json(sys: &Sys, args: &[&str]) -> Value {
    serde_json::from_str(&(sys.run)(args).1).unwrap_or(Value::Array(vec![]))
}

fn list(v: &Value) -> &[Value] {
    v.as_array().map(Vec::as_slice).unwrap_or(&[])
}

pub fn network(sys: &Sys, interface: &str) -> Value {
    let mut ipv4 = vec![];
    let mut ipv6 = vec![];
    let mut gateways: Vec<String> = vec![];
    let mut dns: Vec<String> = vec![];
    if interface.is_empty() || interface.contains('/') || interface.contains('\0') {
        return json!({"ipv4": ipv4, "ipv6": ipv6, "gateways": gateways, "dns": dns});
    }
    for device in list(&read_json(sys, &["ip", "-j", "address", "show", "dev", interface])) {
        if device.get("ifname").and_then(Value::as_str) != Some(interface) { continue; }
        for a in list(device.get("addr_info").unwrap_or(&Value::Null)) {
            let (Some(local), Some(prefix)) = (a.get("local").and_then(Value::as_str), a.get("prefixlen")) else { continue };
            match a.get("family").and_then(Value::as_str) {
                Some("inet") => ipv4.push(format!("{local}/{prefix}")),
                Some("inet6") => ipv6.push(format!("{local}/{prefix}")),
                _ => {}
            }
        }
    }
    for family in ["-4", "-6"] {
        for route in list(&read_json(sys, &["ip", "-j", family, "route", "show", "default", "dev", interface])) {
            if let Some(g) = route.get("gateway").and_then(Value::as_str) {
                if !gateways.iter().any(|x| x == g) { gateways.push(g.to_string()); }
            }
        }
    }
    for line in (sys.run)(&["nmcli", "-g", "IP4.DNS,IP6.DNS", "device", "show", interface]).1.lines() {
        if let Ok(ip) = line.trim().replace("\\:", ":").parse::<IpAddr>() {
            let ip = ip.to_string();
            if !dns.contains(&ip) { dns.push(ip); }
        }
    }
    json!({"ipv4": ipv4, "ipv6": ipv6, "gateways": gateways, "dns": dns})
}

fn bt_address(item: &Value) -> String {
    let props = item.get("properties");
    let prop = |k: &str| props.and_then(|p| p.get(k)).and_then(Value::as_str).filter(|s| !s.is_empty());
    let found = prop("api.bluez5.address").or_else(|| prop("device.string")).map(str::to_string).unwrap_or_else(|| {
        // a card's name carries it as AA_BB_CC_DD_EE_FF
        let name = item.get("name").and_then(Value::as_str).unwrap_or("");
        name.as_bytes().windows(17).find_map(|w| {
            let s = std::str::from_utf8(w).ok()?;
            let ok = s.split('_').count() == 6 && s.split('_').all(|p| p.len() == 2 && p.chars().all(|c| c.is_ascii_hexdigit()));
            ok.then(|| s.replace('_', ":"))
        }).unwrap_or_default()
    });
    let valid = found.split(':').count() == 6 && found.split(':').all(|p| p.len() == 2 && p.chars().all(|c| c.is_ascii_hexdigit()));
    if valid { found.to_uppercase() } else { String::new() }
}

pub fn bluetooth(sys: &Sys) -> Value {
    let mut result = Map::new();
    for card in list(&read_json(sys, &["pactl", "-f", "json", "list", "cards"])) {
        let addr = bt_address(card);
        if !addr.is_empty() {
            let profile = card.get("active_profile").and_then(Value::as_str).unwrap_or("");
            result.insert(addr, json!({"profile": profile, "codec": "", "rate": ""}));
        }
    }
    let mut nodes = read_json(sys, &["pactl", "-f", "json", "list", "sinks"]).as_array().cloned().unwrap_or_default();
    nodes.extend(read_json(sys, &["pactl", "-f", "json", "list", "sources"]).as_array().cloned().unwrap_or_default());
    for node in &nodes {
        let addr = bt_address(node);
        if addr.is_empty() { continue; }
        let detail = result.entry(addr).or_insert_with(|| json!({"profile": "", "codec": "", "rate": ""}));
        let props = node.get("properties");
        let codec = props.and_then(|p| p.get("api.bluez5.codec").or_else(|| p.get("bluetooth.codec"))).and_then(Value::as_str).filter(|s| !s.is_empty());
        let spec = node.get("sample_specification").and_then(Value::as_str).unwrap_or("");
        let rate = spec.split_whitespace().find_map(|w| w.strip_suffix("Hz").filter(|n| !n.is_empty() && n.chars().all(|c| c.is_ascii_digit())));
        if let (Some(c), true) = (codec, detail["codec"] == "") { detail["codec"] = json!(c); }
        if let (Some(r), true) = (rate, detail["rate"] == "") { detail["rate"] = json!(format!("{r} Hz")); }
    }
    Value::Object(result)
}

/// The processes with the mount open: a file descriptor or working folder inside it (links only,
/// no file is read).
pub fn holders(mountpoint: &str, proc: &Path) -> Vec<Value> {
    let real = std::fs::canonicalize(mountpoint).map(|p| p.to_string_lossy().into_owned()).unwrap_or_else(|_| mountpoint.to_string());
    let mount = format!("{}/", real.trim_end_matches('/'));
    if mount == "/" { return vec![]; }
    let mut pids: Vec<u32> = std::fs::read_dir(proc).map(|d| d.flatten().filter_map(|e| e.file_name().to_str()?.parse().ok()).collect()).unwrap_or_default();
    pids.sort_unstable();
    let mut found = vec![];
    for pid in pids {
        let dir = proc.join(pid.to_string());
        let mut links = vec![dir.join("cwd")];
        if let Ok(fds) = std::fs::read_dir(dir.join("fd")) { links.extend(fds.flatten().map(|e| e.path())); }
        let busy = links.iter().any(|l| std::fs::read_link(l).is_ok_and(|t| {
            let t = t.to_string_lossy();
            format!("{}/", t.trim_end_matches('/')) == mount || t.starts_with(&mount)
        }));
        if busy {
            if let Ok(name) = std::fs::read_to_string(dir.join("comm")) {
                found.push(json!({"pid": pid, "name": name.trim().chars().take(80).collect::<String>()}));
            }
        }
    }
    found
}

/// Some(true/false) only for a successful kernel lookup; errors stay unknown (None).
pub fn device_mounted(sys: &Sys, device: &str) -> Option<bool> {
    let (code, out, err) = (sys.run)(&["findmnt", "--json", "--kernel", "--source", device, "--output", "TARGET"]);
    if code == 1 && out.trim().is_empty() && err.trim().is_empty() { return Some(false); }
    if code != 0 { return None; }
    serde_json::from_str::<Value>(&out).ok()?.get("filesystems")?.as_array().map(|f| !f.is_empty())
}

pub fn eject(sys: &Sys, device: &str, disk: &str, name: &str, mountpoint: &str) -> Value {
    let (code, _, _) = (sys.run)(&["udisksctl", "unmount", "--block-device", device, "--no-user-interaction"]);
    if code != 0 && device_mounted(sys, device) != Some(false) {
        return json!({"ok": false, "name": name, "holders": holders(mountpoint, &sys.proc),
            "message": "Could not unmount. Close files on this drive, then retry. Some applications may be hidden by system permissions."});
    }
    let (code, _, _) = (sys.run)(&["udisksctl", "power-off", "--block-device", disk, "--no-user-interaction"]);
    json!({"ok": code == 0, "name": name, "holders": [],
        "message": if code == 0 { "Safe to remove." } else { "Unmounted, but power-off failed. Retry after checking other volumes on this drive." }})
}

/// The count of ERROR/FATAL lines among the shell's last 200 log lines; never their text.
pub fn shell_errors(sys: &Sys, pid: u32) -> Value {
    let (code, out, _) = (sys.run)(&["qs", "log", "--pid", &pid.to_string(), "--tail", "200", "--no-color"]);
    let lines: Vec<&str> = out.lines().collect();
    let count = lines[lines.len().saturating_sub(200)..].iter().filter(|l| {
        let t = l.trim_start();
        ["ERROR", "FATAL"].iter().any(|w| t.strip_prefix(w).is_some_and(|r| r.starts_with(|c: char| c.is_whitespace() || c == ':')))
    }).count();
    json!({"id": "shell-errors", "title": "Recent shell errors", "detail": "Last 200 log lines · raw content excluded",
        "status": if code == 0 { format!("{count} recent errors") } else { "Log unavailable".into() }})
}

pub fn health(sys: &Sys, auth: bool, pid: Option<u32>, sources: Option<&Path>, path: &std::ffi::OsStr, home: &Path) -> Vec<Value> {
    let mut rows = vec![json!({"id": "shell", "title": "Shell", "detail": "Settings service active", "status": "Running"})];
    if let Some(pid) = pid { rows.push(shell_errors(sys, pid)); }
    // dependencies, fonts, helpers and Python modules: psc doctor's list, the one place it's kept
    for r in crate::doctor::run(path, home) {
        rows.push(json!({"id": r.id, "title": r.title, "detail": if r.kind == crate::doctor::Kind::Required { "Required" } else { "Optional" },
            "status": if r.found { "Installed" } else { "Missing" }}));
    }
    if sources.is_some() {
        for (id, title) in [("psc lens", "Lens helper"), ("psc chat", "Quick chat helper"), ("psc mic-check", "Microphone helper")] {
            rows.push(json!({"id": id, "title": title, "detail": "Built into psc", "status": "Present"}));
        }
    }
    for tool in ["claude", "codex"] {
        let installed = std::env::split_paths(path).any(|d| d.join(tool).is_file());
        let status = if !installed {
            "Not installed".to_string()
        } else if auth {
            let args: &[&str] = if tool == "claude" { &["claude", "auth", "status", "--json"] } else { &["codex", "login", "status"] };
            let (code, out, _) = (sys.run)(args);
            // Exit status is enough for Codex. Claude supplies a boolean: never publish its fields.
            let signed = if tool == "claude" && code == 0 {
                serde_json::from_str::<Value>(&out).ok().and_then(|v| v.get("loggedIn").and_then(Value::as_bool)) == Some(true)
            } else { code == 0 };
            if signed { "Signed in".into() } else { "Not signed in or unavailable".into() }
        } else {
            "Not checked".into()
        };
        let title = if tool == "claude" { "Claude authentication" } else { "Codex authentication" };
        rows.push(json!({"id": format!("{tool}-auth"), "title": title, "detail": "Local CLI status only", "status": status}));
    }
    rows
}

/// Runs a command with no shell, 12 s at most, as system-tools.py's command_status did.
pub fn real_run(args: &[&str]) -> (i32, String, String) {
    run_for(args, std::time::Duration::from_secs(12))
}

pub(crate) fn run_for(args: &[&str], limit: std::time::Duration) -> (i32, String, String) {
    use std::process::{Command, Stdio};
    let Some((program, rest)) = args.split_first() else { return (-1, String::new(), String::new()) };
    let Ok(mut child) = Command::new(program).args(rest).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn() else {
        return (-1, String::new(), String::new());
    };
    let (mut out, mut err) = (child.stdout.take().unwrap(), child.stderr.take().unwrap());
    // the readers report back over a channel, so a pipe held open by a grandchild (a background
    // process of the command) can't keep psc waiting past the limit
    let (send, receive) = std::sync::mpsc::channel();
    let send2 = send.clone();
    std::thread::spawn(move || { let mut s = Vec::new(); let _ = std::io::Read::read_to_end(&mut out, &mut s); let _ = send.send((0, s)); });
    std::thread::spawn(move || { let mut s = Vec::new(); let _ = std::io::Read::read_to_end(&mut err, &mut s); let _ = send2.send((1, s)); });
    let until = std::time::Instant::now() + limit;
    let code = loop {
        match child.try_wait() {
            Ok(Some(s)) => break s.code().unwrap_or(-1),
            Ok(None) if std::time::Instant::now() < until => std::thread::sleep(std::time::Duration::from_millis(20)),
            _ => { let _ = child.kill(); let _ = child.wait(); return (-1, String::new(), String::new()); }
        }
    };
    let (mut stdout, mut stderr) = (Vec::new(), Vec::new());
    for _ in 0..2 {
        let left = until.saturating_duration_since(std::time::Instant::now());
        match receive.recv_timeout(left) {
            Ok((0, bytes)) => stdout = bytes,
            Ok((_, bytes)) => stderr = bytes,
            Err(_) => return (-1, String::new(), String::new()), // output still open at the limit: as a timeout
        }
    }
    (code, String::from_utf8_lossy(&stdout).into_owned(), String::from_utf8_lossy(&stderr).into_owned())
}

/// `psc system …`: prints one JSON value, returns the exit status.
pub fn main(args: &[String]) -> i32 {
    let sys = Sys { run: &real_run, proc: PathBuf::from("/proc") };
    let a: Vec<&str> = args.iter().map(String::as_str).collect();
    let flag = |name: &str| a.iter().position(|x| *x == name).and_then(|i| a.get(i + 1)).copied();
    let result = match a.as_slice() {
        ["network", iface] => network(&sys, iface),
        ["bluetooth"] => bluetooth(&sys),
        ["health", ..] => {
            let home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
            let path = std::env::var_os("PATH").unwrap_or_default();
            Value::Array(health(&sys, a.contains(&"--auth"), flag("--pid").and_then(|p| p.parse().ok()), flag("--sources").map(Path::new), &path, &home))
        }
        ["eject", device, disk, name, mountpoint] => eject(&sys, device, disk, name, mountpoint),
        _ => { eprintln!("Unknown operation"); return 1; }
    };
    println!("{result}");
    0
}

#[cfg(test)]
mod tests {
    //! The cases of the old tests/system.test.py: command and /proc boundaries only, never a device.
    use super::*;
    use std::cell::RefCell;

    fn sys<'a>(run: Run<'a>) -> Sys<'a> { Sys { run, proc: PathBuf::from("/nonexistent-proc") } }

    #[test]
    fn network_limits_reading_to_selected_wired_interface() {
        let run = |a: &[&str]| -> (i32, String, String) {
            let out = match a {
                ["ip", "-j", "address", ..] => r#"[{"ifname":"eth0","addr_info":[{"family":"inet","local":"192.0.2.4","prefixlen":24},{"family":"inet6","local":"2001:db8::4","prefixlen":64}]},{"ifname":"wlan9","addr_info":[{"family":"inet","local":"10.0.0.9","prefixlen":8}]}]"#,
                ["ip", "-j", "-4" | "-6", "route", ..] => r#"[{"gateway":"192.0.2.1"}]"#,
                ["nmcli", ..] => "192.0.2.53\n2001\\:db8\\:\\:53\nnot-an-address\n",
                _ => "[]",
            };
            (0, out.into(), String::new())
        };
        let r = network(&sys(&run), "eth0");
        assert_eq!(r["ipv4"], json!(["192.0.2.4/24"]));
        assert_eq!(r["ipv6"], json!(["2001:db8::4/64"]));
        assert_eq!(r["gateways"], json!(["192.0.2.1"]));
        assert_eq!(r["dns"], json!(["192.0.2.53", "2001:db8::53"]));
        assert_eq!(network(&sys(&run), "../etc"), json!({"ipv4": [], "ipv6": [], "gateways": [], "dns": []}));
    }

    #[test]
    fn diagnostics_only_publish_allowlisted_status_not_auth_output() {
        let secret = "secret-token /home/person/private 192.0.2.5 person@example.org";
        let run = |a: &[&str]| -> (i32, String, String) {
            if a[0] == "claude" { (0, format!("{{\"loggedIn\":true,\"email\":\"{secret}\"}}"), String::new()) } else { (0, secret.into(), String::new()) }
        };
        let bin = std::env::temp_dir().join(format!("psc-health-{}", std::process::id()));
        std::fs::create_dir_all(&bin).unwrap();
        for t in ["claude", "codex"] { std::fs::write(bin.join(t), "").unwrap(); }
        let report = health(&sys(&run), true, None, Some(&bin), bin.as_os_str(), &bin);
        let text = Value::Array(report.clone()).to_string();
        assert!(!text.contains(secret) && !text.contains("192.0.2.5"));
        let auth: Vec<&str> = report.iter().filter(|r| matches!(r["id"].as_str(), Some("claude-auth" | "codex-auth"))).map(|r| r["status"].as_str().unwrap()).collect();
        assert_eq!(auth, ["Signed in", "Signed in"]);
        assert_eq!(report[0]["id"], "shell");
        assert!(report.iter().any(|r| r["id"] == "qs" && r["detail"] == "Required"), "dependency rows come from doctor's list");
        for id in ["psc lens", "psc chat", "psc mic-check"] {
            assert!(report.iter().any(|row| row["id"] == id && row["status"] == "Present"), "{id} is in the running psc");
        }
        let _ = std::fs::remove_dir_all(bin);
    }

    #[test]
    fn drive_holders_resolve_fd_and_cwd_without_reading_files() {
        let base = std::env::temp_dir().join(format!("psc-holders-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let mount = base.join("mount");
        std::fs::create_dir_all(&mount).unwrap();
        std::fs::write(mount.join("secret"), "hidden").unwrap();
        let proc = base.join("proc");
        std::fs::create_dir_all(proc.join("44/fd")).unwrap();
        std::fs::write(proc.join("44/comm"), "editor\n").unwrap();
        std::os::unix::fs::symlink(mount.join("secret"), proc.join("44/fd/3")).unwrap();
        std::fs::create_dir_all(proc.join("45/fd")).unwrap();
        std::fs::write(proc.join("45/comm"), "terminal\n").unwrap();
        std::os::unix::fs::symlink(&mount, proc.join("45/cwd")).unwrap();
        std::fs::create_dir_all(proc.join("46/fd")).unwrap();
        std::fs::write(proc.join("46/comm"), "other\n").unwrap();
        assert_eq!(holders(mount.to_str().unwrap(), &proc), vec![json!({"pid": 44, "name": "editor"}), json!({"pid": 45, "name": "terminal"})]);
        assert!(holders("/", &proc).is_empty());
        let _ = std::fs::remove_dir_all(base);
    }

    #[test]
    fn recent_errors_are_bounded_and_raw_lines_never_escape() {
        let private = "email@example.org /home/person/private api-secret";
        let calls = RefCell::new(vec![]);
        let run = |a: &[&str]| -> (i32, String, String) {
            calls.borrow_mut().push(a.iter().map(|s| s.to_string()).collect::<Vec<_>>());
            (0, format!("  ERROR scene: {private}\n  WARN: harmless\n ERROR: second\n ERRORS are not a level\n"), String::new())
        };
        let row = shell_errors(&sys(&run), 123);
        assert_eq!(calls.borrow()[0], ["qs", "log", "--pid", "123", "--tail", "200", "--no-color"]);
        assert_eq!(row["status"], "2 recent errors");
        assert!(!row.to_string().contains(private));
    }

    #[test]
    fn bluetooth_details_use_active_card_and_node_sample_spec() {
        let run = |a: &[&str]| -> (i32, String, String) {
            let out = match a.last() {
                Some(&"cards") => r#"[{"name":"bluez_card.AA_BB_CC_DD_EE_FF","properties":{},"active_profile":"a2dp-sink"}]"#,
                Some(&"sinks") => r#"[{"properties":{"api.bluez5.address":"aa:bb:cc:dd:ee:ff","api.bluez5.codec":"aac"},"sample_specification":"float32le 2ch 48000Hz"}]"#,
                _ => "[]",
            };
            (0, out.into(), String::new())
        };
        assert_eq!(bluetooth(&sys(&run))["AA:BB:CC:DD:EE:FF"], json!({"profile": "a2dp-sink", "codec": "aac", "rate": "48000 Hz"}));
    }

    #[test]
    fn eject_never_powers_off_after_failed_unmount() {
        let calls = RefCell::new(vec![]);
        let run = |a: &[&str]| -> (i32, String, String) {
            calls.borrow_mut().push(a[1].to_string());
            if a[0] == "findmnt" { (0, r#"{"filesystems":[{"target":"/mnt/USB"}]}"#.into(), String::new()) } else { (1, "busy".into(), String::new()) }
        };
        let r = eject(&sys(&run), "/dev/sdz1", "/dev/sdz", "USB", "/mnt/USB");
        assert_eq!(r["ok"], false);
        assert!(!calls.borrow().iter().any(|c| c == "power-off"));
    }

    #[test]
    fn mount_probe_distinguishes_absence_from_failure() {
        let answer = |code: i32, out: &'static str, err: &'static str| move |_: &[&str]| -> (i32, String, String) { (code, out.into(), err.into()) };
        assert_eq!(device_mounted(&sys(&answer(1, "", "")), "/dev/sdz1"), Some(false));
        assert_eq!(device_mounted(&sys(&answer(1, "", "lookup failed")), "/dev/sdz1"), None);
        assert_eq!(device_mounted(&sys(&answer(0, r#"{"filesystems":[{"target":"/mnt/USB"}]}"#, "")), "/dev/sdz1"), Some(true));
        assert_eq!(device_mounted(&sys(&answer(0, "garbled", "")), "/dev/sdz1"), None);
    }

    #[test]
    fn eject_retries_poweroff_after_successful_unmount() {
        let answers = RefCell::new(vec![(0, ""), (1, "power-off failed"), (1, "not mounted"), (1, ""), (0, "")].into_iter());
        let calls = RefCell::new(vec![]);
        let run = |a: &[&str]| -> (i32, String, String) {
            calls.borrow_mut().push(a[1].to_string());
            let (c, o) = answers.borrow_mut().next().unwrap();
            (c, o.into(), String::new())
        };
        let s = sys(&run);
        let first = eject(&s, "/dev/sdz1", "/dev/sdz", "USB", "/mnt/USB");
        let second = eject(&s, "/dev/sdz1", "/dev/sdz", "USB", "/mnt/USB"); // unmount fails as it's gone, findmnt says absent
        assert_eq!((first["ok"].clone(), second["ok"].clone()), (json!(false), json!(true)));
        assert_eq!(calls.borrow().iter().filter(|c| *c == "power-off").count(), 2);
    }

    #[test]
    fn a_child_that_keeps_the_pipe_open_doesnt_hang() {
        // sh exits at once, but the background sleep keeps stdout open
        let began = std::time::Instant::now();
        let (code, out, _) = run_for(&["sh", "-c", "sleep 30 & echo hi"], std::time::Duration::from_secs(1));
        assert!(began.elapsed() < std::time::Duration::from_secs(5), "waited {:?}", began.elapsed());
        assert!(code == -1 || out.contains("hi"), "{code} {out}");
    }

    #[test]
    fn mount_probe_errors_do_not_authorise_poweroff() {
        let calls = RefCell::new(0);
        let run = |a: &[&str]| -> (i32, String, String) {
            if a[0] == "udisksctl" { *calls.borrow_mut() += 1; (1, "unmount failed".into(), String::new()) } else { (2, String::new(), "findmnt broke".into()) }
        };
        let r = eject(&sys(&run), "/dev/sdz1", "/dev/sdz", "USB", "/mnt/USB");
        assert_eq!((r["ok"].clone(), *calls.borrow()), (json!(false), 1));
    }
}
