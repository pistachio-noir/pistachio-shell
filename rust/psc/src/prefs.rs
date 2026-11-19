//! `psc prefs export|read PATH [JSON]`: the shell's preferences as TOML (Settings → About → Your
//! settings, services/Preferences.qml). Python's prefs.py until 19 November 2026; same arguments,
//! same JSON, same checks and messages.
//!
//! Owner's call, 15 November 2026: a one-off snapshot of every Settings preference and the launcher's
//! customisations in ~/.config/pistachio/pistachio-shell/settings.toml. Never the Cider token,
//! LocalSend's known devices, notification or usage history, running state, the wallpaper or desktop
//! icon positions.
//!
//!   psc prefs export PATH JSON   JSON = {"values": {storeKey: value}}; writes PATH (the old file kept
//!                                as PATH.bak), atomically; prints {"ok": true, "path": PATH}
//!   psc prefs read PATH JSON     JSON = {"actions": [ids], "claudeModels": [...], "codexModels": [...]}
//!                                prints {"ok": true, "values": {storeKey: value}, "skipped": [{key, reason}]}
//! Errors print {"ok": false, "error": "..."} and exit 1. JSON comes as an argument (stdin when left
//! out): Quickshell's Process can't reopen stdin once closed.
use serde_json::{json, Map, Value};
use std::io::Read;
use std::path::{Path, PathBuf};

const INTEGRATIONS: &[&str] = &["calendar", "clocks", "weather", "vscode", "clion", "steam", "sober", "cider", "claude", "qalc", "tldr"];
const EFFORTS: &[&str] = &["low", "medium", "high"];

pub enum Check {
    Bool, Choice(&'static [&'static str]), ChoiceInt(&'static [i64]), ChoiceCtx(&'static str), Text(usize), Time,
    Integer(i64, i64), Folder, Names(usize), GameClasses, ThemingKeep, Integrations, Rules, Pins, Aliases, Presets,
}
use Check::*;

const fn bool_() -> Check { Bool }
const fn choice(o: &'static [&'static str]) -> Check { Choice(o) }
const fn choice_int(o: &'static [i64]) -> Check { ChoiceInt(o) }
const fn ctx_choice(key: &'static str) -> Check { ChoiceCtx(key) }
const fn text(limit: usize) -> Check { Text(limit) }
const fn time() -> Check { Time }
const fn integer(lo: i64, hi: i64) -> Check { Integer(lo, hi) }
const fn folder() -> Check { Folder }
const fn names(limit: usize) -> Check { Names(limit) }
const fn game_classes() -> Check { GameClasses }
const fn theming_keep() -> Check { ThemingKeep }
const fn integrations() -> Check { Integrations }
const fn rules() -> Check { Rules }
const fn pins() -> Check { Pins }
const fn aliases() -> Check { Aliases }
const fn presets() -> Check { Presets }

/// (section, toml key, store key, check). tests/prefs.test.py reads the store keys from these lines
/// and checks they match Preferences.qml's titles: keep one row per line in this shape.
pub const SCHEMA: &[(&str, &str, &str, Check)] = &[
    ("appearance", "frosted", "frosted", bool_()),
    ("appearance", "frost_style", "frostStyle", choice(&["subtle", "glassy"])),
    ("appearance", "shadows", "shadows", bool_()),
    ("appearance", "desktop_icons", "desktopIcons", bool_()),
    ("appearance", "workspace_osd", "workspaceOsd", bool_()),
    ("appearance", "tabbed_osd", "tabbedOsd", bool_()),
    ("experimental", "style", "appearanceStyle", choice(&["classic", "tui"])),
    ("experimental", "tui_hyprland", "tuiHyprland", bool_()),
    ("experimental", "colours", "colourScheme", choice(&["pistachio", "noir"])),
    ("experimental", "tui_tray_open", "tuiTrayOpen", bool_()),
    ("experimental", "phone_preview", "phonePreview", bool_()),
    ("experimental", "desktop_cat", "desktopCat", bool_()),
    ("experimental", "cat_skin", "catSkin", choice(&["cream", "ginger", "midnight"])),
    ("experimental", "clipboard_history", "clipboardHistory", bool_()),
    ("experimental", "monochrome_wallpaper", "monochromeWallpaper", bool_()),
    ("experimental", "game_mode", "gameMode", bool_()),
    ("appearance", "theming_integration", "themingIntegration", bool_()),
    ("appearance", "theming_keep", "themingKeep", theming_keep()),
    ("experimental", "game_classes", "gameClasses", game_classes()),
    ("display", "night_light", "nightLight", bool_()),
    ("display", "night_warmth", "temperature", integer(2500, 6500)),
    ("display", "night_schedule", "nightSchedule", bool_()),
    ("display", "night_from", "nightFrom", time()),
    ("display", "night_to", "nightTo", time()),
    ("sound", "headphones_take_over", "headphonesTakeOver", bool_()),
    ("sound", "volume_tick", "volumeTick", bool_()),
    ("notifications", "do_not_disturb", "dnd", bool_()),
    ("notifications", "quiet_schedule", "dndSchedule", bool_()),
    ("notifications", "quiet_follows_night_light", "dndFollowsNight", bool_()),
    ("notifications", "quiet_from", "dndFrom", time()),
    ("notifications", "quiet_to", "dndTo", time()),
    ("notifications", "quiet_in_fullscreen", "quietFullscreen", bool_()),
    ("notifications", "quiet_during_calls", "quietCalls", bool_()),
    ("notifications", "sound", "notificationSound", bool_()),
    ("notifications", "rules", "notificationRules", rules()),
    ("focus", "zen_pomodoro", "zenPomodoro", bool_()),
    ("focus", "focus_pomodoro", "focusPomodoro", bool_()),
    ("focus", "focus_minutes", "focusMinutes", choice_int(&[15, 25, 30, 45, 50, 60, 90, 120])),
    ("focus", "zen_during_focus", "focusZen", bool_()),
    ("focus", "allowed_apps", "focusAllowed", names(200)),
    ("focus", "pomodoro_work", "pomodoroWork", choice_int(&[15, 20, 25, 30, 45, 50])),
    ("focus", "pomodoro_break", "pomodoroBreak", choice_int(&[3, 5, 10, 15])),
    ("focus", "pomodoro_long_break", "pomodoroLongBreak", choice_int(&[10, 15, 20, 30])),
    ("focus", "pomodoro_rounds", "pomodoroRounds", choice_int(&[2, 3, 4, 5, 6])),
    ("lens", "provider", "lensProvider", choice(&["claude", "codex"])),
    ("lens", "claude_model", "lensClaudeModel", ctx_choice("claudeModels")),
    ("lens", "claude_effort", "lensClaudeEffort", choice(EFFORTS)),
    ("lens", "codex_model", "lensCodexModel", ctx_choice("codexModels")),
    ("lens", "codex_effort", "lensCodexEffort", choice(EFFORTS)),
    ("lens", "claude_fallback", "lensClaudeFallback", bool_()),
    ("lens", "codex_fallback", "lensCodexFallback", bool_()),
    ("lens", "suggest_coding_model", "lensSuggestCoding", bool_()),
    ("lens", "claude_coding_model", "lensClaudeCodingModel", ctx_choice("claudeModels")),
    ("lens", "claude_coding_effort", "lensClaudeCodingEffort", choice(EFFORTS)),
    ("lens", "codex_coding_model", "lensCodexCodingModel", ctx_choice("codexModels")),
    ("lens", "codex_coding_effort", "lensCodexCodingEffort", choice(EFFORTS)),
    ("lens", "quick_chat_tile", "quickChatTile", bool_()),
    ("capture", "screenshot_output", "screenshotOutput", choice(&["save", "copy", "both"])),
    ("capture", "recording_audio", "recordingAudio", choice(&["off", "system", "mic", "both"])),
    ("capture", "recording_countdown", "recordingCountdown", choice_int(&[0, 3, 5, 10])),
    ("apps", "terminal", "terminal", text(64)),
    ("apps", "weather_city", "weatherCity", text(100)),
    ("integrations", "off", "integrationsOff", integrations()),
    ("integrations", "calendar_events", "calendarEvents", bool_()),
    ("localsend", "receive", "localsendReceive", bool_()),
    ("localsend", "name", "localsendName", text(64)),
    ("localsend", "folder", "localsendFolder", folder()),
    ("localsend", "accept_known", "localsendAcceptKnown", bool_()),
    ("launcher", "pins", "launcherPins", pins()),
    ("launcher", "aliases", "launcherAliases", aliases()),
    ("launcher", "presets", "workspacePresets", presets()),
];

const SECTIONS: &[(&str, &str)] = &[
    ("appearance", "Settings → Appearance"), ("experimental", "Settings → Experimental"), ("display", "Settings → Display & night light"),
    ("sound", "Settings → Sound"), ("notifications", "Settings → Notifications (rules: app = \"no toasts\")"),
    ("focus", "Settings → Focus & Zen"), ("lens", "Settings → Lens and AI"), ("capture", "the screenshot menu and recording setup"),
    ("apps", "Settings → Apps & places (terminal \"\" = automatic)"), ("integrations", "Settings → Integrations (off = the switched-off ones)"),
    ("localsend", "Settings → LocalSend (name/folder \"\" = automatic)"), ("launcher", "the launcher's pins, aliases and workspace presets"),
];

// --- checks ---------------------------------------------------------------------------------------

/// Python's repr of a value in a message: 'text' for strings, the JSON otherwise.
fn repr(v: &Value) -> String {
    match v { Value::String(s) => format!("'{s}'"), other => other.to_string() }
}

fn is_int(v: &Value) -> bool { v.is_i64() || v.is_u64() }

fn text_ok(v: &Value, limit: usize) -> Result<String, String> {
    match v.as_str() {
        Some(s) if s.chars().count() <= limit && !s.chars().any(|c| (c as u32) < 32) => Ok(s.to_string()),
        _ => Err(format!("expected text of at most {limit} characters")),
    }
}

fn names_ok(v: &Value, limit: usize) -> Result<Vec<String>, String> {
    let list = v.as_array().filter(|l| l.len() <= limit).ok_or("expected a list of names")?;
    let mut out: Vec<String> = vec![];
    for x in list {
        let s = x.as_str().filter(|s| !s.is_empty() && s.chars().count() <= 200).ok_or("expected a list of names")?;
        if !out.iter().any(|o| o == s) { out.push(s.to_string()); }
    }
    Ok(out)
}

fn expand(path: &str) -> String {
    match path.strip_prefix('~') {
        Some(rest) if rest.is_empty() || rest.starts_with('/') => format!("{}{rest}", std::env::var("HOME").unwrap_or_default()),
        _ => path.to_string(),
    }
}

fn target(entry: &Value, ctx: &Value, aliasing: bool) -> Result<Value, String> {
    let bad = || "expected { kind = ..., target = ... }".to_string();
    let obj = entry.as_object().ok_or_else(bad)?;
    if obj.len() != 2 || !obj.contains_key("kind") || !obj.contains_key("target") { return Err(bad()); }
    let target = obj["target"].as_str().filter(|t| !t.is_empty() && t.chars().count() <= 300).ok_or_else(bad)?;
    let kind = &obj["kind"];
    let actions: Vec<&str> = ctx.get("actions").and_then(Value::as_array).map(|a| a.iter().filter_map(Value::as_str).collect()).unwrap_or_default();
    if kind == "action" && !actions.contains(&target) {
        return Err(format!("unknown shell action '{target}'"));
    }
    let allowed: &[&str] = if aliasing { &["app", "action"] } else { &["app", "preset", "action"] };
    if !kind.as_str().is_some_and(|k| allowed.contains(&k)) {
        return Err(format!("kind {} can't be {}", repr(kind), if aliasing { "aliased" } else { "pinned" }));
    }
    Ok(json!({"kind": kind, "target": target}))
}

fn alias_name_ok(name: &str) -> bool {
    let n = name.chars().count();
    (1..=32).contains(&n) && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-' || ('\u{C0}'..='\u{24F}').contains(&c))
}

fn class_ok(s: &str) -> bool {
    (1..=100).contains(&s.len()) && s.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || matches!(c, '.' | '_' | '-'))
}

pub fn check(c: &Check, v: &Value, ctx: &Value) -> Result<Value, String> {
    match c {
        Bool => v.as_bool().map(Value::Bool).ok_or_else(|| "expected true or false".into()),
        Choice(opts) => match v.as_str() {
            Some(s) if opts.contains(&s) => Ok(v.clone()),
            _ => Err(format!("expected one of {}", opts.iter().map(|o| format!("\"{o}\"")).collect::<Vec<_>>().join(", "))),
        },
        ChoiceInt(opts) => match v.as_i64() {
            Some(n) if is_int(v) && opts.contains(&n) => Ok(v.clone()),
            _ => Err(format!("expected one of {}", opts.iter().map(|o| o.to_string()).collect::<Vec<_>>().join(", "))),
        },
        ChoiceCtx(key) => {
            let opts: Vec<&str> = ctx.get(*key).and_then(Value::as_array).ok_or(format!("'{key}'"))?.iter().filter_map(Value::as_str).collect();
            match v.as_str() {
                Some(s) if opts.contains(&s) => Ok(v.clone()),
                _ => Err(format!("expected one of {}", opts.iter().map(|o| format!("\"{o}\"")).collect::<Vec<_>>().join(", "))),
            }
        }
        Text(limit) => text_ok(v, *limit).map(Value::String),
        Time => {
            let parsed = v.as_str().and_then(|s| {
                let (h, m) = s.trim().split_once(':')?;
                let digits = |x: &str| !x.is_empty() && x.chars().all(|c| c.is_ascii_digit());
                if !(digits(h) && digits(m) && (1..=2).contains(&h.len()) && m.len() == 2) { return None; }
                let (h, m): (i64, i64) = (h.parse().ok()?, m.parse().ok()?);
                (h < 24 && m < 60).then_some(h * 60 + m)
            });
            parsed.map(|n| json!(n)).ok_or_else(|| "expected a time like \"20:00\"".into())
        }
        Integer(lo, hi) => match v.as_i64() {
            Some(n) if is_int(v) && (*lo..=*hi).contains(&n) => Ok(v.clone()),
            _ => Err(format!("expected a whole number from {lo} to {hi}")),
        },
        Folder => {
            let s = text_ok(v, 4096)?;
            if !s.is_empty() && !Path::new(&expand(&s)).is_dir() { return Err("that folder doesn't exist on this machine".into()); }
            Ok(Value::String(if s.is_empty() { s } else { expand(&s) }))
        }
        Names(limit) => names_ok(v, *limit).map(|n| json!(n)),
        GameClasses => {
            let list = v.as_array().filter(|l| l.len() <= 20).ok_or("expected up to 20 lowercase window classes")?;
            let mut out: Vec<&str> = vec![];
            for x in list {
                let s = x.as_str().filter(|s| class_ok(s)).ok_or("expected up to 20 lowercase window classes")?;
                if !out.contains(&s) { out.push(s); }
            }
            Ok(json!(out))
        }
        ThemingKeep => {
            let list = v.as_array().ok_or("expected a list of kitty / neovim")?;
            let mut out: Vec<&str> = vec![];
            for x in list {
                let s = x.as_str().filter(|s| matches!(*s, "kitty" | "neovim")).ok_or("expected a list of kitty / neovim")?;
                if !out.contains(&s) { out.push(s); }
            }
            Ok(json!(out))
        }
        Integrations => {
            let list = names_ok(v, INTEGRATIONS.len())?;
            let unknown: Vec<&str> = list.iter().map(String::as_str).filter(|x| !INTEGRATIONS.contains(x)).collect();
            if !unknown.is_empty() { return Err(format!("unknown integration {}", unknown.join(", "))); }
            Ok(json!(list))
        }
        Rules => {
            let table = v.as_object().filter(|t| t.len() <= 500).ok_or("expected app = \"no toasts\" lines")?;
            let mut out = Map::new();
            for (app, rule) in table {
                if rule != "no toasts" || app.is_empty() || app.chars().count() > 200 {
                    return Err(format!("'{app}': only \"no toasts\" can be imported"));
                }
                out.insert(app.clone(), json!({"noToasts": true}));
            }
            Ok(Value::Object(out))
        }
        Pins => {
            let list = v.as_array().filter(|l| l.len() <= 100).ok_or("expected a list of { kind, target }")?;
            let mut out: Vec<Value> = vec![];
            for entry in list {
                let t = target(entry, ctx, false)?;
                if !out.contains(&t) { out.push(t); }
            }
            Ok(Value::Array(out))
        }
        Aliases => {
            let table = v.as_object().filter(|t| t.len() <= 200).ok_or("expected alias = { kind, target } lines")?;
            let mut out = Map::new();
            for (name, entry) in table {
                if !alias_name_ok(name) { return Err(format!("alias '{name}': use 1–32 letters, numbers, _ or -")); }
                out.insert(name.to_lowercase(), target(entry, ctx, true)?);
            }
            Ok(Value::Object(out))
        }
        Presets => {
            let list = v.as_array().filter(|l| l.len() <= 50).ok_or("expected a list of presets")?;
            let ws = |k: &str| k.parse::<u32>().is_ok_and(|n| (1..=10).contains(&n)) && !k.starts_with('0');
            let mut out = vec![];
            let mut seen: Vec<String> = vec![];
            for p in list {
                let name = p.get("name").and_then(Value::as_str)
                    .filter(|n| !n.is_empty() && n.chars().count() <= 40 && !seen.iter().any(|s| s == n))
                    .ok_or("each preset needs a unique name")?;
                let empty = Value::Object(Map::new());
                let names = p.get("names").unwrap_or(&empty);
                let apps = p.get("apps").unwrap_or(&empty);
                let names_good = names.as_object().is_some_and(|o| o.iter().all(|(k, x)| ws(k) && x.as_str().is_some_and(|s| s.chars().count() <= 40)));
                if !names_good { return Err(format!("preset '{name}': names are workspace = \"name\" (1–10)")); }
                let apps_good = apps.as_object().is_some_and(|o| o.iter().all(|(k, x)| ws(k) && x.as_array().is_some_and(|a| a.len() <= 20
                    && a.iter().all(|s| s.as_str().is_some_and(|s| !s.is_empty() && s.chars().count() <= 300)))));
                if !apps_good { return Err(format!("preset '{name}': apps are workspace = [app ids] (1–10)")); }
                seen.push(name.to_string());
                out.push(json!({"name": name, "names": names, "apps": apps}));
            }
            Ok(Value::Array(out))
        }
    }
}

// --- writing TOML ---------------------------------------------------------------------------------

fn key(k: &str) -> String {
    if !k.is_empty() && k.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-') { k.to_string() } else { string(k) }
}

fn string(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' | '\\' => { out.push('\\'); out.push(c); }
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 32 || c as u32 == 127 => out.push_str(&format!("\\u{:04X}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn value(v: &Value) -> Result<String, String> {
    Ok(match v {
        Value::Bool(b) => b.to_string(),
        Value::Number(n) if n.is_i64() || n.is_u64() => n.to_string(),
        Value::Number(n) => match n.as_f64() {
            Some(f) if f.fract() == 0.0 && f.abs() < 9.0e15 => format!("{}", f as i64),
            _ => return Err("can't write float".into()),
        },
        Value::String(s) => string(s),
        Value::Array(a) => format!("[{}]", a.iter().map(value).collect::<Result<Vec<_>, _>>()?.join(", ")),
        Value::Object(o) if o.is_empty() => "{}".into(),
        Value::Object(o) => format!("{{ {} }}", o.iter().map(|(k, x)| Ok(format!("{} = {}", key(k), value(x)?))).collect::<Result<Vec<_>, String>>()?.join(", ")),
        Value::Null => return Err("can't write NoneType".into()),
    })
}

/// QML hands numbers over as floats; whole ones go back to whole numbers.
fn plain(v: &Value) -> Value {
    match v {
        Value::Number(n) if !n.is_i64() && !n.is_u64() => match n.as_f64() {
            Some(f) if f.fract() == 0.0 && f.abs() < 9.0e15 => json!(f as i64),
            _ => v.clone(),
        },
        Value::Array(a) => Value::Array(a.iter().map(plain).collect()),
        Value::Object(o) => Value::Object(o.iter().map(|(k, x)| (k.clone(), plain(x))).collect()),
        _ => v.clone(),
    }
}

fn now() -> String {
    let mut buf = [0u8; 64];
    unsafe {
        let t = libc::time(std::ptr::null_mut());
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&t, &mut tm);
        let n = libc::strftime(buf.as_mut_ptr() as *mut libc::c_char, buf.len(), c"%-d %b %Y %H:%M".as_ptr(), &tm);
        String::from_utf8_lossy(&buf[..n]).into_owned()
    }
}

pub fn to_toml(values: &Map<String, Value>) -> Result<String, String> {
    let mut lines = vec![
        format!("# Pistachio shell settings, exported {}.", now()),
        "# Import them in Settings → About → Your settings; you'll see the changes before they apply.".to_string(),
        "# Times are 24-hour \"HH:MM\". Left out on purpose: tokens, LocalSend's known devices, history.".to_string(),
    ];
    for (section, comment) in SECTIONS {
        let rows: Vec<(&str, &str)> = SCHEMA.iter().filter(|r| r.0 == *section && values.contains_key(r.2)).map(|r| (r.1, r.2)).collect();
        if rows.is_empty() { continue; }
        lines.extend(["".to_string(), format!("# {comment}"), format!("[{section}]")]);
        let mut tables: Vec<(&str, Value)> = vec![];
        for (tk, sk) in rows {
            let mut v = plain(&values[sk]);
            if matches!(sk, "nightFrom" | "nightTo" | "dndFrom" | "dndTo") {
                if let Some(n) = v.as_i64() { v = json!(format!("{:02}:{:02}", n.div_euclid(60), n.rem_euclid(60))); }
            }
            if sk == "notificationRules" {
                let mut out = Map::new();
                if let Some(o) = v.as_object() {
                    for (app, r) in o {
                        if r.get("noToasts").and_then(Value::as_bool).unwrap_or(false) { out.insert(app.clone(), json!("no toasts")); }
                    }
                }
                tables.push((tk, Value::Object(out)));
                continue;
            }
            if sk == "launcherAliases" {
                tables.push((tk, if v.is_null() { json!({}) } else { v }));
                continue;
            }
            if sk == "workspacePresets" && v.as_array().is_some_and(|a| !a.is_empty()) {
                tables.push(("presets", v)); // one [[launcher.presets]] each; none is `presets = []`
                continue;
            }
            lines.push(format!("{} = {}", key(tk), value(&v)?));
        }
        for (tk, v) in tables {
            match v {
                Value::Array(list) => {
                    for p in list {
                        lines.extend(["".to_string(), format!("[[{section}.{tk}]]")]);
                        if let Some(o) = p.as_object() {
                            for (k, x) in o { lines.push(format!("{} = {}", key(k), value(x)?)); }
                        }
                    }
                }
                Value::Object(o) => {
                    lines.extend(["".to_string(), format!("[{section}.{tk}]")]);
                    for (k, x) in &o { lines.push(format!("{} = {}", key(k), value(x)?)); }
                }
                other => lines.push(format!("{} = {}", key(tk), value(&other)?)),
            }
        }
    }
    Ok(lines.join("\n") + "\n")
}

// --- reading TOML ---------------------------------------------------------------------------------

fn from_toml(v: &toml::Value) -> Value {
    match v {
        toml::Value::String(s) => json!(s),
        toml::Value::Integer(i) => json!(i),
        toml::Value::Float(f) => json!(f),
        toml::Value::Boolean(b) => json!(b),
        toml::Value::Datetime(_) => Value::Null, // no setting takes a TOML date: every check refuses it
        toml::Value::Array(a) => Value::Array(a.iter().map(from_toml).collect()),
        toml::Value::Table(t) => Value::Object(t.iter().map(|(k, x)| (k.clone(), from_toml(x))).collect()),
    }
}

/// One line for Settings' status, as prefs.py gave: the parser's first line and where, never the
/// file's own text (toml's Display quotes the line with a caret under it).
fn short(e: &toml::de::Error, text: &str) -> String {
    let what = e.message().lines().next().unwrap_or("invalid TOML").to_string();
    match e.span() {
        Some(span) => {
            let before = &text[..span.start.min(text.len())];
            let line = before.matches('\n').count() + 1;
            let column = before.rsplit('\n').next().unwrap_or("").chars().count() + 1;
            format!("{what} (at line {line}, column {column})")
        }
        None => what,
    }
}

pub fn read(text: &str, ctx: &Value) -> Result<(Map<String, Value>, Vec<Value>), String> {
    let data: toml::Table = text.parse().map_err(|e: toml::de::Error| format!("the file isn't valid TOML: {}", short(&e, text)))?;
    let data = from_toml(&toml::Value::Table(data));
    let data = data.as_object().unwrap();
    let mut values = Map::new();
    let mut skipped = vec![];
    for (section, tk, sk, c) in SCHEMA {
        if let Some(v) = data.get(*section).and_then(Value::as_object).and_then(|t| t.get(*tk)) {
            match check(c, v, ctx) {
                Ok(ok) => { values.insert(sk.to_string(), ok); }
                Err(reason) => skipped.push(json!({"key": format!("{section}.{tk}"), "reason": reason})),
            }
        }
    }
    for (section, table) in data {
        if !SCHEMA.iter().any(|r| r.0 == section) {
            skipped.push(json!({"key": section, "reason": "unknown section"}));
        } else if let Some(t) = table.as_object() {
            for tk in t.keys() {
                if !SCHEMA.iter().any(|r| r.0 == section && r.1 == tk) {
                    skipped.push(json!({"key": format!("{section}.{tk}"), "reason": "unknown setting"}));
                }
            }
        }
    }
    Ok((values, skipped))
}

fn write_settings(path: &Path, body: &str) -> Result<(), String> {
    let dir = path.parent().ok_or("no folder for the settings file")?;
    std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    if path.exists() {
        let mut bak = path.as_os_str().to_owned();
        bak.push(".bak");
        std::fs::rename(path, PathBuf::from(bak)).map_err(|e| e.to_string())?;
    }
    let tmp = dir.join(format!(".settings-{}.toml", std::process::id()));
    std::fs::write(&tmp, body).map_err(|e| e.to_string())?;
    std::os::unix::fs::PermissionsExt::set_mode(&mut std::fs::metadata(&tmp).map_err(|e| e.to_string())?.permissions(), 0o644);
    std::fs::set_permissions(&tmp, std::os::unix::fs::PermissionsExt::from_mode(0o644)).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp, path).map_err(|e| e.to_string())
}

/// `psc prefs …`: prints one JSON line, returns the exit status.
pub fn main(args: &[String]) -> i32 {
    let fail = |error: String| { println!("{}", json!({"ok": false, "error": error})); 1 };
    if !(args.len() == 2 || args.len() == 3) || !matches!(args[0].as_str(), "export" | "read") {
        return fail("usage: psc prefs export|read PATH [JSON]".into());
    }
    let path = PathBuf::from(expand(&args[1]));
    let raw = match args.get(2) {
        Some(s) => s.clone(),
        None => { let mut s = String::new(); let _ = std::io::stdin().read_to_string(&mut s); s }
    };
    let payload: Value = match serde_json::from_str(if raw.is_empty() { "{}" } else { &raw }) {
        Ok(v) => v,
        Err(e) => return fail(e.to_string()),
    };
    if args[0] == "export" {
        let empty = Map::new();
        let values = payload.get("values").and_then(Value::as_object).unwrap_or(&empty);
        let body = match to_toml(values) { Ok(b) => b, Err(e) => return fail(e) };
        if let Err(e) = body.parse::<toml::Table>() { return fail(format!("the file isn't valid TOML: {}", short(&e, &body))); } // never leave a file that won't read back
        match write_settings(&path, &body) {
            Ok(()) => { println!("{}", json!({"ok": true, "path": path.to_string_lossy()})); 0 }
            Err(e) => fail(e),
        }
    } else {
        let text = match std::fs::read_to_string(&path) {
            Ok(t) => t,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return fail("no settings file yet: export first".into()),
            Err(e) => return fail(e.to_string()),
        };
        match read(&text, &payload) {
            Ok((values, skipped)) => { println!("{}", json!({"ok": true, "values": values, "skipped": skipped})); 0 }
            Err(e) => fail(e),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn checks_match_prefs_py() {
        let ctx = json!({"actions": ["lens"], "claudeModels": ["sonnet"], "codexModels": []});
        assert_eq!(check(&Time, &json!(" 7:05 "), &ctx), Ok(json!(425)));
        assert!(check(&Time, &json!("24:00"), &ctx).is_err() && check(&Time, &json!("7:5"), &ctx).is_err());
        assert!(check(&ChoiceInt(&[15, 25]), &json!(15.0), &ctx).is_err(), "a float isn't one of the whole-number choices");
        assert!(check(&Integer(1, 9), &json!(true), &ctx).is_err());
        assert_eq!(check(&Choice(&["a", "b"]), &json!("c"), &ctx), Err("expected one of \"a\", \"b\"".into()));
        assert_eq!(check(&Pins, &json!([{"kind": "action", "target": "rm"}]), &ctx), Err("unknown shell action 'rm'".into()));
        assert_eq!(check(&Aliases, &json!({"Hl": {"kind": "app", "target": "helium"}}), &ctx), Ok(json!({"hl": {"kind": "app", "target": "helium"}})));
        assert!(check(&Aliases, &json!({"bad alias!": {"kind": "app", "target": "x"}}), &ctx).is_err());
        assert_eq!(check(&Rules, &json!({"Spotify": "silence"}), &ctx), Err("'Spotify': only \"no toasts\" can be imported".into()));
        assert_eq!(value(&json!({"a b": 1, "c": [true, "x\"y"]})).unwrap(), "{ \"a b\" = 1, c = [true, \"x\\\"y\"] }");
        assert_eq!(plain(&json!([3750.0, 1.5])), json!([3750, 1.5]));
    }
}
