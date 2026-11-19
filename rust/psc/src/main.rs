//! psc: Pistachio Shell Control, in Rust (19 November 2026; replaces the bin/psc shell script).
mod agent;
mod boot;
mod chat;
mod capture;
mod cli;
mod clocks;
mod completions;
mod doctor;
mod files;
mod ipc;
mod lens;
mod library;
mod logs;
mod mic;
mod phone;
mod prefs;
mod status;
mod swatch;
mod system;
mod theme;
mod tools;
mod shell;

use clap::Parser;
use cli::{Cli, Cmd};
use std::ffi::OsString;

fn main() {
    // like other Unix tools, end quietly when the reader goes away (`psc log --errors | head`)
    unsafe { libc::signal(libc::SIGPIPE, libc::SIG_DFL) };
    let args: Vec<OsString> = std::env::args_os().skip(1).collect();
    // the shell's own helpers (were Python): `psc prefs|theme|system …`, hidden from --help
    match args.first().and_then(|a| a.to_str()) {
        Some("chat") if args.len() == 1 => std::process::exit(chat::main()),
        Some("lens") if args.len() == 1 => std::process::exit(lens::main()),
        Some("boot-entries") => { println!("{}", boot::entries(std::path::Path::new("/sys"))); std::process::exit(0) }
        Some("swatch") => {
            let rest: Vec<String> = args[1..].iter().map(|a| a.to_string_lossy().into_owned()).collect();
            std::process::exit(swatch::main(&rest));
        }
        Some(helper @ ("prefs" | "theme" | "system" | "capture" | "mic-check" | "phone-timer" | "files" | "library" | "clocks" | "launcher-tools")) => {
            let rest: Vec<String> = args[1..].iter().map(|a| a.to_string_lossy().into_owned()).collect();
            std::process::exit(match helper { "prefs" => prefs::main(&rest), "theme" => theme::main(&rest), "capture" => capture::main(&rest), "mic-check" => mic::main(&rest), "phone-timer" => phone::main(&rest), "files" => files::main(&rest), "library" => library::main(&rest), "clocks" => clocks::main(&rest), "launcher-tools" => tools::main(&rest), _ => system::main(&rest) });
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
        Some(Cmd::Doctor { json }) => {
            let home = std::path::PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
            let rows = doctor::run(&std::env::var_os("PATH").unwrap_or_default(), &home);
            if json { println!("{}", doctor::json(&rows)); } else { print!("{}", doctor::text(&rows)); }
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
