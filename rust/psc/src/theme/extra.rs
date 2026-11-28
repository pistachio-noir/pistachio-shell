//! The apps added on 28 November 2026 (owner: "GTK3/4 integration", "vesktop via css", "btop yazi and
//! zathura"): GTK 3 and 4, Vesktop, btop, yazi and zathura follow Colours like Kitty does. Their theme
//! files are made from src/Theme.qml by tools/make-app-themes.py and built in. Each has status, setup,
//! undo and publish (rewrite the colours on a switch); the same rules as the others: an own theme is
//! asked about first, configs are backed up before a change, and undo removes only what the shell added.
//!
//! Live switching: btop (SIGUSR2), zathura (D-Bus SourceConfig) and Vesktop (Vencord watches its
//! quickCss.css, so that file is written in place: a renamed file would end the watch) switch at once;
//! GTK apps and yazi read their colours only when they start.
use super::{backup_path, rewrite, which, with_newline, write_atomic, Env, Fail, LINKED};
use std::path::{Path, PathBuf};

const MARK: &str = "pistachio-shell theming";

macro_rules! schemes {
    ($dir:literal, $prefix:literal, $ext:literal) => {
        [
            include_bytes!(concat!("../../../../integrations/", $dir, "/", $prefix, "pistachio-noir", $ext)) as &[u8],
            include_bytes!(concat!("../../../../integrations/", $dir, "/", $prefix, "noir", $ext)),
            include_bytes!(concat!("../../../../integrations/", $dir, "/", $prefix, "oled-noir", $ext)),
        ]
    };
}
const GTK4: [&[u8]; 3] = schemes!("gtk", "gtk4-", ".css");
const GTK3: [&[u8]; 3] = schemes!("gtk", "gtk3-", ".css");
const BTOP: [&[u8]; 3] = schemes!("btop", "", ".theme");
const YAZI: [&[u8]; 3] = schemes!("yazi", "", ".toml");
const YAZI_TM: [&[u8]; 3] = schemes!("yazi", "", ".tmtheme.xml");
const ZATHURA: [&[u8]; 3] = schemes!("zathura", "", "");
const VESKTOP: [&[u8]; 3] = schemes!("vesktop", "", ".css");

fn pick<'a>(files: &[&'a [u8]; 3], scheme: &str) -> &'a str {
    std::str::from_utf8(files[match scheme { "noir" => 1, "oled" => 2, _ => 0 }]).unwrap_or_default()
}

fn read(path: &Path) -> Result<Option<String>, Fail> {
    match std::fs::read_to_string(path) {
        Ok(text) => Ok(Some(text)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e.into()),
    }
}

/// Lines that say something (not blank, not a comment starting with one of `comments`).
fn says_something(text: &str, comments: &[&str]) -> bool {
    text.lines().any(|l| { let t = l.trim(); !t.is_empty() && !comments.iter().any(|c| t.starts_with(c)) })
}

/// `file.pistachio-own`: the user's own config, put aside by "Use Pistachio" and put back by undo.
fn own_copy(conf: &Path) -> PathBuf {
    let mut name = conf.file_name().unwrap_or_default().to_owned();
    name.push(".pistachio-own");
    conf.with_file_name(name)
}

/// Use Pistachio over an own config: it moves aside whole (and a dated backup is kept, as for the others).
fn set_aside(conf: &Path) -> Result<(), Fail> {
    std::fs::copy(conf, backup_path(conf))?;
    let aside = own_copy(conf);
    if aside.exists() {
        std::fs::copy(&aside, backup_path(&aside))?;
    }
    std::fs::rename(conf, aside)?;
    Ok(())
}

/// After undo took the shell's lines out (`rest`: what's left, maybe the user's later additions): the
/// own config set aside comes back first, then those additions; an empty file goes.
fn put_back(conf: &Path, before: &str, rest: &str) -> Result<(), Fail> {
    let aside = own_copy(conf);
    let own = read(&aside)?;
    let rest_says = says_something(rest, &[]);
    let after = match (&own, rest_says) {
        (Some(own), true) => with_newline(own) + rest,
        (Some(own), false) => own.clone(),
        (None, _) => rest.to_string(),
    };
    if says_something(&after, &[]) {
        if after != before { rewrite(conf, before, &after)?; }
    } else {
        std::fs::remove_file(conf)?;
    }
    if own.is_some() {
        std::fs::remove_file(aside)?;
    }
    Ok(())
}

fn remove_if_there(path: &Path) -> Result<(), Fail> {
    match std::fs::remove_file(path) {
        Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(e.into()),
        _ => Ok(()),
    }
}

/// `program`, found on env's PATH only (tests give a stand-in folder, so nothing real runs there).
fn tool(env: &Env, program: &str) -> Option<std::process::Command> {
    let found = std::env::split_paths(&env.path).map(|d| d.join(program)).find(|f| f.is_file())?;
    let mut c = std::process::Command::new(found);
    c.env("PATH", &env.path).stdin(std::process::Stdio::null());
    Some(c)
}

// --- GTK ------------------------------------------------------------------------------------------
// gtk-4.0/gtk.css and gtk-3.0/gtk.css start with the marker and an @import of pistachio-shared.css (the
// colours, beside it): libadwaita 1.6+ takes CSS variables, GTK 3 apps need the adw-gtk3 theme, which
// the shell selects (org.gnome.desktop.interface gtk-theme; the old name kept in the marker for undo).

const GTK_IMPORT: &str = "@import url(\"pistachio-shared.css\");";
const ADW: &str = "adw-gtk3-dark";
const STOCK_THEMES: &[&str] = &["", "Adwaita", "Adwaita-dark", "Default", "adw-gtk3", ADW];

fn gtk_mark(was: Option<&str>) -> String {
    match was {
        Some(w) => format!("/* {MARK}: follows the shell's Colours (gtk-theme was {}) */", serde_json::to_string(w).unwrap_or_default()),
        None => format!("/* {MARK}: follows the shell's Colours */"),
    }
}

fn gtk_folders(config: &Path) -> [(PathBuf, &'static [&'static [u8]; 3]); 2] {
    [(config.join("gtk-4.0"), &GTK4), (config.join("gtk-3.0"), &GTK3)]
}

/// A gtk.css that sets colours of its own: libadwaita's variables or GTK 3's named colours.
fn gtk_own_colours(text: &str) -> bool {
    !text.lines().any(|l| l.trim() == GTK_IMPORT) && text.lines().any(|l| {
        let t = l.trim_start();
        t.starts_with("@define-color") || t.starts_with("--") && t.contains("-color") && t.contains(':')
    })
}

fn gsettings_theme(env: &Env) -> Option<String> {
    let out = tool(env, "gsettings")?.args(["get", "org.gnome.desktop.interface", "gtk-theme"]).output().ok()?;
    out.status.success().then(|| String::from_utf8_lossy(&out.stdout).trim().trim_matches('\'').to_string())
}

fn set_gsettings_theme(env: &Env, theme: &str) {
    if let Some(mut c) = tool(env, "gsettings") {
        let _ = c.args(["set", "org.gnome.desktop.interface", "gtk-theme", theme]).status();
    }
}

fn adw_installed(env: &Env) -> bool {
    [env.home.join(".local/share/themes"), env.home.join(".themes"), PathBuf::from("/usr/share/themes"), PathBuf::from("/usr/local/share/themes")]
        .iter().any(|d| d.join(ADW).join("gtk-3.0").is_dir())
}

pub(super) fn gtk_status(config: &Path, env: &Env) -> Result<(&'static str, String), Fail> {
    let mut own = false;
    for (folder, _) in gtk_folders(config) {
        let conf = folder.join("gtk.css");
        if conf.is_symlink() {
            return Ok(("unsupported", format!("{} {LINKED}", conf.strip_prefix(config).unwrap_or(&conf).display())));
        }
        if let Some(text) = read(&conf)? {
            if folder.ends_with("gtk-4.0") && text.lines().any(|l| l.trim() == GTK_IMPORT) {
                let detail = if !adw_installed(env) { "GTK 3 apps need the adw-gtk3 theme; restart apps to see a change" } else { "Restart an app to see a change" };
                return Ok(("following", detail.into()));
            }
            own |= gtk_own_colours(&text);
        }
    }
    let theme = gsettings_theme(env);
    if own || theme.as_deref().is_some_and(|t| !STOCK_THEMES.contains(&t)) {
        return Ok(("own", String::new()));
    }
    Ok(("available", String::new()))
}

pub(super) fn gtk_setup(config: &Path, env: &Env, scheme: &str, force: bool) -> Result<(), Fail> {
    let state = gtk_status(config, env)?.0;
    if matches!(state, "following" | "unsupported") || state == "own" && !force {
        return Ok(());
    }
    // GTK 3's theme: its old name goes into gtk-3.0's marker, and the theme changes only once the
    // files are written (a failed write must not leave a changed theme nobody can undo)
    let was = if adw_installed(env) { gsettings_theme(env).filter(|t| t != ADW) } else { None };
    for (folder, files) in gtk_folders(config) {
        let conf = folder.join("gtk.css");
        write_atomic(&folder.join("pistachio-shared.css"), pick(files, scheme).as_bytes())?;
        let block = format!("{}\n{GTK_IMPORT}\n", gtk_mark(if folder.ends_with("gtk-3.0") { was.as_deref() } else { None }));
        match read(&conf)? {
            Some(text) if gtk_own_colours(&text) => { set_aside(&conf)?; write_atomic(&conf, block.as_bytes())?; }
            // rules of the user's own (no colours): the import goes first, as CSS wants
            Some(text) => rewrite(&conf, &text, &(block + &text))?,
            None => write_atomic(&conf, block.as_bytes())?,
        }
    }
    if was.is_some() {
        set_gsettings_theme(env, ADW);
    }
    Ok(())
}

pub(super) fn gtk_undo(config: &Path, env: &Env) -> Result<(), Fail> {
    for (folder, _) in gtk_folders(config) {
        let conf = folder.join("gtk.css");
        if let Some(before) = read(&conf)? {
            let mut rest = String::new();
            for line in before.split_inclusive('\n') {
                let t = line.trim();
                if let Some(mark) = t.strip_prefix(&format!("/* {MARK}")) {
                    // "(gtk-theme was "Adwaita")": GTK 3's theme goes back, unless the user changed it since
                    if let Some(was) = mark.split("(gtk-theme was ").nth(1).and_then(|w| w.strip_suffix(") */")) {
                        if let Ok(was) = serde_json::from_str::<String>(was) {
                            if gsettings_theme(env).as_deref() == Some(ADW) { set_gsettings_theme(env, &was); }
                        }
                    }
                    continue;
                }
                if t == GTK_IMPORT { continue; }
                rest.push_str(line);
            }
            if rest != before || own_copy(&conf).exists() {
                put_back(&conf, &before, &rest)?;
            }
        }
        remove_if_there(&folder.join("pistachio-shared.css"))?;
    }
    Ok(())
}

pub(super) fn gtk_publish(config: &Path, env: &Env, scheme: &str) -> Result<(), Fail> {
    if gtk_status(config, env)?.0 != "following" {
        return Ok(());
    }
    for (folder, files) in gtk_folders(config) {
        let shared = folder.join("pistachio-shared.css");
        if folder.join("gtk.css").exists() && read(&shared)?.as_deref() != Some(pick(files, scheme)) {
            write_atomic(&shared, pick(files, scheme).as_bytes())?;
        }
    }
    Ok(())
}

// --- btop -----------------------------------------------------------------------------------------
// btop.conf: color_theme = "pistachio-shell", the theme file in btop/themes/. btop rewrites its whole
// config (comments lost) after a change made in btop, so the value itself says it's ours, and the
// theme file's first line keeps the user's old theme name for undo.

const BTOP_NAME: &str = "pistachio-shell";

fn btop_value(text: &str) -> Option<String> {
    text.lines().find_map(|l| {
        let (key, value) = l.split_once('=')?;
        (key.trim() == "color_theme").then(|| value.trim().trim_matches('"').to_string())
    })
}

fn btop_ours(value: &str) -> bool {
    value == BTOP_NAME || value.ends_with("/pistachio-shell.theme")
}

fn btop_was(theme_file: &Path) -> Result<Option<String>, Fail> {
    Ok(read(theme_file)?.and_then(|t| t.lines().next().and_then(|l| l.split("color_theme was ").nth(1)).and_then(|w| serde_json::from_str(w.trim()).ok())))
}

fn btop_theme(scheme: &str, was: &str) -> String {
    format!("# {MARK}: the shell's Colours ({scheme}), rewritten when they change; color_theme was {}\n{}",
        serde_json::to_string(was).unwrap_or_default(), pick(&BTOP, scheme))
}

fn btop_with(text: &str, value: &str) -> String {
    let line = format!("color_theme = \"{value}\"");
    if btop_value(text).is_none() {
        return with_newline(text) + &line + "\n";
    }
    text.split_inclusive('\n').map(|l| match l.split_once('=') {
        Some((key, _)) if key.trim() == "color_theme" => format!("{line}{}", if l.ends_with('\n') { "\n" } else { "" }),
        _ => l.to_string(),
    }).collect()
}

pub(super) fn btop_status(config: &Path, env: &Env) -> Result<(&'static str, String), Fail> {
    let conf = config.join("btop/btop.conf");
    if conf.is_symlink() {
        return Ok(("unsupported", format!("btop.conf {LINKED}")));
    }
    let Some(text) = read(&conf)? else {
        return Ok(if config.join("btop").is_dir() || which(env, "btop") { ("available", String::new()) } else { ("missing", String::new()) });
    };
    Ok(match btop_value(&text) {
        Some(v) if btop_ours(&v) => ("following", String::new()),
        Some(v) if !matches!(v.as_str(), "" | "Default") => ("own", String::new()),
        _ => ("available", String::new()),
    })
}

pub(super) fn btop_setup(config: &Path, env: &Env, scheme: &str, force: bool) -> Result<(), Fail> {
    let state = btop_status(config, env)?.0;
    if matches!(state, "following" | "unsupported" | "missing") || state == "own" && !force {
        return Ok(());
    }
    let conf = config.join("btop/btop.conf");
    let before = read(&conf)?;
    let was = before.as_deref().and_then(btop_value).unwrap_or_else(|| "Default".into());
    write_atomic(&config.join("btop/themes/pistachio-shell.theme"), btop_theme(scheme, &was).as_bytes())?;
    match before {
        Some(text) => rewrite(&conf, &text, &btop_with(&text, BTOP_NAME))?,
        None => write_atomic(&conf, btop_with("", BTOP_NAME).as_bytes())?,
    }
    (env.reload)("btop");
    Ok(())
}

pub(super) fn btop_undo(config: &Path, env: &Env) -> Result<(), Fail> {
    let conf = config.join("btop/btop.conf");
    let theme = config.join("btop/themes/pistachio-shell.theme");
    if let Some(text) = read(&conf)? {
        if btop_value(&text).is_some_and(|v| btop_ours(&v)) {
            let was = btop_was(&theme)?.unwrap_or_else(|| "Default".into());
            rewrite(&conf, &text, &btop_with(&text, &was))?;
        }
    }
    remove_if_there(&theme)?;
    (env.reload)("btop");
    Ok(())
}

pub(super) fn btop_publish(config: &Path, env: &Env, scheme: &str) -> Result<(), Fail> {
    let theme = config.join("btop/themes/pistachio-shell.theme");
    if btop_status(config, env)?.0 != "following" || !theme.exists() {
        return Ok(());
    }
    let content = btop_theme(scheme, &btop_was(&theme)?.unwrap_or_else(|| "Default".into()));
    if read(&theme)?.as_deref() != Some(content.as_str()) {
        write_atomic(&theme, content.as_bytes())?;
        (env.reload)("btop");
    }
    Ok(())
}

// --- yazi -----------------------------------------------------------------------------------------
// theme.toml picks the flavor flavors/pistachio-shell.yazi (flavor.toml, tmtheme.xml for code) in
// dark and light. theme.toml is all theme, so any setting there is the user's own.

fn yazi_block() -> String {
    format!("# {MARK}: follows the shell's Colours (restart yazi to see a change)\n[flavor]\ndark = \"pistachio-shell\"\nlight = \"pistachio-shell\"\n")
}

fn yazi_flavor(config: &Path) -> PathBuf {
    config.join("yazi/flavors/pistachio-shell.yazi")
}

pub(super) fn yazi_status(config: &Path, env: &Env) -> Result<(&'static str, String), Fail> {
    let conf = config.join("yazi/theme.toml");
    if conf.is_symlink() {
        return Ok(("unsupported", format!("theme.toml {LINKED}")));
    }
    match read(&conf)? {
        Some(text) if text.lines().any(|l| l.starts_with(&format!("# {MARK}"))) => Ok(("following", "Restart yazi to see a change".into())),
        Some(text) if says_something(&text, &["#"]) => Ok(("own", String::new())),
        _ if config.join("yazi").is_dir() || which(env, "yazi") => Ok(("available", String::new())),
        _ => Ok(("missing", String::new())),
    }
}

fn yazi_files(config: &Path, scheme: &str) -> Result<(), Fail> {
    let flavor = yazi_flavor(config);
    for (name, files) in [("flavor.toml", &YAZI), ("tmtheme.xml", &YAZI_TM)] {
        let path = flavor.join(name);
        if read(&path)?.as_deref() != Some(pick(files, scheme)) {
            write_atomic(&path, pick(files, scheme).as_bytes())?;
        }
    }
    Ok(())
}

pub(super) fn yazi_setup(config: &Path, env: &Env, scheme: &str, force: bool) -> Result<(), Fail> {
    let state = yazi_status(config, env)?.0;
    if matches!(state, "following" | "unsupported" | "missing") || state == "own" && !force {
        return Ok(());
    }
    yazi_files(config, scheme)?;
    let conf = config.join("yazi/theme.toml");
    match read(&conf)? {
        Some(text) if says_something(&text, &["#"]) => { set_aside(&conf)?; write_atomic(&conf, yazi_block().as_bytes())?; }
        Some(text) => rewrite(&conf, &text, &(with_newline(&text) + &yazi_block()))?,
        None => write_atomic(&conf, yazi_block().as_bytes())?,
    }
    Ok(())
}

pub(super) fn yazi_undo(config: &Path, _env: &Env) -> Result<(), Fail> {
    let conf = config.join("yazi/theme.toml");
    if let Some(before) = read(&conf)? {
        let block = yazi_block();
        if before.contains(&block) || own_copy(&conf).exists() {
            put_back(&conf, &before, &before.replacen(&block, "", 1))?;
        }
    }
    let flavor = yazi_flavor(config);
    remove_if_there(&flavor.join("flavor.toml"))?;
    remove_if_there(&flavor.join("tmtheme.xml"))?;
    let _ = std::fs::remove_dir(&flavor); // only when empty
    Ok(())
}

pub(super) fn yazi_publish(config: &Path, env: &Env, scheme: &str) -> Result<(), Fail> {
    if yazi_status(config, env)?.0 == "following" { yazi_files(config, scheme)?; }
    Ok(())
}

// --- zathura --------------------------------------------------------------------------------------
// zathurarc ends with the marker and `include pistachio-shared` (girara reads it relative to zathurarc),
// so its `set` lines come last and win.

const ZATHURA_INCLUDE: &str = "include pistachio-shared";

fn zathura_mark() -> String {
    format!("# {MARK}: follows the shell's Colours")
}

fn zathura_colour_line(line: &str) -> bool {
    let mut words = line.split_whitespace();
    // default-bg, statusbar-fg, highlight-color, recolor-darkcolor…; not `set recolor true` (a switch)
    words.next() == Some("set") && words.next().is_some_and(|o| o.ends_with("-bg") || o.ends_with("-fg") || o.ends_with("color") && o != "recolor")
}

pub(super) fn zathura_status(config: &Path, env: &Env) -> Result<(&'static str, String), Fail> {
    let conf = config.join("zathura/zathurarc");
    if conf.is_symlink() {
        return Ok(("unsupported", format!("zathurarc {LINKED}")));
    }
    match read(&conf)? {
        Some(text) if text.lines().any(|l| l.trim() == ZATHURA_INCLUDE) => Ok(("following", String::new())),
        Some(text) if text.lines().any(zathura_colour_line) => Ok(("own", String::new())),
        _ if config.join("zathura").is_dir() || which(env, "zathura") => Ok(("available", String::new())),
        _ => Ok(("missing", String::new())),
    }
}

pub(super) fn zathura_setup(config: &Path, env: &Env, scheme: &str, force: bool) -> Result<(), Fail> {
    let state = zathura_status(config, env)?.0;
    if matches!(state, "following" | "unsupported" | "missing") || state == "own" && !force {
        return Ok(());
    }
    write_atomic(&config.join("zathura/pistachio-shared"), pick(&ZATHURA, scheme).as_bytes())?;
    let conf = config.join("zathura/zathurarc");
    let block = format!("{}\n{ZATHURA_INCLUDE}\n", zathura_mark());
    match read(&conf)? {
        Some(text) => rewrite(&conf, &text, &(with_newline(&text) + &block))?,
        None => write_atomic(&conf, block.as_bytes())?,
    }
    (env.reload)("zathura");
    Ok(())
}

pub(super) fn zathura_undo(config: &Path, env: &Env) -> Result<(), Fail> {
    let conf = config.join("zathura/zathurarc");
    if let Some(before) = read(&conf)? {
        let rest: String = before.split_inclusive('\n').filter(|l| l.trim() != zathura_mark() && l.trim() != ZATHURA_INCLUDE).collect();
        if rest != before {
            if says_something(&rest, &[]) { rewrite(&conf, &before, &rest)?; } else { std::fs::remove_file(&conf)?; }
        }
    }
    remove_if_there(&config.join("zathura/pistachio-shared"))?;
    (env.reload)("zathura");
    Ok(())
}

pub(super) fn zathura_publish(config: &Path, env: &Env, scheme: &str) -> Result<(), Fail> {
    let shared = config.join("zathura/pistachio-shared");
    if zathura_status(config, env)?.0 == "following" && read(&shared)?.as_deref() != Some(pick(&ZATHURA, scheme)) {
        write_atomic(&shared, pick(&ZATHURA, scheme).as_bytes())?;
        (env.reload)("zathura");
    }
    Ok(())
}

/// Every open zathura window (bus name org.pwmt.zathura.PID-<pid>) reads its config again.
pub(super) fn zathura_source_config() {
    let bus = gio::bus_get_sync(gio::BusType::Session, gio::Cancellable::NONE);
    // gio's first D-Bus connection sets SIGPIPE to ignored, which every child would inherit (gotchas)
    unsafe { libc::signal(libc::SIGPIPE, libc::SIG_DFL) };
    let Ok(bus) = bus else { return };
    let Ok(names) = bus.call_sync(Some("org.freedesktop.DBus"), "/org/freedesktop/DBus", "org.freedesktop.DBus", "ListNames", None,
        Some(gio::glib::VariantTy::new("(as)").unwrap()), gio::DBusCallFlags::NONE, 1000, gio::Cancellable::NONE) else { return };
    for name in names.child_value(0).get::<Vec<String>>().unwrap_or_default().into_iter().filter(|n| n.starts_with("org.pwmt.zathura.PID-")) {
        if let Err(e) = bus.call_sync(Some(&name), "/org/pwmt/zathura", "org.pwmt.zathura", "SourceConfig", None, None,
            gio::DBusCallFlags::NONE, 1000, gio::Cancellable::NONE) {
            eprintln!("Could not reload zathura's configuration: {e}");
        }
    }
}

// --- Vesktop --------------------------------------------------------------------------------------
// A marked block in Vencord's QuickCSS (vesktop/settings/quickCss.css), written in place: Vencord
// watches that file (fs.watch) and applies it at once. A Vencord theme of the user's own (enabledThemes,
// themeLinks in settings/settings.json) is asked about first; the QuickCSS block comes after it.

fn vesktop_start(scheme: &str) -> String {
    format!("/* {MARK}: start. The shell's Colours ({scheme}), rewritten when they change: edit outside this block */")
}
fn vesktop_end() -> String {
    format!("/* {MARK}: end */")
}

/// The block's byte range, both marker lines and their line ends included.
fn vesktop_block(text: &str) -> Option<std::ops::Range<usize>> {
    let start = text.find(&format!("/* {MARK}: start"))?;
    let start = text[..start].rfind('\n').map_or(0, |i| i + 1);
    let end = start + text[start..].find(&vesktop_end())? + vesktop_end().len();
    Some(start..if text[end..].starts_with('\n') { end + 1 } else { end })
}

fn vesktop_css(scheme: &str) -> String {
    format!("{}\n{}{}\n", vesktop_start(scheme), with_newline(pick(&VESKTOP, scheme)), vesktop_end())
}

/// Vencord sees only a change to the same file: write it in place (truncate and write), never renamed.
/// Setup and undo back it up first; a colour switch, which changes only the shell's block, doesn't.
fn write_in_place(path: &Path, before: Option<&str>, after: &str, backup: bool) -> Result<(), Fail> {
    #[cfg(test)]
    super::BEFORE_WRITE.with(|hook| if let Some(f) = hook.borrow().as_ref() { f() });
    if read(path)?.as_deref() != before {
        return Err(Fail::Changed);
    }
    if before.is_some() && backup {
        std::fs::copy(path, backup_path(path))?;
    } else if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    std::fs::write(path, after)?;
    Ok(())
}

fn vencord_settings(config: &Path) -> serde_json::Value {
    std::fs::read_to_string(config.join("vesktop/settings/settings.json")).ok()
        .and_then(|t| serde_json::from_str(&t).ok()).unwrap_or(serde_json::Value::Null)
}

pub(super) fn vesktop_status(config: &Path, env: &Env) -> Result<(&'static str, String), Fail> {
    let quick = config.join("vesktop/settings/quickCss.css");
    if quick.is_symlink() {
        return Ok(("unsupported", format!("quickCss.css {LINKED}")));
    }
    if !config.join("vesktop").is_dir() && !which(env, "vesktop") {
        return Ok(("missing", String::new()));
    }
    let settings = vencord_settings(config);
    if read(&quick)?.as_deref().and_then(vesktop_block).is_some() {
        let off = settings["useQuickCss"] == false;
        return Ok(("following", if off { "Turn on QuickCSS in Vencord's settings to see it".into() } else { String::new() }));
    }
    let listed = |key: &str| settings[key].as_array().is_some_and(|a| !a.is_empty());
    Ok(if listed("enabledThemes") || listed("themeLinks") { ("own", String::new()) } else { ("available", String::new()) })
}

pub(super) fn vesktop_setup(config: &Path, env: &Env, scheme: &str, force: bool) -> Result<(), Fail> {
    let state = vesktop_status(config, env)?.0;
    if matches!(state, "following" | "unsupported" | "missing") || state == "own" && !force {
        return Ok(());
    }
    let quick = config.join("vesktop/settings/quickCss.css");
    let before = read(&quick)?;
    let after = match &before {
        Some(text) if !text.trim().is_empty() => with_newline(text) + &vesktop_css(scheme),
        _ => vesktop_css(scheme),
    };
    write_in_place(&quick, before.as_deref(), &after, true)
}

pub(super) fn vesktop_undo(config: &Path, _env: &Env) -> Result<(), Fail> {
    let quick = config.join("vesktop/settings/quickCss.css");
    if let Some(before) = read(&quick)? {
        if let Some(range) = vesktop_block(&before) {
            let mut after = before.clone();
            after.replace_range(range, "");
            write_in_place(&quick, Some(&before), &after, true)?;
        }
    }
    Ok(())
}

pub(super) fn vesktop_publish(config: &Path, _env: &Env, scheme: &str) -> Result<(), Fail> {
    let quick = config.join("vesktop/settings/quickCss.css");
    let Some(before) = read(&quick)? else { return Ok(()) };
    let Some(range) = vesktop_block(&before) else { return Ok(()) };
    let mut after = before.clone();
    after.replace_range(range, &vesktop_css(scheme));
    if after != before { write_in_place(&quick, Some(&before), &after, false)?; }
    Ok(())
}
