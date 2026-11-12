//! Files on the way out and in: what the shell asks about paths, the clipboard, safe names for
//! what arrives, and a file's type from its name.

use std::collections::HashMap;
use std::path::{Component, Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::OnceLock;
use std::time::{Duration, Instant};

use serde_json::{json, Value};

use crate::http::percent_decode;

/// The path made absolute and tidy (no "." or ".." left), without touching the disk.
pub fn absolute(path: &str) -> PathBuf {
    let path = Path::new(path);
    let full = if path.is_absolute() { path.to_path_buf() } else { std::env::current_dir().unwrap_or_default().join(path) };
    let mut out = PathBuf::new();
    for part in full.components() {
        match part {
            Component::ParentDir => {
                out.pop();
            }
            Component::CurDir => {}
            other => out.push(other),
        }
    }
    out
}

pub fn text(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn base_name(path: &Path) -> String {
    path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()
}

/// The files under a folder: each folder's own files by name, then its folders. Links to folders
/// are not followed.
pub fn walk(folder: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = std::fs::read_dir(folder) else { return };
    let mut entries: Vec<PathBuf> = entries.flatten().map(|e| e.path()).collect();
    entries.sort();
    let is_folder = |p: &PathBuf| std::fs::symlink_metadata(p).is_ok_and(|m| m.is_dir());
    out.extend(entries.iter().filter(|p| !is_folder(p) && p.is_file()).cloned());
    for sub in entries.iter().filter(|p| is_folder(p)) {
        walk(sub, out);
    }
}

/// What the shell shows about paths it may send: {"path", "name", "size", "count", "dir", "mime"}.
pub fn inspect(paths: &[String]) -> Value {
    let mut items = Vec::new();
    for path in paths {
        let path = absolute(path);
        if path.is_dir() {
            let mut files = Vec::new();
            walk(&path, &mut files);
            let sizes: Vec<u64> = files.iter().filter_map(|f| std::fs::metadata(f).ok()).map(|m| m.len()).collect();
            items.push(json!({"path": text(&path), "name": base_name(&path), "size": sizes.iter().sum::<u64>(), "count": sizes.len(), "dir": true, "mime": "inode/directory"}));
        } else if path.is_file() {
            let size = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
            items.push(json!({"path": text(&path), "name": base_name(&path), "size": size, "count": 1, "dir": false, "mime": mime(&base_name(&path))}));
        }
    }
    json!({"event": "items", "items": items})
}

/// Runs a command for at most three seconds; its output when it ended well.
fn run(program: &str, args: &[&str]) -> Option<Vec<u8>> {
    use std::io::Read;
    let mut child = Command::new(program).args(args).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().ok()?;
    let mut stdout = child.stdout.take()?;
    let reading = std::thread::spawn(move || {
        let mut out = Vec::new();
        let _ = stdout.read_to_end(&mut out);
        out
    });
    let end = Instant::now() + Duration::from_secs(3);
    loop {
        match child.try_wait() {
            Ok(Some(status)) => return reading.join().ok().filter(|_| status.success()),
            Ok(None) if Instant::now() < end => std::thread::sleep(Duration::from_millis(15)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return None;
            }
        }
    }
}

/// The clipboard, as something to send: copied files, else text, else nothing.
pub fn paste() -> Value {
    let read = |kind: &str| run("wl-paste", &["--no-newline", "--type", kind]).map(|out| String::from_utf8_lossy(&out).into_owned()).unwrap_or_default();
    let nothing = json!({"event": "paste"});
    let Some(types) = run("wl-paste", &["--list-types"]) else { return nothing };
    let types = String::from_utf8_lossy(&types).into_owned();
    let types: Vec<&str> = types.split_whitespace().collect();
    for kind in ["text/uri-list", "x-special/gnome-copied-files"] {
        if !types.contains(&kind) {
            continue;
        }
        let paths: Vec<String> = read(kind).lines().map(str::trim).filter_map(|line| line.strip_prefix("file://")).map(file_path).collect();
        if !paths.is_empty() {
            return json!({"event": "paste", "paths": paths});
        }
    }
    if types.iter().any(|t| t.starts_with("text/plain") || ["UTF8_STRING", "STRING", "TEXT"].contains(t)) {
        let mut text = read("text/plain;charset=utf-8");
        if text.is_empty() {
            text = read("text/plain");
        }
        if !text.trim().is_empty() {
            return json!({"event": "paste", "text": text});
        }
    }
    nothing
}

/// The path in what follows "file://": past the host, up to a query or fragment, unescaped.
fn file_path(rest: &str) -> String {
    let path = rest.find('/').map_or("", |at| &rest[at..]);
    let path = path.split(['?', '#']).next().unwrap_or_default();
    percent_decode(path, false)
}

/// Where to save an arriving file: inside `folder` whatever its name says, its folders made, and
/// never over a file that's there or arriving ("name (2).ext"). The file is written as
/// "<path>.part" first; that file is made here, already open, so two files arriving at once under
/// one name can't pick the same path.
pub fn claim(folder: &Path, name: &str) -> std::io::Result<(PathBuf, std::fs::File)> {
    loop {
        let path = safe_path(folder, name)?;
        match std::fs::OpenOptions::new().write(true).create_new(true).open(part_of(&path)) {
            Ok(file) => return Ok((path, file)),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue, // someone was faster: the next number
            Err(e) => return Err(e),
        }
    }
}

/// The name a file has while it arrives.
pub fn part_of(path: &Path) -> PathBuf {
    PathBuf::from(format!("{}.part", text(path)))
}

/// A free path for an arriving file (see [`claim`], which also takes it).
pub fn safe_path(folder: &Path, name: &str) -> std::io::Result<PathBuf> {
    let name = name.replace('\\', "/");
    let mut parts: Vec<&str> = name.split('/').filter(|p| !matches!(*p, "" | "." | "..")).collect();
    if parts.is_empty() {
        parts.push("file");
    }
    let mut path = folder.to_path_buf();
    path.extend(&parts);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    // as Python's splitext: the last dot of the last part, unless the name starts with it
    let full = text(&path);
    let file = parts[parts.len() - 1];
    let dot = file.rfind('.').filter(|at| file[..*at].chars().any(|c| c != '.'));
    let (root, ext) = match dot {
        Some(at) => (&full[..full.len() - (file.len() - at)], &file[at..]),
        None => (full.as_str(), ""),
    };
    let taken = |p: &Path| p.exists() || PathBuf::from(format!("{}.part", text(p))).exists();
    let mut n = 2;
    while taken(&path) {
        path = PathBuf::from(format!("{root} ({n}){ext}"));
        n += 1;
    }
    Ok(path)
}

/// The type of a file from its name, as Python's mimetypes guesses it: the system's
/// /etc/mime.types first, then a table of the common ones; "name.tar.gz" is its inner type.
pub fn mime(name: &str) -> String {
    static SYSTEM: OnceLock<HashMap<String, String>> = OnceLock::new();
    let system = SYSTEM.get_or_init(|| {
        let mut types = HashMap::new();
        for line in std::fs::read_to_string("/etc/mime.types").unwrap_or_default().lines() {
            let mut words = line.split('#').next().unwrap_or_default().split_whitespace();
            let Some(kind) = words.next() else { continue };
            for extension in words {
                types.insert(extension.to_string(), kind.to_string());
            }
        }
        types
    });
    let mut name = name.rsplit('/').next().unwrap_or(name).to_string();
    for (short, long) in [(".svgz", ".svg.gz"), (".tgz", ".tar.gz"), (".taz", ".tar.gz"), (".tz", ".tar.gz"), (".tbz2", ".tar.bz2"), (".txz", ".tar.xz")] {
        if let Some(stem) = name.strip_suffix(short) {
            name = format!("{stem}{long}");
        }
    }
    for packed in [".gz", ".Z", ".bz2", ".xz", ".br"] {
        if let Some(stem) = name.strip_suffix(packed) {
            name = stem.to_string();
            break;
        }
    }
    let extension = match name.rfind('.') {
        Some(at) if name[..at].chars().any(|c| c != '.') => &name[at + 1..],
        _ => return "application/octet-stream".into(),
    };
    let find = |ext: &str| system.get(ext).cloned().or_else(|| COMMON.iter().find(|(e, _)| *e == ext).map(|(_, kind)| kind.to_string()));
    find(extension).or_else(|| find(&extension.to_ascii_lowercase())).unwrap_or_else(|| "application/octet-stream".into())
}

const COMMON: &[(&str, &str)] = &[
    ("txt", "text/plain"), ("md", "text/markdown"), ("html", "text/html"), ("htm", "text/html"), ("css", "text/css"), ("csv", "text/csv"),
    ("js", "text/javascript"), ("mjs", "text/javascript"), ("json", "application/json"), ("xml", "text/xml"), ("py", "text/x-python"),
    ("c", "text/plain"), ("h", "text/plain"), ("sh", "application/x-sh"), ("rtf", "application/rtf"), ("ics", "text/calendar"),
    ("png", "image/png"), ("jpg", "image/jpeg"), ("jpeg", "image/jpeg"), ("jpe", "image/jpeg"), ("gif", "image/gif"), ("webp", "image/webp"),
    ("svg", "image/svg+xml"), ("bmp", "image/bmp"), ("ico", "image/vnd.microsoft.icon"), ("tif", "image/tiff"), ("tiff", "image/tiff"),
    ("heic", "image/heic"), ("heif", "image/heif"), ("avif", "image/avif"),
    ("mp3", "audio/mpeg"), ("m4a", "audio/mp4"), ("aac", "audio/aac"), ("flac", "audio/flac"), ("ogg", "audio/ogg"), ("opus", "audio/opus"), ("wav", "audio/x-wav"),
    ("mp4", "video/mp4"), ("m4v", "video/mp4"), ("mkv", "video/x-matroska"), ("webm", "video/webm"), ("mov", "video/quicktime"), ("avi", "video/x-msvideo"), ("mpeg", "video/mpeg"), ("mpg", "video/mpeg"), ("3gp", "video/3gpp"),
    ("pdf", "application/pdf"), ("zip", "application/zip"), ("tar", "application/x-tar"), ("7z", "application/x-7z-compressed"), ("rar", "application/vnd.rar"),
    ("doc", "application/msword"), ("docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"),
    ("xls", "application/vnd.ms-excel"), ("xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
    ("ppt", "application/vnd.ms-powerpoint"), ("pptx", "application/vnd.openxmlformats-officedocument.presentationml.presentation"),
    ("odt", "application/vnd.oasis.opendocument.text"), ("ods", "application/vnd.oasis.opendocument.spreadsheet"), ("epub", "application/epub+zip"),
    ("apk", "application/vnd.android.package-archive"), ("exe", "application/octet-stream"), ("bin", "application/octet-stream"), ("iso", "application/x-iso9660-image"),
    ("wasm", "application/wasm"), ("ttf", "font/ttf"), ("otf", "font/otf"), ("woff", "font/woff"), ("woff2", "font/woff2"),
];

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let folder = std::env::temp_dir().join(format!("pistachio-localsend-test-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&folder);
        std::fs::create_dir_all(&folder).unwrap();
        folder
    }

    #[test]
    fn an_arriving_name_cannot_leave_the_folder() {
        let folder = scratch("safe");
        for name in ["../../etc/passwd", "/etc/passwd", "..\\..\\etc\\passwd", "a/../../b/./passwd"] {
            let path = safe_path(&folder, name).unwrap();
            assert!(path.starts_with(&folder), "{name} -> {path:?}");
            assert_eq!(path.file_name().unwrap(), "passwd");
        }
        assert_eq!(safe_path(&folder, "../..").unwrap(), folder.join("file"));
        assert_eq!(safe_path(&folder, "album/sub/x.jpg").unwrap(), folder.join("album/sub/x.jpg"));
        assert!(folder.join("album/sub").is_dir());
        std::fs::remove_dir_all(folder).unwrap();
    }

    #[test]
    fn a_name_already_there_or_arriving_gets_a_number() {
        let folder = scratch("taken");
        std::fs::write(folder.join("photo.jpg"), b"x").unwrap();
        assert_eq!(safe_path(&folder, "photo.jpg").unwrap(), folder.join("photo (2).jpg"));
        std::fs::write(folder.join("photo (2).jpg.part"), b"x").unwrap();
        assert_eq!(safe_path(&folder, "photo.jpg").unwrap(), folder.join("photo (3).jpg"));
        std::fs::write(folder.join(".bashrc"), b"x").unwrap();
        assert_eq!(safe_path(&folder, ".bashrc").unwrap(), folder.join(".bashrc (2)"));
        std::fs::write(folder.join("notes"), b"x").unwrap();
        assert_eq!(safe_path(&folder, "notes").unwrap(), folder.join("notes (2)"));
        std::fs::remove_dir_all(folder).unwrap();
    }

    #[test]
    fn files_arriving_at_once_under_one_name_each_get_their_own() {
        let folder = scratch("claim");
        let claims: Vec<_> = (0..8).map(|_| { let folder = folder.clone(); std::thread::spawn(move || claim(&folder, "IMG_0001.jpg").unwrap().0) }).collect();
        let mut paths: Vec<PathBuf> = claims.into_iter().map(|c| c.join().unwrap()).collect();
        paths.sort();
        paths.dedup();
        assert_eq!(paths.len(), 8);
        assert!(paths.iter().all(|p| part_of(p).exists()));
        std::fs::remove_dir_all(folder).unwrap();
    }

    #[test]
    fn types_are_guessed_from_names() {
        assert_eq!(mime("Photo.JPG"), "image/jpeg");
        assert_eq!(mime("notes.txt"), "text/plain");
        assert_eq!(mime("backup.tar.gz"), "application/x-tar");
        assert_eq!(mime("backup.tgz"), "application/x-tar");
        assert_eq!(mime("README"), "application/octet-stream");
        assert_eq!(mime(".hidden"), "application/octet-stream");
        assert_eq!(mime("thing.unknownext"), "application/octet-stream");
    }

    #[test]
    fn a_copied_files_address_becomes_its_path() {
        assert_eq!(file_path("/home/sx/a%20b.txt"), "/home/sx/a b.txt");
        assert_eq!(file_path("localhost/home/sx/x#frag"), "/home/sx/x");
    }

    #[test]
    fn a_folder_is_walked_files_first_by_name_and_tidied_paths() {
        let folder = scratch("walk");
        std::fs::create_dir_all(folder.join("album/sub")).unwrap();
        for file in ["album/b.txt", "album/a.txt", "album/sub/c.txt"] {
            std::fs::write(folder.join(file), b"12345").unwrap();
        }
        let mut files = Vec::new();
        walk(&folder.join("album"), &mut files);
        let names: Vec<String> = files.iter().map(|f| text(f.strip_prefix(&folder).unwrap())).collect();
        assert_eq!(names, ["album/a.txt", "album/b.txt", "album/sub/c.txt"]);
        let seen = inspect(&[format!("{}/album/../album", text(&folder))]);
        assert_eq!(seen["items"][0]["path"], text(&folder.join("album")));
        assert_eq!((seen["items"][0]["size"].as_u64(), seen["items"][0]["count"].as_u64()), (Some(15), Some(3)));
        std::fs::remove_dir_all(folder).unwrap();
    }
}
