# Handoff for Claude Code

Written by Codex on 19 November 2026 at the owner's request. The Quick chat and Lens ports and the subsequent TUI changes are ready for pickup on `psc-rust`.

## 1. Read first, in this order

1. `CLAUDE.md` and this handoff. The project's rules apply throughout. `AGENTS.md` records the incoming scope and workflow from Claude. This handoff and the current tree give the delivery status.
2. `docs/decisions.md` and `docs/gotchas.md`, especially the 19 November 2026 entries on psc and TUI. `todos/TODO_19-11-26.md` tracks verification, owner checks and deferred minors. Older handoff notes live in `todos/handoff-archive.md`.
3. `README.md` and the pages it links in `docs/` for installation, requirements and IPC (`docs/ipc-and-keybinds.md`), `docs/plan.md` for architecture, and the separate `pistachio-shell-design` repo (`~/Desktop/pistachio/pistachio-shell-design/`, moved out on 21 November 2026) for approved boards.
4. For psc work, read `docs/superpowers/specs/2026-11-19-psc-rust-design.md` and `docs/superpowers/plans/2026-11-19-psc-level2.md`. For sibling apps, read each app's own `CLAUDE.md` and the suite rules at `~/Desktop/pistachio/pistachio-suite/CLAUDE.md`. Some older imports point at the previous location.

## 2. What the project is

Pistachio Noir Shell runs Quickshell 0.3.2/QML on a single-monitor Arch desktop with Hyprland. `src/` is linked at `~/.config/quickshell/pistachio`. System access stays in `src/services/`, including the `Compositor.qml` adapter. UI lives in `src/bar/`, `panels/`, `popups/`, `settings/`, `launcher/` and `lock/`. Use the shared components and `src/Theme.qml` for colours, geometry and motion. Use the existing `open`/Reveal contract for windows.

`rust/` contains the all-day auth, devices and LocalSend helpers plus `rust/psc/`, the CLI and on-demand helpers. QML runs `$HOME/.local/bin/psc`. The hidden commands are dispatched in `rust/psc/src/main.rs`. Shell colour publishing is `psc theme`. Text, FM and Notes follow the shared colour file at `$XDG_CONFIG_HOME/pistachio/shared-theme`, and Kitty and Neovim have their own managed integration. Those apps are in sibling repos under `~/Desktop/pistachio/`.

Check `pgrep -ax qs` first. Keep one production shell. Use `psc <target> <function>` for IPC and check `qs log -c pistachio --no-color` for a new Configuration Loaded entry after QML edits. In-place saves retain the watcher. An open Settings window can block new IPC across a reload, so close it before a planned live reload test. Native Wayland fixtures use private state and run sequentially. Use the suites named in `CLAUDE.md` and the day's TODO.

## 3. Owner's working preferences

- Stay on `psc-rust` for this batch. Preserve existing tracked, untracked and ignored work. The owner stages, commits and pushes. Give lowercase `new: …` or `fix: …` commit messages as text. Leave the owner's `CLAUDE.md` front matter alone.
- Do not edit `~/.config/hypr/*`. The shell uses its approved runtime Hyprland settings. Install only psc after a Rust helper change. From `rust/`, build with `cargo build --release -p psc`, then from the repo root run `rm -f ~/.local/bin/psc && install -m 755 rust/target/release/psc ~/.local/bin/psc`. Removing the old executable first lets a running helper finish with its old inode. Do not run the whole `install.sh`.
- One helper ecosystem in Rust is the owner's direction. A Python calendar is acceptable only if Rust cannot support it well. Keep Classic and TUI choices as agreed. The owner specifically asked to keep the interactive desktop cat in TUI.
- Talk plainly, recommend one direction, and ask only about real choices. Leave owner hand checks as recorded until the owner confirms them.

## 3b. How the owner and Codex worked together

**Follow this workflow.** The owner expects it through each change.

1. Talk through new work in a few points and wait for go. Direct requests and prior approvals cover their agreed scope.
2. Follow approved boards. For small owner-directed changes, extend existing components and Theme tokens. Pistachio marks active state. Keep TUI square and monospaced.
3. Verify before coding. Check Quickshell types against the 0.3.2 docs, the installed CLI's `--help` for flags, and the crate APIs for the versions in `Cargo.lock`. Check compositor facts on the running system.
4. Build in small steps. Reproduce bugs and get a failing check before the fix. For helper ports, first point existing tests at the release-build psc with a `PSC` override, run old and new side by side with the same fake inputs, and compare protocol events, provider calls and files. Record intentional differences. Move pure unit cases into Rust.
5. Run the relevant suites and test the real entry point. Check shell reload and logs. For helper changes, compare `/proc/<pid>/exe` to the release binary and verify restart after ending the helper. Clean up temporary fixtures and restore any preferences changed for checks. Run `tests/settings.sh` clear of live reloads because its guard checks owner config mtimes.
6. Write README changes, the short decision in `CLAUDE.md`, details in `docs/decisions.md` and `docs/gotchas.md`, and the dated TODO in the same session. Review the whole diff before reporting. Check process lifetimes and error paths, fix real regressions with failing checks first, and record deferred minors.
7. Give a plain report with the actual commands and results, including failures and unverified checks. Finish with commit messages in chat.

For Chat and Lens tests use fake `claude`/`codex`, private HOME and XDG paths. Rewrite the copied QML psc command to a fixture command or repo build and assert the substitution matched. Never send real requests, use the owner's chat archives or calendars as fixtures, toggle Ethernet, disconnect Bluetooth, or change audio routing during tests.

## 4. Current task and delivered work

The owner assigned the first-run wizard backend to Claude. The QML frontend and fixture are ready in `src/setup/` and `tests/first-run.test.py`. Use `docs/first-run-frontend.md` for integration. The notes below also describe the recent changes in the working tree.

**Quick chat and Lens.** `rust/psc/src/chat.rs` and `lens.rs` replace `src/services/chat.py` and `lens.py`. `Chat.qml` and `Lens.qml` launch the installed binary. Bare `psc chat` starts the helper. Commands such as `psc chat toggle` still route to shell IPC. The JSON-lines protocol, archives, provider flags, streaming, cancellation and 180-second deadlines follow the old behaviour. Lens keeps structured read-only responses, up to three images, one text file with explicit Apply, Ask both, and coding presets with consent. Defined differences and the subprocess cleanup fixes are in the round 3 decisions and gotchas. The earlier GNOME Clocks Stop/Snooze investigation in the old handoff was finished before this round.

**TUI changes.**

- `Compositor.qml` applies a named runtime rule for square window corners only when TUI and the Hyprland integration switch are both on. The switch is available in Settings → Experimental and Launcher → System → Experimental and defaults off. Switching either condition off restores the usual window rounding.
- Hyprland's own group bar uses zero for both `gradient_rounding` and `rounding` whenever TUI is active. Classic restores 11 px. This uses the existing tab styling path for startup, style/scheme changes and Hyprland config reload. The window-corner opt-in is independent.
- `SettingsWindow.qml` removes Minimise, paints a solid surface across the TUI title strip, and shows the existing section icons beside TUI sidebar labels. The square controls and JetBrains Mono remain.
- `Wallpaper.qml` keeps the wallpaper and interactive cat in TUI. Desktop icons, background shortcuts, the desktop context menu and file actions are Classic-only. The TUI wallpaper's input region is limited to the cat when visible. The Classic icon preference is preserved.
- `Theme.qml` sets the TUI top strip and its reservation to 35 px, with 34 px controls and a 1 px rule. Workspace buttons stay 40 px wide. Bar-relative popup placement follows the height token.
- The owner added one follow-up after the handoff. The desktop cat stays nameless. Settings → Experimental offers Cream (the original), Ginger and Midnight, saved through Store and `psc prefs`. Three pets trigger a purr and a tail swish, and an idle beat shows him sitting on a pixel laptop. See the day's TODO for test results and the owner's screenshot review.
- The cat now uses the laptop beside focused floating editors, carries a clock for running timers, stopwatch and Focus/Pomodoro, and wears headphones during MPRIS playback. The clock takes the laptop's place and either pose can have headphones. The wallpaper keeps the existing visibility rules.

## 5. Other open threads

- (Done by Claude on 20 November 2026: `psc events` replaced `events.py`, see the "Calendar events in Rust" decision.) Calendar verdict delivered. `src/services/events.py` remained Python then. Installed EDS 3.62.1 and libical 4.0.8 support a small runtime-loaded libecal/libedataserver/libical-glib interface in Rust. This keeps EDS optional and lets it own recurrence expansion and timezones. Raw D-Bus would couple the helper to versioned backend interfaces and require more iCalendar handling. Wait for a new go before writing it. Start with an isolated EDS fixture covering recurrence, all-day events, timezones and offline calendars.
- (Done by Claude on 19 November 2026, evening: frontend finished as a normal window, backend, `psc setup`; see the "First-run setup, finished" decision.) First-run wizard frontend is implemented at the owner's request in `src/setup/`, matching `pistachio-shell-design/FirstRun/`. The owner assigned the backend to Claude. Read `docs/first-run-frontend.md` for the mount point, inputs, setting keys and signal contract. Wire first-run detection, `psc setup`, check state, real preference actions and the completion destination. The fixture works without a controller and provides both offscreen and native previews.
- Packaging or a rebuild needs discussion before merging `experimental` into `main`. Headphone toast restyle, GNOME search providers, scheduled tasks, and further app theming integrations are on hold.
- The TODO still lists hand checks for Settings export/import, launcher jobs and previews, alarms, real Quick chat/Lens use and the TUI changes. The request to hand off authorizes the switch of agents. It did not report the results of those checks.

## 6. State right now

- Branch `psc-rust`, HEAD `d8673af`. The tree contains substantial unstaged work from all psc rounds and the TUI changes. `rust/psc/`, `legacy/` and `design/FirstRun/` are among the untracked paths. Preserve the existing `bin/psc` deletion and the rest of the owner's work. No staging or commits were made during Codex's turn.
- Round 3 passed `cargo test --workspace --offline` in `rust/`, `python3 -B tests/chat.test.py`, `sh tests/lens.sh`, `sh tests/lens-native.sh`, `sh tests/settings.sh` and `sh tests/layout.sh`. Side-by-side parity matched Chat's 31 events, 10 provider calls and six saved files, and Lens's 28 events, 10 calls and three saved files after normalizing fixture paths and timings. The two ports also matched the old deadline behaviour. The live shell ran the new helper binaries and restarted each after termination. Only psc was installed.
- The TUI changes passed the relevant Settings, layout, JS, launcher, cat and native bar checks as recorded in the TODO. One native bar run failed the LocalSend placement assertion and two reruns passed. Live checks confirmed the 35 px bar and reservation, the cat's input region, window rounding and both group tab radii at zero. An isolated style-switch check recorded both tab radii going 11 → 0 → 11. The visual check of an actual tabbed workspace remains with the owner.
- At handoff, the sole production shell was PID `235336`. Its current log showed Configuration Loaded with no ERROR/FATAL entries, and the installed psc matched the repo release build. Historical Wayland focus and occasional D-Bus/image warnings are known. Recheck the running state before assuming it stays the same.
