//! `psc theme …`: publish the shell's colour choice, and set apps up to follow it (theming
//! integration, services/AppTheming.qml). Python's shared-theme.py until 19 November 2026; same
//! arguments, same JSON, same files and markers.
//!
//!   psc theme publish SCHEME (or just SCHEME)   write the choice; switch wired apps (Kitty) live
//!   psc theme status                            {"apps": [{id, name, state, detail}]}
//!   psc theme setup APP | use APP | undo APP    act (setup leaves an own theme alone; use doesn't), then status
//!
//! States: following (wired up), own (the app has its own theme: asked first), available (can be set
//! up), missing (not installed), unsupported (detail says why). Owner's call, 19 November 2026: the
//! shell wires apps itself behind one switch, never over a user's own theme without asking, and undo
//! removes only the lines it added (marked), so the app's own settings apply again.
use serde_json::{json, Value};
use std::ffi::OsString;
use std::path::{Path, PathBuf};

const MARK_LUA: &str = " -- pistachio-shell theming";
// Kitty takes no comment after an include on the same line (it read the whole rest as the file name
// and skipped it), so its marker is a comment line of its own right above a plain include
const KITTY_MARK: &str = "# pistachio-shell theming: follows the shell's Colours";
const KITTY_INCLUDE: &str = "include pistachio-shared.conf";
const KITTY_OLD: &str = "include pistachio-shared.conf  # pistachio-shell theming"; // the first, broken form
const NVIM_LINE: &str = "pcall(function() require(\"pistachio-shared\").setup() end) -- pistachio-shell theming";
const LEGACY_NVIM: &str = "require(\"pistachio-shared\").setup()";
const LEGACY_RESTORE: &str = "vim.cmd(\"colorscheme pistachio-noir\")";
const LINKED: &str = "is a symbolic link (a dotfile manager?); set it up by hand";

// the theme files, built in: psc lives in ~/.local/bin, away from the repo's integrations/
const KITTY_PISTACHIO: &[u8] = include_bytes!("../../../integrations/kitty/kitty-pistachio-noir.conf");
const KITTY_NOIR: &[u8] = include_bytes!("../../../integrations/kitty/kitty-noir.conf");
const NVIM_COLORS: &[u8] = include_bytes!("../../../integrations/neovim/colors/pistachio-noir.lua");
const NVIM_SHARED: &[u8] = include_bytes!("../../../integrations/neovim/lua/pistachio-shared.lua");

/// What the outside world is: where to look for programs, and how to ask Kitty to reload.
pub struct Env<'a> {
    pub path: OsString,
    pub reload: &'a dyn Fn(),
}

#[derive(Debug)]
enum Fail {
    Changed,
    Io(String),
}

impl From<std::io::Error> for Fail {
    fn from(e: std::io::Error) -> Fail {
        Fail::Io(describe(&e))
    }
}

/// Like Python's strerror: "Permission denied", not "Permission denied (os error 13)".
fn describe(e: &std::io::Error) -> String {
    let text = e.to_string();
    text.split(" (os error").next().unwrap_or(&text).to_string()
}

#[cfg(test)]
thread_local! {
    /// tests: something to run between reading a config and writing it back (the user saving meanwhile)
    pub static BEFORE_WRITE: std::cell::RefCell<Option<Box<dyn Fn()>>> = const { std::cell::RefCell::new(None) };
}

fn stamp() -> String {
    let mut buf = [0u8; 32];
    unsafe {
        let t = libc::time(std::ptr::null_mut());
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&t, &mut tm);
        let n = libc::strftime(buf.as_mut_ptr() as *mut libc::c_char, buf.len(), c"%Y%m%d-%H%M%S".as_ptr(), &tm);
        String::from_utf8_lossy(&buf[..n]).into_owned()
    }
}

fn backup_path(path: &Path) -> PathBuf {
    let mut name = path.file_name().unwrap_or_default().to_owned();
    name.push(format!(".pistachio-bak-{}", stamp()));
    path.with_file_name(name)
}

fn write_atomic(path: &Path, content: &[u8]) -> Result<(), Fail> {
    let dir = path.parent().unwrap_or(Path::new("."));
    std::fs::create_dir_all(dir)?;
    let tmp = dir.join(format!(".shared-theme-{}-{}", std::process::id(), stamp()));
    std::fs::write(&tmp, content)?;
    if let Ok(meta) = std::fs::metadata(path) {
        let _ = std::fs::set_permissions(&tmp, meta.permissions());
    }
    if let Err(e) = std::fs::rename(&tmp, path) {
        let _ = std::fs::remove_file(&tmp);
        return Err(e.into());
    }
    Ok(())
}

/// Back up and replace a config the shell read as `before`; refuse if it changed meanwhile.
fn rewrite(path: &Path, before: &str, after: &str) -> Result<(), Fail> {
    #[cfg(test)]
    BEFORE_WRITE.with(|hook| if let Some(f) = hook.borrow().as_ref() { f() });
    if std::fs::read_to_string(path)? != before {
        return Err(Fail::Changed);
    }
    std::fs::copy(path, backup_path(path))?;
    write_atomic(path, after.as_bytes())
}

/// Put a theme file in place; a different file already there is backed up first.
fn copy_in(source: &[u8], target: &Path) -> Result<(), Fail> {
    if let Ok(existing) = std::fs::read(target) {
        if existing == source {
            return Ok(());
        }
        std::fs::copy(target, backup_path(target))?;
    }
    if let Some(dir) = target.parent() {
        std::fs::create_dir_all(dir)?;
    }
    std::fs::write(target, source)?;
    Ok(())
}

fn which(env: &Env, program: &str) -> bool {
    std::env::split_paths(&env.path).any(|d| {
        d.join(program).metadata().map(|m| m.is_file() && std::os::unix::fs::PermissionsExt::mode(&m.permissions()) & 0o111 != 0).unwrap_or(false)
    })
}

fn with_newline(text: &str) -> String {
    if text.is_empty() || text.ends_with('\n') { text.to_string() } else { format!("{text}\n") }
}

// --- Kitty ----------------------------------------------------------------------------------------

/// A theme of the user's own: colour lines, or an include of a file that isn't one of ours.
fn kitty_colour_line(line: &str) -> bool {
    let t = line.trim_start();
    let then_space = |rest: &str| rest.starts_with(|c: char| c.is_whitespace());
    for word in ["foreground", "background"] {
        if let Some(rest) = t.strip_prefix(word) {
            if then_space(rest) { return true; }
        }
    }
    if let Some(rest) = t.strip_prefix("color") {
        let digits = rest.chars().take_while(|c| c.is_ascii_digit()).count();
        if (1..=3).contains(&digits) && then_space(&rest[digits..]) { return true; }
    }
    for word in ["include", "globinclude", "envinclude"] {
        if let Some(rest) = t.strip_prefix(word) {
            if !then_space(rest) { continue; }
            let file = rest.trim_start();
            if file.is_empty() { continue; }
            let ours = ["pistachio-shared.conf", "pistachio-noir.conf", "noir.conf"].iter().any(|o| {
                file.strip_prefix(o).is_some_and(|after| !after.starts_with(|c: char| c.is_alphanumeric() || c == '_'))
            });
            if !ours { return true; }
        }
    }
    false
}

fn kitty_status(config: &Path, env: &Env) -> Result<(&'static str, String), Fail> {
    let conf = config.join("kitty/kitty.conf");
    if conf.is_symlink() {
        return Ok(("unsupported", format!("kitty.conf {LINKED}")));
    }
    if !conf.exists() {
        return Ok(if config.join("kitty").is_dir() || which(env, "kitty") { ("available", String::new()) } else { ("missing", String::new()) });
    }
    let text = std::fs::read_to_string(&conf)?;
    if text.lines().any(|l| l.trim() == KITTY_INCLUDE) {
        return Ok(("following", String::new()));
    }
    if text.lines().any(kitty_colour_line) {
        return Ok(("own", String::new()));
    }
    Ok(("available", String::new()))
}

/// The shared file holds the colours themselves, not an include of a theme file: Kitty refuses a
/// file included twice ("has already been included", its Errors parsing configuration window), and a
/// kitty.conf that includes pistachio-noir.conf itself, as the owner's does, made the Pistachio
/// include a second one (owner's report, 19 November 2026).
fn kitty_scheme(scheme: &str) -> String {
    let colours = String::from_utf8_lossy(if scheme == "noir" { KITTY_NOIR } else { KITTY_PISTACHIO });
    format!("# pistachio-shell theming: the shell's Colours ({scheme}), rewritten when they change\n{}", with_newline(&colours))
}

fn kitty_setup(config: &Path, env: &Env, scheme: &str, force: bool) -> Result<(), Fail> {
    let folder = config.join("kitty");
    let conf = folder.join("kitty.conf");
    let state = kitty_status(config, env)?.0;
    if matches!(state, "following" | "unsupported" | "missing") || state == "own" && !force {
        return Ok(());
    }
    let before = if conf.exists() { Some(std::fs::read_to_string(&conf)?) } else { None };
    copy_in(KITTY_PISTACHIO, &folder.join("pistachio-noir.conf"))?;
    copy_in(KITTY_NOIR, &folder.join("noir.conf"))?;
    write_atomic(&folder.join("pistachio-shared.conf"), kitty_scheme(scheme).as_bytes())?;
    let block = format!("{KITTY_MARK}\n{KITTY_INCLUDE}\n");
    match before {
        None => write_atomic(&conf, block.as_bytes())?,
        Some(before) => {
            let kept: String = before.split_inclusive('\n').filter(|l| l.trim() != KITTY_OLD).collect();
            rewrite(&conf, &before, &(with_newline(&kept) + &block))?;
        }
    }
    (env.reload)();
    Ok(())
}

fn kitty_undo(config: &Path, env: &Env) -> Result<(), Fail> {
    let conf = config.join("kitty/kitty.conf");
    if conf.exists() {
        let before = std::fs::read_to_string(&conf)?;
        let mut kept = String::new();
        let mut ours = false; // the line after our marker is our include
        for line in before.split_inclusive('\n') {
            let bare = line.trim();
            if bare == KITTY_MARK {
                ours = true;
                continue;
            }
            if bare == KITTY_OLD || ours && bare == KITTY_INCLUDE {
                ours = false;
                continue;
            }
            ours = false;
            if bare == KITTY_INCLUDE {
                // the hand install of 18 November replaced this line
                kept.push_str(&line.replacen(KITTY_INCLUDE, "include pistachio-noir.conf", 1));
            } else {
                kept.push_str(line);
            }
        }
        if kept != before {
            rewrite(&conf, &before, &kept)?;
        }
    }
    let include = config.join("kitty/pistachio-shared.conf");
    if include.exists() {
        std::fs::remove_file(include)?;
    }
    (env.reload)();
    Ok(())
}

// --- Neovim ---------------------------------------------------------------------------------------

fn comment(line: &str) -> bool {
    line.trim_start().starts_with("--")
}

/// The colour schemes a Lua line names: `colorscheme x`, vim.cmd.colorscheme("x") / 'x', LazyVim's
/// opts = { colorscheme = "x" }.
fn colorschemes(line: &str) -> Vec<String> {
    let mut found = vec![];
    let mut rest = line;
    while let Some(at) = rest.find("colorscheme") {
        let mut after = &rest[at + "colorscheme".len()..];
        rest = after;
        let spaced = after.trim_start();
        let gap = after.len() - spaced.len();
        if let Some(r) = spaced.strip_prefix('=').or_else(|| spaced.strip_prefix('(')) {
            after = r.trim_start();
        } else if gap > 0 {
            after = spaced;
        } else {
            continue;
        }
        let after = after.strip_prefix(['"', '\'']).unwrap_or(after);
        let name: String = after.chars().take_while(|c| c.is_alphanumeric() || matches!(c, '_' | '.' | '-')).collect();
        if !name.is_empty() {
            found.push(name);
        }
    }
    found
}

fn lua_files(dir: &Path, out: &mut Vec<PathBuf>) {
    if let Ok(entries) = std::fs::read_dir(dir) {
        for e in entries.flatten() {
            let p = e.path();
            if p.is_dir() {
                lua_files(&p, out);
            } else if p.extension().is_some_and(|x| x == "lua") && p.file_name().is_some_and(|n| n != "pistachio-shared.lua") {
                out.push(p);
            }
        }
    }
}

fn nvim_status(config: &Path, env: &Env) -> Result<(&'static str, String), Fail> {
    let folder = config.join("nvim");
    let init = folder.join("init.lua");
    if init.is_symlink() || folder.is_symlink() {
        return Ok(("unsupported", format!("{}{LINKED}", if init.is_symlink() { "init.lua " } else { "the nvim folder " })));
    }
    if !init.exists() {
        if folder.join("init.vim").exists() {
            return Ok(("unsupported", "Neovim is set up with init.vim; only init.lua is supported".into()));
        }
        return Ok(if folder.is_dir() || which(env, "nvim") { ("available", String::new()) } else { ("missing", String::new()) });
    }
    let text = std::fs::read_to_string(&init)?;
    if text.lines().any(|l| l.contains(LEGACY_NVIM) && !comment(l)) {
        return Ok(("following", String::new()));
    }
    let mut sources = vec![text];
    let mut files = vec![];
    lua_files(&folder.join("lua"), &mut files);
    files.sort();
    for f in files {
        sources.push(std::fs::read_to_string(f).unwrap_or_default());
    }
    for source in &sources {
        for line in source.lines().filter(|l| !comment(l)) {
            if colorschemes(line).iter().any(|n| n != "pistachio-noir") {
                return Ok(("own", String::new()));
            }
        }
    }
    Ok(("available", String::new()))
}

fn nvim_setup(config: &Path, env: &Env, _scheme: &str, force: bool) -> Result<(), Fail> {
    let folder = config.join("nvim");
    let init = folder.join("init.lua");
    let state = nvim_status(config, env)?.0;
    if matches!(state, "following" | "unsupported" | "missing") || state == "own" && !force {
        return Ok(());
    }
    let before = if init.exists() { Some(std::fs::read_to_string(&init)?) } else { None };
    copy_in(NVIM_COLORS, &folder.join("colors/pistachio-noir.lua"))?;
    copy_in(NVIM_SHARED, &folder.join("lua/pistachio-shared.lua"))?;
    match before {
        None => write_atomic(&init, format!("{NVIM_LINE}\n").as_bytes()),
        Some(before) => rewrite(&init, &before, &format!("{}{NVIM_LINE}\n", with_newline(&before))),
    }
}

fn nvim_undo(config: &Path, _env: &Env) -> Result<(), Fail> {
    let init = config.join("nvim/init.lua");
    if !init.exists() {
        return Ok(());
    }
    let before = std::fs::read_to_string(&init)?;
    let mut out = String::new();
    for line in before.split_inclusive('\n') {
        let bare = line.trim_end_matches('\n');
        if bare.ends_with(MARK_LUA) {
            continue;
        }
        if bare.trim() == LEGACY_NVIM {
            // the hand install of 18 November replaced this line
            out.push_str(&line.replacen(LEGACY_NVIM, LEGACY_RESTORE, 1));
        } else {
            out.push_str(line);
        }
    }
    if out != before {
        rewrite(&init, &before, &out)?;
    }
    Ok(())
}

// --- the app table --------------------------------------------------------------------------------

type Status = fn(&Path, &Env) -> Result<(&'static str, String), Fail>;
type Setup = fn(&Path, &Env, &str, bool) -> Result<(), Fail>;
type Undo = fn(&Path, &Env) -> Result<(), Fail>;

struct App {
    id: &'static str,
    name: &'static str,
    status: Status,
    setup: Setup,
    undo: Undo,
}

const APPS: &[App] = &[
    App { id: "kitty", name: "Kitty", status: kitty_status, setup: kitty_setup, undo: kitty_undo },
    App { id: "neovim", name: "Neovim", status: nvim_status, setup: nvim_setup, undo: nvim_undo },
];

fn entry(app: &App, config: &Path, env: &Env) -> Value {
    let (state, detail) = match (app.status)(config, env) {
        Ok((s, d)) => (s.to_string(), d),
        Err(Fail::Io(e)) => ("unsupported".to_string(), e),
        Err(Fail::Changed) => ("unsupported".to_string(), "its config changed while reading; try again".to_string()),
    };
    json!({"id": app.id, "name": app.name, "state": state, "detail": detail})
}

pub fn status(config: &Path, env: &Env) -> Vec<Value> {
    APPS.iter().map(|a| entry(a, config, env)).collect()
}

fn current_scheme(config: &Path) -> &'static str {
    match std::fs::read_to_string(config.join("pistachio/shared-theme")).unwrap_or_default().trim() {
        "noir" => "noir",
        _ => "pistachio",
    }
}

/// `setup` (quietly; an `own` theme is left alone), `use` (Use Pistachio: over its theme) or `undo`.
pub fn act(config: &Path, env: &Env, app_id: &str, action: &str) -> Option<Value> {
    let app = APPS.iter().find(|a| a.id == app_id)?;
    let done = match action {
        "undo" => (app.undo)(config, env),
        _ => (app.setup)(config, env, current_scheme(config), action == "use"),
    };
    Some(match done {
        Ok(()) => entry(app, config, env),
        Err(Fail::Changed) => json!({"id": app.id, "name": app.name, "state": "unsupported", "detail": "its config changed while reading; try again"}),
        Err(Fail::Io(e)) => json!({"id": app.id, "name": app.name, "state": "unsupported", "detail": e}),
    })
}

pub fn publish(path: &Path, scheme: &str, env: &Env) -> Result<(), String> {
    if !matches!(scheme, "pistachio" | "noir") {
        return Err("invalid colour scheme".into());
    }
    write_atomic(path, format!("{scheme}\n").as_bytes()).map_err(|e| format!("{e:?}"))?;
    let kitty = path.parent().and_then(Path::parent).map(|c| c.join("kitty/pistachio-shared.conf"));
    if let Some(kitty) = kitty.filter(|k| k.exists()) {
        let content = kitty_scheme(scheme);
        if std::fs::read_to_string(&kitty).unwrap_or_default() != content {
            write_atomic(&kitty, content.as_bytes()).map_err(|e| format!("{e:?}"))?;
            (env.reload)();
        }
    }
    Ok(())
}

fn reload_kitty() {
    let uid = unsafe { libc::getuid() }.to_string();
    let code = std::process::Command::new("pkill").args(["-USR1", "-u", &uid, "-x", "kitty"]).status().map(|s| s.code().unwrap_or(2)).unwrap_or(2);
    if !matches!(code, 0 | 1) {
        eprintln!("Could not reload Kitty configuration");
    }
}

/// `psc theme …`: prints one JSON line (nothing for a bare `psc theme SCHEME`), returns the exit status.
pub fn main(args: &[String]) -> i32 {
    let config = std::env::var_os("XDG_CONFIG_HOME").filter(|c| !c.is_empty()).map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".config"));
    let env = Env { path: std::env::var_os("PATH").unwrap_or_default(), reload: &reload_kitty };
    let shared = config.join("pistachio/shared-theme");
    let fail = |e: String| { println!("{}", json!({"error": e})); 1 };
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    let result = match args.as_slice() {
        [scheme @ ("pistachio" | "noir")] => return match publish(&shared, scheme, &env) { Ok(()) => 0, Err(e) => fail(e) },
        ["publish", scheme] => publish(&shared, scheme, &env).map(|()| None),
        [action @ ("setup" | "use" | "undo"), app] if APPS.iter().any(|a| a.id == *app) => Ok(act(&config, &env, app, action)),
        ["status"] => Ok(None),
        _ => Err("usage: psc theme publish SCHEME | status | setup APP | use APP | undo APP".to_string()),
    };
    match result {
        Ok(acted) => {
            let mut apps = status(&config, &env);
            // keep the reason the action gave (e.g. changed meanwhile)
            if let Some(r) = acted.filter(|r| r["state"] == "unsupported") {
                for a in apps.iter_mut() {
                    if a["id"] == r["id"] { *a = r.clone(); }
                }
            }
            println!("{}", json!({"apps": apps}));
            0
        }
        Err(e) => fail(e),
    }
}

#[cfg(test)]
mod tests;
