# psc in Rust (Level 1) — design

19 November 2026. Owner's call: replace the `bin/psc` shell script with a Rust binary of the same name, built on the temporary branch `psc-rust` so `experimental` stays safe; first step of moving from Python towards Rust. Inspired by Dank Material Shell's Go `dms` CLI (commands, not its daemon). No theme command for now (owner).

## Commands
- `psc` — run the shell in this terminal (`qs -c pistachio`).
- `psc start | stop | restart | force-restart` — as today: start once (`-n -d`); stop waits 5 s for a clean exit, then SIGTERM (2 s), then SIGKILL, so the next copy can take the notification bus name; force-restart SIGKILLs each shell's direct children and the shell, then starts it.
- `psc status` — running or not; for each shell: PID, uptime, memory (RSS of the shell, and of its helpers), the helpers it runs (direct children by name). `--json`.
- `psc log [-f] [--errors]` — `qs log -c pistachio`; `--errors` keeps only ERROR/FATAL/WARN lines and drops the known noise (`qt.qpa.wayland.textinput`, grabToImage sourceSize).
- `psc ipc` — every IPC target and its functions, readably grouped (from `qs ipc show`); `psc ipc <anything>` passes through as today.
- `psc <target> <function> [args]` — unchanged pass-through to `qs ipc call`, so keybinds keep working.
- `psc list | kill | msg …` — other `qs` subcommands for this config, as today.
- `psc doctor` — the tools, fonts, helpers and services the README lists: each found / missing, with the Arch package to install and what stops working without it; required ones first. `--json` (so Settings → Shell health can use it later). Exit status 1 if something required is missing.
- `psc completions zsh|bash|fish` — tab completion for the commands (IPC targets completed from the running shell where the shell allows a dynamic list; Claude's call: static first).
- `psc help` / `--help` / `<command> --help` — plain-language help.

## How (Claude's calls)
- New crate `rust/psc` in the existing workspace; `clap` (derive) and `clap_complete` for parsing, help and completions; no other new dependencies. Release profile as the workspace's.
- `install.sh` builds it and installs it as `~/.local/bin/psc`, replacing the link to `bin/psc`; `bin/psc` stays in the repo until the owner removes it after the merge. README's psc section updated.
- Shell state comes from `qs` itself (`qs list`, `qs log`, `qs ipc show`), and `/proc` for PIDs, children, memory and uptime. No new IPC in the shell; nothing in `src/` changes.
- The theming helper (`shared-theme.py`) stays Python in Level 1; it moves to Rust as its own later step.

## Approaches
1. **Rust binary with clap (picked):** real help and completions, and the base for later levels (settings, daemon).
2. Rust without clap (hand-written parsing): smaller binary, but help and completions by hand.
3. Keep the shell script and add commands to it: no move towards Rust; doctor/status get awkward in sh.

## Tests
`cargo test` for parsing, `qs list` output parsing, `/proc` reading, log filtering and doctor rows (with a fake PATH); an integration test runs the built binary against a stand-in `qs` script (start/stop/restart/force-restart order and waits, pass-through arguments unchanged, status output). Live: `psc status`, `psc doctor`, `psc log --errors`, `psc ipc` against the owner's running shell, read-only; start/stop/restart left as owner hand checks (they restart the session's shell).

## Out of scope
Theme command, settings from the terminal, the daemon (Levels 2 and 3).
