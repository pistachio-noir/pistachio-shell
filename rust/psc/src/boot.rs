//! `psc boot-entries`: the power menu's "Restart into…" list (services/Session.qml). Python's
//! boot-entries.py until 19 November 2026. Limine publishes its menu in the boot loader interface's
//! EFI variables, readable without root: LoaderEntries (all of them) and LoaderEntrySelected (the one
//! booted now, left out). Prints one JSON line: {"efi": bool, "entries": [{id, name}]}.
use serde_json::{json, Value};
use std::path::Path;

const VENDOR: &str = "4a67b082-0a4c-41cf-b6c7-440b29bb8c4f";

/// A variable's UTF-16 strings (after its 4 bytes of attributes); none when it's missing or broken.
fn read(sys: &Path, name: &str) -> Vec<String> {
    let Ok(data) = std::fs::read(sys.join(format!("firmware/efi/efivars/{name}-{VENDOR}"))) else { return vec![] };
    let units: Vec<u16> = data.get(4..).unwrap_or(&[]).chunks_exact(2).map(|b| u16::from_le_bytes([b[0], b[1]])).collect();
    match String::from_utf16(&units) {
        Ok(text) => text.split('\0').filter(|e| !e.is_empty()).map(str::to_string).collect(),
        Err(_) => vec![],
    }
}

/// Limine turns non-alphanumerics into "-": "Arch Linux (linux)" arrives as "Arch-Linux--linux-".
pub fn pretty(entry: &str) -> String {
    // "--(.+?)-$" → " (\1)": the first "--" with something after it, up to a final "-"
    let mut s = entry.to_string();
    if let Some(at) = s.find("--") {
        let inner = &s[at + 2..];
        if inner.len() > 1 && inner.ends_with('-') {
            s = format!("{} ({})", &s[..at], &inner[..inner.len() - 1]);
        }
    }
    // "-+" → " ", trimmed
    let mut out = String::new();
    let mut dash = false;
    for c in s.chars() {
        if c == '-' { if !dash { out.push(' '); } dash = true; } else { out.push(c); dash = false; }
    }
    let out = out.trim().to_string();
    if out.is_empty() { entry.to_string() } else { out }
}

/// The bytes of a LoaderEntryOneShot variable: attributes NON_VOLATILE | BOOTSERVICE_ACCESS |
/// RUNTIME_ACCESS (7), then the entry as NUL-terminated UTF-16LE (what bootctl wrote).
pub fn oneshot_bytes(id: &str) -> Vec<u8> {
    let mut out = vec![7, 0, 0, 0];
    for unit in id.encode_utf16().chain([0]) {
        out.extend(unit.to_le_bytes());
    }
    out
}

/// `psc boot-entries set-oneshot ID`, as root (pkexec, from the power menu): boot ID once, next time.
/// Was `pkexec bootctl set-oneshot` until 21 November 2026 (no bootctl without systemd). Limine reads
/// LoaderEntryOneShot (its LoaderFeatures has EntryOneShot). Only an entry Limine itself published is
/// taken, so the password dialog can't be used to write anything else.
pub fn set_oneshot(sys: &Path, id: &str) -> Result<(), String> {
    if id.is_empty() || !read(sys, "LoaderEntries").iter().any(|e| e == id) {
        return Err(format!("{id:?} is not one of Limine's boot entries"));
    }
    let file = sys.join(format!("firmware/efi/efivars/LoaderEntryOneShot-{VENDOR}"));
    if file.exists() {
        // an older one-shot: efivarfs marks variables it found at mount immutable (chattr -i), and
        // deleting the file deletes the variable, so the new one is written fresh
        clear_immutable(&file);
        std::fs::remove_file(&file).map_err(|e| format!("{}: {e}", file.display()))?;
    }
    // one write() of attributes and value: efivarfs takes a variable whole
    let mut out = std::fs::OpenOptions::new().write(true).create_new(true).open(&file).map_err(|e| format!("{}: {e}", file.display()))?;
    let bytes = oneshot_bytes(id);
    match std::io::Write::write(&mut out, &bytes) {
        Ok(n) if n == bytes.len() => Ok(()),
        Ok(n) => Err(format!("{}: wrote {n} of {} bytes", file.display(), bytes.len())),
        Err(e) => Err(format!("{}: {e}", file.display())),
    }
}

fn clear_immutable(file: &Path) {
    use std::os::fd::AsRawFd;
    const FS_IMMUTABLE_FL: libc::c_int = 0x10;
    let Ok(f) = std::fs::File::open(file) else { return };
    let mut flags: libc::c_int = 0;
    // on files that don't have flags (tmpfs in tests) both calls just fail, harmlessly
    unsafe {
        if libc::ioctl(f.as_raw_fd(), libc::FS_IOC_GETFLAGS, &mut flags) == 0 && flags & FS_IMMUTABLE_FL != 0 {
            flags &= !FS_IMMUTABLE_FL;
            libc::ioctl(f.as_raw_fd(), libc::FS_IOC_SETFLAGS, &flags);
        }
    }
}

pub fn main(args: &[String]) -> i32 {
    let sys = Path::new("/sys");
    match args {
        [] => { println!("{}", entries(sys)); 0 }
        [cmd, id] if cmd == "set-oneshot" => match set_oneshot(sys, id) {
            Ok(()) => 0,
            Err(e) => { eprintln!("psc boot-entries: {e}"); 1 }
        },
        _ => { eprintln!("usage: psc boot-entries [set-oneshot ID]"); 2 }
    }
}

pub fn entries(sys: &Path) -> Value {
    let current = read(sys, "LoaderEntrySelected").into_iter().next().unwrap_or_default();
    let list: Vec<Value> = read(sys, "LoaderEntries").into_iter().filter(|e| *e != current).map(|e| json!({"id": e, "name": pretty(&e)})).collect();
    json!({"efi": sys.join("firmware/efi").exists(), "entries": list})
}

#[cfg(test)]
mod tests {
    use super::*;

    fn utf16(entries: &[&str]) -> Vec<u8> {
        let mut out = vec![7, 0, 0, 0]; // 4 bytes of attributes
        for e in entries { for u in e.encode_utf16().chain([0]) { out.extend(u.to_le_bytes()); } }
        out
    }

    #[test]
    fn limine_entries_without_the_current_one() {
        let root = std::env::temp_dir().join(format!("psc-boot-{}", std::process::id()));
        let vars = root.join("firmware/efi/efivars");
        std::fs::create_dir_all(&vars).unwrap();
        std::fs::write(vars.join("LoaderEntries-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f"), utf16(&["Arch-Linux--linux-", "Windows", "Arch--tweaked-"])).unwrap();
        std::fs::write(vars.join("LoaderEntrySelected-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f"), utf16(&["Arch-Linux--linux-"])).unwrap();
        assert_eq!(entries(&root), json!({"efi": true, "entries": [{"id": "Windows", "name": "Windows"}, {"id": "Arch--tweaked-", "name": "Arch (tweaked)"}]}));
        assert_eq!(entries(&root.join("nowhere")), json!({"efi": false, "entries": []}));

        // set-oneshot: only Limine's own entries; the variable as bootctl wrote it, read back as one entry
        let oneshot = vars.join("LoaderEntryOneShot-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f");
        assert!(set_oneshot(&root, "Gentoo").is_err() && set_oneshot(&root, "").is_err() && !oneshot.exists());
        set_oneshot(&root, "Arch--tweaked-").unwrap();
        assert_eq!(std::fs::read(&oneshot).unwrap(), utf16(&["Arch--tweaked-"]));
        assert_eq!(read(&root, "LoaderEntryOneShot"), ["Arch--tweaked-"]);
        set_oneshot(&root, "Windows").unwrap(); // over an existing variable
        assert_eq!(read(&root, "LoaderEntryOneShot"), ["Windows"]);
        assert_eq!(oneshot_bytes("W"), [7, 0, 0, 0, b'W', 0, 0, 0]);
        assert_eq!(main(&["set-oneshot".into()]), 2);
        let _ = std::fs::remove_dir_all(root);
        assert_eq!(pretty("Arch-Linux--linux-"), "Arch Linux (linux)");
        assert_eq!(pretty("---"), "---");
    }
}
