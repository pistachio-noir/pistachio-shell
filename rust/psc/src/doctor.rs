//! `psc doctor`: what the shell needs (the README's Requirements), found or missing, with the Arch
//! package and what stops working without it.
use std::ffi::OsStr;
use std::path::Path;

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Kind { Required, Optional }

pub enum Find { Program(&'static str), Font(&'static str), Helper(&'static str), Python(&'static str) }

pub struct Check { pub id: &'static str, pub title: &'static str, pub kind: Kind, pub find: Find, pub package: &'static str, pub without: &'static str }

#[derive(Debug)]
pub struct Row { pub id: &'static str, pub title: &'static str, pub kind: Kind, pub found: bool, pub package: &'static str, pub without: &'static str }

use Find::*;
use Kind::*;

macro_rules! check {
    ($id:expr, $title:expr, $kind:expr, $find:expr, $package:expr, $without:expr) => {
        Check { id: $id, title: $title, kind: $kind, find: $find, package: $package, without: $without }
    };
}

/// Mirrors README.md's Requirements table and system-tools.py's DEPENDENCIES (keep them in step):
/// required means the shell can't run without it, as there.
pub const CHECKS: &[Check] = &[
    check!("hyprctl", "Hyprland", Required, Program("hyprctl"), "hyprland", "nothing works: Hyprland only"),
    check!("qs", "Quickshell", Required, Program("qs"), "quickshell", "nothing works"),
    check!("python3", "Python", Required, Program("python3"), "python", "calendar events"),
    check!("python-gi", "Python GObject", Optional, Python("gi"), "python-gobject", "calendar events"),
    check!("wl-copy", "Wayland clipboard", Required, Program("wl-copy"), "wl-clipboard", "copying text, emoji and screenshots"),
    check!("pactl", "PipeWire's pactl", Optional, Program("pactl"), "pipewire-pulse", "audio devices and plugged-in inputs"),
    check!("pw-play", "PipeWire playback", Optional, Program("pw-play"), "pipewire", "notification and timer sounds"),
    check!("systemctl", "systemd", Optional, Program("systemctl"), "systemd", "suspend, reboot, shut down"),
    check!("manrope", "Manrope font", Optional, Font("Manrope"), "install.sh downloads it", "the shell falls back to another font"),
    check!("pistachio-auth", "Polkit agent", Optional, Helper("pistachio-auth"), "./install.sh (builds rust/)", "the admin password dialog; apps needing admin rights hang"),
    check!("pistachio-devices", "Bluetooth agent and drive mounter", Optional, Helper("pistachio-devices"), "./install.sh (builds rust/)", "pairing with codes, USB drive automount"),
    check!("notify-send", "Notifications", Optional, Program("notify-send"), "libnotify", "screenshot and recording notifications"),
    check!("bluetoothctl", "Bluetooth", Optional, Program("bluetoothctl"), "bluez bluez-utils", "Bluetooth shows as off"),
    check!("nmcli", "NetworkManager", Optional, Program("nmcli"), "networkmanager", "Ethernet details"),
    check!("ip", "iproute2", Optional, Program("ip"), "iproute2", "network addresses in Settings"),
    check!("ddcutil", "Monitor brightness", Optional, Program("ddcutil"), "ddcutil", "the brightness slider is hidden"),
    check!("hyprsunset", "Night light", Optional, Program("hyprsunset"), "hyprsunset", "Night light says Not installed"),
    check!("grim", "Screenshots", Optional, Program("grim"), "grim", "screenshots"),
    check!("slurp", "Region selection", Optional, Program("slurp"), "slurp", "picking a region for screenshots"),
    check!("pw-record", "Microphone check", Optional, Program("pw-record"), "pipewire", "Settings → Sound's microphone check"),
    check!("ffprobe", "Recording trim (lengths)", Optional, Program("ffprobe"), "ffmpeg", "Trim on recordings"),
    check!("gpu-screen-recorder", "Screen recording", Optional, Program("gpu-screen-recorder"), "gpu-screen-recorder", "Record in the screenshot menu"),
    check!("ffmpeg", "Recording trim", Optional, Program("ffmpeg"), "ffmpeg", "Trim on recordings"),
    check!("hyprpicker", "Colour picker", Optional, Program("hyprpicker"), "hyprpicker", "Colour in the screenshot menu"),
    check!("satty", "Screenshot editor", Optional, Program("satty"), "satty", "Edit on screenshot notifications"),
    check!("tesseract", "Text from the screen", Optional, Program("tesseract"), "tesseract tesseract-data-eng", "Text in the screenshot menu"),
    check!("cliphist", "Clipboard history", Optional, Program("cliphist"), "cliphist", "the launcher's ; history"),
    check!("qrencode", "QR codes", Optional, Program("qrencode"), "qrencode", "the phone timer's QR code (the link still works)"),
    check!("zenity", "File chooser", Optional, Program("zenity"), "zenity", "attaching files in Lens and LocalSend"),
    check!("pdftoppm", "PDF preview", Optional, Program("pdftoppm"), "poppler", "PDF previews in the launcher"),
    check!("udisksctl", "Drive eject", Optional, Program("udisksctl"), "udisks2", "ejecting drives"),
    check!("gio", "GLib tools", Optional, Program("gio"), "glib2", "Move to trash on desktop icons"),
    check!("xdg-open", "Opening files", Optional, Program("xdg-open"), "xdg-utils", "opening files and folders"),
    check!("qalc", "Calculator fallback", Optional, Program("qalc"), "libqalculate", "units and harder sums in the launcher"),
    check!("tldr", "tldr pages", Optional, Program("tldr"), "tldr", "the launcher's tldr"),
    check!("fastfetch", "Showoff mode", Optional, Program("fastfetch"), "fastfetch", "the terminal in showoff mode"),
    check!("hypridle", "Idle lock", Optional, Program("hypridle"), "hypridle", "locking after idle time"),
    check!("claude", "Claude Code CLI", Optional, Program("claude"), "claude-code", "Lens and quick chat with Claude"),
    check!("codex", "Codex CLI", Optional, Program("codex"), "openai-codex", "Lens and quick chat with ChatGPT"),
    check!("pistachio-localsend", "LocalSend helper", Optional, Helper("pistachio-localsend"), "./install.sh (builds rust/)", "LocalSend in quick settings"),
    check!("jetbrains-mono", "JetBrains Mono font", Optional, Font("JetBrainsMono Nerd Font"), "ttf-jetbrains-mono-nerd", "the TUI style and code text use another font"),
];

fn on_path(path: &OsStr, program: &str) -> bool {
    std::env::split_paths(path).any(|dir| {
        let f = dir.join(program);
        f.metadata().map(|m| m.is_file() && std::os::unix::fs::PermissionsExt::mode(&m.permissions()) & 0o111 != 0).unwrap_or(false)
    })
}

fn quiet(path: &OsStr, program: &str, args: &[&str]) -> Option<std::process::Output> {
    let found = std::env::split_paths(path).map(|d| d.join(program)).find(|f| f.is_file())?;
    std::process::Command::new(found).args(args).env("PATH", path).stdin(std::process::Stdio::null()).output().ok()
}

fn found(find: &Find, path: &OsStr, home: &Path) -> bool {
    match find {
        Program(p) => on_path(path, p),
        Helper(h) => home.join(".local/bin").join(h).metadata().map(|m| std::os::unix::fs::PermissionsExt::mode(&m.permissions()) & 0o111 != 0).unwrap_or(false),
        Font(family) => quiet(path, "fc-list", &[":", "family"]).is_some_and(|o| String::from_utf8_lossy(&o.stdout).lines().any(|l| l.split(',').any(|f| f.trim() == *family))),
        Python(module) => quiet(path, "python3", &["-c", &format!("import {module}")]).is_some_and(|o| o.status.success()),
    }
}

/// Every check, required ones first (the list's own order within each).
pub fn run(path: &OsStr, home: &Path) -> Vec<Row> {
    let mut rows: Vec<Row> = CHECKS.iter().map(|c| Row { id: c.id, title: c.title, kind: c.kind, found: found(&c.find, path, home), package: c.package, without: c.without }).collect();
    rows.sort_by_key(|r| r.kind == Optional);
    rows
}

pub fn missing_required(rows: &[Row]) -> bool {
    rows.iter().any(|r| r.kind == Required && !r.found)
}

pub fn json(rows: &[Row]) -> serde_json::Value {
    serde_json::Value::Array(rows.iter().map(|r| serde_json::json!({
        "id": r.id, "title": r.title, "kind": if r.kind == Required { "required" } else { "optional" },
        "found": r.found, "package": r.package, "without": r.without,
    })).collect())
}

pub fn text(rows: &[Row]) -> String {
    let mut out = String::new();
    for (kind, heading) in [(Required, "Required"), (Optional, "Optional")] {
        out += &format!("{heading}\n");
        for r in rows.iter().filter(|r| r.kind == kind) {
            if r.found {
                out += &format!("  ✓ {}\n", r.title);
            } else {
                out += &format!("  ✗ {}: install {}. Without it: {}.\n", r.title, r.package, r.without);
            }
        }
    }
    let missing = rows.iter().filter(|r| !r.found).count();
    let required = rows.iter().filter(|r| !r.found && r.kind == Required).count();
    out += &match (missing, required) {
        (0, _) => "\nEverything is in place.\n".to_string(),
        (m, 0) => format!("\n{m} optional {} missing; the shell runs without {}.\n", if m == 1 { "item" } else { "items" }, if m == 1 { "it" } else { "them" }),
        (m, r) => format!("\n{m} missing, {r} of them required.\n"),
    };
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn doctor_minimal_path() {
        let dir = std::env::temp_dir().join(format!("psc-doctor-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let qs = dir.join("qs");
        std::fs::write(&qs, "#!/bin/sh\n").unwrap();
        std::fs::set_permissions(&qs, std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
        let rows = run(dir.as_os_str(), &dir);
        let row = |id: &str| rows.iter().find(|r| r.id == id).unwrap_or_else(|| panic!("no row {id}"));
        assert!(row("qs").found && !row("hyprctl").found && row("hyprctl").kind == Kind::Required);
        assert!(!row("manrope").found && !row("python-gi").found && !row("pistachio-auth").found);
        let first_optional = rows.iter().position(|r| r.kind == Kind::Optional).unwrap();
        assert!(rows[..first_optional].iter().all(|r| r.kind == Kind::Required) && rows[first_optional..].iter().all(|r| r.kind == Kind::Optional));
        assert!(missing_required(&rows));
        let required: Vec<&str> = rows.iter().filter(|r| r.kind == Kind::Required).map(|r| r.id).collect();
        assert_eq!(required, ["hyprctl", "qs", "python3", "wl-copy"], "only what the shell can't run without");
        for id in ["slurp", "pw-record", "ffprobe", "pactl", "pw-play", "manrope", "pistachio-devices"] { row(id); }
        let json = json(&rows);
        let first = &json.as_array().unwrap()[0];
        for key in ["id", "title", "kind", "found", "package", "without"] { assert!(first.get(key).is_some(), "{key}"); }
        let _ = std::fs::remove_dir_all(dir);
    }
}
