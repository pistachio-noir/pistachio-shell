//! `psc events FROM TO`: calendar events for the shell's month calendar (services/Events.qml), read from
//! Evolution Data Server, where GNOME Calendar keeps them. Read-only: nothing is ever written. Python's
//! events.py until 20 November 2026 (owner's call: no Python at runtime).
//!
//!   psc events FROM TO      dates as YYYY-MM-DD, TO exclusive (without them: the weeks around this month)
//!
//! prints one JSON line:
//!
//!   {"calendars": [{"uid", "name", "color"}],
//!    "events": [{"calendar", "title", "location", "start", "end", "allDay"}]}
//!
//! start and end are local times in ms since the epoch; an all-day event's end is the day after its last
//! day. Repeating events come as one entry per occurrence (EDS expands them, with their time zones). Every
//! enabled calendar is read; one that can't be opened (an offline account) is named on stderr and left out.
//!
//! EDS has no Rust bindings, so libecal, libedataserver and libical-glib are loaded at run time (dlopen):
//! psc builds and runs without them, and then this prints "events: unavailable: …" on stderr and exits 1,
//! which Events.qml takes as "can't read calendars". Signatures and ownership were checked against the
//! installed headers and GIR files (EDS 3.62.1, libical 4.0.8): the registry, the source list and each
//! client are ours to free; everything else here is borrowed and never freed.
//!
//! One intended difference from events.py: EDS resolves floating times ("12:00", no zone) in the client's
//! default zone, which is UTC unless set, so events.py put a 12:00 lunch at 13:00 in Warsaw. The local zone
//! is set as each client's default, so a floating time is local time, as events.py's own notes meant.

use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};

use gio::glib::ffi::{g_error_free, g_list_free_full, gboolean, gpointer, GError, GList, GFALSE, GTRUE};
use gio::glib::gobject_ffi::g_object_unref;
use serde_json::{json, Value};

/// A local calendar never reports itself connected; reads work after a second (checked), so waiting longer
/// only delays.
const WAIT_SECONDS: u32 = 1;
const EVENTS: c_int = 0; // E_CAL_CLIENT_SOURCE_TYPE_EVENTS
const CALENDAR: &CStr = c"Calendar"; // E_SOURCE_EXTENSION_CALENDAR

type Ptr = *mut c_void;
type InstanceCb = unsafe extern "C" fn(Ptr, Ptr, Ptr, gpointer, Ptr, *mut *mut GError) -> gboolean;

/// The functions used, looked up once. Each library's soname first, then the unversioned name.
struct Eds {
    registry_new_sync: unsafe extern "C" fn(Ptr, *mut *mut GError) -> Ptr,
    registry_list_enabled: unsafe extern "C" fn(Ptr, *const c_char) -> *mut GList,
    source_get_extension: unsafe extern "C" fn(Ptr, *const c_char) -> Ptr,
    source_get_uid: unsafe extern "C" fn(Ptr) -> *const c_char,
    source_get_display_name: unsafe extern "C" fn(Ptr) -> *const c_char,
    selectable_get_color: unsafe extern "C" fn(Ptr) -> *const c_char,
    client_connect_sync: unsafe extern "C" fn(Ptr, c_int, u32, Ptr, *mut *mut GError) -> Ptr,
    client_set_default_timezone: unsafe extern "C" fn(Ptr, Ptr),
    client_generate_instances_sync: unsafe extern "C" fn(Ptr, libc::time_t, libc::time_t, Ptr, InstanceCb, gpointer),
    builtin_timezone: unsafe extern "C" fn(*const c_char) -> Ptr,
    time_is_date: unsafe extern "C" fn(Ptr) -> gboolean,
    time_is_utc: unsafe extern "C" fn(Ptr) -> gboolean,
    time_is_null_time: unsafe extern "C" fn(Ptr) -> gboolean,
    time_get_timezone: unsafe extern "C" fn(Ptr) -> Ptr,
    time_as_timet_with_zone: unsafe extern "C" fn(Ptr, Ptr) -> libc::time_t,
    time_get_year: unsafe extern "C" fn(Ptr) -> c_int,
    time_get_month: unsafe extern "C" fn(Ptr) -> c_int,
    time_get_day: unsafe extern "C" fn(Ptr) -> c_int,
    time_get_hour: unsafe extern "C" fn(Ptr) -> c_int,
    time_get_minute: unsafe extern "C" fn(Ptr) -> c_int,
    time_get_second: unsafe extern "C" fn(Ptr) -> c_int,
    component_get_summary: unsafe extern "C" fn(Ptr) -> *const c_char,
    component_get_location: unsafe extern "C" fn(Ptr) -> *const c_char,
}

const ECAL: &[&str] = &["libecal-2.0.so.3", "libecal-2.0.so"];
const EDATASERVER: &[&str] = &["libedataserver-1.2.so.28", "libedataserver-1.2.so"];
const ICALGLIB: &[&str] = &["libical-glib.so.4", "libical-glib.so"];

fn open(names: &[&str]) -> Result<Ptr, String> {
    for name in names {
        let c = CString::new(*name).expect("no NUL in a library name");
        // SAFETY: dlopen takes a NUL-terminated name; the handle is kept for the life of the process.
        let handle = unsafe { libc::dlopen(c.as_ptr(), libc::RTLD_NOW | libc::RTLD_LOCAL) };
        if !handle.is_null() {
            return Ok(handle);
        }
    }
    Err(format!("{} not found", names[0]))
}

fn symbol<T: Copy>(handle: Ptr, name: &str) -> Result<T, String> {
    assert_eq!(std::mem::size_of::<T>(), std::mem::size_of::<Ptr>(), "a function pointer");
    let c = CString::new(name).expect("no NUL in a symbol name");
    // SAFETY: handle came from dlopen; the symbol's C signature is the one written in `Eds` (checked
    // against the installed headers), so reading the address as that function pointer type is sound.
    unsafe {
        let address = libc::dlsym(handle, c.as_ptr());
        if address.is_null() {
            return Err(format!("{name} missing"));
        }
        Ok(std::mem::transmute_copy::<Ptr, T>(&address))
    }
}

impl Eds {
    fn load(ecal: &[&str], edataserver: &[&str], icalglib: &[&str]) -> Result<Eds, String> {
        let (cal, data, ical) = (open(ecal)?, open(edataserver)?, open(icalglib)?);
        Ok(Eds {
            registry_new_sync: symbol(data, "e_source_registry_new_sync")?,
            registry_list_enabled: symbol(data, "e_source_registry_list_enabled")?,
            source_get_extension: symbol(data, "e_source_get_extension")?,
            source_get_uid: symbol(data, "e_source_get_uid")?,
            source_get_display_name: symbol(data, "e_source_get_display_name")?,
            selectable_get_color: symbol(data, "e_source_selectable_get_color")?,
            client_connect_sync: symbol(cal, "e_cal_client_connect_sync")?,
            client_set_default_timezone: symbol(cal, "e_cal_client_set_default_timezone")?,
            client_generate_instances_sync: symbol(cal, "e_cal_client_generate_instances_sync")?,
            builtin_timezone: symbol(ical, "i_cal_timezone_get_builtin_timezone")?,
            time_is_date: symbol(ical, "i_cal_time_is_date")?,
            time_is_utc: symbol(ical, "i_cal_time_is_utc")?,
            time_is_null_time: symbol(ical, "i_cal_time_is_null_time")?,
            time_get_timezone: symbol(ical, "i_cal_time_get_timezone")?,
            time_as_timet_with_zone: symbol(ical, "i_cal_time_as_timet_with_zone")?,
            time_get_year: symbol(ical, "i_cal_time_get_year")?,
            time_get_month: symbol(ical, "i_cal_time_get_month")?,
            time_get_day: symbol(ical, "i_cal_time_get_day")?,
            time_get_hour: symbol(ical, "i_cal_time_get_hour")?,
            time_get_minute: symbol(ical, "i_cal_time_get_minute")?,
            time_get_second: symbol(ical, "i_cal_time_get_second")?,
            component_get_summary: symbol(ical, "i_cal_component_get_summary")?,
            component_get_location: symbol(ical, "i_cal_component_get_location")?,
        })
    }
}

/// A borrowed C string as text ("" for NULL).
fn text(p: *const c_char) -> String {
    if p.is_null() {
        return String::new();
    }
    // SAFETY: a non-NULL pointer from EDS/libical is a NUL-terminated string valid for this call.
    unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned()
}

/// Takes and frees a GError, returning its message.
fn error(e: *mut GError) -> String {
    if e.is_null() {
        return "unknown error".into();
    }
    // SAFETY: e was set by the call that failed; we own it and free it once.
    unsafe {
        let message = text((*e).message);
        g_error_free(e);
        message
    }
}

unsafe extern "C" fn unref(object: gpointer) {
    g_object_unref(object as *mut _);
}

/// A local wall-clock time as seconds since the epoch, as Python's naive datetime.timestamp() reads it.
pub fn local_seconds(year: i32, month: i32, day: i32, hour: i32, minute: i32, second: i32) -> i64 {
    // SAFETY: tm is fully initialised from zero; mktime only reads and normalises it.
    unsafe {
        let mut tm: libc::tm = std::mem::zeroed();
        tm.tm_year = year - 1900;
        tm.tm_mon = month - 1;
        tm.tm_mday = day;
        tm.tm_hour = hour;
        tm.tm_min = minute;
        tm.tm_sec = second;
        tm.tm_isdst = -1;
        libc::mktime(&mut tm) as i64
    }
}

/// "YYYY-MM-DD" as (year, month, day).
pub fn parse_date(s: &str) -> Option<(i32, i32, i32)> {
    let mut parts = s.split('-');
    let (y, m, d) = (parts.next()?.parse().ok()?, parts.next()?.parse().ok()?, parts.next()?.parse().ok()?);
    if parts.next().is_some() || s.len() != 10 || !(1..=12).contains(&m) || !(1..=31).contains(&d) {
        return None;
    }
    Some((y, m, d))
}

/// The local zone's name for libical: TZ ("Europe/Warsaw" or ":Europe/Warsaw"), else /etc/localtime's link.
pub fn local_zone_name(tz: Option<String>, localtime: Option<std::path::PathBuf>) -> Option<String> {
    if let Some(tz) = tz.map(|t| t.trim_start_matches(':').to_string()).filter(|t| t.contains('/')) {
        return Some(tz);
    }
    let link = localtime?.to_string_lossy().into_owned();
    link.split_once("zoneinfo/").map(|(_, name)| name.to_string()).filter(|n| !n.is_empty())
}

struct Reading<'a> {
    eds: &'a Eds,
    calendar: String,
    events: Vec<Value>,
}

impl Eds {
    /// A component time as ms since the epoch, and whether it's a whole day. A time is read in its own zone
    /// (libical's as_timet_with_zone takes the zone the time is in, not one to convert to); a date is local.
    unsafe fn ms(&self, t: Ptr) -> (i64, bool) {
        let (y, mo, d) = ((self.time_get_year)(t), (self.time_get_month)(t), (self.time_get_day)(t));
        if (self.time_is_date)(t) != GFALSE {
            return (local_seconds(y, mo, d, 0, 0, 0) * 1000, true);
        }
        let zone = (self.time_get_timezone)(t);
        if zone.is_null() && (self.time_is_utc)(t) == GFALSE {
            let (h, mi, s) = ((self.time_get_hour)(t), (self.time_get_minute)(t), (self.time_get_second)(t));
            return (local_seconds(y, mo, d, h, mi, s) * 1000, false);
        }
        ((self.time_as_timet_with_zone)(t, zone) as i64 * 1000, false)
    }
}

/// One occurrence, from e_cal_client_generate_instances_sync. Everything passed in is borrowed.
unsafe extern "C" fn found(component: Ptr, start: Ptr, end: Ptr, data: gpointer, _: Ptr, _: *mut *mut GError) -> gboolean {
    let reading = &mut *(data as *mut Reading);
    let done = catch_unwind(AssertUnwindSafe(|| {
        let eds = reading.eds;
        let (first, all_day) = eds.ms(start);
        let (last, _) = if !end.is_null() && (eds.time_is_null_time)(end) == GFALSE { eds.ms(end) } else { (first, all_day) };
        reading.events.push(json!({
            "calendar": reading.calendar,
            "title": text((eds.component_get_summary)(component)),
            "location": text((eds.component_get_location)(component)),
            "start": first,
            "end": last.max(first),
            "allDay": all_day,
        }));
    }));
    if done.is_ok() { GTRUE } else { GFALSE }
}

fn read(eds: &Eds, begin: i64, finish: i64, zone_name: Option<&str>) -> Result<Value, String> {
    let mut calendars = Vec::new();
    let mut events = Vec::new();
    // SAFETY: each call follows its C signature (see `Eds`); owned results (registry, list, clients) are
    // freed exactly once below; borrowed ones (sources in the list, extensions, strings, zones) never are.
    unsafe {
        let mut e: *mut GError = std::ptr::null_mut();
        let registry = (eds.registry_new_sync)(std::ptr::null_mut(), &mut e);
        if registry.is_null() {
            return Err(error(e));
        }
        let zone = match zone_name {
            Some(name) => CString::new(name).map(|n| (eds.builtin_timezone)(n.as_ptr())).unwrap_or(std::ptr::null_mut()),
            None => std::ptr::null_mut(),
        };
        let list = (eds.registry_list_enabled)(registry, CALENDAR.as_ptr());
        let mut node = list;
        while !node.is_null() {
            let source = (*node).data as Ptr;
            node = (*node).next;
            let name = text((eds.source_get_display_name)(source));
            let uid = text((eds.source_get_uid)(source));
            let extension = (eds.source_get_extension)(source, CALENDAR.as_ptr());
            let mut e: *mut GError = std::ptr::null_mut();
            let client = (eds.client_connect_sync)(source, EVENTS, WAIT_SECONDS, std::ptr::null_mut(), &mut e);
            if client.is_null() {
                eprintln!("events: {name}: {}", error(e)); // an account that's offline or gone
                continue;
            }
            let color = if extension.is_null() { String::new() } else { text((eds.selectable_get_color)(extension)) };
            calendars.push(json!({"uid": uid, "name": name, "color": color}));
            if !zone.is_null() {
                (eds.client_set_default_timezone)(client, zone);
            }
            let mut reading = Reading { eds, calendar: uid, events: Vec::new() };
            (eds.client_generate_instances_sync)(client, begin as libc::time_t, finish as libc::time_t, std::ptr::null_mut(), found, &mut reading as *mut Reading as gpointer);
            events.append(&mut reading.events);
            g_object_unref(client as *mut _);
        }
        if !list.is_null() {
            g_list_free_full(list, Some(unref));
        }
        g_object_unref(registry as *mut _);
    }
    sort(&mut events);
    Ok(json!({"calendars": calendars, "events": events}))
}

/// By start, all-day ones first, then by title (as events.py sorted).
pub fn sort(events: &mut [Value]) {
    events.sort_by_cached_key(|e| {
        (e["start"].as_i64().unwrap_or(0), !e["allDay"].as_bool().unwrap_or(false), e["title"].as_str().unwrap_or("").to_lowercase())
    });
}

/// The range to read: FROM and TO as given, else from a week before this month to 50 days later.
pub fn range(args: &[String], today: (i32, i32)) -> (i64, i64) {
    match (args.first().and_then(|a| parse_date(a)), args.get(1).and_then(|a| parse_date(a))) {
        (Some((y, m, d)), Some((y2, m2, d2))) => (local_seconds(y, m, d, 0, 0, 0), local_seconds(y2, m2, d2, 0, 0, 0)),
        _ => {
            let (y, m) = today;
            (local_seconds(y, m, 1 - 7, 0, 0, 0), local_seconds(y, m, 1 - 7 + 50, 0, 0, 0))
        }
    }
}

/// Whether the libraries load: `psc doctor`'s calendar row.
pub fn available() -> bool {
    Eds::load(ECAL, EDATASERVER, ICALGLIB).is_ok()
}

pub fn main(args: &[String]) -> i32 {
    let eds = match Eds::load(ECAL, EDATASERVER, ICALGLIB) {
        Ok(eds) => eds,
        Err(e) => {
            eprintln!("events: unavailable: {e}");
            return 1;
        }
    };
    // SAFETY: localtime_r fills tm from the current time; nothing else is read.
    let today = unsafe {
        let now = libc::time(std::ptr::null_mut());
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&now, &mut tm);
        (tm.tm_year + 1900, tm.tm_mon + 1)
    };
    let (begin, finish) = range(args, today);
    let zone = local_zone_name(std::env::var("TZ").ok(), std::fs::read_link("/etc/localtime").ok());
    match read(&eds, begin, finish, zone.as_deref()) {
        Ok(result) => {
            println!("{result}");
            0
        }
        Err(e) => {
            eprintln!("events: {e}");
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dates_parse_strictly() {
        assert_eq!(parse_date("2026-03-01"), Some((2026, 3, 1)));
        for bad in ["2026-3-1", "2026-13-01", "2026-03-00", "2026-03-01-02", "", "march"] {
            assert_eq!(parse_date(bad), None, "{bad}");
        }
    }

    #[test]
    fn zone_from_tz_or_localtime() {
        assert_eq!(local_zone_name(Some(":Europe/Warsaw".into()), None).as_deref(), Some("Europe/Warsaw"));
        assert_eq!(local_zone_name(None, Some("/usr/share/zoneinfo/Europe/Warsaw".into())).as_deref(), Some("Europe/Warsaw"));
        assert_eq!(local_zone_name(Some("UTC".into()), Some("../usr/share/zoneinfo/America/New_York".into())).as_deref(), Some("America/New_York"));
        assert_eq!(local_zone_name(None, None), None);
    }

    #[test]
    fn sorted_by_start_then_all_day_then_title() {
        let mut events = vec![
            json!({"start": 2, "allDay": false, "title": "b"}),
            json!({"start": 1, "allDay": false, "title": "Zed"}),
            json!({"start": 1, "allDay": true, "title": "zz"}),
            json!({"start": 1, "allDay": false, "title": "apple"}),
        ];
        sort(&mut events);
        let titles: Vec<_> = events.iter().map(|e| e["title"].as_str().unwrap()).collect();
        assert_eq!(titles, ["zz", "apple", "Zed", "b"]);
    }

    #[test]
    fn default_range_is_the_weeks_around_this_month() {
        let (begin, finish) = range(&[], (2026, 3));
        assert_eq!(begin, local_seconds(2026, 2, 22, 0, 0, 0));
        assert_eq!(finish, local_seconds(2026, 4, 13, 0, 0, 0));
        assert_eq!(range(&["2026-03-01".into(), "2026-04-01".into()], (2000, 1)), (local_seconds(2026, 3, 1, 0, 0, 0), local_seconds(2026, 4, 1, 0, 0, 0)));
    }

    #[test]
    fn missing_libraries_are_reported_not_fatal() {
        let err = Eds::load(&["libno-such-ecal.so.99"], EDATASERVER, ICALGLIB).err().expect("fails");
        assert!(err.contains("libno-such-ecal.so.99 not found"), "{err}");
    }
}
