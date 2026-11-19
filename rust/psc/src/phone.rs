//! `psc phone-timer`: the read-only phone view of a Focus/Pomodoro session (services/FocusMode.qml).
//! Python's phone-timer.py until 19 November 2026; same protocol: timer state arrives as JSON lines
//! on stdin (a heartbeat each second); prints one line {url, qr, qrError} or {error}. Serves only GET
//! / and /state to the local network's own subnet; /state is 503 when the last update is over 5 s
//! old. EOF or SIGTERM stops it and removes the temporary QR image.
use serde_json::{json, Value};
use std::io::{BufRead, Read, Write};
use std::net::{IpAddr, Ipv4Addr, TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const PAGE: &[u8] = br#"<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Focus timer</title><style>body{background:Canvas;color:CanvasText;font:18px sans-serif;text-align:center;margin:20vh 1rem}h1{font-size:1.5rem}#countdown{font-size:5rem}</style></head><body><h1 id="phase">Connecting...</h1><div id="countdown">--:--</div><p id="status"></p><script>let state=null,last=0;async function refresh(){try{let r=await fetch('/state',{cache:'no-store'});if(!r.ok)throw 0;state=await r.json();last=performance.now();document.body.style.background=state.bg;document.body.style.color=state.text;document.getElementById("countdown").style.color=state.accent}catch(e){}}function draw(){if(!state||performance.now()-last>5000){document.getElementById('status').textContent='Connection lost';return}let ms=state.paused?state.left:Math.max(0,state.endsAt-state.serverNow-(performance.now()-last));let s=Math.ceil(ms/1000),h=Math.floor(s/3600),m=Math.floor(s%3600/60),sec=s%60;document.getElementById('phase').textContent=state.phase;document.getElementById('countdown').textContent=(h?h+':'+String(m).padStart(2,'0'):m)+':'+String(sec).padStart(2,'0');document.getElementById('status').textContent=state.paused?'Paused':''}refresh();setInterval(refresh,1500);setInterval(draw,250)</script></body></html>"#;

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
    let reason = match status { 200 => "OK", 403 => "Forbidden", 404 => "Not Found", 405 => "Method Not Allowed", 501 => "Not Implemented", _ => "Service Unavailable" };
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
    let allowed = stream.peer_addr().map(|a| in_network(a.ip(), net, prefix)).unwrap_or(false);
    match (method, path) {
        ("GET", _) if !allowed => reply(&mut stream, 403, "text/plain", b"Forbidden"),
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
        ("POST", _) => reply(&mut stream, 405, "text/plain", b"Method Not Allowed"),
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
        for k in ["bg", "text", "accent"] { state.insert(k.into(), v.get(k).cloned().unwrap_or(json!(""))); }
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
