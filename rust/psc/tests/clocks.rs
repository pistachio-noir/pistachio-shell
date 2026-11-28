//! `psc clocks` without GNOME Clocks (owner's machine, 28 November 2026): no `org.gnome.clocks` schema
//! made gio abort psc (exit 134) at every call, once a minute from services/Clocks.qml. psc is run
//! with empty data folders, so it finds no schema on any machine, and the memory GSettings backend,
//! so nothing reaches a real dconf.
use std::process::{Command, Output};

fn psc(args: &[&str]) -> Output {
    static N: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
    let n = N.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
    let empty = std::env::temp_dir().join(format!("psc-clocks-test-{}-{n}", std::process::id()));
    std::fs::create_dir_all(&empty).unwrap();
    let out = Command::new(env!("CARGO_BIN_EXE_psc"))
        .args(["clocks"]).args(args)
        .env("XDG_DATA_DIRS", &empty).env("XDG_DATA_HOME", &empty).env_remove("GSETTINGS_SCHEMA_DIR")
        .env("GSETTINGS_BACKEND", "memory")
        .output().unwrap();
    let _ = std::fs::remove_dir_all(&empty);
    out
}

#[test]
fn list_without_clocks_is_empty() {
    let out = psc(&["list"]);
    assert_eq!(out.status.code(), Some(0), "stderr: {}", String::from_utf8_lossy(&out.stderr));
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), "[]");
}

#[test]
fn changes_without_clocks_are_refused_plainly() {
    for args in [&["add", "7", "30", "wake"][..], &["set", "x", "inactive"], &["remove", "x"], &["stop", "x"], &["snooze", "x"]] {
        let out = psc(args);
        assert_eq!(out.status.code(), Some(1), "{args:?}");
        assert!(out.stdout.is_empty(), "{args:?}");
        assert_eq!(String::from_utf8_lossy(&out.stderr).trim(), "psc clocks: GNOME Clocks isn't installed", "{args:?}");
    }
}
