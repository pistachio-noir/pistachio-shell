//! `psc library`: what the launcher offers from other apps, as one JSON line (services/Library.qml
//! runs it each time the launcher opens). Python's library.py until 19 November 2026; same JSON:
//!   {"clion": [{name, path, opened, git}], "vscode": [{name, path, opened, git}], "steam": [{appid, name, cover}]}
//! CLion's recent projects (newest first, from its recentProjects.xml), VS Code's recent folders and
//! workspaces (from the per-project folders in workspaceStorage: 1.145 keeps no recently-opened list),
//! with each project's Git branch and whether it has uncommitted changes; and the Steam games in every
//! library folder with their covers (runtimes, Proton and redistributables left out).
use serde_json::{json, Value};
use std::path::{Path, PathBuf};
use std::time::Duration;

fn entries(dir: &Path) -> Vec<PathBuf> {
    std::fs::read_dir(dir).map(|d| d.flatten().map(|e| e.path()).collect()).unwrap_or_default()
}

fn millis(path: &Path) -> i64 {
    std::fs::metadata(path).and_then(|m| m.modified()).ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).map(|d| (d.as_secs_f64() * 1000.0) as i64).unwrap_or(0)
}

fn base(path: &str) -> String {
    path.trim_end_matches('/').rsplit('/').next().unwrap_or(path).to_string()
}

/// file:///home/x/a%20b → /home/x/a b (the host part dropped, as urlparse(...).path)
fn file_path(uri: &str) -> Option<String> {
    let rest = uri.strip_prefix("file://")?;
    let path = &rest[rest.find('/').unwrap_or(rest.len())..];
    let bytes = path.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(b) = u8::from_str_radix(std::str::from_utf8(&bytes[i + 1..i + 3]).unwrap_or("zz"), 16) {
                out.push(b);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    Some(String::from_utf8_lossy(&out).into_owned())
}

/// Local folders and .code-workspace files VS Code opened, newest first (30 at most); VS Code's own
/// files (its agent-sessions workspace) and paths that are gone are left out.
pub fn vscode(home: &Path) -> Vec<Value> {
    let own = format!("{}/.config/Code/", home.display());
    let mut found: Vec<(String, Value)> = vec![];
    for folder in entries(&home.join(".config/Code/User/workspaceStorage")) {
        let Ok(text) = std::fs::read_to_string(folder.join("workspace.json")) else { continue };
        let Ok(d) = serde_json::from_str::<Value>(&text) else { continue };
        let uri = d.get("folder").and_then(Value::as_str).filter(|s| !s.is_empty())
            .or_else(|| d.get("workspace").and_then(Value::as_str)).unwrap_or("");
        let Some(path) = file_path(uri) else { continue }; // remote, WSL and untitled workspaces
        if path.starts_with(&own) || !Path::new(&path).exists() { continue; }
        let state = folder.join("state.vscdb");
        let opened = millis(if state.exists() { &state } else { &folder });
        let mut name = base(&path);
        if let Some(n) = name.strip_suffix(".code-workspace") { name = n.to_string(); }
        match found.iter_mut().find(|(p, _)| *p == path) {
            Some((_, v)) if v["opened"].as_i64() < Some(opened) => *v = json!({"name": name, "path": path, "opened": opened}),
            Some(_) => {}
            None => found.push((path.clone(), json!({"name": name, "path": path, "opened": opened}))),
        }
    }
    let mut list: Vec<Value> = found.into_iter().map(|(_, v)| v).collect();
    list.sort_by_key(|p| -p["opened"].as_i64().unwrap_or(0));
    list.truncate(30);
    list
}

pub fn clion(home: &Path) -> Vec<Value> {
    let mut lists: Vec<PathBuf> = entries(&home.join(".config/JetBrains"))
        .into_iter().filter(|d| d.file_name().is_some_and(|n| n.to_string_lossy().starts_with("CLion")))
        .map(|d| d.join("options/recentProjects.xml")).filter(|f| f.is_file()).collect();
    lists.sort();
    let Some(list) = lists.last() else { return vec![] };
    let Ok(text) = std::fs::read_to_string(list) else { return vec![] };
    let home_text = home.to_string_lossy();
    let mut reader = quick_xml::Reader::from_str(&text);
    let mut projects = vec![];
    let mut current: Option<(String, i64)> = None;
    let mut depth_in_entry = 0usize;
    let attr = |e: &quick_xml::events::BytesStart, key: &[u8]| -> Option<String> {
        e.attributes().flatten().find(|a| a.key.as_ref() == key).and_then(|a| a.unescape_value().ok()).map(|v| v.into_owned())
    };
    loop {
        match reader.read_event() {
            Ok(quick_xml::events::Event::Start(e)) => {
                if current.is_some() { depth_in_entry += 1; }
                if e.name().as_ref() == b"entry" && current.is_none() {
                    current = Some((attr(&e, b"key").unwrap_or_default(), 0));
                    depth_in_entry = 0;
                } else if e.name().as_ref() == b"option" {
                    if let Some(c) = current.as_mut() {
                        if attr(&e, b"name").as_deref() == Some("projectOpenTimestamp") { c.1 = attr(&e, b"value").and_then(|v| v.parse().ok()).unwrap_or(0); }
                    }
                }
            }
            Ok(quick_xml::events::Event::Empty(e)) => {
                if e.name().as_ref() == b"option" {
                    if let Some(c) = current.as_mut() {
                        if attr(&e, b"name").as_deref() == Some("projectOpenTimestamp") { c.1 = attr(&e, b"value").and_then(|v| v.parse().ok()).unwrap_or(0); }
                    }
                } else if e.name().as_ref() == b"entry" && current.is_none() {
                    projects.push((attr(&e, b"key").unwrap_or_default(), 0));
                }
            }
            Ok(quick_xml::events::Event::End(e)) => {
                if current.is_some() {
                    if depth_in_entry == 0 && e.name().as_ref() == b"entry" {
                        projects.push(current.take().unwrap());
                    } else {
                        depth_in_entry = depth_in_entry.saturating_sub(1);
                    }
                }
            }
            Ok(quick_xml::events::Event::Eof) => break,
            Err(_) => return vec![], // a broken file: as ElementTree's ParseError
            _ => {}
        }
    }
    let mut out: Vec<Value> = projects.into_iter().filter_map(|(key, opened)| {
        let path = key.replace("$USER_HOME$", &home_text);
        (!path.is_empty() && Path::new(&path).is_dir()).then(|| json!({"name": base(&path), "path": path, "opened": opened}))
    }).collect();
    out.sort_by_key(|p| -p["opened"].as_i64().unwrap_or(0));
    out
}

/// "key"   "value" pairs of a Valve KeyValues file
fn vdf_values<'a>(text: &'a str, key: &str) -> Vec<&'a str> {
    let needle = format!("\"{key}\"");
    let mut out = vec![];
    let mut rest = text;
    while let Some(at) = rest.find(&needle) {
        let after = &rest[at + needle.len()..];
        let trimmed = after.trim_start();
        if trimmed.len() < after.len() {
            if let Some(v) = trimmed.strip_prefix('"').and_then(|t| t.split_once('"')).map(|(v, _)| v) {
                if !v.is_empty() { out.push(v); }
            }
        }
        rest = after;
    }
    out
}

pub fn steam(home: &Path) -> Vec<Value> {
    let root = home.join(".local/share/Steam");
    let mut folders: Vec<PathBuf> = vec![];
    match std::fs::read_to_string(root.join("steamapps/libraryfolders.vdf")) {
        Ok(text) => {
            for p in vdf_values(&text, "path").into_iter().map(PathBuf::from).chain([root.clone()]) {
                if !folders.contains(&p) { folders.push(p); }
            }
        }
        Err(_) => folders.push(root.clone()),
    }
    let not_games = ["steam linux runtime", "steamworks", "proton", "redistributable", "steamvr"];
    let mut games = vec![];
    for folder in folders {
        for manifest in entries(&folder.join("steamapps")) {
            let name_ok = manifest.file_name().map(|n| n.to_string_lossy().into_owned()).is_some_and(|n| n.starts_with("appmanifest_") && n.ends_with(".acf"));
            if !name_ok { continue; }
            let Ok(bytes) = std::fs::read(&manifest) else { continue };
            let text = String::from_utf8_lossy(&bytes);
            let appid = vdf_values(&text, "appid").into_iter().find(|v| v.chars().all(|c| c.is_ascii_digit())).map(str::to_string);
            let name = vdf_values(&text, "name").into_iter().next().map(str::to_string);
            let (Some(appid), Some(name)) = (appid, name) else { continue };
            if not_games.iter().any(|w| name.to_lowercase().contains(w)) { continue; }
            let cache = root.join("appcache/librarycache").join(&appid);
            let mut covers = vec![cache.join("library_600x900.jpg"), cache.join("header.jpg")];
            covers.extend(entries(&cache).into_iter().map(|d| d.join("library_600x900.jpg")));
            let cover = covers.into_iter().find(|c| c.exists()).map(|c| c.to_string_lossy().into_owned()).unwrap_or_default();
            games.push(json!({"appid": appid, "name": name, "cover": cover}));
        }
    }
    games.sort_by_key(|g| g["name"].as_str().unwrap_or("").to_lowercase());
    games
}

pub fn git_status(path: &str) -> Value {
    if !Path::new(path).is_dir() { return Value::Null; }
    let (code, out, _) = crate::system::run_for(&["git", "--no-optional-locks", "-C", path, "-c", "core.fsmonitor=false", "status", "--porcelain=v1", "--branch", "--untracked-files=normal"], Duration::from_secs(1));
    if code != 0 { return Value::Null; }
    let lines: Vec<&str> = out.lines().collect();
    let Some(header) = lines.first().and_then(|l| l.strip_prefix("## ")) else { return Value::Null };
    let header = header.strip_prefix("No commits yet on ").or_else(|| header.strip_prefix("Initial commit on ")).unwrap_or(header);
    let mut branch = header.split("...").next().unwrap_or("").to_string();
    if branch.starts_with("HEAD ") { branch = "detached HEAD".into(); }
    json!({"branch": branch, "dirty": lines.len() > 1})
}

/// Each project's Git status, eight at a time.
fn with_git(lists: &mut [&mut Vec<Value>]) {
    let mut paths: Vec<String> = vec![];
    for list in lists.iter() {
        for p in list.iter() {
            let path = p["path"].as_str().unwrap_or("").to_string();
            if !paths.contains(&path) { paths.push(path); }
        }
    }
    let mut states: Vec<(String, Value)> = vec![];
    for chunk in paths.chunks(8) {
        let found: Vec<(String, Value)> = std::thread::scope(|s| {
            let handles: Vec<_> = chunk.iter().map(|p| s.spawn(move || (p.clone(), git_status(p)))).collect();
            handles.into_iter().filter_map(|h| h.join().ok()).collect()
        });
        states.extend(found);
    }
    for list in lists.iter_mut() {
        for p in list.iter_mut() {
            let path = p["path"].as_str().unwrap_or("").to_string();
            p["git"] = states.iter().find(|(s, _)| *s == path).map(|(_, v)| v.clone()).unwrap_or(Value::Null);
        }
    }
}

pub fn main(_args: &[String]) -> i32 {
    let home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
    let (mut clion_projects, mut code_projects) = (clion(&home), vscode(&home));
    with_git(&mut [&mut clion_projects, &mut code_projects]);
    println!("{}", json!({"clion": clion_projects, "vscode": code_projects, "steam": steam(&home)}));
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clean_dirty_and_non_repository() {
        let dir = std::env::temp_dir().join(format!("psc-git-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.to_str().unwrap();
        assert_eq!(git_status(path), Value::Null, "not a repository");
        std::process::Command::new("git").args(["init", "-q", path]).status().unwrap();
        let clean = git_status(path);
        assert!(!clean["branch"].as_str().unwrap().is_empty() && clean["dirty"] == false, "{clean}");
        std::fs::write(dir.join("new.txt"), "hello").unwrap();
        assert_eq!(git_status(path)["dirty"], true);
        assert_eq!(git_status(&format!("{path}/missing")), Value::Null);
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn uris_and_valve_files() {
        assert_eq!(file_path("file:///home/x/a%20b/%C5%BC"), Some("/home/x/a b/ż".into()));
        assert_eq!(file_path("file://host/srv/p"), Some("/srv/p".into()));
        assert_eq!(file_path("vscode-remote://ssh/x"), None);
        assert_eq!(vdf_values("\"path\"\t\t\"/mnt/games\"\n\"path\" \"/x\"", "path"), ["/mnt/games", "/x"]);
    }
}
