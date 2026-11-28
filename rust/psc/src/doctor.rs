//! `psc doctor`: what the shell needs (docs/requirements.md), found or missing, with the package
//! and what stops working without it. Arch package names, or Gentoo atoms on Gentoo (owner's move to
//! Gentoo with OpenRC, 21 November 2026), where `atom[flag]` means the package with that USE flag on.
use std::ffi::OsStr;
use std::path::Path;

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Kind { Required, Optional }

pub enum Find { Program(&'static str), Font(&'static str), Helper(&'static str), Calendar, Logind }

/// Which package names to give: read from os-release (ID, then ID_LIKE). Anything else gets Arch's names.
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Distro { Arch, Gentoo, Other }

pub fn distro(os_release: &str) -> Distro {
    let field = |key: &str| os_release.lines().find_map(|l| l.strip_prefix(key)?.strip_prefix('=')).map(|v| v.trim().trim_matches(['"', '\'']).to_string()).unwrap_or_default();
    let ids = format!("{} {}", field("ID"), field("ID_LIKE"));
    let has = |name: &str| ids.split_whitespace().any(|w| w == name);
    if has("gentoo") { Distro::Gentoo } else if has("arch") { Distro::Arch } else { Distro::Other }
}

pub fn this_distro() -> Distro {
    distro(&std::fs::read_to_string("/etc/os-release").or_else(|_| std::fs::read_to_string("/usr/lib/os-release")).unwrap_or_default())
}

/// Gentoo atoms by check id (checked against ::gentoo, ::guru and ::hyproverlay, 21 November 2026).
/// Every check has one (a test says so); "install.sh" entries stay as they are.
pub fn gentoo(id: &str) -> Option<&'static str> {
    Some(match id {
        "hyprctl" => "gui-wm/hyprland",
        "qs" => "gui-apps/quickshell",
        "calendar" => "gnome-extra/evolution-data-server",
        "wl-copy" => "gui-apps/wl-clipboard",
        "pactl" => "media-libs/libpulse",
        "pw-play" | "pw-record" => "media-video/pipewire[extra]",
        "logind" => "sys-auth/elogind",
        "setpriv" => "sys-apps/util-linux[caps]",
        "notify-send" => "x11-libs/libnotify",
        "bluetoothctl" => "net-wireless/bluez",
        "nmcli" => "net-misc/networkmanager",
        "ip" => "sys-apps/iproute2",
        "ddcutil" => "app-misc/ddcutil",
        "hyprsunset" => "gui-apps/hyprsunset",
        "grim" => "gui-apps/grim",
        "slurp" => "gui-apps/slurp",
        "ffprobe" | "ffmpeg" => "media-video/ffmpeg",
        "gpu-screen-recorder" => "media-video/gpu-screen-recorder",
        "hyprpicker" => "gui-apps/hyprpicker",
        "satty" => "gui-apps/satty",
        "tesseract" => "app-text/tesseract app-text/tessdata_fast[l10n_en]",
        "cliphist" => "app-misc/cliphist",
        "qrencode" => "media-gfx/qrencode",
        "gnome-clocks" => "gnome-extra/gnome-clocks",
        "zenity" => "gnome-extra/zenity",
        "pdftoppm" => "app-text/poppler",
        "udisksctl" => "sys-fs/udisks",
        "gio" => "dev-libs/glib",
        "xdg-open" => "x11-misc/xdg-utils",
        "qalc" => "sci-libs/libqalculate",
        "tldr" => "app-text/tldr",
        "fastfetch" => "app-misc/fastfetch",
        "hypridle" => "gui-apps/hypridle",
        "claude" => "dev-util/claude-code",
        "codex" => "dev-util/codex",
        "jetbrains-mono" => "media-fonts/nerdfonts[jetbrainsmono]",
        _ => return None, // manrope and the helpers: install.sh

    })
}

pub struct Check { pub id: &'static str, pub title: &'static str, pub kind: Kind, pub find: Find, pub package: &'static str, pub without: &'static str }

#[derive(Debug, Clone, Copy)]
pub struct Row { pub id: &'static str, pub title: &'static str, pub kind: Kind, pub found: bool, pub package: &'static str, pub without: &'static str }

use Find::*;
use Kind::*;

macro_rules! check {
    ($id:expr, $title:expr, $kind:expr, $find:expr, $package:expr, $without:expr) => {
        Check { id: $id, title: $title, kind: $kind, find: $find, package: $package, without: $without }
    };
}

/// Mirrors docs/requirements.md's table and system-tools.py's DEPENDENCIES (keep them in step):
/// required means the shell can't run without it, as there.
pub const CHECKS: &[Check] = &[
    check!("hyprctl", "Hyprland", Required, Program("hyprctl"), "hyprland", "nothing works: Hyprland only"),
    check!("qs", "Quickshell", Required, Program("qs"), "quickshell", "nothing works"),
    // no Python since 20 November 2026: `psc events` loads EDS's own libraries, and this asks it whether it can
    check!("calendar", "Calendar libraries", Optional, Calendar, "evolution-data-server", "calendar events (GNOME Calendar's) in the month calendar"),
    check!("wl-copy", "Wayland clipboard", Required, Program("wl-copy"), "wl-clipboard", "copying text, emoji and screenshots"),
    check!("pactl", "PipeWire's pactl", Optional, Program("pactl"), "pipewire-pulse", "audio devices and plugged-in inputs"),
    check!("pw-play", "PipeWire playback", Optional, Program("pw-play"), "pipewire", "notification and timer sounds"),
    // systemd-logind or elogind (Gentoo/OpenRC): `psc power` asks it over D-Bus (21 November 2026)
    check!("logind", "Login manager (logind)", Optional, Logind, "systemd", "suspend, reboot, shut down"),
    // its --pdeathsig stops pactl subscribe, notify-send and the recorder with the shell (Gentoo: USE=caps)
    check!("setpriv", "setpriv", Optional, Program("setpriv"), "util-linux", "audio device updates, screenshot notifications and screen recording"),
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
    check!("gnome-clocks", "Alarms", Optional, Program("gnome-clocks"), "gnome-clocks", "alarms (timers and the stopwatch still work)"),
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
        Calendar => crate::events::available(),
        Logind => crate::power::logind_running(),
    }
}

/// Every check, required ones first (the list's own order within each).
pub fn run(path: &OsStr, home: &Path, distro: Distro) -> Vec<Row> {
    let package = |c: &Check| if distro == Distro::Gentoo { gentoo(c.id).unwrap_or(c.package) } else { c.package };
    let mut rows: Vec<Row> = CHECKS.iter().map(|c| Row { id: c.id, title: c.title, kind: c.kind, found: found(&c.find, path, home), package: package(c), without: c.without }).collect();
    rows.sort_by_key(|r| r.kind == Optional);
    rows
}

/// The packages (with any `[flags]`) of the missing checks of one kind, each once. Entries that
/// aren't packages ("install.sh downloads it", "./install.sh (builds rust/)") are left out.
fn wanted(rows: &[Row], kind: Kind) -> Vec<&'static str> {
    let mut out: Vec<&'static str> = Vec::new();
    for row in rows.iter().filter(|r| r.kind == kind && !r.found) {
        if row.package.contains("install.sh") {
            continue;
        }
        for name in row.package.split_whitespace() {
            if !out.contains(&name) {
                out.push(name);
            }
        }
    }
    out
}

/// Package names alone (no `[flags]`), space-separated by the caller: `psc doctor --packages`.
pub fn packages(rows: &[Row], kind: Kind) -> Vec<&'static str> {
    let mut out: Vec<&'static str> = Vec::new();
    for name in wanted(rows, kind).into_iter().map(|p| p.split('[').next().unwrap_or(p)) {
        if !out.contains(&name) {
            out.push(name);
        }
    }
    out
}

/// What to run for the missing packages of one kind (install.sh prints these): one pacman line on
/// Arch; on Gentoo the package.use lines first (emerge refuses `atom[flag]` while the flag is off),
/// then an emerge line that also rebuilds an installed package whose flags changed. Empty when nothing
/// is missing.
pub fn install_lines(rows: &[Row], kind: Kind, distro: Distro) -> Vec<String> {
    let names = packages(rows, kind);
    if names.is_empty() {
        return vec![];
    }
    match distro {
        Distro::Arch => vec![format!("sudo pacman -S --needed {}", names.join(" "))],
        Distro::Gentoo => {
            let mut out: Vec<String> = wanted(rows, kind).iter().filter_map(|p| {
                let (atom, flags) = p.strip_suffix(']')?.split_once('[')?;
                Some(format!("# in /etc/portage/package.use: {atom} {}", flags.replace(',', " ")))
            }).collect();
            out.push(format!("sudo emerge -av --noreplace --changed-use {}", names.join(" ")));
            out
        }
        Distro::Other => vec![format!("install (Arch names): {}", names.join(" "))],
    }
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
        let rows = run(dir.as_os_str(), &dir, Distro::Arch);
        let row = |id: &str| rows.iter().find(|r| r.id == id).unwrap_or_else(|| panic!("no row {id}"));
        assert!(row("qs").found && !row("hyprctl").found && row("hyprctl").kind == Kind::Required);
        assert!(!row("manrope").found && !row("pistachio-auth").found);
        let first_optional = rows.iter().position(|r| r.kind == Kind::Optional).unwrap();
        assert!(rows[..first_optional].iter().all(|r| r.kind == Kind::Required) && rows[first_optional..].iter().all(|r| r.kind == Kind::Optional));
        assert!(missing_required(&rows));
        let required: Vec<&str> = rows.iter().filter(|r| r.kind == Kind::Required).map(|r| r.id).collect();
        assert_eq!(required, ["hyprctl", "qs", "wl-copy"], "only what the shell can't run without");
        assert!(rows.iter().all(|r| !r.id.starts_with("python")), "no Python at runtime");
        assert_eq!(packages(&rows, Kind::Required), ["hyprland", "wl-clipboard"], "qs was found, so not quickshell");
        let optional = packages(&rows, Kind::Optional);
        assert!(optional.contains(&"tesseract-data-eng") && optional.contains(&"bluez-utils"), "multi-package entries split");
        assert!(!optional.iter().any(|p| p.contains("install.sh") || p.starts_with('.') || p.contains('(')), "{optional:?}");
        assert_eq!(optional.iter().filter(|p| **p == "ffmpeg").count(), 1, "each package once");
        row("calendar");
        for id in ["slurp", "pw-record", "ffprobe", "pactl", "pw-play", "manrope", "pistachio-devices"] { row(id); }
        let json = json(&rows);
        let first = &json.as_array().unwrap()[0];
        for key in ["id", "title", "kind", "found", "package", "without"] { assert!(first.get(key).is_some(), "{key}"); }
        assert_eq!(install_lines(&rows, Kind::Required, Distro::Arch), ["sudo pacman -S --needed hyprland wl-clipboard"]);
        assert!(!rows.iter().any(|r| r.id == "systemctl") && row("logind").package == "systemd", "logind, not systemctl (OpenRC has none)");
        row("setpriv");

        // Gentoo: atoms, USE flags as package.use lines before the emerge line
        let rows = run(dir.as_os_str(), &dir, Distro::Gentoo);
        let row = |id: &str| rows.iter().find(|r| r.id == id).unwrap();
        assert_eq!(row("pw-play").package, "media-video/pipewire[extra]");
        assert_eq!(row("logind").package, "sys-auth/elogind");
        assert_eq!(row("manrope").package, "install.sh downloads it", "not a package anywhere");
        assert_eq!(packages(&rows, Kind::Required), ["gui-wm/hyprland", "gui-apps/wl-clipboard"]);
        let optional = install_lines(&rows, Kind::Optional, Distro::Gentoo);
        let emerge = optional.last().unwrap();
        assert!(emerge.starts_with("sudo emerge -av --noreplace --changed-use ") && emerge.contains(" media-video/pipewire ") && !emerge.contains('['), "{emerge}");
        assert_eq!(emerge.matches("media-video/pipewire").count(), 1, "pw-play and pw-record share it");
        for line in ["# in /etc/portage/package.use: media-video/pipewire extra", "# in /etc/portage/package.use: sys-apps/util-linux caps", "# in /etc/portage/package.use: app-text/tessdata_fast l10n_en"] {
            assert!(optional.iter().any(|l| l == line), "{line} in {optional:?}");
        }
        assert_eq!(install_lines(&rows, Kind::Required, Distro::Gentoo), ["sudo emerge -av --noreplace --changed-use gui-wm/hyprland gui-apps/wl-clipboard"]);
        let all_found: Vec<Row> = rows.iter().map(|r| Row { found: true, ..*r }).collect();
        assert!(install_lines(&all_found, Kind::Optional, Distro::Gentoo).is_empty());
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn every_check_has_a_gentoo_package() {
        for c in CHECKS {
            assert!(gentoo(c.id).is_some() || c.package.contains("install.sh"), "{} has no Gentoo atom", c.id);
            if let Some(atom) = gentoo(c.id) {
                assert!(atom.split_whitespace().all(|a| a.contains('/')), "{atom}: category/name");
            }
        }
    }

    #[test]
    fn distro_from_os_release() {
        assert_eq!(distro("NAME='Gentoo'\nID='gentoo'\n"), Distro::Gentoo);
        assert_eq!(distro("NAME=\"Arch Linux\"\nID=arch\n"), Distro::Arch);
        assert_eq!(distro("ID=cachyos\nID_LIKE=arch\n"), Distro::Arch);
        assert_eq!(distro("ID=\"funtoo\"\nID_LIKE=\"gentoo\"\n"), Distro::Gentoo);
        assert_eq!(distro("ID=fedora\n"), Distro::Other);
        assert_eq!(distro(""), Distro::Other);
        assert_eq!(distro("ID=archer\n"), Distro::Other, "whole words");
    }
}
