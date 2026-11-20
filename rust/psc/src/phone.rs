//! `psc phone-timer`: the phone view of a Focus/Pomodoro session (services/FocusMode.qml).
//! Python's phone-timer.py until 19 November 2026: timer state arrives as JSON lines on stdin (a
//! heartbeat each second); prints one line {url, qr, qrError} or {error}. Serves GET / and /state,
//! and POST /pause, /skip, /end (owner's request, 20 November 2026: no key, a home network), only to
//! the local network's own subnet; each POST prints {"action": …} for FocusMode to carry out. /state
//! is 503 when the last update is over 5 s old. EOF or SIGTERM stops it and removes the QR image.
use serde_json::{json, Value};
use std::io::{BufRead, Read, Write};
use std::net::{IpAddr, Ipv4Addr, TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const PAGE: &[u8] = include_bytes!("phone.html");

/// The shell's colours the page may use (Theme names; accent is pistachio, danger terracotta).
const COLOURS: [&str; 10] = ["bg", "bgAlt", "overlay", "overlay2", "subtext", "text", "textBright", "accent", "teal", "danger"];

struct Shared {
    state: Option<Value>,
    updated: Instant,
}

/// The first private IPv4 address on a wired or wireless interface (en*, eth*, wl*), from
/// `ip -j -4 address show up scope global`: works on networks with no default route too.
pub fn pick_address(ip_json: &str) -> Result<(Ipv4Addr, u8), String> {
    let entries: Value = serde_json::from_str(ip_json).map_err(|_| "Cannot discover a local network address".to_string())?;
    let private = |ip: Ipv4Addr| { let o = ip.octets(); o[0] == 10 || (o[0] == 172 && (16..32).contains(&o[1])) || (o[0] == 192 && o[1] == 168) };
    for entry in entries.as_array().map(Vec::as_slice).unwrap_or(&[]) {
        let name = entry["ifname"].as_str().unwrap_or("");
        if !["en", "eth", "wl"].iter().any(|p| name.starts_with(p)) { continue; }
        for info in entry["addr_info"].as_array().map(Vec::as_slice).unwrap_or(&[]) {
            let (Some(ip), Some(prefix)) = (info["local"].as_str().and_then(|s| s.parse::<Ipv4Addr>().ok()), info["prefixlen"].as_u64()) else { continue };
            if private(ip) { return Ok((ip, prefix.min(32) as u8)); }
        }
    }
    Err("No private wired or wireless network address is available".into())
}

fn local_address() -> Result<(Ipv4Addr, u8), String> {
    if let Some(test) = std::env::var("PSC_PHONE_TEST_ADDRESS").ok().filter(|v| !v.is_empty()) {
        // tests only: serve on this address instead of the LAN's (tests/phone-timer.test.py)
        let (ip, prefix) = test.split_once('/').unwrap_or((&test, "32"));
        return Ok((ip.parse().map_err(|_| "bad PSC_PHONE_TEST_ADDRESS")?, prefix.parse().unwrap_or(32)));
    }
    let (code, out, _) = crate::system::run_for(&["ip", "-j", "-4", "address", "show", "up", "scope", "global"], Duration::from_secs(3));
    if code != 0 { return Err("Cannot discover a local network address".into()); }
    pick_address(&out)
}

fn in_network(client: IpAddr, net: Ipv4Addr, prefix: u8) -> bool {
    let IpAddr::V4(client) = client else { return false };
    let mask = if prefix == 0 { 0 } else { u32::MAX << (32 - prefix as u32) };
    u32::from(client) & mask == u32::from(net) & mask
}

fn reply(stream: &mut TcpStream, status: u16, kind: &str, body: &[u8]) {
    let reason = match status { 200 => "OK", 204 => "No Content", 403 => "Forbidden", 404 => "Not Found", 405 => "Method Not Allowed", 501 => "Not Implemented", _ => "Service Unavailable" };
    let head = format!("HTTP/1.1 {status} {reason}\r\nContent-Type: {kind}\r\nCache-Control: no-store\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", body.len());
    let _ = stream.write_all(head.as_bytes());
    let _ = stream.write_all(body);
}

fn serve(mut stream: TcpStream, shared: Arc<Mutex<Shared>>, net: Ipv4Addr, prefix: u8) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));
    let mut head = Vec::new();
    let mut byte = [0u8; 1];
    while !head.ends_with(b"\r\n\r\n") && head.len() < 8192 {
        match stream.read(&mut byte) { Ok(1) => head.push(byte[0]), _ => return }
    }
    let text = String::from_utf8_lossy(&head);
    let mut first = text.lines().next().unwrap_or("").split_whitespace();
    let (method, path) = (first.next().unwrap_or(""), first.next().unwrap_or(""));
    // read a small body away (none is used), so closing doesn't reset the connection under the reply
    let length = text.lines().find_map(|l| l.split_once(':').filter(|(k, _)| k.eq_ignore_ascii_case("content-length")).and_then(|(_, v)| v.trim().parse::<usize>().ok())).unwrap_or(0);
    if length > 0 && length <= 8192 { let mut body = vec![0u8; length]; let _ = stream.read_exact(&mut body); }
    let allowed = stream.peer_addr().map(|a| in_network(a.ip(), net, prefix)).unwrap_or(false);
    match (method, path) {
        (_, _) if !allowed => reply(&mut stream, 403, "text/plain", b"Forbidden"),
        ("GET", "/") => reply(&mut stream, 200, "text/html; charset=utf-8", PAGE),
        ("GET", "/state") => {
            let state = {
                let s = shared.lock().unwrap();
                s.state.clone().filter(|_| s.updated.elapsed() < Duration::from_secs(5))
            };
            match state {
                Some(mut v) => {
                    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0);
                    v["serverNow"] = json!(now);
                    reply(&mut stream, 200, "application/json", v.to_string().as_bytes());
                }
                None => reply(&mut stream, 503, "application/json", b"null"),
            }
        }
        ("GET", _) => reply(&mut stream, 404, "text/plain", b"Not Found"),
        ("POST", "/pause" | "/skip" | "/end") => {
            {
                let mut out = std::io::stdout().lock();
                let _ = writeln!(out, "{}", json!({"action": &path[1..]}));
                let _ = out.flush();
            }
            reply(&mut stream, 204, "text/plain", b"");
        }
        ("POST", _) => reply(&mut stream, 404, "text/plain", b"Not Found"),
        _ => reply(&mut stream, 501, "text/plain", b"Not Implemented"),
    }
}

/// The QR image's path, for the SIGTERM handler (unlink and _exit are safe inside a handler).
static mut QR: [u8; 512] = [0; 512];

extern "C" fn term(_: libc::c_int) {
    unsafe {
        let qr = std::ptr::addr_of!(QR) as *const libc::c_char;
        if *qr != 0 { libc::unlink(qr); }
        libc::_exit(0);
    }
}

pub fn main(_args: &[String]) -> i32 {
    unsafe { libc::signal(libc::SIGTERM, term as extern "C" fn(libc::c_int) as libc::sighandler_t) };
    let fail = |e: String| { println!("{}", json!({"error": e})); 0 };
    let (address, prefix) = match local_address() { Ok(a) => a, Err(e) => return fail(e) };
    let listener = match TcpListener::bind((address, 0)) { Ok(l) => l, Err(e) => return fail(e.to_string()) };
    let port = listener.local_addr().map(|a| a.port()).unwrap_or(0);
    let url = format!("http://{address}:{port}/");
    let runtime = std::env::var_os("XDG_RUNTIME_DIR").map(std::path::PathBuf::from).unwrap_or_else(std::env::temp_dir);
    let qr = runtime.join(format!("pistachio-phone-{}.png", std::process::id()));
    let made = std::process::Command::new("qrencode").args(["-o"]).arg(&qr).args(["-s", "6", &url])
        .stdout(std::process::Stdio::null()).stderr(std::process::Stdio::null()).status().map(|s| s.success()).unwrap_or(false);
    let qr = if made && qr.is_file() {
        let bytes = qr.as_os_str().as_encoded_bytes();
        if bytes.len() < 511 { unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), std::ptr::addr_of_mut!(QR) as *mut u8, bytes.len()); } }
        Some(qr)
    } else {
        let _ = std::fs::remove_file(&qr);
        None
    };
    println!("{}", json!({"url": url, "qr": qr.as_ref().map(|q| q.to_string_lossy().into_owned()).unwrap_or_default(),
        "qrError": if qr.is_some() { "" } else { "QR code unavailable; use the address below." }}));
    let _ = std::io::stdout().flush();
    let shared = Arc::new(Mutex::new(Shared { state: None, updated: Instant::now() }));
    let server = shared.clone();
    std::thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            let s = server.clone();
            std::thread::spawn(move || serve(stream, s, address, prefix));
        }
    });
    for line in std::io::stdin().lock().lines().map_while(Result::ok) {
        let Ok(v) = serde_json::from_str::<Value>(&line) else { continue };
        if !["phase", "endsAt", "left", "paused"].iter().all(|k| v.get(*k).is_some()) { continue; }
        let mut state = serde_json::Map::new();
        for k in ["phase", "endsAt", "left", "paused"] { state.insert(k.into(), v[k].clone()); }
        for k in COLOURS { state.insert(k.into(), v.get(k).cloned().filter(Value::is_string).unwrap_or(json!(""))); }
        for k in ["length", "pomodoro", "working"] { if let Some(x) = v.get(k) { state.insert(k.into(), x.clone()); } }
        let mut s = shared.lock().unwrap();
        s.state = Some(Value::Object(state));
        s.updated = Instant::now();
    }
    if let Some(qr) = qr { let _ = std::fs::remove_file(qr); }
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn address_without_default_route() {
        let ip = r#"[{"ifname":"tailscale0","addr_info":[{"local":"100.64.0.5","prefixlen":32}]},{"ifname":"eno1","addr_info":[{"local":"192.168.4.7","prefixlen":24}]}]"#;
        assert_eq!(pick_address(ip), Ok(("192.168.4.7".parse().unwrap(), 24)));
        assert!(pick_address(r#"[{"ifname":"eth0","addr_info":[{"local":"8.8.8.8","prefixlen":24}]}]"#).is_err());
        assert!(in_network("192.168.4.20".parse().unwrap(), "192.168.4.7".parse().unwrap(), 24));
        assert!(!in_network("192.168.5.20".parse().unwrap(), "192.168.4.7".parse().unwrap(), 24));
    }
}
