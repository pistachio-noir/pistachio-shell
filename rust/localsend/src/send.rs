//! Sending: ask the device (prepare-upload), then upload each file it took.

use std::io::{self, BufReader, Read, Write};
use std::net::{Shutdown, TcpStream};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use pistachio_lines::{emit, log};
use serde_json::{json, Map, Value};

use crate::{files, host_of, http, lock, random_hex, App, Progress, API, CHUNK};

/// The transfer being sent, as the other threads see it.
pub struct Job {
    device: Value,
    state: Mutex<&'static str>,
    cancelled: AtomicBool,
    connection: Mutex<Option<TcpStream>>, // the one in use, to end it when the owner cancels
}

impl Job {
    fn active(&self) -> bool {
        matches!(*lock(&self.state), "waiting" | "sending")
    }

    fn cancelled(&self) -> bool {
        self.cancelled.load(Ordering::SeqCst)
    }
}

struct FileOut {
    path: Option<PathBuf>,  // a file on disk,
    data: Option<Vec<u8>>,  // or a text message
    name: String,
    size: u64,
    mime: String,
    preview: Option<String>,
    id: String,
    state: &'static str, // waiting, sending, sent, skipped
}

/// The files to send for these paths (a folder brings everything in it, named from the folder
/// down) and this text.
fn collect(paths: &[String], text: &str) -> Vec<FileOut> {
    let mut found: Vec<(PathBuf, String)> = Vec::new();
    for path in paths {
        let path = files::absolute(path);
        if path.is_dir() {
            let top = path.parent().map(PathBuf::from).unwrap_or_default();
            let mut inside = Vec::new();
            files::walk(&path, &mut inside);
            found.extend(inside.into_iter().map(|file| {
                let name = files::text(file.strip_prefix(&top).unwrap_or(&file));
                (file, name)
            }));
        } else if path.is_file() {
            let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
            found.push((path, name));
        }
    }
    let mut out: Vec<FileOut> = found
        .into_iter()
        .map(|(path, name)| FileOut {
            size: std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0),
            mime: files::mime(&name),
            path: Some(path),
            data: None,
            name,
            preview: None,
            id: String::new(),
            state: "waiting",
        })
        .collect();
    if !text.is_empty() {
        let preview = out.is_empty().then(|| text.to_string());
        out.push(FileOut { path: None, data: Some(text.as_bytes().to_vec()), name: "message.txt".into(), size: text.len() as u64, mime: "text/plain".into(), preview, id: String::new(), state: "waiting" });
    }
    for (i, file) in out.iter_mut().enumerate() {
        file.id = format!("{i}-{}", random_hex(4));
    }
    out
}

/// The sending thread's own view of the transfer.
struct Run {
    job: Arc<Job>,
    files: Vec<FileOut>,
    done: u64,
    total: u64,
    progress: Progress,
}

impl Run {
    fn report(&mut self, force: bool) {
        if !self.progress.due(self.done, force) {
            return;
        }
        let files: Vec<Value> = self.files.iter().map(|f| json!({"name": f.name, "size": f.size, "mime": f.mime, "state": f.state})).collect();
        emit(&json!({"event": "send", "state": *lock(&self.job.state), "device": self.job.device, "done": self.done, "total": self.total,
                     "speed": self.progress.speed.round() as u64, "files": files}));
    }

    fn finish(&mut self, state: &'static str) {
        *lock(&self.job.state) = state;
        self.report(true);
    }

    /// A connection to the device, noted so that cancelling can end it.
    fn connect(&self, app: &App, timeout: Option<Duration>) -> io::Result<BufReader<http::Stream>> {
        let (stream, handle) = app.connect(&self.job.device, timeout)?;
        if self.job.cancelled() {
            // cancelled while it was connecting, when there was nothing yet to end
            let _ = handle.shutdown(Shutdown::Both);
        }
        *lock(&self.job.connection) = Some(handle);
        Ok(BufReader::new(stream))
    }

    /// Asks the device to take the files: the status and body of its answer, however long it takes.
    fn prepare(&self, app: &App) -> io::Result<(u16, Vec<u8>)> {
        let mut described = Map::new();
        for f in &self.files {
            described.insert(f.id.clone(), json!({"id": f.id, "fileName": f.name, "size": f.size, "fileType": f.mime, "sha256": null, "preview": f.preview, "metadata": null}));
        }
        let body = json!({"info": app.info(), "files": described}).to_string().into_bytes();
        let mut stream = self.connect(app, None)?; // waits as long as they take to answer
        http::write_request(stream.get_mut(), &format!("{API}/prepare-upload"), &host_of(&self.job.device), "application/json", body.len() as u64)?;
        stream.get_mut().write_all(&body)?;
        stream.get_mut().flush()?;
        http::read_response(&mut stream)
    }

    fn upload(&mut self, app: &App, at: usize, session: &str, token: &str) -> io::Result<()> {
        let query = http::encode_query(&[("sessionId", session), ("fileId", &self.files[at].id), ("token", token)]);
        let mut stream = self.connect(app, Some(Duration::from_secs(60)))?;
        http::write_request(stream.get_mut(), &format!("{API}/upload?{query}"), &host_of(&self.job.device), "application/octet-stream", self.files[at].size)?;
        if let Some(data) = self.files[at].data.clone() {
            stream.get_mut().write_all(&data)?;
            self.done += data.len() as u64;
        } else if let Some(path) = self.files[at].path.clone() {
            let mut source = std::fs::File::open(path)?;
            let mut chunk = vec![0u8; CHUNK];
            while !self.job.cancelled() {
                let read = source.read(&mut chunk)?;
                if read == 0 {
                    break;
                }
                stream.get_mut().write_all(&chunk[..read])?;
                self.done += read as u64;
                self.report(false);
            }
        }
        if self.job.cancelled() {
            return Ok(());
        }
        stream.get_mut().flush()?;
        let (status, _) = http::read_response(&mut stream)?;
        if status != 200 {
            return Err(io::Error::other(format!("upload answered {status}")));
        }
        self.files[at].state = "sent";
        Ok(())
    }

    fn run(mut self, app: &App) {
        self.report(true);
        let answered = self.prepare(app);
        if self.job.cancelled() {
            return self.finish("cancelled");
        }
        let Ok((status, body)) = answered else { return self.finish("failed") };
        if status == 204 {
            for f in &mut self.files {
                f.state = "sent";
            }
            self.done = self.total;
            return self.finish("done");
        }
        if status != 200 {
            return self.finish(match status {
                401 => "pin",
                403 => "declined",
                409 | 429 => "busy",
                _ => "failed",
            });
        }
        let answer: Value = serde_json::from_slice(&body).unwrap_or_default();
        let (Some(session), Some(tokens)) = (answer["sessionId"].as_str().map(String::from), answer["files"].as_object().cloned()) else { return self.finish("failed") };
        *lock(&self.job.state) = "sending";
        for f in &mut self.files {
            if !tokens.contains_key(&f.id) {
                f.state = "skipped"; // they picked some of the files
                self.total = self.total.saturating_sub(f.size);
            }
        }
        let mut failed = None;
        for at in 0..self.files.len() {
            if self.files[at].state == "skipped" {
                continue;
            }
            if self.job.cancelled() {
                break;
            }
            self.files[at].state = "sending";
            self.report(true);
            let token = tokens[&self.files[at].id].as_str().unwrap_or_default().to_string();
            if let Err(e) = self.upload(app, at, &session, &token) {
                failed = Some(e);
                break;
            }
            if self.job.cancelled() {
                break;
            }
        }
        if self.job.cancelled() {
            let _ = app.call(&self.job.device, "/cancel", None, &[("sessionId", &session)], Duration::from_secs(3));
            return self.finish("cancelled");
        }
        if let Some(e) = failed {
            log(&format!("send failed: {e}"));
            return self.finish("failed");
        }
        self.finish("done");
    }
}

/// Starts sending to the device with this fingerprint, unless something is being sent already.
pub fn start(app: &Arc<App>, fingerprint: &str, paths: &[String], text: &str) {
    let run = {
        let mut job = lock(&app.job);
        let Some(device) = lock(&app.devices).get(fingerprint).cloned() else { return };
        if job.as_ref().is_some_and(|j| j.active()) {
            return;
        }
        let files = collect(paths, text);
        if files.is_empty() {
            return;
        }
        let new = Arc::new(Job { device, state: Mutex::new("waiting"), cancelled: AtomicBool::new(false), connection: Mutex::new(None) });
        *job = Some(Arc::clone(&new));
        Run { job: new, total: files.iter().fold(0u64, |sum, f| sum.saturating_add(f.size)), files, done: 0, progress: Progress::default() }
    };
    let app = Arc::clone(app);
    thread::spawn(move || run.run(&app));
}

/// The owner gave up on the transfer being sent.
pub fn cancel(app: &App) {
    let Some(job) = lock(&app.job).clone() else { return };
    if !job.active() {
        return;
    }
    job.cancelled.store(true, Ordering::SeqCst);
    let connection = lock(&job.connection);
    if let Some(connection) = connection.as_ref() {
        let _ = connection.shutdown(Shutdown::Both); // wakes the thread waiting for an answer
    }
    drop(connection);
}
