//! Receiving: the HTTPS server other devices talk to while Receive is on.

use std::io::{self, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::os::fd::AsRawFd;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use openssl::ssl::SslStream;
use pistachio_lines::emit;
use serde_json::{json, Map, Value};

use crate::{discovery, files, http, lock, random_hex, App, Progress, API, CHUNK};

const TIMEOUT: Duration = Duration::from_secs(60);
/// How long a request waits for the owner's answer.
const PATIENCE: Duration = Duration::from_secs(600);
/// The most of an unwanted request body that is read away to keep the connection.
const UNREAD: u64 = 1024 * 1024;

pub struct Server {
    listener: Arc<TcpListener>,
    accepting: JoinHandle<()>,
    stopping: Arc<AtomicBool>,
}

/// The most connections served at once: a transfer uses a few, and a device on the network must
/// not be able to start threads without end.
const MAX_CONNECTIONS: usize = 64;

/// Counts something going on, until it's dropped.
pub struct Slot(Arc<AtomicUsize>);

impl Slot {
    /// A slot, unless `limit` are taken.
    pub fn take(count: &Arc<AtomicUsize>, limit: usize) -> Option<Slot> {
        count.try_update(Ordering::SeqCst, Ordering::SeqCst, |n| (n < limit).then_some(n + 1)).ok().map(|_| Slot(Arc::clone(count)))
    }
}

impl Drop for Slot {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::SeqCst);
    }
}

struct FileIn {
    key: String,
    name: String,
    size: u64,
    mime: String,
    preview: Value,
    token: Option<String>,
    started: bool,
    finished: bool,
}

struct State {
    files: Vec<FileIn>, // in the sender's order
    answered: bool,
    accepted: bool,
    cancelled: bool,
    gone: bool,
    done: u64,
    current: String,
    saved: Vec<String>,
    progress: Progress,
}

/// A transfer being received, or a request waiting for the owner's answer.
pub struct Session {
    id: String,
    sender: Value,
    total: u64,
    state: Mutex<State>,
    answer: Condvar,
}

impl Session {
    fn report(&self, force: bool) {
        let mut state = lock(&self.state);
        let done = state.done;
        if !state.progress.due(done, force) {
            return;
        }
        let finished = state.files.iter().filter(|f| f.finished).count();
        let event = json!({"event": "receiving", "session": self.id, "done": done, "total": self.total, "speed": state.progress.speed.round() as u64,
                           "file": state.current, "index": (finished + 1).min(state.files.len()), "count": state.files.len()});
        drop(state);
        emit(&event);
    }

    fn settle(&self, change: impl FnOnce(&mut State)) {
        let mut state = lock(&self.state);
        change(&mut state);
        state.answered = true;
        drop(state);
        self.answer.notify_all();
    }
}

/// Ends the session, if it is still the one going on, and tells the shell how.
fn end(app: &App, session: &Arc<Session>, event: &str, extra: Value) {
    {
        let mut current = lock(&app.session);
        if !current.as_ref().is_some_and(|c| Arc::ptr_eq(c, session)) {
            return;
        }
        *current = None;
    }
    let mut message = json!({"event": event, "session": session.id});
    message.as_object_mut().expect("an object").extend(extra.as_object().cloned().unwrap_or_default());
    emit(&message);
}

/// One connection from a device, and the request on it being answered.
struct Conn {
    stream: BufReader<SslStream<TcpStream>>,
    socket: TcpStream, // the same connection, to see whether the other side is still there
    ip: String,
    left: u64,   // of the request's body, not read yet
    close: bool, // don't wait for another request on it
}

/// The request can't be understood: answered 400.
struct Bad;

impl Conn {
    fn reply(&mut self, status: u16, body: Option<&Value>) {
        if http::write_response(self.stream.get_mut(), status, body).is_err() {
            self.close = true;
        }
    }

    fn json_body(&mut self) -> Result<Value, Bad> {
        if self.left > 4 * 1024 * 1024 {
            return Err(Bad);
        }
        let mut data = vec![0u8; self.left as usize];
        self.stream.read_exact(&mut data).map_err(|_| Bad)?;
        self.left = 0;
        if data.is_empty() {
            return Ok(json!({}));
        }
        serde_json::from_slice(&data).map_err(|_| Bad)
    }

    /// Whether the other side closed the connection while it waits for an answer.
    fn peer_gone(&mut self) -> bool {
        let _ = self.socket.set_nonblocking(true);
        let waiting = self.socket.peek(&mut [0u8; 1]);
        let _ = self.socket.set_nonblocking(false);
        match waiting {
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => false,
            Err(_) | Ok(0) => true,
            Ok(_) => {
                // something came: a goodbye, as TLS says it, reads as the end
                let _ = self.socket.set_read_timeout(Some(Duration::from_millis(200)));
                let read = self.stream.get_mut().read(&mut [0u8; 1]);
                let _ = self.socket.set_read_timeout(Some(TIMEOUT));
                match read {
                    Ok(0) => true,
                    Ok(_) => false,
                    Err(e) => !matches!(e.kind(), io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut),
                }
            }
        }
    }
}

fn serve(app: &Arc<App>, tcp: TcpStream, ip: String) {
    if tcp.set_read_timeout(Some(TIMEOUT)).is_err() || tcp.set_write_timeout(Some(TIMEOUT)).is_err() {
        return;
    }
    let Ok(socket) = tcp.try_clone() else { return };
    let Ok(tls) = app.acceptor.accept(tcp) else { return }; // a failed handshake; nothing to tell
    let mut conn = Conn { stream: BufReader::with_capacity(64 * 1024, tls), socket, ip, left: 0, close: false };
    while let Ok(Some(head)) = http::read_request(&mut conn.stream) {
        conn.left = head.length().unwrap_or(0);
        route(app, &mut conn, &head);
        // A body nobody read (a refused upload) would be taken for the next request, and closing
        // on it unread resets the connection before the sender has our answer: a small one is
        // read away, a large one ends the connection.
        if !conn.close && conn.left > 0 && conn.left <= UNREAD {
            let unread = conn.left;
            if io::copy(&mut conn.stream.by_ref().take(unread), &mut io::sink()).is_ok_and(|read| read == unread) {
                conn.left = 0;
            }
        }
        if conn.close || conn.left > 0 || !head.keep_alive {
            break;
        }
    }
    let _ = conn.stream.get_mut().shutdown();
}

fn route(app: &Arc<App>, conn: &mut Conn, head: &http::Head) {
    let path = head.path.strip_prefix(API).unwrap_or_default();
    let handled = match (head.method.as_str(), path) {
        ("GET", "/info") => {
            conn.reply(200, Some(&app.info()));
            Ok(())
        }
        ("GET", _) => {
            conn.reply(404, None);
            Ok(())
        }
        ("POST", "/register") => conn.json_body().and_then(|body| if body.is_object() { Ok(body) } else { Err(Bad) }).map(|body| {
            app.seen(&body, &conn.ip.clone());
            conn.reply(200, Some(&app.info()));
        }),
        ("POST", "/prepare-upload") => conn.json_body().and_then(|body| prepare(app, conn, &body)),
        ("POST", "/upload") => {
            upload(app, conn, head);
            Ok(())
        }
        ("POST", "/cancel") => {
            cancelled_by_sender(app, conn, head);
            Ok(())
        }
        ("POST", _) => {
            conn.reply(404, None);
            Ok(())
        }
        _ => {
            conn.reply(501, None);
            Ok(())
        }
    };
    if handled.is_err() {
        conn.reply(400, None);
    }
}

/// A file as the sender describes it.
fn described(key: &str, file: &Value) -> Result<FileIn, Bad> {
    let file = file.as_object().ok_or(Bad)?;
    let get = |name: &str| file.get(name).unwrap_or(&Value::Null);
    let text = |value: &Value| match value {
        Value::String(s) => s.clone(),
        other => other.to_string(),
    };
    let size = match get("size") {
        Value::Number(n) => n.as_u64().or_else(|| n.as_f64().filter(|f| *f >= 0.0).map(|f| f as u64)).ok_or(Bad)?,
        Value::String(s) if !s.is_empty() => s.trim().parse().map_err(|_| Bad)?,
        Value::Null | Value::String(_) | Value::Bool(false) => 0,
        _ => return Err(Bad),
    };
    Ok(FileIn {
        key: if crate::truthy(get("id")) { text(get("id")) } else { key.to_string() },
        name: text(file.get("fileName").ok_or(Bad)?),
        size,
        mime: if crate::truthy(get("fileType")) { text(get("fileType")) } else { String::new() },
        preview: get("preview").clone(),
        token: None,
        started: false,
        finished: false,
    })
}

/// A device asks to send: a text is shown at once, files wait for the owner's answer.
fn prepare(app: &Arc<App>, conn: &mut Conn, body: &Value) -> Result<(), Bad> {
    if !body["info"].is_object() {
        return Err(Bad);
    }
    let sender = App::device(&body["info"], &conn.ip);
    let mut files: Vec<FileIn> = Vec::new();
    for (key, file) in body["files"].as_object().ok_or(Bad)? {
        let file = described(key, file)?;
        match files.iter_mut().find(|f| f.key == file.key) {
            Some(same) => *same = file,
            None => files.push(file),
        }
    }
    if files.is_empty() {
        return Err(Bad);
    }
    if let ([only], Value::String(text)) = (files.as_slice(), &files[0].preview) {
        if only.mime.starts_with("text/") {
            emit(&json!({"event": "message", "from": sender, "text": text}));
            conn.reply(204, None);
            return Ok(());
        }
    }
    let listed: Vec<Value> = files.iter().map(|f| json!({"name": f.name, "size": f.size, "mime": f.mime})).collect();
    let total = files.iter().fold(0u64, |sum, f| sum.saturating_add(f.size));
    let session = {
        let mut current = lock(&app.session);
        if current.is_some() {
            drop(current);
            conn.reply(409, None);
            return Ok(());
        }
        let state = State { files, answered: false, accepted: false, cancelled: false, gone: false, done: 0, current: String::new(), saved: Vec::new(), progress: Progress::default() };
        let session = Arc::new(Session { id: random_hex(8), sender: sender.clone(), total, state: Mutex::new(state), answer: Condvar::new() });
        *current = Some(Arc::clone(&session));
        session
    };
    let auto = {
        let config = lock(&app.config);
        config.accept_known && config.known.contains(sender["fingerprint"].as_str().unwrap_or_default())
    };
    emit(&json!({"event": "request", "session": session.id, "files": listed, "total": total, "auto": auto, "from": sender}));
    if auto {
        lock(&session.state).accepted = true;
    } else {
        let deadline = Instant::now() + PATIENCE;
        loop {
            let state = lock(&session.state);
            let (state, _) = session.answer.wait_timeout_while(state, Duration::from_millis(500), |s| !s.answered).unwrap_or_else(|p| p.into_inner());
            if state.answered {
                break;
            }
            let gone = state.gone;
            drop(state);
            if gone || conn.peer_gone() || Instant::now() > deadline {
                end(app, &session, "requestGone", json!({}));
                conn.close = true;
                return Ok(());
            }
        }
    }
    let (accepted, cancelled, gone) = {
        let state = lock(&session.state);
        (state.accepted, state.cancelled, state.gone)
    };
    if !accepted || cancelled {
        if gone {
            end(app, &session, "requestGone", json!({}));
        }
        let mut current = lock(&app.session);
        if current.as_ref().is_some_and(|c| Arc::ptr_eq(c, &session)) {
            *current = None;
        }
        drop(current);
        conn.reply(403, None);
        return Ok(());
    }
    let mut tokens = Map::new();
    for file in &mut lock(&session.state).files {
        let token = random_hex(16);
        tokens.insert(file.key.clone(), json!(token));
        file.token = Some(token);
    }
    session.report(true);
    conn.reply(200, Some(&json!({"sessionId": session.id, "files": tokens})));
    Ok(())
}

/// Why a file didn't arrive whole.
enum Stopped {
    ByOwner,
    Lost,
}

/// Reads the rest of the request's body into the open file.
fn save(conn: &mut Conn, session: &Session, mut target: std::fs::File) -> Result<(), Stopped> {
    let mut chunk = vec![0u8; CHUNK];
    while conn.left > 0 {
        if lock(&session.state).cancelled {
            return Err(Stopped::ByOwner);
        }
        let want = (conn.left as usize).min(CHUNK);
        let read = conn.stream.read(&mut chunk[..want]).map_err(|_| Stopped::Lost)?;
        if read == 0 {
            return Err(Stopped::Lost); // the sender went away
        }
        target.write_all(&chunk[..read]).map_err(|_| Stopped::Lost)?;
        conn.left -= read as u64;
        lock(&session.state).done += read as u64;
        session.report(false);
    }
    target.flush().map_err(|_| Stopped::Lost)
}

/// One file of an accepted transfer arriving.
fn upload(app: &Arc<App>, conn: &mut Conn, head: &http::Head) {
    let query = |name: &str| head.query.get(name).map(String::as_str).unwrap_or_default();
    let session = lock(&app.session).clone();
    let claimed = session.as_ref().and_then(|s| {
        let mut state = lock(&s.state);
        let allowed = state.accepted && s.id == query("sessionId") && s.sender["ip"] == conn.ip.as_str();
        let file = state.files.iter_mut().find(|f| f.key == query("fileId")).filter(|f| allowed && !f.started && f.token.as_deref().is_some_and(|t| head.query.get("token").is_some_and(|q| q == t)))?;
        file.started = true;
        Some((file.key.clone(), file.name.clone(), file.size))
    });
    let (Some(session), Some((key, name, size))) = (session, claimed) else {
        conn.reply(403, None);
        return;
    };
    if head.length().is_none() {
        conn.left = size;
    }
    let folder = lock(&app.config).folder.clone();
    let arrived = files::claim(&folder, &name).map_err(|_| Stopped::Lost).and_then(|(path, target)| {
        let part = files::part_of(&path);
        lock(&session.state).current = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        let saved = save(conn, &session, target).and_then(|()| std::fs::rename(&part, &path).map_err(|_| Stopped::Lost));
        if saved.is_err() {
            let _ = std::fs::remove_file(&part);
        }
        saved.map(|()| path)
    });
    let path = match arrived {
        Ok(path) => path,
        Err(why) => {
            if !lock(&session.state).cancelled {
                end(app, &session, "receiveFailed", json!({"reason": "lost", "from": session.sender}));
            }
            if matches!(why, Stopped::ByOwner) {
                conn.reply(409, None);
            }
            conn.close = true;
            return;
        }
    };
    let all = {
        let mut state = lock(&session.state);
        if let Some(file) = state.files.iter_mut().find(|f| f.key == key) {
            file.finished = true;
        }
        state.saved.push(files::text(&path));
        state.files.iter().filter(|f| f.token.is_some()).all(|f| f.finished)
    };
    conn.reply(200, None);
    if all {
        session.report(true);
        let paths = lock(&session.state).saved.clone();
        end(app, &session, "received", json!({"folder": files::text(&folder), "paths": paths, "from": session.sender}));
    }
}

/// The sender gave up, before or after the owner's answer.
fn cancelled_by_sender(app: &Arc<App>, conn: &mut Conn, head: &http::Head) {
    let session = lock(&app.session).clone();
    if let Some(session) = session.filter(|s| s.sender["ip"] == conn.ip.as_str() && head.query.get("sessionId").is_none_or(|id| *id == s.id)) {
        let accepted = lock(&session.state).accepted;
        {
            let mut state = lock(&session.state);
            state.gone = true;
            state.cancelled = true;
        }
        if accepted {
            end(app, &session, "receiveFailed", json!({"reason": "cancelled", "from": session.sender}));
        }
        session.settle(|_| {});
    }
    conn.reply(200, None);
}

/// Turns receiving on or off: the server other devices send to.
pub fn set_receive(app: &Arc<App>, on: bool) {
    let mut server = lock(&app.server);
    if on && server.is_none() {
        let listener = match TcpListener::bind(("0.0.0.0", app.port)) {
            Ok(listener) => Arc::new(listener),
            Err(_) => {
                drop(server);
                emit(&json!({"event": "receive", "on": false, "busy": true}));
                return;
            }
        };
        let (accepting_app, accepting) = (Arc::clone(app), Arc::clone(&listener));
        let stopping = Arc::new(AtomicBool::new(false));
        let stopped = Arc::clone(&stopping);
        let accepting = thread::spawn(move || {
            let connections = Arc::new(AtomicUsize::new(0));
            // until set_receive shuts the listener down; any other error (a connection that went
            // away again, too many open files) is one connection's, not the server's
            while !stopped.load(Ordering::SeqCst) {
                let Ok((tcp, from)) = accepting.accept() else {
                    thread::sleep(Duration::from_millis(50));
                    continue;
                };
                let Some(slot) = Slot::take(&connections, MAX_CONNECTIONS) else { continue }; // full: dropped
                let app = Arc::clone(&accepting_app);
                // a thread that can't be started loses that connection, nothing more
                let _ = thread::Builder::new().spawn(move || {
                    serve(&app, tcp, from.ip().to_string());
                    drop(slot);
                });
            }
        });
        *server = Some(Server { listener, accepting, stopping });
        drop(server);
        emit(&json!({"event": "receive", "on": true, "busy": false}));
        discovery::announce(app, true); // devices with LocalSend open see this one at once
    } else if !on {
        let Some(old) = server.take() else { return };
        old.stopping.store(true, Ordering::SeqCst);
        // SAFETY: shutting down a socket that is ours and still open; it wakes the accepting thread
        unsafe {
            libc::shutdown(old.listener.as_raw_fd(), libc::SHUT_RDWR);
        }
        let _ = old.accepting.join();
        drop(old.listener); // the port is free again before the shell hears so
        drop(server);
        emit(&json!({"event": "receive", "on": false, "busy": false}));
    }
}

/// The owner stops the transfer being received, or dismisses the request.
pub fn cancel(app: &Arc<App>) {
    let Some(session) = lock(&app.session).clone() else { return };
    let accepted = lock(&session.state).accepted;
    session.settle(|state| state.cancelled = true);
    if accepted {
        end(app, &session, "receiveFailed", json!({"reason": "stopped", "from": session.sender}));
    }
}

/// The owner's answer to a request.
pub fn answer(app: &Arc<App>, id: &str, accept: bool) {
    let Some(session) = lock(&app.session).clone() else { return };
    if session.id != id || lock(&session.state).answered {
        return;
    }
    session.settle(|state| state.accepted = accept);
}
