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
        let _ = std::fs::remove_dir_all(root);
        assert_eq!(pretty("Arch-Linux--linux-"), "Arch Linux (linux)");
        assert_eq!(pretty("---"), "---");
    }
}
