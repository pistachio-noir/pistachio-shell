//! `psc power suspend|reboot|poweroff|firmware`: the power menu's actions (services/Session.qml).
//! It was `systemctl …` until 21 November 2026; the owner moved to Gentoo with OpenRC, which has no
//! systemctl. Both systemd-logind and elogind serve org.freedesktop.login1 on the system bus, so asking
//! it directly works under either init. `interactive` is true, so polkit may ask when the rules want
//! it (logind allows all four for the active session without a password, checked on elogind 255).
//! A test may point the system bus elsewhere with DBUS_SYSTEM_BUS_ADDRESS (GLib honours it).
use gio::prelude::*;

const NAME: &str = "org.freedesktop.login1";
const PATH: &str = "/org/freedesktop/login1";
const MANAGER: &str = "org.freedesktop.login1.Manager";

fn call(bus: &gio::DBusConnection, method: &str, arg: bool) -> Result<(), String> {
    bus.call_sync(Some(NAME), PATH, MANAGER, method, Some(&(arg,).to_variant()), None, gio::DBusCallFlags::NONE, 10_000, gio::Cancellable::NONE)
        .map(|_| ())
        .map_err(|e| format!("{method}: {e}"))
}

/// The logind calls one action makes, in order.
pub fn calls(action: &str) -> Option<&'static [(&'static str, bool)]> {
    Some(match action {
        "suspend" => &[("Suspend", true)],
        "reboot" => &[("Reboot", true)],
        "poweroff" => &[("PowerOff", true)],
        // the firmware's setup on the next boot, then a reboot (what `systemctl reboot --firmware-setup` did)
        "firmware" => &[("SetRebootToFirmwareSetup", true), ("Reboot", true)],
        _ => return None,
    })
}

pub fn main(args: &[String]) -> i32 {
    let Some(steps) = args.first().and_then(|a| calls(a)).filter(|_| args.len() == 1) else {
        eprintln!("usage: psc power suspend|reboot|poweroff|firmware");
        return 2;
    };
    let bus = match gio::bus_get_sync(gio::BusType::System, gio::Cancellable::NONE) {
        Ok(bus) => bus,
        Err(e) => { eprintln!("psc power: no system bus: {e}"); return 1; }
    };
    for (method, arg) in steps {
        if let Err(e) = call(&bus, method, *arg) {
            eprintln!("psc power: {e}");
            return 1;
        }
    }
    0
}

/// Whether a logind (systemd's or elogind) owns its name on the system bus: `psc doctor`.
pub fn logind_running() -> bool {
    let bus = gio::bus_get_sync(gio::BusType::System, gio::Cancellable::NONE);
    // GDBus sets SIGPIPE to ignored when it starts; psc's main wants the default back, so
    // `psc doctor | head` still ends quietly (lifecycle test broken_pipe_is_quiet)
    unsafe { libc::signal(libc::SIGPIPE, libc::SIG_DFL) };
    let Ok(bus) = bus else { return false };
    bus.call_sync(Some("org.freedesktop.DBus"), "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner", Some(&(NAME,).to_variant()),
        Some(gio::glib::VariantTy::new("(b)").unwrap()), gio::DBusCallFlags::NONE, 2000, gio::Cancellable::NONE)
        .map(|v| v.child_value(0).get::<bool>().unwrap_or(false))
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn power_actions() {
        assert_eq!(calls("suspend"), Some(&[("Suspend", true)][..]));
        assert_eq!(calls("reboot"), Some(&[("Reboot", true)][..]));
        assert_eq!(calls("poweroff"), Some(&[("PowerOff", true)][..]));
        assert_eq!(calls("firmware"), Some(&[("SetRebootToFirmwareSetup", true), ("Reboot", true)][..]));
        assert_eq!(calls("hibernate"), None);
        assert_eq!(main(&["shutdown".into()]), 2);
        assert_eq!(main(&[]), 2);
        assert_eq!(main(&["reboot".into(), "now".into()]), 2);
    }
}
