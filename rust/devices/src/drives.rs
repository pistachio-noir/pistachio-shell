//! Removable drives for the shell; services/Drives.qml runs it. It does what udiskie did for the
//! shell (`udiskie --automount --notify --no-tray`, whose rules and notification texts these are)
//! and what `udisksctl monitor` did: mount a drive the moment it's plugged in, and the ones already
//! in at startup, say so in notifications, and tell the shell whenever UDisks changes something.
//!
//!   out  {"event": "ready"}      watching UDisks; the drives already in are being mounted
//!   out  {"event": "changed"}    UDisks reported a change: the shell reads the mounted drives again
//!
//! Nothing comes in on stdin; it exits when stdin closes, so it never outlives the shell.
//!
//! Which devices: udiskie's defaults. A device is left alone when it, or the device it is a part
//! of, is marked by UDisks as one to ignore (HintIgnore) or is a whole system disk (HintSystem);
//! a loop device with a file behind it is handled (an image the owner set up), except the system's
//! own (/var/lib/extensions, /var/lib/confexts, snap).
//!
//! Notifications (app name and wording as udiskie's): "Device added", "Device mounted" with Browse
//! directory (xdg-open), "Device unmounted", "Device removed", "Job failed" with Retry. An encrypted
//! drive is not unlocked here (udiskie asked for its passphrase in a window of its own): one
//! notification says so and offers the file manager, which can unlock it.
//!
//! With --session it talks to a stand-in UDisks on the session bus (tests/drives.sh) and prints
//! each notification as {"event": "toast", "summary", "body", "icon", "actions": [labels]} instead
//! of showing it.

use std::collections::{HashMap, HashSet};
use std::sync::mpsc::{self, Receiver};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use pistachio_bus::zbus::blocking::{Connection, MessageIterator};
use pistachio_bus::zbus::message::Type;
use pistachio_bus::zbus::MatchRule;
use pistachio_bus::zvariant::{OwnedObjectPath, OwnedValue, Value};
use pistachio_bus as bus;
use pistachio_lines::{emit, log};
use serde_json::json;

const UDISKS: &str = "org.freedesktop.UDisks2";
const ROOT: &str = "/org/freedesktop/UDisks2";
const BLOCK: &str = "org.freedesktop.UDisks2.Block";
const FILESYSTEM: &str = "org.freedesktop.UDisks2.Filesystem";
const NOTIFICATIONS: &str = "org.freedesktop.Notifications";
/// Changes come in bursts (a drive brings several); one reading per burst.
const SETTLE: Duration = Duration::from_millis(150);

type Properties = HashMap<String, OwnedValue>;
type Objects = HashMap<OwnedObjectPath, HashMap<String, Properties>>;

fn get<T: TryFrom<OwnedValue>>(properties: Option<&Properties>, key: &str) -> Option<T> {
    properties?.get(key)?.try_clone().ok()?.try_into().ok()
}

/// A path UDisks gives as bytes with a NUL at the end.
fn text(bytes: Vec<u8>) -> String {
    String::from_utf8_lossy(bytes.split(|b| *b == 0).next().unwrap_or_default()).into_owned()
}

/// What this program needs to know of one block device.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Device {
    pub presentation: String, // the device file to show: /dev/sdb1
    pub label: String,
    pub uuid: String,
    pub drive_label: String, // the drive's vendor and model
    pub icon: String,
    pub ignored: bool,          // HintIgnore
    pub system: bool,           // HintSystem
    pub crypto: bool,           // holds an encrypted volume
    pub filesystem: bool,       // can be mounted
    pub mount_points: Vec<String>,
    pub table: Option<String>,   // the device this is a partition of
    pub backing: Option<String>, // the encrypted device this is the unlocked content of
    pub loop_file: Option<String>, // Some for a loop device, its file ("" when none)
}

/// The block devices UDisks knows, by object path.
pub type Snapshot = HashMap<String, Device>;

fn object_path(properties: Option<&Properties>, key: &str) -> Option<String> {
    get::<OwnedObjectPath>(properties, key).map(|p| p.to_string()).filter(|p| p != "/")
}

pub fn snapshot(objects: &Objects) -> Snapshot {
    let mut devices = Snapshot::new();
    for (path, interfaces) in objects {
        let Some(block) = interfaces.get(BLOCK) else { continue };
        let block = Some(block);
        let filesystem = interfaces.get(FILESYSTEM);
        let partition = interfaces.get("org.freedesktop.UDisks2.Partition");
        let loop_device = interfaces.get("org.freedesktop.UDisks2.Loop");
        let drive = object_path(block, "Drive").and_then(|drive| objects.iter().find(|(p, _)| p.as_str() == drive)).and_then(|(_, i)| i.get("org.freedesktop.UDisks2.Drive"));
        let words = [get::<String>(drive, "Vendor"), get::<String>(drive, "Model")];
        let presentation = get::<Vec<u8>>(block, "PreferredDevice").map(text).filter(|p| !p.is_empty()).or_else(|| get::<Vec<u8>>(block, "Device").map(text));
        devices.insert(
            path.to_string(),
            Device {
                presentation: presentation.unwrap_or_default(),
                label: get(block, "IdLabel").unwrap_or_default(),
                uuid: get(block, "IdUUID").unwrap_or_default(),
                drive_label: words.into_iter().flatten().filter(|w| !w.is_empty()).collect::<Vec<_>>().join(" "),
                icon: get::<String>(block, "HintIconName").filter(|i| !i.is_empty()).unwrap_or_else(|| "drive-removable-media".into()),
                ignored: get(block, "HintIgnore").unwrap_or(false),
                system: get(block, "HintSystem").unwrap_or(false),
                crypto: get::<String>(block, "IdUsage").as_deref() == Some("crypto"),
                filesystem: filesystem.is_some(),
                mount_points: get::<Vec<Vec<u8>>>(filesystem, "MountPoints").unwrap_or_default().into_iter().map(text).collect(),
                table: object_path(partition, "Table"),
                backing: object_path(block, "CryptoBackingDevice"),
                loop_file: loop_device.map(|l| get::<Vec<u8>>(Some(l), "BackingFile").map(text).unwrap_or_default()),
            },
        );
    }
    devices
}

impl Device {
    fn mounted(&self) -> bool {
        !self.mount_points.is_empty()
    }

    /// Not a part of another device.
    fn toplevel(&self) -> bool {
        self.table.is_none() && self.backing.is_none()
    }

    fn parent(&self) -> Option<&String> {
        self.table.as_ref().or(self.backing.as_ref())
    }
}

/// Whether the device is ours to mount and tell about (udiskie's default rules, first match wins,
/// asked of the device and then of each device it is a part of).
pub fn handleable(devices: &Snapshot, path: &str) -> bool {
    let mut at = devices.get(path);
    let mut steps = 0;
    while let Some(device) = at {
        if let Some(file) = &device.loop_file {
            if ["/var/lib/extensions/", "/var/lib/confexts/", "/var/lib/snapd/snaps/"].iter().any(|system| file.starts_with(system)) {
                return false;
            }
            if !device.ignored && file.starts_with('/') {
                return true;
            }
        }
        if (device.system && device.toplevel()) || device.ignored {
            return false;
        }
        steps += 1;
        at = device.parent().filter(|_| steps < 8).and_then(|parent| devices.get(parent));
    }
    true
}

fn unlocked(devices: &Snapshot, path: &str) -> bool {
    devices.values().any(|d| d.backing.as_deref() == Some(path))
}

/// A mountable device that isn't mounted yet.
fn addable(devices: &Snapshot, path: &str) -> bool {
    devices.get(path).is_some_and(|d| d.filesystem && !d.mounted()) && handleable(devices, path)
}

/// "/dev/sdb1: Label", as udiskie names a device.
fn ui_label(devices: &Snapshot, device: &Device) -> String {
    let shown = device.backing.as_ref().and_then(|b| devices.get(b)).map_or(&device.presentation, |b| &b.presentation);
    let name = [&device.label, &device.uuid, &device.drive_label].into_iter().find(|n| !n.is_empty());
    [Some(shown), name].into_iter().flatten().filter(|part| !part.is_empty()).cloned().collect::<Vec<_>>().join(": ")
}

/// What a notification's button does.
#[derive(Clone, Debug, PartialEq)]
pub enum Action {
    Browse(String),     // open the folder
    Retry(String),      // mount the device at this object path again
    FileManager,        // open the file manager, which can unlock an encrypted drive
}

#[derive(Clone, Debug, PartialEq)]
pub struct Toast {
    pub summary: &'static str,
    pub body: String,
    pub icon: String,
    pub actions: Vec<(&'static str, &'static str, Action)>, // key, label, what it does
}

/// What to do about a change.
#[derive(Debug, PartialEq)]
pub enum Step {
    Mount(String), // object path
    Show(Toast),
}

/// What follows from UDisks going from `old` to `new`. `first`: `old` is empty because this is the
/// first reading, so the drives already in are mounted without "Device added".
pub fn steps(old: &Snapshot, new: &Snapshot, first: bool) -> Vec<Step> {
    let mut out = Vec::new();
    let mut paths: Vec<&String> = new.keys().collect();
    paths.sort();
    for path in paths {
        let device = &new[path];
        let before = old.get(path);
        if !handleable(new, path) {
            continue;
        }
        if before.is_none() && !first && device.toplevel() && !device.presentation.is_empty() {
            out.push(Step::Show(Toast { summary: "Device added", body: format!("device appeared on {}", device.presentation), icon: device.icon.clone(), actions: vec![] }));
        }
        let was_mounted = before.is_some_and(Device::mounted);
        if device.mounted() && !was_mounted && !first {
            let folder = device.mount_points[0].clone();
            out.push(Step::Show(Toast {
                summary: "Device mounted",
                body: format!("{} mounted on {folder}", ui_label(new, device)),
                icon: device.icon.clone(),
                actions: vec![("browse", "Browse directory", Action::Browse(folder))],
            }));
        } else if !device.mounted() && was_mounted {
            out.push(Step::Show(Toast { summary: "Device unmounted", body: format!("{} unmounted", ui_label(new, device)), icon: device.icon.clone(), actions: vec![] }));
        }
        // new, or only now mountable (UDisks sometimes adds a device empty and fills it in later);
        // not one the owner just unmounted
        let was_removable = before.is_some_and(|b| b.filesystem && b.mounted());
        if addable(new, path) && (before.is_none() || (!addable(old, path) && !was_removable)) {
            out.push(Step::Mount(path.clone()));
        }
        let locked = |devices: &Snapshot| devices.get(path).is_some_and(|d| d.crypto) && !unlocked(devices, path);
        if locked(new) && (before.is_none() || !before.is_some_and(|b| b.crypto)) {
            out.push(Step::Show(Toast {
                summary: "Encrypted drive",
                body: format!("{} is encrypted. Open it in the file manager to unlock it.", ui_label(new, device)),
                icon: device.icon.clone(),
                actions: vec![("files", "Open file manager", Action::FileManager)],
            }));
        }
    }
    let mut gone: Vec<&String> = old.keys().filter(|path| !new.contains_key(*path)).collect();
    gone.sort();
    for path in gone {
        let device = &old[path];
        if handleable(old, path) && device.toplevel() && !device.presentation.is_empty() {
            out.push(Step::Show(Toast { summary: "Device removed", body: format!("device disappeared on {}", device.presentation), icon: device.icon.clone(), actions: vec![] }));
        }
    }
    out
}

struct Drives {
    udisks: Connection,
    notifications: Option<Connection>, // None with --session: toasts are printed
    buttons: Mutex<HashMap<u32, Vec<(&'static str, Action)>>>, // notification id -> its buttons
    mounting: Mutex<HashSet<String>>,
}

impl Drives {
    fn show(self: &Arc<Self>, toast: Toast) {
        let Some(notifications) = &self.notifications else {
            emit(&json!({"event": "toast", "summary": toast.summary, "body": toast.body, "icon": toast.icon, "actions": toast.actions.iter().map(|a| a.1).collect::<Vec<_>>()}));
            return;
        };
        let labels: Vec<&str> = toast.actions.iter().flat_map(|(key, label, _)| [*key, *label]).collect();
        let hints: HashMap<&str, Value> = HashMap::new();
        let shown = notifications
            .call_method(Some(NOTIFICATIONS), "/org/freedesktop/Notifications", Some(NOTIFICATIONS), "Notify", &("udiskie", 0u32, toast.icon.as_str(), toast.summary, toast.body.as_str(), labels, hints, -1i32))
            .and_then(|reply| reply.body().deserialize::<(u32,)>());
        match shown {
            Ok((id,)) if !toast.actions.is_empty() => {
                let mut buttons = self.buttons.lock().unwrap_or_else(|p| p.into_inner());
                if buttons.len() > 64 {
                    buttons.clear(); // old notifications nobody clicked
                }
                buttons.insert(id, toast.actions.into_iter().map(|(key, _, action)| (key, action)).collect());
            }
            Ok(_) => {}
            Err(e) => log(&format!("could not show a notification: {e}")),
        }
    }

    /// Mounts on a thread of its own: a slow drive must not hold up the others.
    fn mount(self: &Arc<Self>, path: String, shown: String, icon: String) {
        if !self.mounting.lock().unwrap_or_else(|p| p.into_inner()).insert(path.clone()) {
            return;
        }
        let drives = Arc::clone(self);
        thread::spawn(move || {
            let options: HashMap<&str, Value> = HashMap::new();
            let mounted = drives.udisks.call_method(Some(UDISKS), path.as_str(), Some(FILESYSTEM), "Mount", &(options,));
            drives.mounting.lock().unwrap_or_else(|p| p.into_inner()).remove(&path);
            if let Err(e) = mounted {
                let message = match &e {
                    bus::zbus::Error::MethodError(_, Some(message), _) => message.clone(),
                    other => other.to_string(),
                };
                let body = if message.is_empty() { format!("failed to mount device {shown}.") } else { format!("failed to mount {shown}:\n{message}") };
                drives.show(Toast { summary: "Job failed", body, icon, actions: vec![("retry", "Retry", Action::Retry(path))] });
            }
        });
    }

    fn act(self: &Arc<Self>, action: Action, devices: &Mutex<Snapshot>) {
        let open = |target: &str| {
            if let Err(e) = std::process::Command::new("xdg-open").arg(target).spawn().map(|mut child| thread::spawn(move || child.wait())) {
                log(&format!("could not run xdg-open: {e}"));
            }
        };
        match action {
            Action::Browse(folder) => open(&folder),
            Action::FileManager => open(&std::env::var("HOME").unwrap_or_else(|_| "/".into())),
            Action::Retry(path) => {
                let device = devices.lock().unwrap_or_else(|p| p.into_inner()).get(&path).cloned();
                if let Some(device) = device {
                    self.mount(path, device.presentation, device.icon);
                }
            }
        }
    }

    fn read(&self) -> Option<Snapshot> {
        let objects = self
            .udisks
            .call_method(Some(UDISKS), ROOT, Some("org.freedesktop.DBus.ObjectManager"), "GetManagedObjects", &())
            .and_then(|reply| reply.body().deserialize::<(Objects,)>());
        match objects {
            Ok((objects,)) => Some(snapshot(&objects)),
            Err(e) => {
                log(&format!("could not read UDisks: {e}"));
                None
            }
        }
    }
}

/// Sends a () for every signal matching the rule.
fn signals(connection: &Connection, rule: MatchRule<'static>) -> Option<Receiver<bus::Message>> {
    let messages = match MessageIterator::for_match_rule(rule, connection, Some(64)) {
        Ok(messages) => messages,
        Err(e) => {
            log(&format!("could not listen on the bus: {e}"));
            return None;
        }
    };
    let (heard, hears) = mpsc::channel();
    thread::spawn(move || {
        for message in messages.flatten() {
            if heard.send(message).is_err() {
                return;
            }
        }
    });
    Some(hears)
}

pub fn run(session: bool) {
    thread::spawn(|| {
        pistachio_lines::read_lines(|_| {});
        std::process::exit(0); // the shell is gone
    });
    let connect = |session| match bus::connect(session) {
        Ok(connection) => connection,
        Err(e) => {
            log(&format!("could not reach the bus: {e}"));
            std::process::exit(1);
        }
    };
    let drives = Arc::new(Drives { udisks: connect(session), notifications: (!session).then(|| connect(true)), buttons: Mutex::default(), mounting: Mutex::default() });
    let devices = Arc::new(Mutex::new(Snapshot::new()));

    if let Some(notifications) = &drives.notifications {
        let rule = MatchRule::builder().msg_type(Type::Signal).interface(NOTIFICATIONS).and_then(|b| b.member("ActionInvoked")).map(|b| b.build());
        if let Some(clicks) = rule.ok().and_then(|rule| signals(notifications, rule)) {
            let (drives, devices) = (Arc::clone(&drives), Arc::clone(&devices));
            thread::spawn(move || {
                for click in clicks {
                    let Ok((id, key)) = click.body().deserialize::<(u32, String)>() else { continue };
                    let action = drives.buttons.lock().unwrap_or_else(|p| p.into_inner()).get(&id).and_then(|buttons| buttons.iter().find(|(k, _)| *k == key).map(|(_, action)| action.clone()));
                    if let Some(action) = action {
                        drives.act(action, &devices);
                    }
                }
            });
        }
    }

    let rule = MatchRule::builder().msg_type(Type::Signal).path_namespace(ROOT).map(|b| b.build());
    let Some(changes) = rule.ok().and_then(|rule| signals(&drives.udisks, rule)) else { std::process::exit(1) };
    let mut first = true;
    loop {
        if let Some(new) = drives.read() {
            let old = std::mem::replace(&mut *devices.lock().unwrap_or_else(|p| p.into_inner()), new.clone());
            for step in steps(&old, &new, first) {
                match step {
                    Step::Show(toast) => drives.show(toast),
                    Step::Mount(path) => {
                        let device = &new[&path];
                        drives.mount(path, device.presentation.clone(), device.icon.clone());
                    }
                }
            }
            emit(&json!({"event": if first { "ready" } else { "changed" }}));
            first = false;
        }
        if changes.recv().is_err() {
            return;
        }
        thread::sleep(SETTLE);
        while changes.try_recv().is_ok() {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn stick() -> Snapshot {
        let disk = Device { presentation: "/dev/sdb".into(), drive_label: "Kingston DataTraveler".into(), icon: "drive-removable-media".into(), ..Device::default() };
        let part = Device { presentation: "/dev/sdb1".into(), label: "FILES".into(), filesystem: true, table: Some("/b/sdb".into()), icon: "drive-removable-media".into(), ..Device::default() };
        Snapshot::from([("/b/sdb".to_string(), disk), ("/b/sdb1".to_string(), part)])
    }

    fn bodies(steps: &[Step]) -> Vec<String> {
        steps.iter().map(|s| match s { Step::Mount(p) => format!("mount {p}"), Step::Show(t) => format!("{}: {}", t.summary, t.body) }).collect()
    }

    #[test]
    fn a_drive_already_in_at_startup_is_mounted_quietly() {
        assert_eq!(bodies(&steps(&Snapshot::new(), &stick(), true)), ["mount /b/sdb1"]);
    }

    #[test]
    fn a_drive_plugged_in_is_announced_and_mounted() {
        assert_eq!(bodies(&steps(&Snapshot::new(), &stick(), false)), ["Device added: device appeared on /dev/sdb", "mount /b/sdb1"]);
    }

    #[test]
    fn mounting_is_told_with_the_folder_and_a_browse_button() {
        let (old, mut new) = (stick(), stick());
        new.get_mut("/b/sdb1").unwrap().mount_points = vec!["/run/media/sx/FILES".into()];
        let out = steps(&old, &new, false);
        assert_eq!(bodies(&out), ["Device mounted: /dev/sdb1: FILES mounted on /run/media/sx/FILES"]);
        let Step::Show(toast) = &out[0] else { panic!() };
        assert_eq!(toast.actions, [("browse", "Browse directory", Action::Browse("/run/media/sx/FILES".into()))]);
    }

    #[test]
    fn unmounting_is_told_and_the_drive_is_not_mounted_again() {
        let (mut old, new) = (stick(), stick());
        old.get_mut("/b/sdb1").unwrap().mount_points = vec!["/run/media/sx/FILES".into()];
        assert_eq!(bodies(&steps(&old, &new, false)), ["Device unmounted: /dev/sdb1: FILES unmounted"]);
    }

    #[test]
    fn pulling_the_drive_out_is_told_once_for_the_drive() {
        assert_eq!(bodies(&steps(&stick(), &Snapshot::new(), false)), ["Device removed: device disappeared on /dev/sdb"]);
    }

    #[test]
    fn a_system_disk_and_its_partitions_are_left_alone() {
        let mut devices = stick();
        devices.get_mut("/b/sdb").unwrap().system = true;
        assert!(steps(&Snapshot::new(), &devices, false).is_empty());
        assert!(steps(&devices, &Snapshot::new(), false).is_empty());
    }

    #[test]
    fn an_ignored_partition_is_left_alone_but_its_drive_is_announced() {
        let mut devices = stick();
        devices.get_mut("/b/sdb1").unwrap().ignored = true;
        assert_eq!(bodies(&steps(&Snapshot::new(), &devices, false)), ["Device added: device appeared on /dev/sdb"]);
    }

    #[test]
    fn a_device_that_becomes_mountable_later_is_mounted_then() {
        let (mut old, new) = (stick(), stick());
        old.get_mut("/b/sdb1").unwrap().filesystem = false;
        assert_eq!(bodies(&steps(&old, &new, false)), ["mount /b/sdb1"]);
    }

    #[test]
    fn an_encrypted_drive_is_not_touched_only_told() {
        let mut devices = stick();
        let part = devices.get_mut("/b/sdb1").unwrap();
        part.filesystem = false;
        part.crypto = true;
        let out = steps(&Snapshot::new(), &devices, false);
        assert_eq!(bodies(&out), ["Device added: device appeared on /dev/sdb", "Encrypted drive: /dev/sdb1: FILES is encrypted. Open it in the file manager to unlock it."]);
        // unlocked elsewhere: its content appears and is mounted, named by the drive it's on
        let mut open = devices.clone();
        open.insert("/b/dm0".into(), Device { presentation: "/dev/dm-0".into(), label: "SECRET".into(), filesystem: true, backing: Some("/b/sdb1".into()), ..Device::default() });
        assert_eq!(bodies(&steps(&devices, &open, false)), ["mount /b/dm0"]);
        assert_eq!(ui_label(&open, &open["/b/dm0"]), "/dev/sdb1: SECRET");
    }

    #[test]
    fn an_image_the_owner_set_up_is_handled_the_systems_own_are_not() {
        let image = |file: &str| Snapshot::from([("/b/loop0".to_string(), Device { presentation: "/dev/loop0".into(), system: true, filesystem: true, loop_file: Some(file.into()), ..Device::default() })]);
        assert!(handleable(&image("/home/sx/arch.iso"), "/b/loop0"));
        assert!(!handleable(&image("/var/lib/snapd/snaps/core.snap"), "/b/loop0"));
        assert!(!handleable(&image(""), "/b/loop0"));
    }

    #[test]
    fn a_label_falls_back_to_the_uuid_then_the_drive() {
        let mut devices = stick();
        let part = devices.get_mut("/b/sdb1").unwrap();
        part.label.clear();
        part.uuid = "1234-ABCD".into();
        assert_eq!(ui_label(&devices, &devices["/b/sdb1"]), "/dev/sdb1: 1234-ABCD");
        assert_eq!(ui_label(&devices, &devices["/b/sdb"]), "/dev/sdb: Kingston DataTraveler");
    }
}
