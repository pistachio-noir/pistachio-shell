//! BlueZ pairing agent for the shell; services/Bluetooth.qml runs it.
//!
//! Quickshell's Bluetooth module has no agent, so devices that show or ask for a code could not
//! pair. This registers an org.bluez.Agent1 object as BlueZ's default agent (again whenever
//! bluetoothd restarts) and passes each question to the shell as a JSON line on stdout. The shell
//! answers on stdin.
//!
//!   out  {"event": "ready"}                  registered as the default agent
//!   out  {"event": "lost"}                   bluetoothd went away, and the registration with it
//!   out  {"event": "request", "id": 1, "kind": "confirm", "device": "/org/bluez/hci0/dev_…", "code": "012345"}
//!   out  {"event": "cancel"}                 BlueZ dropped the question it asked last
//!   in   {"id": 1, "accept": true, "value": "0000"}     value only for "pin" and "passkey"
//!
//! Kinds: confirm (do both sides show this code?), authorize (a device asks to pair), service (a
//! paired device asks to use a service, with "uuid"), pin and passkey (type the code the device
//! shows), and display-pin and display-passkey (show a code to type on the device, with "entered",
//! the keys typed so far, or -1). The display kinds are answered at once, so they carry id 0.
//!
//! With --session it serves on the session bus without BlueZ, so tests/bluetooth-agent.sh can ask
//! it questions (the system bus lets only root call an agent).

use std::collections::HashMap;
use std::sync::{Arc, Mutex, MutexGuard};
use std::thread;

use pistachio_bus::zbus::blocking::Connection;
use pistachio_bus::zvariant::{ObjectPath, OwnedObjectPath};
use pistachio_bus::{self as bus, Call, Message};
use pistachio_lines::{emit, log};
use serde_json::json;

const PATH: &str = "/pistachio/agent";
const INTERFACE: &str = "org.bluez.Agent1";
const INTROSPECTION: &str = r#"
  <interface name="org.bluez.Agent1">
    <method name="Release"/>
    <method name="RequestPinCode"><arg type="o" direction="in"/><arg type="s" direction="out"/></method>
    <method name="DisplayPinCode"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
    <method name="RequestPasskey"><arg type="o" direction="in"/><arg type="u" direction="out"/></method>
    <method name="DisplayPasskey"><arg type="o" direction="in"/><arg type="u" direction="in"/><arg type="q" direction="in"/></method>
    <method name="RequestConfirmation"><arg type="o" direction="in"/><arg type="u" direction="in"/></method>
    <method name="RequestAuthorization"><arg type="o" direction="in"/></method>
    <method name="AuthorizeService"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
    <method name="Cancel"/>
  </interface>"#;
const BLUEZ: &str = "org.bluez";
const REJECTED: &str = "org.bluez.Error.Rejected";
const CANCELED: &str = "org.bluez.Error.Canceled";

#[derive(Default)]
struct State {
    pending: HashMap<u64, (Message, &'static str)>, // id -> the call and its kind, waiting for the shell
    last_id: u64,
    bluez: Option<String>, // bluetoothd's unique bus name while it runs
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

    fn drop_pending(&self) {
        let pending: Vec<_> = self.state().pending.drain().collect();
        for (_, (call, _)) in pending {
            bus::refuse(&self.connection, &call, CANCELED, "The question was withdrawn");
        }
    }

    fn on_call(&self, call: Call) {
        if !self.session && self.state().bluez.as_deref() != Some(call.sender.as_str()) {
            bus::refuse(&self.connection, &call.message, REJECTED, "Only BlueZ asks this agent");
            return;
        }
        let body = call.message.body();
        let malformed = || bus::refuse(&self.connection, &call.message, REJECTED, "Not a question this agent knows");
        let mut event = json!({"event": "request"});
        let kind = match call.member.as_str() {
            "Release" => {
                bus::reply(&self.connection, &call.message, &());
                return;
            }
            "Cancel" => {
                self.drop_pending();
                bus::reply(&self.connection, &call.message, &());
                emit(&json!({"event": "cancel"}));
                return;
            }
            "RequestConfirmation" => {
                let Ok((device, code)) = body.deserialize::<(OwnedObjectPath, u32)>() else { return malformed() };
                event["device"] = json!(device.as_str());
                event["code"] = json!(format!("{code:06}"));
                "confirm"
            }
            "DisplayPasskey" => {
                let Ok((device, code, entered)) = body.deserialize::<(OwnedObjectPath, u32, u16)>() else { return malformed() };
                event["device"] = json!(device.as_str());
                event["code"] = json!(format!("{code:06}"));
                event["entered"] = json!(entered);
                "display-passkey"
            }
            "DisplayPinCode" => {
                let Ok((device, code)) = body.deserialize::<(OwnedObjectPath, String)>() else { return malformed() };
                event["device"] = json!(device.as_str());
                event["code"] = json!(code);
                event["entered"] = json!(-1);
                "display-pin"
            }
            "AuthorizeService" => {
                let Ok((device, uuid)) = body.deserialize::<(OwnedObjectPath, String)>() else { return malformed() };
                event["device"] = json!(device.as_str());
                event["uuid"] = json!(uuid);
                "service"
            }
            member @ ("RequestPinCode" | "RequestPasskey" | "RequestAuthorization") => {
                let Ok((device,)) = body.deserialize::<(OwnedObjectPath,)>() else { return malformed() };
                event["device"] = json!(device.as_str());
                match member {
                    "RequestPinCode" => "pin",
                    "RequestPasskey" => "passkey",
                    _ => "authorize",
                }
            }
            _ => {
                bus::refuse(&self.connection, &call.message, "org.freedesktop.DBus.Error.UnknownMethod", "No such method");
                return;
            }
        };
        event["kind"] = json!(kind);
        drop(body);
        if kind.starts_with("display") {
            event["id"] = json!(0);
            bus::reply(&self.connection, &call.message, &());
        } else {
            let mut state = self.state();
            state.last_id += 1;
            event["id"] = json!(state.last_id);
            let id = state.last_id;
            state.pending.insert(id, (call.message, kind));
        }
        emit(&event);
    }

    /// The shell's answer to a question.
    fn answer(&self, line: &str) {
        let message: serde_json::Value = serde_json::from_str(line).unwrap_or_default();
        let asked = message["id"].as_u64().and_then(|id| self.state().pending.remove(&id));
        let Some((call, kind)) = asked else {
            log("ignored answer: not for a question that is waiting"); // never the line: it may hold a PIN
            return;
        };
        let value = match &message["value"] {
            serde_json::Value::String(text) => text.clone(),
            serde_json::Value::Null => String::new(),
            other => other.to_string(),
        };
        let accept = !matches!(&message["accept"], serde_json::Value::Null | serde_json::Value::Bool(false));
        let passkey = || value.parse::<u32>().ok().filter(|code| !value.is_empty() && value.bytes().all(|b| b.is_ascii_digit()) && *code <= 999_999);
        if !accept {
            bus::refuse(&self.connection, &call, REJECTED, "Declined");
        } else if kind == "pin" && (1..=16).contains(&value.chars().count()) {
            bus::reply(&self.connection, &call, &(value,));
        } else if let (true, Some(code)) = (kind == "passkey", passkey()) {
            bus::reply(&self.connection, &call, &(code,));
        } else if kind == "pin" || kind == "passkey" {
            bus::refuse(&self.connection, &call, REJECTED, "Not a valid code");
        } else {
            bus::reply(&self.connection, &call, &());
        }
    }

    fn on_bluez(&self, owner: Option<String>) {
        let Some(owner) = owner else {
            if self.state().bluez.take().is_none() {
                return; // not there at startup: nothing to lose
            }
            self.drop_pending();
            emit(&json!({"event": "lost"}));
            return;
        };
        self.state().bluez = Some(owner);
        let path = ObjectPath::try_from(PATH).expect("a valid path");
        let manager = |method: &str, body: &dyn Fn() -> pistachio_bus::zbus::Result<Message>| body().map(|_| ()).map_err(|e| format!("{method}: {e}"));
        let registered = manager("RegisterAgent", &|| self.connection.call_method(Some(BLUEZ), "/org/bluez", Some("org.bluez.AgentManager1"), "RegisterAgent", &(&path, "KeyboardDisplay")))
            .and_then(|()| manager("RequestDefaultAgent", &|| self.connection.call_method(Some(BLUEZ), "/org/bluez", Some("org.bluez.AgentManager1"), "RequestDefaultAgent", &(&path,))));
        match registered {
            Ok(()) => emit(&json!({"event": "ready"})),
            Err(e) => log(&format!("could not register with BlueZ: {e}")),
        }
    }
}

pub fn run(session: bool) {
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
        std::process::exit(0); // the shell is gone
    });

    if session {
        emit(&json!({"event": "ready", "name": bus::unique_name(&connection)}));
    } else {
        let watcher = Arc::clone(&agent);
        if let Err(e) = bus::watch_name(&connection, BLUEZ, false, move |owner| watcher.on_bluez(owner)) {
            log(&format!("could not watch for BlueZ: {e}"));
        }
    }
    bus::serve(&connection, calls, PATH, INTERFACE, INTROSPECTION, |call| agent.on_call(call));
}
