//! What the shell's D-Bus agents share. An agent answers some calls long after they arrive (once the
//! owner has typed a password or agreed to a pairing), so calls are handled by hand here, each kept
//! as its message until it's answered, instead of through zbus's object server.

use std::thread;

use zbus::blocking::{fdo::DBusProxy, Connection, MessageIterator};
use zbus::message::Type;
use zbus::names::BusName;
pub use zbus::{self, zvariant, Message};

const INTROSPECTABLE: &str = "org.freedesktop.DBus.Introspectable";

/// The session bus for `--session` (the tests), else the system bus.
pub fn connect(session: bool) -> zbus::Result<Connection> {
    if session {
        Connection::session()
    } else {
        Connection::system()
    }
}

/// The connection's own name on the bus (":1.42").
pub fn unique_name(connection: &Connection) -> String {
    connection.unique_name().map(|n| n.to_string()).unwrap_or_default()
}

/// A method call on the served object, waiting for its answer.
pub struct Call {
    pub message: Message,
    pub member: String,
    pub sender: String,
}

/// The calls arriving on the connection from now on. Take it before registering with a daemon or
/// telling the shell "ready": a call that arrives before anyone listens is never answered.
pub fn calls(connection: &Connection) -> MessageIterator {
    MessageIterator::from(connection)
}

/// Serves one object: every call to `interface` at `path` goes to `on_call`, which answers it with
/// [`reply`] or [`refuse`], then or later. `introspection` is the interface's XML (`<interface …>`),
/// given to whoever asks: `gdbus call`, which the tests use, reads the argument types from it.
/// Returns when the connection ends.
pub fn serve(connection: &Connection, calls: MessageIterator, path: &str, interface: &str, introspection: &str, mut on_call: impl FnMut(Call)) {
    for message in calls {
        let Ok(message) = message else { return };
        let header = message.header();
        if header.message_type() != Type::MethodCall {
            continue;
        }
        if header.path().map(|p| p.as_str()) != Some(path) {
            drop(header);
            refuse(connection, &message, "org.freedesktop.DBus.Error.UnknownObject", "No such object");
            continue;
        }
        let member = header.member().map(|m| m.to_string()).unwrap_or_default();
        let called = header.interface().map(|i| i.to_string()).unwrap_or_default();
        if called == INTROSPECTABLE && member == "Introspect" {
            let xml = format!(
                "<!DOCTYPE node PUBLIC \"-//freedesktop//DTD D-BUS Object Introspection 1.0//EN\" \
                 \"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd\">\n<node>{introspection}</node>"
            );
            reply(connection, &message, &(xml,));
        } else if called == interface || called.is_empty() {
            let sender = header.sender().map(|s| s.to_string()).unwrap_or_default();
            drop(header);
            on_call(Call { message, member, sender });
        } else {
            refuse(connection, &message, "org.freedesktop.DBus.Error.UnknownMethod", "No such method");
        }
    }
}

/// Answers a call. A caller that has gone is not an error worth more than a log line.
pub fn reply<B>(connection: &Connection, call: &Message, body: &B)
where
    B: serde::Serialize + zvariant::DynamicType,
{
    if let Err(e) = connection.reply(&call.header(), body) {
        pistachio_lines::log(&format!("could not answer a call: {e}"));
    }
}

/// Answers a call with a D-Bus error.
pub fn refuse(connection: &Connection, call: &Message, name: &str, text: &str) {
    if let Err(e) = connection.reply_error(&call.header(), name, &(text,)) {
        pistachio_lines::log(&format!("could not answer a call: {e}"));
    }
}

/// Watches who owns `name`, on a thread of its own: `on_change` hears the owner's unique name when
/// the service is there (at once, if it already is) and `None` when it goes. With `start` the bus is
/// asked to start the service first.
pub fn watch_name(connection: &Connection, name: &'static str, start: bool, on_change: impl Fn(Option<String>) + Send + 'static) -> zbus::Result<()> {
    let bus = DBusProxy::new(connection)?;
    let changes = bus.receive_name_owner_changed_with_args(&[(0, name)])?;
    if start {
        let _ = connection.call_method(Some("org.freedesktop.DBus"), "/org/freedesktop/DBus", Some("org.freedesktop.DBus"), "StartServiceByName", &(name, 0u32));
    }
    // an owner that appears between subscribing and asking is told once, not twice
    let mut last = bus.get_name_owner(BusName::try_from(name)?).ok().map(|owner| owner.to_string());
    if last.is_some() {
        on_change(last.clone());
    }
    thread::spawn(move || {
        for change in changes {
            let Ok(args) = change.args() else { continue };
            let owner = args.new_owner().as_ref().map(|owner| owner.to_string());
            if owner != last {
                last = owner.clone();
                on_change(owner);
            }
        }
    });
    Ok(())
}
