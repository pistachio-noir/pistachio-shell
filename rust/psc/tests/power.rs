//! `psc power` against a fake logind on a private dbus-daemon this test starts itself (never the real
//! system bus). psc is pointed at it with DBUS_SYSTEM_BUS_ADDRESS. Before any power call the test
//! proves the redirect works: psc doctor must find no logind there until the fake one owns the name,
//! so a real suspend or reboot can't be sent from here.
use gio::glib;
use gio::prelude::*;
use std::io::BufRead;
use std::process::{Command, Stdio};
use std::sync::{mpsc, Arc, Mutex};

const XML: &str = r#"<node><interface name="org.freedesktop.login1.Manager">
  <method name="Suspend"><arg type="b" direction="in"/></method>
  <method name="Reboot"><arg type="b" direction="in"/></method>
  <method name="PowerOff"><arg type="b" direction="in"/></method>
  <method name="SetRebootToFirmwareSetup"><arg type="b" direction="in"/></method>
</interface></node>"#;

type Calls = Arc<Mutex<Vec<(String, bool)>>>;

struct Daemon(std::process::Child);
impl Drop for Daemon {
    fn drop(&mut self) { let _ = self.0.kill(); let _ = self.0.wait(); }
}

fn psc(address: &str, args: &[&str]) -> std::process::Output {
    Command::new(env!("CARGO_BIN_EXE_psc")).args(args).env("DBUS_SYSTEM_BUS_ADDRESS", address).output().unwrap()
}

fn doctor_logind(address: &str) -> bool {
    let out = psc(address, &["doctor", "--json"]);
    let rows: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap();
    rows.as_array().unwrap().iter().find(|r| r["id"] == "logind").unwrap()["found"].as_bool().unwrap()
}

/// The fake logind, on its own thread and main context; `fail` names methods that answer with an error.
fn fake_logind(address: String, calls: Calls, fail: Arc<Mutex<Vec<String>>>) {
    let (ready, wait) = mpsc::channel();
    std::thread::spawn(move || {
        let context = glib::MainContext::new();
        let _guard = context.acquire().unwrap();
        context.with_thread_default(|| {
            let flags = gio::DBusConnectionFlags::AUTHENTICATION_CLIENT | gio::DBusConnectionFlags::MESSAGE_BUS_CONNECTION;
            let bus = gio::DBusConnection::for_address_sync(&address, flags, None, gio::Cancellable::NONE).unwrap();
            let info = gio::DBusNodeInfo::for_xml(XML).unwrap().lookup_interface("org.freedesktop.login1.Manager").unwrap();
            let _id = bus.register_object("/org/freedesktop/login1", &info)
                .method_call(move |_, _, _, _, method, params, invocation| {
                    calls.lock().unwrap().push((method.to_string(), params.child_value(0).get::<bool>().unwrap()));
                    if fail.lock().unwrap().iter().any(|m| m == method) {
                        invocation.return_dbus_error("org.freedesktop.login1.NotAllowed", "refused by the test");
                    } else {
                        invocation.return_value(None);
                    }
                })
                .build().unwrap();
            bus.call_sync(Some("org.freedesktop.DBus"), "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName",
                Some(&("org.freedesktop.login1", 4u32).to_variant()), None, gio::DBusCallFlags::NONE, 5000, gio::Cancellable::NONE).unwrap();
            ready.send(()).unwrap();
            glib::MainLoop::new(Some(&context), false).run();
        }).unwrap();
    });
    wait.recv_timeout(std::time::Duration::from_secs(5)).expect("the fake logind didn't start");
}

#[test]
fn power_reaches_logind() {
    let mut child = Command::new("dbus-daemon").args(["--session", "--nofork", "--print-address=1"])
        .stdout(Stdio::piped()).stderr(Stdio::null()).spawn().expect("dbus-daemon");
    let mut address = String::new();
    std::io::BufReader::new(child.stdout.take().unwrap()).read_line(&mut address).unwrap();
    let _daemon = Daemon(child);
    let address = address.trim().to_string();
    assert!(address.starts_with("unix:"), "{address}");

    // the gate: nothing owns login1 on this bus yet, so psc must not find one
    assert!(!doctor_logind(&address), "psc reached a logind: DBUS_SYSTEM_BUS_ADDRESS isn't honoured, stopping");

    let calls: Calls = Arc::default();
    let fail: Arc<Mutex<Vec<String>>> = Arc::default();
    fake_logind(address.clone(), calls.clone(), fail.clone());
    assert!(doctor_logind(&address), "doctor finds the fake logind");

    let taken = |calls: &Calls| std::mem::take(&mut *calls.lock().unwrap());
    let call = |m: &str| (m.to_string(), true);
    for (action, expected) in [
        ("suspend", vec![call("Suspend")]),
        ("reboot", vec![call("Reboot")]),
        ("poweroff", vec![call("PowerOff")]),
        ("firmware", vec![call("SetRebootToFirmwareSetup"), call("Reboot")]),
    ] {
        let out = psc(&address, &["power", action]);
        assert!(out.status.success(), "{action}: {out:?}");
        assert_eq!(taken(&calls), expected, "{action}");
    }

    // refused: exit 1 with logind's reason, and firmware stops before rebooting
    fail.lock().unwrap().push("SetRebootToFirmwareSetup".into());
    let out = psc(&address, &["power", "firmware"]);
    assert_eq!(out.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&out.stderr).contains("refused by the test"), "{out:?}");
    assert_eq!(taken(&calls), [call("SetRebootToFirmwareSetup")]);

    for bad in [&["power"][..], &["power", "hibernate"], &["power", "reboot", "now"]] {
        assert_eq!(psc(&address, bad).status.code(), Some(2), "{bad:?}");
    }
    assert!(taken(&calls).is_empty(), "bad arguments call nothing");
}
