//! LocalSend for the shell; services/LocalSend.qml runs it while the LocalSend app is installed.
//!
//! The shell is a LocalSend device of its own (protocol v2: https://github.com/localsend/protocol):
//! it finds devices by multicast on 224.0.0.167:53317 (asking every address on the network when
//! nobody answers), receives over HTTPS on port 53317 with its own certificate, and sends to the
//! devices it found. The LocalSend app can't run beside it, since both need that port. The
//! certificate is made once with openssl and kept, so the fingerprint other devices know stays.
//! JSON lines on stdout, commands on stdin:
//!
//!   out  {"event": "ready", "fingerprint": "…", "host": "arch"}
//!   out  {"event": "receive", "on": true, "busy": false}       busy: another program has the port
//!   out  {"event": "scan", "running": true}                    a scan began ("clear" before it) or ended
//!   out  {"event": "clear"}
//!   out  {"event": "device", "fingerprint", "alias", "model", "type", "ip", "port", "protocol"}
//!   out  {"event": "items", "items": [{"path", "name", "size", "count", "dir", "mime"}]}
//!   out  {"event": "paste", "paths": […]} or {"event": "paste", "text": "…"} or {"event": "paste"}
//!   out  {"event": "send", "state", "device", "done", "total", "speed", "files": [{"name", "size", "state"}]}
//!          state: waiting (for them to accept), sending, done, declined, busy, pin, failed, cancelled
//!   out  {"event": "request", "session", "from": {device}, "files": [{"name", "size", "mime"}], "total", "auto"}
//!   out  {"event": "message", "from": {device}, "text": "…"}
//!   out  {"event": "requestGone", "session"}                   the sender gave up before an answer
//!   out  {"event": "receiving", "session", "done", "total", "speed", "file", "index", "count"}
//!   out  {"event": "received", "session", "from", "folder", "paths": […]}
//!   out  {"event": "receiveFailed", "session", "from", "reason"}   reason: cancelled (by them), stopped (by you), lost
//!   in   {"cmd": "config", "alias", "folder", "acceptKnown", "known": [fingerprints]}
//!   in   {"cmd": "receive", "on": true}
//!   in   {"cmd": "scan", "legacy": true}
//!   in   {"cmd": "inspect", "paths": […]}
//!   in   {"cmd": "paste"}
//!   in   {"cmd": "send", "device": fingerprint, "paths": […], "text": "…"}
//!   in   {"cmd": "cancelSend"}
//!   in   {"cmd": "answer", "session", "accept": true}
//!   in   {"cmd": "cancelReceive"}
//!
//! It exits when stdin closes, so it never outlives the shell. --port and --data let
//! tests/localsend.sh run two of them side by side.

mod discovery;
mod files;
mod http;
mod receive;
mod send;

use std::collections::HashSet;
use std::io::{self, BufReader, Write};
use std::net::{SocketAddr, TcpStream, UdpSocket};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard};
use std::thread;
use std::time::{Duration, Instant};

use openssl::ssl::{SslAcceptor, SslConnector, SslFiletype, SslMethod, SslVerifyMode};
use pistachio_lines::{emit, log};
use serde_json::{json, Map, Value};

pub const MULTICAST_PORT: u16 = 53317;
pub const API: &str = "/api/localsend/v2";
pub const CHUNK: usize = 256 * 1024;

pub struct Config {
    pub alias: String,
    pub folder: PathBuf,
    pub accept_known: bool,
    pub known: HashSet<String>,
}

pub struct App {
    pub port: u16,
    pub fingerprint: String,
    pub host: String,
    pub acceptor: SslAcceptor,
    pub connector: SslConnector,
    pub udp: Option<UdpSocket>,
    pub config: Mutex<Config>,
    pub devices: Mutex<Map<String, Value>>, // fingerprint -> device
    pub server: Mutex<Option<receive::Server>>,
    pub session: Mutex<Option<Arc<receive::Session>>>, // the transfer being received, or the request waiting for an answer
    pub job: Mutex<Option<Arc<send::Job>>>,            // the transfer being sent
}

/// A lock that a panicked thread held is still ours to use: one failed transfer must not end the
/// helper.
pub fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// As Python reads a value in a condition: null, false, 0, "" and empty lists and objects are no.
pub fn truthy(value: &Value) -> bool {
    match value {
        Value::Null => false,
        Value::Bool(b) => *b,
        Value::Number(n) => n.as_f64() != Some(0.0),
        Value::String(s) => !s.is_empty(),
        Value::Array(a) => !a.is_empty(),
        Value::Object(o) => !o.is_empty(),
    }
}

/// A value as text, or `default` when it says nothing.
pub fn text_or(value: &Value, default: &str) -> String {
    match value {
        Value::String(s) if !s.is_empty() => s.clone(),
        other if truthy(other) => other.to_string(),
        _ => default.to_string(),
    }
}

/// How much of a transfer is done and how fast it goes, told at most every 0.12 s.
pub struct Progress {
    reported: Option<Instant>,
    mark: (Instant, u64),
    pub speed: f64,
}

impl Default for Progress {
    fn default() -> Self {
        Progress { reported: None, mark: (Instant::now(), 0), speed: 0.0 }
    }
}

impl Progress {

    /// Whether to report now; the speed is brought up to date first.
    pub fn due(&mut self, done: u64, force: bool) -> bool {
        let now = Instant::now();
        if !force && self.reported.is_some_and(|then| now.duration_since(then) < Duration::from_millis(120)) {
            return false;
        }
        let (then, before) = self.mark;
        let since = now.duration_since(then).as_secs_f64();
        if since >= 0.5 {
            let rate = done.saturating_sub(before) as f64 / since;
            self.speed = if self.speed == 0.0 { rate } else { 0.6 * self.speed + 0.4 * rate };
            self.mark = (now, done);
        }
        self.reported = Some(now);
        true
    }
}

pub fn random_hex(bytes: usize) -> String {
    let mut buffer = vec![0u8; bytes];
    openssl::rand::rand_bytes(&mut buffer).expect("the system's random numbers");
    buffer.iter().map(|b| format!("{b:02x}")).collect()
}

fn host_name() -> String {
    let mut buffer = [0u8; 256];
    // SAFETY: the buffer is ours and its length is given
    if unsafe { libc::gethostname(buffer.as_mut_ptr().cast(), buffer.len()) } != 0 {
        return "localhost".into();
    }
    String::from_utf8_lossy(buffer.split(|b| *b == 0).next().unwrap_or_default()).into_owned()
}

fn other(error: impl std::fmt::Display) -> io::Error {
    io::Error::other(error.to_string())
}

/// The certificate and key in `folder`, made once; the fingerprint is the certificate's SHA-256.
fn certificate(folder: &Path) -> io::Result<(PathBuf, PathBuf, String)> {
    use std::os::unix::fs::{DirBuilderExt, PermissionsExt};
    std::fs::DirBuilder::new().recursive(true).mode(0o700).create(folder)?;
    let (cert, key) = (folder.join("cert.pem"), folder.join("key.pem"));
    if !(cert.exists() && key.exists()) {
        let made = std::process::Command::new("openssl")
            .args(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout"])
            .arg(&key)
            .arg("-out")
            .arg(&cert)
            .args(["-days", "3650", "-subj", "/CN=LocalSend User"])
            .output()?;
        if !made.status.success() {
            return Err(other(format!("openssl could not make the certificate: {}", String::from_utf8_lossy(&made.stderr).trim())));
        }
        std::fs::set_permissions(&key, std::fs::Permissions::from_mode(0o600))?;
    }
    let der = openssl::x509::X509::from_pem(&std::fs::read(&cert)?).and_then(|c| c.to_der()).map_err(other)?;
    let fingerprint = openssl::sha::sha256(&der).iter().map(|b| format!("{b:02X}")).collect();
    Ok((cert, key, fingerprint))
}

impl App {
    /// What this device says of itself.
    pub fn info(&self) -> Value {
        json!({"alias": lock(&self.config).alias, "version": "2.1", "deviceModel": "Linux", "deviceType": "desktop",
               "fingerprint": self.fingerprint, "port": self.port, "protocol": "https", "download": false})
    }

    /// A device from what it says of itself and the address it spoke from.
    pub fn device(data: &Value, ip: &str) -> Value {
        let port = match &data["port"] {
            Value::Number(n) => n.as_u64(),
            Value::String(s) => s.parse().ok(),
            _ => None,
        }
        .filter(|port| (1..=65535).contains(port)); // anything else: the usual port
        json!({"fingerprint": text_or(&data["fingerprint"], ""), "alias": text_or(&data["alias"], "Unknown device"),
               "model": text_or(&data["deviceModel"], ""), "type": text_or(&data["deviceType"], "desktop"), "ip": ip,
               "port": port.unwrap_or(MULTICAST_PORT as u64), "protocol": if data["protocol"] == "http" { "http" } else { "https" }})
    }

    /// Notes a device that showed itself, and tells the shell when it's new or changed.
    pub fn seen(&self, data: &Value, ip: &str) {
        let device = App::device(data, ip);
        let fingerprint = device["fingerprint"].as_str().unwrap_or_default().to_string();
        if fingerprint.is_empty() || fingerprint == self.fingerprint {
            return;
        }
        {
            let mut devices = lock(&self.devices);
            if devices.get(&fingerprint) == Some(&device) {
                return;
            }
            devices.insert(fingerprint, device.clone());
        }
        let mut event = json!({"event": "device"});
        event.as_object_mut().expect("an object").extend(device.as_object().cloned().unwrap_or_default());
        emit(&event);
    }

    /// Connects to a device. With a timeout it also bounds every read and write. The second
    /// stream is the same connection, for ending it from another thread.
    pub fn connect(&self, device: &Value, timeout: Option<Duration>) -> io::Result<(http::Stream, TcpStream)> {
        let ip = device["ip"].as_str().unwrap_or_default();
        let port = device["port"].as_u64().unwrap_or(MULTICAST_PORT as u64) as u16;
        let address: SocketAddr = format!("{ip}:{port}").parse().map_err(other)?;
        let tcp = match timeout {
            Some(limit) => TcpStream::connect_timeout(&address, limit)?,
            None => TcpStream::connect(address)?,
        };
        tcp.set_read_timeout(timeout)?;
        tcp.set_write_timeout(timeout)?;
        let handle = tcp.try_clone()?;
        if device["protocol"] == "http" {
            return Ok((http::Stream::Plain(tcp), handle));
        }
        // LocalSend devices use self-made certificates: nothing to check them against
        let tls = self.connector.configure().map_err(other)?.verify_hostname(false).use_server_name_indication(false).connect("localsend", tcp).map_err(other)?;
        Ok((http::Stream::Tls(Box::new(tls)), handle))
    }

    /// One POST to a device's LocalSend API: the status and body of its answer.
    pub fn call(&self, device: &Value, path: &str, body: Option<&Value>, query: &[(&str, &str)], timeout: Duration) -> io::Result<(u16, Vec<u8>)> {
        let (stream, _) = self.connect(device, Some(timeout))?;
        let mut stream = BufReader::new(stream);
        let data = body.map(|b| b.to_string().into_bytes()).unwrap_or_default();
        let target = if query.is_empty() { format!("{API}{path}") } else { format!("{API}{path}?{}", http::encode_query(query)) };
        http::write_request(stream.get_mut(), &target, &host_of(device), "application/json", data.len() as u64)?;
        stream.get_mut().write_all(&data)?;
        stream.get_mut().flush()?;
        http::read_response(&mut stream)
    }

    fn handle(self: &Arc<Self>, message: &Value) {
        let list = |value: &Value| -> Vec<String> { value.as_array().map(|a| a.iter().map(|v| text_or(v, "")).collect()).unwrap_or_default() };
        match message["cmd"].as_str().unwrap_or_default() {
            "config" => {
                let mut config = lock(&self.config);
                config.alias = text_or(&message["alias"], &self.host);
                let folder = text_or(&message["folder"], "~/Downloads");
                let home = std::env::var("HOME").unwrap_or_default();
                config.folder = match folder.strip_prefix('~') {
                    Some(rest) if rest.is_empty() || rest.starts_with('/') => PathBuf::from(format!("{home}{rest}")),
                    _ => PathBuf::from(folder),
                };
                config.accept_known = truthy(&message["acceptKnown"]);
                config.known = list(&message["known"]).into_iter().collect();
            }
            "receive" => receive::set_receive(self, truthy(&message["on"])),
            "scan" => {
                let (app, legacy) = (Arc::clone(self), message.get("legacy").is_none_or(truthy));
                thread::spawn(move || discovery::scan(&app, legacy));
            }
            "inspect" => {
                let paths = list(&message["paths"]);
                thread::spawn(move || emit(&files::inspect(&paths)));
            }
            "paste" => {
                thread::spawn(|| emit(&files::paste()));
            }
            "send" => send::start(self, message["device"].as_str().unwrap_or_default(), &list(&message["paths"]), message["text"].as_str().unwrap_or_default()),
            "cancelSend" => send::cancel(self),
            "answer" => receive::answer(self, message["session"].as_str().unwrap_or_default(), truthy(&message["accept"])),
            "cancelReceive" => receive::cancel(self),
            _ => {}
        }
    }
}

/// "ip:port", for the Host header.
pub fn host_of(device: &Value) -> String {
    format!("{}:{}", device["ip"].as_str().unwrap_or_default(), device["port"].as_u64().unwrap_or(MULTICAST_PORT as u64))
}

fn start() -> io::Result<Arc<App>> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let value = |name: &str| args.iter().position(|a| a == name).and_then(|i| args.get(i + 1)).cloned();
    let port = match value("--port") {
        Some(port) => port.parse().map_err(|_| other("--port takes a number"))?,
        None => MULTICAST_PORT,
    };
    let data = value("--data").map(PathBuf::from).unwrap_or_else(|| {
        let share = std::env::var("XDG_DATA_HOME").ok().filter(|d| !d.is_empty()).unwrap_or_else(|| format!("{}/.local/share", std::env::var("HOME").unwrap_or_default()));
        PathBuf::from(share).join("pistachio-shell").join("localsend")
    });
    let (cert, key, fingerprint) = certificate(&data)?;
    let mut acceptor = SslAcceptor::mozilla_intermediate_v5(SslMethod::tls()).map_err(other)?;
    acceptor.set_certificate_chain_file(&cert).map_err(other)?;
    acceptor.set_private_key_file(&key, SslFiletype::PEM).map_err(other)?;
    let mut connector = SslConnector::builder(SslMethod::tls()).map_err(other)?;
    connector.set_verify(SslVerifyMode::NONE);
    connector.set_certificate_chain_file(&cert).map_err(other)?;
    connector.set_private_key_file(&key, SslFiletype::PEM).map_err(other)?;
    let udp = match discovery::open_multicast() {
        Ok(udp) => Some(udp),
        Err(e) => {
            log(&format!("no multicast, devices are found by asking every address: {e}"));
            None
        }
    };
    let host = host_name();
    let home = std::env::var("HOME").unwrap_or_default();
    Ok(Arc::new(App {
        port,
        fingerprint,
        acceptor: acceptor.build(),
        connector: connector.build(),
        udp,
        config: Mutex::new(Config { alias: host.clone(), folder: PathBuf::from(format!("{home}/Downloads")), accept_known: false, known: HashSet::new() }),
        host,
        devices: Mutex::default(),
        server: Mutex::default(),
        session: Mutex::default(),
        job: Mutex::default(),
    }))
}

fn main() {
    pistachio_lines::die_with_parent();
    // a device that goes away mid-write must not end the helper
    // SAFETY: ignoring a signal changes no memory of ours
    unsafe {
        libc::signal(libc::SIGPIPE, libc::SIG_IGN);
    }
    let app = match start() {
        Ok(app) => app,
        Err(e) => {
            log(&format!("could not start: {e}"));
            std::process::exit(1);
        }
    };
    if app.udp.is_some() {
        let listener = Arc::clone(&app);
        thread::spawn(move || discovery::listen(&listener));
    }
    emit(&json!({"event": "ready", "fingerprint": app.fingerprint, "host": app.host}));
    pistachio_lines::read_lines(|line| match serde_json::from_str::<Value>(line) {
        Ok(message) if message.is_object() => app.handle(&message),
        _ => log(&format!("bad command: {}", line.trim())),
    });
    receive::set_receive(&app, false);
    std::process::exit(0);
}
