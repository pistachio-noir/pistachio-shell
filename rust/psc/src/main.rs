//! psc: Pistachio Shell Control, in Rust (19 November 2026; replaces the bin/psc shell script).
mod agent;
mod boot;
mod chat;
mod capture;
mod cli;
mod clocks;
mod completions;
mod doctor;
mod events;
mod files;
mod ipc;
mod lens;
mod library;
mod logs;
mod mic;
mod phone;
mod power;
mod prefs;
mod status;
mod swatch;
mod system;
mod theme;
mod tools;
mod vsix;
mod shell;

use clap::Parser;
use cli::{Cli, Cmd};
use std::ffi::OsString;

fn main() {
    // like other Unix tools, end quietly when the reader goes away (`psc log --errors | head`)
    unsafe { libc::signal(libc::SIGPIPE, libc::SIG_DFL) };
    // ~/.local/bin, where Claude Code's installer puts `claude` (and psc lives), is often only on an
    // interactive shell's PATH (the owner's ~/.zshrc): the session, so the shell and psc, lacked it on
    // Gentoo and Quick chat said Claude wasn't installed (21 November 2026). Appended, so it never
    // shadows a system tool; everything psc starts inherits it.
    if let Some(path) = with_local_bin(&std::env::var_os("PATH").unwrap_or_default(), std::env::var_os("HOME").as_deref()) {
        std::env::set_var("PATH", path);
    }
    let args: Vec<OsString> = std::env::args_os().skip(1).collect();
    // the shell's own helpers (were Python): `psc prefs|theme|system …`, hidden from --help
    match args.first().and_then(|a| a.to_str()) {
        Some("chat") if args.len() == 1 => std::process::exit(chat::main()),
        Some("lens") if args.len() == 1 => std::process::exit(lens::main()),
        Some(helper @ ("boot-entries" | "power")) => {
            let rest: Vec<String> = args[1..].iter().map(|a| a.to_string_lossy().into_owned()).collect();
            std::process::exit(if helper == "power" { power::main(&rest) } else { boot::main(&rest) });
        }
        Some("swatch") => {
            let rest: Vec<String> = args[1..].iter().map(|a| a.to_string_lossy().into_owned()).collect();
            std::process::exit(swatch::main(&rest));
        }
        Some(helper @ ("prefs" | "theme" | "system" | "capture" | "mic-check" | "phone-timer" | "files" | "library" | "clocks" | "launcher-tools" | "events")) => {
            let rest: Vec<String> = args[1..].iter().map(|a| a.to_string_lossy().into_owned()).collect();
            std::process::exit(match helper { "prefs" => prefs::main(&rest), "theme" => theme::main(&rest), "capture" => capture::main(&rest), "mic-check" => mic::main(&rest), "phone-timer" => phone::main(&rest), "files" => files::main(&rest), "library" => library::main(&rest), "clocks" => clocks::main(&rest), "launcher-tools" => tools::main(&rest), "events" => events::main(&rest), _ => system::main(&rest) });
        }
        _ => {}
    }
    if cli::raw_passthrough(&args) {
        shell::exec_qs(&args);
    }
    let command = match Cli::parse().command {
        Some(Cmd::Log { errors, rest }) => {
            let (errors, rest) = cli::log_errors(errors, rest);
            Some(Cmd::Log { errors, rest })
        }
        other => other,
    };
    let code = match command {
        None => shell::exec_qs(&[]),
        Some(Cmd::Start) => shell::exec_qs(&["-n".into(), "-d".into()]),
        Some(Cmd::Stop) => done(shell::stop()),
        Some(Cmd::Restart) => match shell::stop() {
            Ok(()) => shell::exec_qs(&["-n".into(), "-d".into()]),
            Err(e) => done(Err(e)),
        },
        Some(Cmd::ForceRestart) => match shell::force_stop() {
            Ok(()) => shell::exec_qs(&["-n".into(), "-d".into()]),
            Err(e) => done(Err(e)),
        },
        Some(Cmd::Log { errors: false, rest }) => shell::exec_qs(&[vec!["log".into()], rest].concat()),
        Some(Cmd::Ipc { rest }) if !rest.is_empty() => shell::exec_qs(&[vec!["ipc".into()], rest].concat()),
        Some(Cmd::Setup { rest }) => {
            let rest = if rest.is_empty() { vec!["open".into()] } else { rest };
            shell::exec_qs(&[vec!["ipc".into(), "call".into(), "setup".into()], rest].concat())
        }
        Some(Cmd::Call(call)) => shell::exec_qs(&[vec!["ipc".into(), "call".into()], call].concat()),
        Some(Cmd::Status { json }) => {
            let shells: Vec<_> = shell::pids().into_iter().filter_map(|p| status::read(p, std::path::Path::new("/proc"))).collect();
            if json { println!("{}", status::json(&shells)); } else { print!("{}", status::text(&shells)); }
            if shells.is_empty() { 1 } else { 0 }
        }
        Some(Cmd::Log { errors: true, rest }) => {
            use std::io::{BufRead, BufReader};
            match shell::qs().arg("log").arg("--no-color").args(&rest).stdout(std::process::Stdio::piped()).spawn() {
                Ok(mut child) => {
                    for line in BufReader::new(child.stdout.take().unwrap()).lines().map_while(Result::ok) {
                        if logs::keep(&line) { println!("{line}"); }
                    }
                    child.wait().map(|s| s.code().unwrap_or(1)).unwrap_or(1)
                }
                Err(e) => { eprintln!("psc: couldn't run qs: {e}"); 127 }
            }
        }
        Some(Cmd::Ipc { .. }) => match shell::qs().args(["ipc", "show"]).output() {
            Ok(o) if o.status.success() && !o.stdout.is_empty() => { print!("{}", ipc::text(&ipc::parse(&String::from_utf8_lossy(&o.stdout)), ipc::colour_wanted())); 0 }
            Ok(o) => {
                let why = String::from_utf8_lossy(&o.stderr);
                eprintln!("psc: the shell didn't answer{}", if why.trim().is_empty() { " (is it running? psc status)".into() } else { format!(": {}", why.trim()) });
                1
            }
            Err(e) => { eprintln!("psc: couldn't run qs: {e}"); 127 }
        },
        Some(Cmd::Doctor { json, packages, install }) => {
            let home = std::path::PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
            let distro = doctor::this_distro();
            let rows = doctor::run(&std::env::var_os("PATH").unwrap_or_default(), &home, distro);
            let kind_of = |k: &str| if k == "required" { doctor::Kind::Required } else { doctor::Kind::Optional };
            if let Some(kind) = packages {
                println!("{}", doctor::packages(&rows, kind_of(&kind)).join(" "));
            } else if let Some(kind) = install {
                for line in doctor::install_lines(&rows, kind_of(&kind), distro) { println!("{line}"); }
            } else if json { println!("{}", doctor::json(&rows)); } else { print!("{}", doctor::text(&rows)); }
            if doctor::missing_required(&rows) { 1 } else { 0 }
        }
        Some(Cmd::Completions { shell }) => { print!("{}", completions::script(shell)); 0 }
    };
    std::process::exit(code);
}

fn done(result: Result<(), String>) -> i32 {
    match result {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("psc: {e}");
            1
        }
    }
}

/// PATH with $HOME/.local/bin appended, or None when it's already there (or there's no HOME).
fn with_local_bin(path: &std::ffi::OsStr, home: Option<&std::ffi::OsStr>) -> Option<OsString> {
    let home = home.filter(|h| !h.is_empty())?;
    let local = std::path::Path::new(home).join(".local/bin");
    let mut dirs: Vec<std::path::PathBuf> = std::env::split_paths(path).filter(|d| !d.as_os_str().is_empty()).collect();
    if dirs.iter().any(|d| *d == local) {
        return None;
    }
    dirs.push(local);
    std::env::join_paths(dirs).ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::OsStr;

    #[test]
    fn local_bin_on_path() {
        let home = Some(OsStr::new("/home/u"));
        assert_eq!(with_local_bin(OsStr::new("/usr/bin:/opt/bin"), home), Some("/usr/bin:/opt/bin:/home/u/.local/bin".into()), "appended, last");
        assert_eq!(with_local_bin(OsStr::new("/home/u/.local/bin:/usr/bin"), home), None, "already there");
        assert_eq!(with_local_bin(OsStr::new(""), home), Some("/home/u/.local/bin".into()));
        assert_eq!(with_local_bin(OsStr::new("/usr/bin"), None), None);
        assert_eq!(with_local_bin(OsStr::new("/usr/bin"), Some(OsStr::new(""))), None);
    }
}
