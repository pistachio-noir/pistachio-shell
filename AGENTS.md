# Handoff for Codex

Written by Claude Code on 19 November 2026. The owner is low on Claude usage and asked Codex to take over round 3 of the Python → Rust move: porting `chat.py` and `lens.py` into `psc`.

## 1. Read first, in this order

1. `CLAUDE.md`: the project's rules, short form. **Everything in it applies to you too**: settled decisions (don't reopen them), style rules, working rules, safety, and the most frequent gotchas. It imports `CLAUDE-HANDOFF.md` (Codex's own handoff from 18 November): that is history now, and this file overrides it.
2. `docs/decisions.md` and `docs/gotchas.md`: the full text of every decision and gotcha. Search gotchas before debugging anything odd. Read the psc entries dated 19 November 2026 in both.
3. `README.md`: requirements, install, IPC, and the `psc` section.
4. `docs/superpowers/specs/2026-11-19-psc-rust-design.md` and `docs/superpowers/plans/2026-11-19-psc-level2.md`: how `psc` is built and how the earlier helpers were moved.
5. `todos/TODO_19-11-26.md`: today's work, hand checks, and the deferred minors from reviews.

## 2. What the project is

Pistachio Noir Shell: a Quickshell 0.3.2 (QML) desktop shell for Hyprland on a single-monitor Arch desktop. `src/` is linked to `~/.config/quickshell/pistachio`.

- `src/services/`: singletons, the **only** places that touch system data. UI reads from them.
- `src/bar/`, `panels/`, `popups/`, `launcher/`, `lock/`, `settings/`: UI. `src/components/`: shared parts. `src/Theme.qml`: all colours, sizes and motion.
- `rust/`: Cargo workspace. All-day helpers (`pistachio-auth`, `pistachio-devices`, `pistachio-localsend`) and **`psc`** (`rust/psc/`): the owner's CLI plus hidden helper commands the shell runs as `Quickshell.env("HOME") + "/.local/bin/psc"`.
- Already in psc: `prefs`, `theme`, `system`, `boot-entries`, `swatch`, `capture`, `mic-check`, `phone-timer`, `files`, `library`, `clocks`, `launcher-tools`. Each is one file in `rust/psc/src/` (e.g. `clocks.rs`, `tools.rs`), dispatched from `main.rs`'s hidden-helper match. `system::run_for(args, limit)` runs a command with a deadline.
- Still Python: `src/services/chat.py` (Quick chat, 503 lines, called from `Chat.qml:359`), `src/services/lens.py` (Lens, 653 lines, called from `Lens.qml:265`), and `src/services/events.py` (calendar). events.py is **not** part of this task.
- Running: `pgrep -ax qs` first; never start a second shell. Talk to it with `psc <target> <function>`. Read `qs log -c pistachio --no-color` and confirm the "Configuration Loaded" count went up after an edit.
- Tests: see CLAUDE.md rule 9. Rust: `cd rust && cargo test --workspace`. For this task: `python3 -B tests/chat.test.py`, `sh tests/lens.sh`, and `sh tests/lens-native.sh` (a native Wayland window with grim screenshots; it runs a separate `qs -p` fixture, not the owner's shell).

## 3. Owner's working preferences

- The owner stages, commits and pushes. "Commit message" means text in chat only, lowercase `new: …` / `fix: …`, in the style of `git log`. Never `git add`/`commit`, and never work on `main`.
- Work stays on branch **`psc-rust`** (a temporary branch, so `experimental` doesn't break). Preserve every uncommitted change you didn't make. Leave `CLAUDE.md`'s front-matter block (title/author/date) alone; it's the owner's.
- Install **only psc** after a Rust change: `rm -f ~/.local/bin/psc && install -m 755 rust/target/release/psc ~/.local/bin/psc` (rm first: a running helper holds the old file). Don't run `install.sh`; the owner doesn't want the whole shell reinstalled.
- Never edit `~/.config/hypr/*`. Talk plainly and briefly, dates written out.
- The owner's direction (19 November 2026): **one ecosystem, every helper in Rust, no hybrids.** The calendar may stay Python only if Rust truly can't do it well.

## 3b. How the owner and Claude worked together

**You MUST work exactly this way.** This is not a suggestion: the owner requires any agent on this repo to follow the workflow below, the same way Claude and the owner worked together. If something here conflicts with your own defaults, this wins.

1. **Idea → talk first.** Propose in a few short points and ask only the owner's genuine calls. Give a recommendation, not a survey. Wait for "go". This task is already approved (section 4): don't ask again, just say your plan in a few lines and build.
2. **Boards are the truth** (`design/*.html`). This task has no UI change: the shell must look and behave the same.
3. **Verify before coding:** Quickshell types against the 0.3.2 docs, CLI flags with installed `--help` (`claude --help`, `codex --help`, `codex exec --help`), crate APIs against docs.rs for the version in `Cargo.lock`. Never from memory.
4. **Build small, test first (RED → GREEN).** Point the existing Python tests at psc (`PSC = os.environ.get("PSC") or <repo>/rust/target/release/psc`, as `tests/clocks.test.py` does), watch them fail, then implement. Move pure-Python unit cases into Rust `#[cfg(test)]` tests, as `tools.rs` did with launcher-tools' cases.
5. **Prove parity side by side.** Run the old Python (`git show HEAD:src/services/chat.py`, into the scratch dir) and the new psc on the same inputs with the same fake CLIs, and compare the JSON events and saved chat files. In round 2 this caught a bug no test had: alarms saved double-wrapped.
6. **Test for real, then clean up.** Run the suites, reload the shell, check the log, and check that the running helper is the new binary (`cmp /proc/<pid>/exe rust/target/release/psc`). After `pkill` of a helper, make sure the shell starts it again.
7. **Write it down the same session:** README's psc line, CLAUDE.md's "On-demand helpers" line (one line), the full text in `docs/decisions.md` and `docs/gotchas.md`, and today's TODO (`todos/TODO_DD-MM-YY.md`) with hand checks for the owner as unticked boxes. Never tick a hand check the owner didn't do.
8. **Review before you report.** Read your whole diff in a separate pass against the Python original: behaviour differences a user would notice, zombies/leaks, signal safety, error paths. Fix the real problems with a failing test first; list the minor ones as "Deferred minors" in the TODO.
9. **Report honestly:** what changed, what passed (commands), what failed, what's untested. Then the commit message as text.

**Bugs:** reproduce first, find the cause, fix it with a test that failed first, and write the cause into `docs/gotchas.md`.

**Safety:** no real Claude/Codex requests, network or accounts in tests: use the fake `claude`/`codex` from `tests/chat.test.py` and `tests/lens.test.py`. Tests use a temporary `HOME`, never the owner's real `~/quick-chats/` or `~/lens-chats/`. A QML fixture must swap the psc command for a stand-in or the repo build, and assert the swap matched (see `tests/launcher-tools-ui.test.py`, `tests/clocks-popup.test.py`). Never toggle Ethernet, disconnect Bluetooth or change audio routing.

## 4. Your task: port chat.py and lens.py into psc (approved)

The owner said "go" for the whole Python → Rust move. Rounds 1 and 2 are done. Round 3 is these two helpers, then a verdict on the calendar (`events.py`). Do **chat first** (smaller, and Lens shares its patterns), then lens.

**What to build**
- `psc chat` (new `rust/psc/src/chat.rs`) and `psc lens` (`lens.rs`), hidden from `--help` like the other helpers, wired into `main.rs`.
- Same stdin/stdout JSON-lines protocol, same events in the same order, same saved files (`~/quick-chats/`, `~/lens-chats/`, same names and JSON shape), same arguments to `claude` and `codex`, same streaming, cancel and timeout behaviour. Read each Python file in full before writing any Rust, and treat it as the spec.
- Lens keeps all its rules: read-only, schema answers, up to 3 images, one text file with diff/Apply, Ask both, coding presets only with consent (docs/decisions.md has the details).
- Switch `Chat.qml:359` and `Lens.qml:265` to `[Quickshell.env("HOME") + "/.local/bin/psc", "chat"]` / `"lens"`, and update their header comments.
- Tests: `tests/chat.test.py` and `tests/lens.test.py` drive psc. `tests/lens-native.sh` and any QML fixture that copies `Lens.qml`/`Chat.qml` rewrite the psc command to the repo build and assert it matched.
- Then delete `chat.py` and `lens.py` (don't stage the deletion; the owner does).
- Dependencies: prefer what `rust/psc/Cargo.toml` already has (serde_json, libc, gio, toml, quick-xml…). Ask the owner before adding a large crate (an async runtime, say). Threads and channels have been enough so far.

**Lessons from rounds 1 and 2** (all in `docs/gotchas.md`):
- Every spawned child must be waited for, or it stays a zombie all session.
- A signal handler may only do async-signal-safe things. Use a self-pipe and a thread, not `sigwait`: a blocked signal is inherited by children.
- Python's unhandled exception means exit 1 with a message on stderr; keep that where the QML relies on it.
- Rust's SIGPIPE is reset to default in `main.rs`; don't undo that.
- Pipes read on a deadline need reader threads and channels (see `system::run_for`), or a stuck child blocks forever.

**Then `events.py`** (the calendar, Evolution Data Server), only after chat and lens are done and reported. The owner's rule: Rust if it can be done well, Python acceptable if it truly can't. First check on the live system which EDS pieces are installed (libecal/libedataserver versions, GObject introspection), then whether Rust can reach them (libecal FFI by hand, or the gio crate talking to EDS over D-Bus). Give the owner a short verdict with the trade-offs **before** writing it. There is no events test yet: write one with a fake EDS (private D-Bus or stand-in data), and never use the owner's real calendars as fixtures.

**Out of scope:** UI changes, new features, the first-run welcome screen (section 5).

**When done**
- [ ] `cargo test --workspace`, `python3 -B tests/chat.test.py`, `sh tests/lens.sh`, `sh tests/lens-native.sh`, `sh tests/settings.sh` and `sh tests/layout.sh` pass.
- [ ] Side-by-side runs against the Python versions are identical, or every difference is written down as a decision.
- [ ] Only psc reinstalled; shell reloaded; Quick chat and Lens helpers are the new binary; no new errors in the log.
- [ ] Docs: README, CLAUDE.md line, docs/decisions.md, docs/gotchas.md, today's TODO with hand checks (a real Quick chat and a Lens snip, sent by the owner).
- [ ] The review pass is done, real problems fixed, minors listed.
- [ ] Report plus a commit message as text.

## 5. Other open threads (don't start without asking)

- **First-run welcome screen:** being designed with Claude right now (boards in `design/FirstRun/`). Don't build it unless the owner hands it to you.
- Before `experimental` is merged into `main`: talk packaging (binary/AppImage) or a rebuild first.
- Headphone toast restyle, GNOME launcher search providers, scheduled shell tasks: ideas only.

## 6. State right now

- Branch `psc-rust`, HEAD `d8673af`. A lot is uncommitted and intentional: psc Level 1 and Level 2 and rounds 1–2 (twelve helpers ported, their Python files deleted but not staged). The owner has the commit messages and may have committed some of it before you start: check `git status` and `git log`, and preserve everything.
- Last verified 19 November 2026, 18:20: all suites in CLAUDE.md rule 9 that don't change devices passed, plus `cargo test --workspace`. The installed `~/.local/bin/psc` was that build, and the shell's `psc launcher-tools` was running the new binary.
- Not yet hand-checked by the owner (in `todos/TODO_19-11-26.md`): alarms through the clock menu, launcher jobs, previews and Open with, and older Level 1/2 and round 1 checks, including that Kitty, Text, FM and Notes are still Noir.
- Known noise in logs: Qt Wayland focus warnings and occasional D-Bus/image warnings existed before. Don't describe the log as warning-free.
