//! `psc clocks …`: GNOME Clocks' alarms for the shell (services/Clocks.qml), through Clocks' own
//! settings (org.gnome.clocks alarms), so the shell's and Clocks' lists are the same. Python's
//! clocks.py until 19 November 2026; same arguments, one JSON line on stdout.
//!
//!   psc clocks list                     [{"id", "name", "hour", "minute", "days", "active"}]
//!   psc clocks add HOUR MINUTE [NAME]   a one-time alarm, active
//!   psc clocks set ID active|inactive
//!   psc clocks stop ID                  stop the matching GNOME alarm (its stop-alarm action), if running
//!   psc clocks snooze ID                snooze it the same way
//!   psc clocks remove ID
//!
//! GNOME Clocks 51 keeps an alarm on with `ring_time` and saves fields the shell doesn't use
//! (`sound_uri`…): every raw field and its type are kept when the shell writes.
use gio::prelude::*;
use gio::glib;
use glib::{Variant, VariantTy};
use serde_json::{json, Value};

struct Alarm {
    id: String,
    name: String,
    hour: i32,
    minute: i32,
    days: Vec<i32>,
    active: bool,
    raw: Vec<(String, Variant)>, // every field as GNOME saved it, in its order
}

fn field<'a>(raw: &'a [(String, Variant)], key: &str) -> Option<&'a Variant> {
    raw.iter().find(|(k, _)| k == key).map(|(_, v)| v)
}

fn read(settings: &gio::Settings) -> Vec<Alarm> {
    let alarms = settings.value("alarms");
    let mut out = vec![];
    for entry in alarms.iter() {
        let mut raw = vec![];
        for pair in entry.iter() {
            let (Some(k), Some(v)) = (pair.child_value(0).str().map(str::to_string), pair.child_value(1).as_variant()) else { continue };
            raw.push((k, v));
        }
        let s = |k: &str| field(&raw, k).and_then(|v| v.str().map(str::to_string)).unwrap_or_default();
        let i = |k: &str| field(&raw, k).and_then(|v| v.get::<i32>()).unwrap_or(0);
        let days = field(&raw, "days").and_then(|v| v.get::<Vec<i32>>()).unwrap_or_default();
        let active = field(&raw, "ring_time").is_some() || field(&raw, "active").and_then(|v| v.get::<bool>()).unwrap_or(false);
        out.push(Alarm { id: s("id"), name: s("name"), hour: i("hour"), minute: i("minute"), days, active, raw });
    }
    out
}

fn write(settings: &gio::Settings, alarms: &[Alarm]) -> Result<(), String> {
    let items: Vec<Variant> = alarms.iter().map(|a| {
        let mut raw = a.raw.clone();
        let mut put = |k: &str, v: Variant| match raw.iter_mut().find(|(key, _)| key == k) {
            Some(slot) => slot.1 = v,
            None => raw.push((k.to_string(), v)),
        };
        put("id", a.id.to_variant());
        put("name", a.name.to_variant());
        put("hour", a.hour.to_variant());
        put("minute", a.minute.to_variant());
        put("days", a.days.to_variant());
        put("active", a.active.to_variant());
        if !a.active {
            raw.retain(|(k, _)| k != "ring_time");
        }
        // DictEntry<String, Variant> boxes the value as `v` itself: wrapping it here too saved every field twice
        let entries: Vec<Variant> = raw.into_iter().map(|(k, v)| glib::variant::DictEntry::new(k, v).to_variant()).collect();
        Variant::array_from_iter_with_type(VariantTy::new("{sv}").unwrap(), entries)
    }).collect();
    settings.set_value("alarms", &Variant::array_from_iter_with_type(VariantTy::new("a{sv}").unwrap(), items)).map_err(|e| e.to_string())?;
    gio::Settings::sync();
    Ok(())
}

fn random_hex() -> String {
    let mut bytes = [0u8; 16];
    if let Ok(mut f) = std::fs::File::open("/dev/urandom") {
        let _ = std::io::Read::read_exact(&mut f, &mut bytes);
    }
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// GNOME Clocks' own stop-alarm / snooze-alarm action, when it runs; Ok(false) when it doesn't.
fn clocks_action(action: &str, id: &str) -> Result<bool, String> {
    let bus = gio::bus_get_sync(gio::BusType::Session, gio::Cancellable::NONE).map_err(|e| e.to_string())?;
    let owner = bus.call_sync(Some("org.freedesktop.DBus"), "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner",
        Some(&("org.gnome.clocks",).to_variant()), Some(VariantTy::new("(b)").unwrap()), gio::DBusCallFlags::NONE, 1000, gio::Cancellable::NONE)
        .map_err(|e| e.to_string())?;
    if !owner.child_value(0).get::<bool>().unwrap_or(false) {
        return Ok(false);
    }
    let params = (action, vec![id.to_variant()], std::collections::HashMap::<String, Variant>::new()).to_variant();
    bus.call_sync(Some("org.gnome.clocks"), "/org/gnome/clocks", "org.gtk.Actions", "Activate", Some(&params), None,
        gio::DBusCallFlags::NONE, 2000, gio::Cancellable::NONE).map_err(|e| e.to_string())?;
    Ok(true)
}

fn listing(alarms: &[Alarm]) -> Value {
    Value::Array(alarms.iter().map(|a| json!({"id": a.id, "name": a.name, "hour": a.hour, "minute": a.minute, "days": a.days, "active": a.active})).collect())
}

pub fn main(args: &[String]) -> i32 {
    let a: Vec<&str> = args.iter().map(String::as_str).collect();
    let settings = gio::Settings::new("org.gnome.clocks");
    let mut alarms = read(&settings);
    let done: Result<(), String> = match a.as_slice() {
        [] | ["list"] => Ok(()),
        ["add", hour, minute, name @ ..] => match (hour.parse::<i32>(), minute.parse::<i32>()) {
            (Ok(hour), Ok(minute)) => {
                let name = if name.is_empty() { "Alarm".to_string() } else { name.join(" ") };
                alarms.push(Alarm { id: random_hex(), name, hour, minute, days: vec![], active: true, raw: vec![] });
                write(&settings, &alarms)
            }
            _ => Err("usage: psc clocks add HOUR MINUTE [NAME]".into()),
        },
        ["set", id, state] => {
            for alarm in alarms.iter_mut().filter(|x| x.id == *id) { alarm.active = *state == "active"; }
            write(&settings, &alarms)
        }
        [action @ ("stop" | "snooze"), id] => match clocks_action(&format!("{action}-alarm"), id) {
            Ok(true) => Ok(()),
            // Clocks isn't running: the shell rang it, so a one-time alarm is done, as in Clocks
            Ok(false) if *action == "stop" => match alarms.iter_mut().find(|x| x.id == *id && x.days.is_empty()) {
                Some(alarm) => { alarm.active = false; write(&settings, &alarms) }
                None => Ok(()),
            },
            Ok(false) => Ok(()),
            Err(e) => Err(e),
        },
        ["remove", id] => { alarms.retain(|x| x.id != *id); write(&settings, &alarms) }
        _ => Err("usage: psc clocks list | add HOUR MINUTE [NAME] | set ID active|inactive | stop ID | snooze ID | remove ID".into()),
    };
    if let Err(e) = done {
        // as Python's uncaught exception: a message on stderr and exit 1, nothing on stdout
        eprintln!("psc clocks: {e}");
        return 1;
    }
    println!("{}", listing(&read(&settings)));
    0
}
