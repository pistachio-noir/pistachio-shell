//! What psc understands. Anything that isn't one of its own commands goes to the shell's IPC, as
//! the old script did, so keybinds like `psc launcher toggle` keep working.
use clap::{Parser, Subcommand};
use std::ffi::OsString;

#[derive(Parser, Debug)]
#[command(name = "psc", version, about = "Pistachio Shell Control: run, stop and call the Pistachio shell",
    long_about = "Pistachio Shell Control: run, stop and call the Pistachio shell.\n\n\
        Without a command, psc runs the shell in this terminal (its log shows here).\n\
        Anything that isn't a psc command is a call to the shell, e.g. \"psc launcher toggle\";\n\
        \"psc ipc\" lists every target and function.",
    allow_external_subcommands = true)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Option<Cmd>,
}

#[derive(Subcommand, Debug)]
pub enum Cmd {
    /// Run the shell in the background (if it isn't running already)
    Start,
    /// Stop the shell, waiting until it has really gone
    Stop,
    /// Stop the shell, then start it again
    Restart,
    /// Kill the shell and its helpers at once, then start it again
    ForceRestart,
    /// Is the shell running: its PID, uptime, memory and helpers
    Status {
        /// Print JSON instead
        #[arg(long)]
        json: bool,
    },
    /// Print the shell's log (-f to follow; --errors for errors and warnings only)
    Log {
        /// Only errors and warnings, without the known Qt noise
        #[arg(long)]
        errors: bool,
        /// Anything else goes to `qs log` (e.g. -f, --tail 200)
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        rest: Vec<OsString>,
    },
    /// List every IPC target and function (with arguments: passed on to `qs ipc`)
    Ipc {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        rest: Vec<OsString>,
    },
    /// Check the tools, fonts, helpers and services the shell needs
    Doctor {
        /// Print JSON instead
        #[arg(long)]
        json: bool,
    },
    /// Open the first-run setup again (it opens by itself only on the very first start);
    /// with a function (`psc setup status`), a call to the shell's `setup` target
    Setup {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        rest: Vec<OsString>,
    },
    /// Print tab completion for a shell (zsh, bash, fish)
    Completions { shell: clap_complete::Shell },
    #[command(external_subcommand)]
    Call(Vec<OsString>),
}

/// `--errors` may come anywhere in `psc log …` (`psc log -f --errors`), not only first.
pub fn log_errors(errors: bool, rest: Vec<OsString>) -> (bool, Vec<OsString>) {
    let found = rest.iter().any(|a| a == "--errors");
    (errors || found, rest.into_iter().filter(|a| a != "--errors").collect())
}

/// The old script's straight pass-throughs to `qs -c pistachio …`: list, kill, msg, and options.
pub fn raw_passthrough(args: &[OsString]) -> bool {
    match args.first().and_then(|a| a.to_str()) {
        Some("list" | "kill" | "msg") => true,
        Some(a) => a.starts_with('-') && !matches!(a, "-h" | "--help" | "-V" | "--version"),
        None => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(args: &[&str]) -> Cli {
        Cli::try_parse_from(std::iter::once("psc").chain(args.iter().copied())).unwrap()
    }

    #[test]
    fn subcommand_names_win() {
        assert!(matches!(parse(&["status"]).command, Some(Cmd::Status { json: false })));
        assert!(matches!(parse(&["doctor", "--json"]).command, Some(Cmd::Doctor { json: true })));
        assert!(matches!(parse(&["completions", "zsh"]).command, Some(Cmd::Completions { .. })));
        match parse(&["launcher", "toggle", "--", "-x", "a b"]).command {
            Some(Cmd::Call(args)) => assert_eq!(args, ["launcher", "toggle", "--", "-x", "a b"].map(OsString::from)),
            other => panic!("{other:?}"),
        }
        assert!(parse(&[]).command.is_none());
        assert!(matches!(parse(&["setup"]).command, Some(Cmd::Setup { rest }) if rest.is_empty()));
        assert!(matches!(parse(&["setup", "status"]).command, Some(Cmd::Setup { rest }) if rest == ["status"]));
        match parse(&["log", "-f", "--errors"]).command {
            Some(Cmd::Log { errors, rest }) => assert_eq!(log_errors(errors, rest), (true, vec![OsString::from("-f")])),
            other => panic!("{other:?}"),
        }
        assert!(raw_passthrough(&["list".into()]) && raw_passthrough(&["--log-rules".into()]));
        assert!(!raw_passthrough(&["--help".into()]) && !raw_passthrough(&["status".into()]));
    }
}
