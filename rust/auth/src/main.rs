//! Polkit authentication agent for the shell; services/Polkit.qml runs it.
//!
//! Quickshell has an agent (Quickshell.Services.Polkit), but it starts PAM the moment a request
//! comes in, so dismissing its dialog counts as a failed login for pam_faillock (three lock the
//! account for 10 minutes, the TTY included). This one registers with polkit for the shell's login
//! session (again whenever polkitd restarts) and passes each request to the shell as a JSON line on
//! stdout. PAM starts only once the shell sends a password, through polkit's own helper (see
//! pam.rs), so cancelling before that touches nothing.
//!
//!   out  {"event": "ready"}                  registered with polkit for this session
//!   out  {"event": "lost"}                   polkitd went away, and the registration with it
//!   out  {"event": "request", "cookie": "…", "action": "org.freedesktop.policykit.exec", "message": "…",
//!         "user": "sx", "requester": "pamac-manager (pid 4182)", "vendor": "PackageKit"}
//!   out  {"event": "prompt", "cookie": "…", "text": "Verification code: ", "echo": true}
//!                                            PAM asks for more than the password; answered like one
//!   out  {"event": "failed", "cookie": "…", "error": "…"}   PAM said no; error is its own message, or ""
//!   out  {"event": "done", "cookie": "…"}    authorised
//!   out  {"event": "cancel", "cookie": "…"}  polkit withdrew the request (the app gave up)
//!   in   {"cookie": "…", "response": "…"}    the password, or the answer to a prompt
//!   in   {"cookie": "…", "cancel": true}     dismissed
//!
//! requester (the app that asked) and vendor are "" when unknown. It exits when stdin closes, so it
//! never outlives the shell. With --session it serves on the session bus without polkit and never
//! starts PAM (a response fails at once), so tests/polkit-agent.sh can make requests; --watch <name>
//! with it stands in for polkitd coming and going.
//!
//! This program is alone in its process on purpose: the password passes through here, so nothing in
//! it listens on the network.

use std::collections::HashMap;
use std::path::Path;
use std::sync::mpsc::{self, Sender};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};
use std::thread;

use pistachio_auth::pam::{self, Canceller, Event};
use pistachio_bus::zbus::blocking::Connection;
use pistachio_bus::zvariant::{OwnedObjectPath, OwnedValue, Value};
use pistachio_bus::{self as bus, Call, Message};
use pistachio_lines::{emit, log};
use serde_json::json;

const PATH: &str = "/pistachio/PolkitAgent";
const INTERFACE: &str = "org.freedesktop.PolicyKit1.AuthenticationAgent";
const INTROSPECTION: &str = r#"
  <interface name="org.freedesktop.PolicyKit1.AuthenticationAgent">
    <method name="BeginAuthentication">
      <arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/>
      <arg type="a{ss}" direction="in"/><arg type="s" direction="in"/><arg type="a(sa{sv})" direction="in"/>
    </method>
    <method name="CancelAuthentication"><arg type="s" direction="in"/></method>
  </interface>"#;
const POLKIT: &str = "org.freedesktop.PolicyKit1";
const AUTHORITY_PATH: &str = "/org/freedesktop/PolicyKit1/Authority";
const AUTHORITY: &str = "org.freedesktop.PolicyKit1.Authority";
const CANCELLED: &str = "org.freedesktop.PolicyKit1.Error.Cancelled";
const FAILED: &str = "org.freedesktop.PolicyKit1.Error.Failed";

type Identities = Vec<(String, HashMap<String, OwnedValue>)>;
type Begin = (String, String, String, HashMap<String, String>, String, Identities);
/// One of polkit's actions, as EnumerateActions lists them: id, description, message, vendor, …
type Action = (String, String, String, String, String, String, u32, u32, u32, HashMap<String, String>);

/// A request waiting for the shell or for PAM.
struct Request {
    call: Message, // polkit's BeginAuthentication call, answered when it's over
    uid: u32,
    pam: Option<Pam>,         // while PAM runs
    password: Option<String>, // sent before PAM asked for it
    waiting: bool,            // PAM asked something the shell hasn't answered yet
    error: String,            // PAM's last error message
}

struct Pam {
    id: u64, // tells this run from an earlier one for the same cookie
    answers: Sender<Option<String>>,
    canceller: Canceller,
}

impl Pam {
    fn cancel(&self) {
        let _ = self.answers.send(None);
        self.canceller.cancel();
    }
}

#[derive(Default)]
struct State {
    requests: HashMap<String, Request>,
    polkitd: Option<String>, // polkitd's unique bus name while it runs
    runs: u64,
}

struct Agent {
    connection: Connection,
    session: bool,
    state: Mutex<State>,
}

impl Agent {
    fn state(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn on_call(self: &Arc<Self>, call: Call) {
        if !self.session && self.state().polkitd.as_deref() != Some(call.sender.as_str()) {
            bus::refuse(&self.connection, &call.message, FAILED, "Only polkit asks this agent");
            return;
        }
        match call.member.as_str() {
            "CancelAuthentication" => {
                let Ok((cookie,)) = call.message.body().deserialize::<(String,)>() else {
                    bus::refuse(&self.connection, &call.message, FAILED, "Not a cookie");
                    return;
                };
                bus::reply(&self.connection, &call.message, &());
                if let Some(request) = self.state().requests.remove(&cookie) {
                    if let Some(pam) = &request.pam {
                        pam.cancel();
                    }
                    bus::refuse(&self.connection, &request.call, CANCELLED, "Withdrawn");
                    emit(&json!({"event": "cancel", "cookie": cookie}));
                }
            }
            "BeginAuthentication" => {
                let body = call.message.body();
                let Ok((action, message, _icon, details, cookie, identities)) = body.deserialize::<Begin>() else {
                    bus::refuse(&self.connection, &call.message, FAILED, "Not a request");
                    return;
                };
                let Some(uid) = user_for(&identities) else {
                    bus::refuse(&self.connection, &call.message, FAILED, "No user to authenticate as");
                    return;
                };
                drop(body);
                let event = json!({
                    "event": "request", "cookie": cookie, "action": action, "message": message, "user": user_name(uid),
                    "requester": requester(&details), "vendor": vendor(&action),
                });
                self.state().requests.insert(cookie, Request { call: call.message, uid, pam: None, password: None, waiting: false, error: String::new() });
                emit(&event);
            }
            _ => bus::refuse(&self.connection, &call.message, "org.freedesktop.DBus.Error.UnknownMethod", "No such method"),
        }
    }

    /// The shell's answer to a request.
    fn answer(self: &Arc<Self>, line: &str) {
        let message: serde_json::Value = serde_json::from_str(line).unwrap_or_default();
        let mut state = self.state();
        let cookie = message["cookie"].as_str().unwrap_or_default().to_string();
        if !state.requests.contains_key(&cookie) {
            drop(state);
            // never the line itself: it may hold a password
            log("ignored answer: not for a request that is waiting");
            return;
        }
        if truthy(&message["cancel"]) {
            let request = state.requests.remove(&cookie).expect("checked");
            drop(state);
            if let Some(pam) = &request.pam {
                pam.cancel(); // only mid-PAM, e.g. at a second prompt: that one may count as a failure
            }
            bus::refuse(&self.connection, &request.call, CANCELLED, "Dismissed");
            return;
        }
        // only a text is an answer: starting PAM with anything else would cost a failed login
        let Some(response) = message["response"].as_str().map(String::from) else {
            drop(state);
            log("ignored answer: no response in it");
            return;
        };
        let request = state.requests.get_mut(&cookie).expect("checked");
        if request.waiting {
            request.waiting = false;
            if let Some(pam) = &request.pam {
                let _ = pam.answers.send(Some(response));
            }
        } else if request.pam.is_some() {
            drop(state);
            log("ignored answer: PAM is still checking the last one");
        } else if self.session {
            drop(state);
            emit(&json!({"event": "failed", "cookie": cookie, "error": "No PAM with --session"}));
        } else {
            let user = user_name(request.uid);
            match pam::Session::start(&user, &cookie, Path::new(pam::SOCKET), Path::new(pam::HELPER)) {
                Ok((session, canceller)) => {
                    let (answers, asked) = mpsc::channel();
                    state.runs += 1;
                    let id = state.runs;
                    let request = state.requests.get_mut(&cookie).expect("checked");
                    request.password = Some(response);
                    request.pam = Some(Pam { id, answers, canceller });
                    drop(state);
                    let agent = Arc::clone(self);
                    thread::spawn(move || agent.run_pam(session, cookie, id, asked));
                }
                Err(e) => {
                    drop(state);
                    log(&format!("could not start polkit's helper: {e}"));
                    emit(&json!({"event": "failed", "cookie": cookie, "error": "Could not reach polkit's authentication helper."}));
                }
            }
        }
    }

    /// One run of PAM for a request, on its own thread.
    fn run_pam(&self, session: pam::Session, cookie: String, id: u64, asked: mpsc::Receiver<Option<String>>) {
        let gained = session.run(|event| {
            let mut state = self.state();
            // gone or restarted meanwhile: this run is nobody's anymore
            let request = state.requests.get_mut(&cookie).filter(|r| r.pam.as_ref().is_some_and(|p| p.id == id))?;
            match event {
                Event::Prompt { text, echo } => {
                    if let Some(password) = request.password.take() {
                        return Some(password);
                    }
                    request.waiting = true;
                    drop(state);
                    emit(&json!({"event": "prompt", "cookie": cookie, "text": text, "echo": echo}));
                    asked.recv().ok().flatten()
                }
                Event::Error(text) => {
                    request.error = text;
                    None
                }
                Event::Info(text) => {
                    drop(state);
                    log(&format!("PAM: {text}"));
                    None
                }
            }
        });
        let mut state = self.state();
        let Some(request) = state.requests.get_mut(&cookie).filter(|r| r.pam.as_ref().is_some_and(|p| p.id == id)) else { return };
        request.pam = None;
        request.password = None;
        request.waiting = false;
        if gained {
            let request = state.requests.remove(&cookie).expect("just seen");
            drop(state);
            bus::reply(&self.connection, &request.call, &());
            emit(&json!({"event": "done", "cookie": cookie}));
        } else {
            let error = std::mem::take(&mut request.error);
            drop(state);
            emit(&json!({"event": "failed", "cookie": cookie, "error": error}));
        }
    }

    fn drop_requests(&self) {
        let requests: Vec<Request> = self.state().requests.drain().map(|(_, request)| request).collect();
        for request in requests {
            if let Some(pam) = &request.pam {
                pam.cancel();
            }
            bus::refuse(&self.connection, &request.call, CANCELLED, "The agent went away");
        }
    }

    /// polkitd is there (`register`: tell it about this agent), or gone.
    fn on_polkit(&self, owner: Option<String>, register: bool) {
        let Some(owner) = owner else {
            if self.state().polkitd.take().is_none() {
                return; // not there at startup: nothing to lose
            }
            self.drop_requests();
            emit(&json!({"event": "lost"}));
            return;
        };
        self.state().polkitd = Some(owner);
        if register {
            let Some(session) = session_id(&self.connection) else {
                log("could not register with polkit: the shell runs outside a login session");
                return;
            };
            let subject = ("unix-session", HashMap::from([("session-id", Value::from(session))]));
            let locale = std::env::var("LANG").unwrap_or_else(|_| "C".into());
            if let Err(e) = self.connection.call_method(Some(POLKIT), AUTHORITY_PATH, Some(AUTHORITY), "RegisterAuthenticationAgent", &(subject, locale, PATH)) {
                log(&format!("could not register with polkit: {e}"));
                return;
            }
        }
        emit(&json!({"event": "ready"}));
    }
}

fn truthy(value: &serde_json::Value) -> bool {
    !matches!(value, serde_json::Value::Null | serde_json::Value::Bool(false)) && value != &json!(0) && value != &json!("")
}

/// The user to authenticate as: this one if polkit allows it, else the first user it names.
fn user_for(identities: &Identities) -> Option<u32> {
    let uids: Vec<u32> = identities.iter().filter(|(kind, _)| kind == "unix-user").filter_map(|(_, details)| u32::try_from(details.get("uid")?).ok()).collect();
    // SAFETY: getuid has no arguments and cannot fail
    let me = unsafe { libc::getuid() };
    if uids.contains(&me) {
        Some(me)
    } else {
        uids.first().copied()
    }
}

fn user_name(uid: u32) -> String {
    let mut record: libc::passwd = unsafe { std::mem::zeroed() };
    let mut buffer = vec![0 as libc::c_char; 16 * 1024];
    let mut found: *mut libc::passwd = std::ptr::null_mut();
    // SAFETY: the record, the buffer and the result pointer are ours and live through the call;
    // pw_name, when found, points into the buffer, which is still alive when it's read
    unsafe {
        if libc::getpwuid_r(uid, &mut record, buffer.as_mut_ptr(), buffer.len(), &mut found) == 0 && !found.is_null() {
            return std::ffi::CStr::from_ptr(record.pw_name).to_string_lossy().into_owned();
        }
    }
    uid.to_string()
}

fn base_name(path: &str) -> &str {
    path.trim_end_matches('/').rsplit('/').next().unwrap_or(path)
}

/// comm, which the kernel cuts to 15 characters, unless argv has the full name.
fn process_name(pid: &str) -> String {
    let (Ok(comm), Ok(cmdline)) = (std::fs::read_to_string(format!("/proc/{pid}/comm")), std::fs::read(format!("/proc/{pid}/cmdline"))) else {
        return String::new();
    };
    let comm = comm.trim();
    let cmdline = String::from_utf8_lossy(&cmdline);
    cmdline.split('\0').take(2).map(base_name).find(|name| !comm.is_empty() && name.starts_with(comm)).unwrap_or(comm).to_string()
}

/// The app that asked: "name (pid 123)", or "".
fn requester(details: &HashMap<String, String>) -> String {
    for key in ["polkit.subject-pid", "polkit.caller-pid"] {
        let pid = details.get(key).map(String::as_str).unwrap_or_default();
        if pid.is_empty() || !pid.bytes().all(|b| b.is_ascii_digit()) {
            continue;
        }
        let name = process_name(pid);
        if !name.is_empty() {
            return format!("{name} (pid {pid})");
        }
    }
    String::new()
}

/// Who an action belongs to, from polkit's own list (on the system bus, with --session too).
fn vendor(action: &str) -> String {
    static SYSTEM: OnceLock<Option<Connection>> = OnceLock::new();
    let Some(system) = SYSTEM.get_or_init(|| Connection::system().ok()) else { return String::new() };
    let locale = std::env::var("LANG").unwrap_or_else(|_| "C".into());
    let actions = system
        .call_method(Some(POLKIT), AUTHORITY_PATH, Some(AUTHORITY), "EnumerateActions", &(locale,))
        .and_then(|reply| reply.body().deserialize::<(Vec<Action>,)>());
    match actions {
        Ok((actions,)) => actions.into_iter().find(|a| a.0 == action).map(|a| a.3).unwrap_or_default(),
        Err(e) => {
            log(&format!("could not list polkit actions: {e}"));
            String::new()
        }
    }
}

/// The login session this process is in, from logind, else from the environment.
fn session_id(system: &Connection) -> Option<String> {
    let from_logind = || -> Option<String> {
        let reply = system.call_method(Some("org.freedesktop.login1"), "/org/freedesktop/login1", Some("org.freedesktop.login1.Manager"), "GetSessionByPID", &(std::process::id(),)).ok()?;
        let (path,): (OwnedObjectPath,) = reply.body().deserialize().ok()?;
        let reply = system.call_method(Some("org.freedesktop.login1"), path.as_str(), Some("org.freedesktop.DBus.Properties"), "Get", &("org.freedesktop.login1.Session", "Id")).ok()?;
        let (id,): (OwnedValue,) = reply.body().deserialize().ok()?;
        String::try_from(id).ok()
    };
    from_logind().or_else(|| std::env::var("XDG_SESSION_ID").ok()).filter(|id| !id.is_empty())
}

fn main() {
    pistachio_lines::die_with_parent();
    let args: Vec<String> = std::env::args().skip(1).collect();
    let session = args.iter().any(|a| a == "--session");
    let watch = args.iter().position(|a| a == "--watch").and_then(|i| args.get(i + 1)).cloned();
    let connection = match bus::connect(session) {
        Ok(connection) => connection,
        Err(e) => {
            log(&format!("could not reach the bus: {e}"));
            std::process::exit(1);
        }
    };
    let calls = bus::calls(&connection);
    let agent = Arc::new(Agent { connection: connection.clone(), session, state: Mutex::default() });

    let reader = Arc::clone(&agent);
    thread::spawn(move || {
        pistachio_lines::read_lines(|line| reader.answer(line));
        reader.drop_requests(); // the shell is gone
        std::process::exit(0);
    });

    let watcher = Arc::clone(&agent);
    let watched = if session {
        emit(&json!({"event": "ready", "name": bus::unique_name(&connection)}));
        // the tests' stand-in for polkitd coming and going
        watch.map(|name| bus::watch_name(&connection, Box::leak(name.into_boxed_str()), false, move |owner| watcher.on_polkit(owner, false)))
    } else {
        Some(bus::watch_name(&connection, POLKIT, true, move |owner| watcher.on_polkit(owner, true)))
    };
    if let Some(Err(e)) = watched {
        log(&format!("could not watch for polkit: {e}"));
    }

    let server = Arc::clone(&agent);
    bus::serve(&connection, calls, PATH, INTERFACE, INTROSPECTION, move |call| server.on_call(call));
    agent.drop_requests();
}
