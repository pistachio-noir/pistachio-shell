//! `psc theme …`: publish the shell's colour choice, and set apps up to follow it (theming
//! integration, services/AppTheming.qml). Python's shared-theme.py until 19 November 2026; same
//! arguments, same JSON, same files and markers.
//!
//!   psc theme publish SCHEME (or just SCHEME)   write the choice; switch wired apps (Kitty) live
//!   psc theme status                            {"apps": [{id, name, state, detail}]}
//!   psc theme setup APP | use APP | undo APP    act (setup leaves an own theme alone; use doesn't), then status
//!   (APP: kitty, neovim or vscode)
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
    /// the home folder: VS Code keeps its extensions there (~/.vscode/extensions), not in the config folder
    pub home: PathBuf,
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

// --- VS Code --------------------------------------------------------------------------------------
// (owner's request, 21 November 2026) The theme is an extension, `integrations/vscode/pistachio-noir`
// (Pistachio Noir and Noir), installed as a .vsix with the editor's own `--install-extension`: VS Code
// lists only extensions it recorded itself, so a folder copied in by hand never showed up. Following =
// settings.json's top-level "workbench.colorTheme" on a line of ours, marked with a comment; VS Code
// applies a settings change at once, so a Colours switch is live. settings.json is JSONC (comments,
// trailing commas): only that one member's text is changed, every other byte stays as written. A theme
// of the user's own is replaced only after asking ("use"), and the marker keeps it for undo.

// a block comment right after the value: a line comment would swallow whatever follows on that line
// (a closing brace, or the next members of a one-line settings.json)
const VS_MARK: &str = "/* pistachio-shell theming";
const VS_ID: &str = "pistachio-shell.pistachio-noir";
const VS_KEY: &str = "workbench.colorTheme";
const VS_PACKAGE: &[u8] = include_bytes!("../../../integrations/vscode/pistachio-noir/package.json");
const VS_PISTACHIO: &[u8] = include_bytes!("../../../integrations/vscode/pistachio-noir/themes/pistachio-noir.json");
const VS_NOIR: &[u8] = include_bytes!("../../../integrations/vscode/pistachio-noir/themes/noir.json");
const VS_FILES: &[(&str, &[u8])] = &[("package.json", VS_PACKAGE), ("themes/pistachio-noir.json", VS_PISTACHIO), ("themes/noir.json", VS_NOIR)];

/// VS Code and its open builds: where each keeps its settings (under the config folder), its command,
/// and its extensions (under home). The first one present is the one themed.
struct Editor { config: &'static str, cli: &'static str, extensions: &'static str }
const EDITORS: &[Editor] = &[
    Editor { config: "Code", cli: "code", extensions: ".vscode/extensions" },
    Editor { config: "VSCodium", cli: "codium", extensions: ".vscode-oss/extensions" },
    Editor { config: "Code - OSS", cli: "code-oss", extensions: ".vscode-oss/extensions" },
];

fn vs_theme(scheme: &str) -> &'static str { if scheme == "noir" { "Noir" } else { "Pistachio Noir" } }

fn editor(config: &Path, env: &Env) -> Option<&'static Editor> {
    EDITORS.iter().find(|e| config.join(e.config).join("User").is_dir() || which(env, e.cli))
}

fn vs_settings(config: &Path, e: &Editor) -> PathBuf { config.join(e.config).join("User/settings.json") }

/// Past whitespace and JSONC comments.
fn skip(b: &[u8], mut i: usize) -> usize {
    while i < b.len() {
        if b[i].is_ascii_whitespace() {
            i += 1;
        } else if b[i..].starts_with(b"//") {
            while i < b.len() && b[i] != b'\n' { i += 1; }
        } else if b[i..].starts_with(b"/*") {
            i = b[i + 2..].windows(2).position(|w| w == b"*/").map(|p| i + 2 + p + 2).unwrap_or(b.len());
        } else {
            break;
        }
    }
    i
}

/// The end of the string starting at `i` (a quote), past its closing quote.
fn string_end(b: &[u8], mut i: usize) -> Option<usize> {
    i += 1;
    while i < b.len() {
        match b[i] {
            b'\\' => i += 2,
            b'"' => return Some(i + 1),
            b'\n' => return None,
            _ => i += 1,
        }
    }
    None
}

/// The end of the value starting at `i`: a string, an object or array (nested), or a bare literal.
fn value_end(b: &[u8], i: usize) -> Option<usize> {
    match *b.get(i)? {
        b'"' => string_end(b, i),
        b'{' | b'[' => {
            let (mut depth, mut j) = (0i32, i);
            while j < b.len() {
                let k = skip(b, j);
                if k != j { j = k; continue; }
                match b[j] {
                    b'"' => { j = string_end(b, j)?; continue; }
                    b'{' | b'[' => depth += 1,
                    b'}' | b']' => { depth -= 1; if depth == 0 { return Some(j + 1); } }
                    _ => {}
                }
                j += 1;
            }
            None
        }
        _ => Some(i + b[i..].iter().position(|c| b",}] \t\r\n/".contains(c)).unwrap_or(b.len() - i)),
    }
}

/// A member of settings.json's top-level object: where its value is, and where its line starts.
#[derive(Debug, Clone)]
struct Member { line_start: usize, value: std::ops::Range<usize> }

fn member(text: &str, key: &str) -> Option<Member> {
    let b = text.as_bytes();
    let (mut i, mut depth) = (0, 0i32);
    while i < b.len() {
        let k = skip(b, i);
        if k != i { i = k; continue; }
        match b[i] {
            b'"' => {
                let end = string_end(b, i)?;
                let colon = skip(b, end);
                if depth == 1 && b.get(colon) == Some(&b':') && serde_json::from_str::<String>(&text[i..end]).ok().as_deref() == Some(key) {
                    let start = skip(b, colon + 1);
                    let value = start..value_end(b, start)?;
                    let line_start = text[..i].rfind('\n').map(|n| n + 1).unwrap_or(0);
                    return Some(Member { line_start, value });
                }
                i = end;
                continue;
            }
            b'{' | b'[' => depth += 1,
            b'}' | b']' => depth -= 1,
            _ => {}
        }
        i += 1;
    }
    None
}

/// Our marker right after a member's value: where it ends, and the theme it replaced (`(was "…")`).
fn marker(text: &str, m: &Member) -> Option<(usize, Option<String>)> {
    let rest = &text[m.value.end..];
    let gap = rest.len() - rest.trim_start_matches([' ', '\t']).len();
    let body = rest[gap..].strip_prefix(VS_MARK)?;
    let close = body.find("*/")?;
    let end = m.value.end + gap + VS_MARK.len() + close + 2;
    let was = body[..close].trim().strip_prefix("(was ").and_then(|w| serde_json::Deserializer::from_str(w).into_iter::<String>().next()?.ok());
    Some((end, was))
}

fn marked(text: &str, m: &Member) -> Option<Option<String>> { marker(text, m).map(|(_, was)| was) }

fn mark(was: Option<&str>) -> String {
    match was { Some(w) => format!(" {VS_MARK} (was {}) */", quoted(w).replace("*/", "*\\/")), None => format!(" {VS_MARK} */") }
}

fn quoted(text: &str) -> String { serde_json::to_string(text).unwrap_or_default() }

/// settings.json with our theme line: a member of ours is switched; the user's own is replaced and
/// remembered in the marker; with none, a marked line goes first in the object.
fn vs_with_theme(text: &str, theme: &str) -> String {
    if let Some(m) = member(text, VS_KEY) {
        if marker(text, &m).is_some() {
            return format!("{}{}{}", &text[..m.value.start], quoted(theme), &text[m.value.end..]);
        }
        let was = serde_json::from_str::<String>(&text[m.value.clone()]).unwrap_or_else(|_| text[m.value.clone()].to_string());
        return format!("{}{}{}{}", &text[..m.value.start], quoted(theme), mark(Some(&was)), &text[m.value.end..]);
    }
    let b = text.as_bytes();
    let open = skip(b, 0);
    if b.get(open) != Some(&b'{') {
        return format!("{{\n    \"{VS_KEY}\": {}{}\n}}\n", quoted(theme), mark(None));
    }
    let first = skip(b, open + 1);
    let more = b.get(first) != Some(&b'}');
    // the indent of the first line inside the object, else four spaces
    let indent = text[open + 1..].split('\n').nth(1).map(|l| l.len() - l.trim_start().len()).filter(|n| *n > 0).unwrap_or(4);
    let line = format!("\n{}\"{VS_KEY}\": {}{}{}", " ".repeat(indent), quoted(theme), mark(None), if more { "," } else { "" });
    format!("{}{}{}", &text[..open + 1], line, &text[open + 1..])
}

/// settings.json without our line: the user's theme back (`was`), or the line gone, newline and all.
fn vs_without_theme(text: &str) -> Option<String> {
    let m = member(text, VS_KEY)?;
    let (end, was) = marker(text, &m)?;
    Some(match was {
        Some(was) => format!("{}{}{}", &text[..m.value.start], quoted(&was), &text[end..]),
        None => {
            // what setup inserted: a newline, the member, the marker and the comma after it
            let from = if m.line_start > 0 && text.as_bytes()[m.line_start - 1] == b'\n' { m.line_start - 1 } else { m.line_start };
            let to = if text[end..].starts_with(',') { end + 1 } else { end };
            format!("{}{}", &text[..from], &text[to..])
        }
    })
}

/// The installed copy matches the theme built into psc: recorded in extensions.json at our version,
/// with the same theme files. Not package.json: VS Code adds its own `__metadata` to it on install.
fn vs_installed(env: &Env, e: &Editor) -> bool {
    let version = serde_json::from_slice::<Value>(VS_PACKAGE).ok().and_then(|p| p["version"].as_str().map(String::from)).unwrap_or_default();
    let folder = env.home.join(e.extensions);
    let Ok(list) = std::fs::read_to_string(folder.join("extensions.json")) else { return false };
    let Ok(Value::Array(list)) = serde_json::from_str::<Value>(&list) else { return false };
    let Some(entry) = list.iter().find(|x| x["identifier"]["id"].as_str().is_some_and(|id| id.eq_ignore_ascii_case(VS_ID))) else { return false };
    if entry["version"].as_str() != Some(version.as_str()) {
        return false;
    }
    let place = entry["relativeLocation"].as_str().map(|r| folder.join(r)).or_else(|| entry["location"]["path"].as_str().map(PathBuf::from));
    place.is_some_and(|p| VS_FILES.iter().filter(|(name, _)| *name != "package.json").all(|(name, data)| std::fs::read(p.join(name)).ok().as_deref() == Some(*data)))
}

fn vs_install(env: &Env, e: &Editor) -> Result<(), Fail> {
    let cli = std::env::split_paths(&env.path).map(|d| d.join(e.cli)).find(|p| p.is_file())
        .ok_or_else(|| Fail::Io(format!("the {} command isn't on the PATH, so the theme can't be installed", e.cli)))?;
    let file = std::env::temp_dir().join(format!("pistachio-noir-{}-{}.vsix", std::process::id(), stamp()));
    std::fs::write(&file, crate::vsix::package("pistachio-shell", "pistachio-noir", "1.0.0", "Pistachio Noir", VS_FILES))?;
    let out = std::process::Command::new(&cli).arg("--install-extension").arg(&file).arg("--force").env("PATH", &env.path)
        .stdin(std::process::Stdio::null()).output();
    let _ = std::fs::remove_file(&file);
    let out = out?;
    if !out.status.success() {
        let why = String::from_utf8_lossy(&out.stderr).lines().chain(String::from_utf8_lossy(&out.stdout).lines()).last().unwrap_or("").to_string();
        return Err(Fail::Io(format!("{} couldn't install the theme{}", e.cli, if why.is_empty() { String::new() } else { format!(": {why}") })));
    }
    Ok(())
}

fn vscode_status(config: &Path, env: &Env) -> Result<(&'static str, String), Fail> {
    let Some(e) = editor(config, env) else { return Ok(("missing", String::new())) };
    let settings = vs_settings(config, e);
    if settings.is_symlink() {
        return Ok(("unsupported", format!("settings.json {LINKED}")));
    }
    let text = if settings.exists() { std::fs::read_to_string(&settings)? } else { String::new() };
    if member(&text, "window.autoDetectColorScheme").is_some_and(|m| &text[m.value] == "true") {
        return Ok(("unsupported", "it follows the system's light or dark setting (window.autoDetectColorScheme); turn that off to use this".into()));
    }
    Ok(match member(&text, VS_KEY) {
        None => ("available", String::new()),
        Some(m) if marked(&text, &m).is_some() => if vs_installed(env, e) { ("following", String::new()) } else { ("available", String::new()) },
        // ours, picked by hand: wired up quietly (the marker keeps that choice for undo)
        Some(m) if matches!(serde_json::from_str::<String>(&text[m.value.clone()]).ok().as_deref(), Some("Pistachio Noir" | "Noir")) => ("available", String::new()),
        Some(_) => ("own", String::new()),
    })
}

fn vscode_setup(config: &Path, env: &Env, scheme: &str, force: bool) -> Result<(), Fail> {
    let state = vscode_status(config, env)?.0;
    if matches!(state, "following" | "unsupported" | "missing") || state == "own" && !force {
        return Ok(());
    }
    let Some(e) = editor(config, env) else { return Ok(()) };
    if !vs_installed(env, e) {
        vs_install(env, e)?;
    }
    let settings = vs_settings(config, e);
    if !settings.exists() {
        return write_atomic(&settings, vs_with_theme("", vs_theme(scheme)).as_bytes());
    }
    let before = std::fs::read_to_string(&settings)?;
    let after = vs_with_theme(&before, vs_theme(scheme));
    if after != before { rewrite(&settings, &before, &after) } else { Ok(()) }
}

fn vscode_undo(config: &Path, env: &Env) -> Result<(), Fail> {
    let Some(e) = editor(config, env) else { return Ok(()) };
    let settings = vs_settings(config, e);
    let Ok(before) = std::fs::read_to_string(&settings) else { return Ok(()) };
    match vs_without_theme(&before) {
        Some(after) => rewrite(&settings, &before, &after),
        None => Ok(()), // nothing of ours; the extension stays installed, harmless and pickable by hand
    }
}

/// A Colours switch: our line, if there is one, to the matching theme. No backup each time (setup made
/// one); refused like `rewrite` if the file changed while reading.
fn vscode_publish(config: &Path, env: &Env, scheme: &str) -> Result<(), Fail> {
    let Some(e) = editor(config, env) else { return Ok(()) };
    let settings = vs_settings(config, e);
    if settings.is_symlink() {
        return Ok(());
    }
    let Ok(before) = std::fs::read_to_string(&settings) else { return Ok(()) };
    let Some(m) = member(&before, VS_KEY).filter(|m| marked(&before, m).is_some()) else { return Ok(()) };
    let after = format!("{}{}{}", &before[..m.value.start], quoted(vs_theme(scheme)), &before[m.value.end..]);
    if after == before {
        return Ok(());
    }
    #[cfg(test)]
    BEFORE_WRITE.with(|hook| if let Some(f) = hook.borrow().as_ref() { f() });
    if std::fs::read_to_string(&settings)? != before {
        return Err(Fail::Changed);
    }
    write_atomic(&settings, after.as_bytes())
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
    App { id: "vscode", name: "VS Code", status: vscode_status, setup: vscode_setup, undo: vscode_undo },
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
    // VS Code picks a settings change up at once; a failure there doesn't undo the publication
    if let Some(config) = path.parent().and_then(Path::parent) {
        match vscode_publish(config, env, scheme) {
            Ok(()) => {}
            Err(Fail::Changed) => eprintln!("VS Code's settings changed while switching its theme; it switches next time"),
            Err(Fail::Io(e)) => eprintln!("Could not switch VS Code's theme: {e}"),
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
    let home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
    let env = Env { path: std::env::var_os("PATH").unwrap_or_default(), home, reload: &reload_kitty };
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
