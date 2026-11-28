# AGENTS.md: Pistachio Noir Shell

The guide for every coding agent on this repo: Codex, Claude Code (`CLAUDE.md` imports this file) and any other. Everything here applies to you. Written 21 November 2026, replacing the old one-off handoffs (`AGENTS.md` for Codex, `CLAUDE-HANDOFF.md`), whose rounds are finished.

A Quickshell 0.3.2 (QML) desktop shell for Hyprland on a single-monitor desktop PC (Gentoo with OpenRC and elogind since 21 November 2026; Arch before, still supported), in the Pistachio Noir colour scheme. `src/` is linked to `~/.config/quickshell/pistachio`. All build phases are done: work is features and fixes on branch **`experimental`**; **`main`** is the stable one.

## Read first

- `README.md`: the public front page (pistachio-fm's style, a little playful). **`docs/README.LLM.md`**: the full feature reference, every feature, key and setting (the old README, written for agents). Keep the reference in step with each change; touch the front page only when a headline changes.
- The pages in `docs/`: `requirements.md`, `install.md`, `ipc-and-keybinds.md` (psc, IPC, keybinds), `frosted-panels.md`, `lock-screen.md`, `login-screen.md`, `theming.md`, `troubleshooting.md`, `repository-layout.md`. Keep them in step with commands and requirements.
- `docs/decisions.md`: **every decision in full** (dates, reasons, details). The list below is the short form.
- `docs/gotchas.md`: **every gotcha in full**, with what was checked. Search it before debugging anything odd.
- `docs/plan.md` (architecture, components), `docs/audio-bluetooth.md` (PipeWire, BlueZ, brightness, OSD), `docs/first-run-frontend.md` (the first-run setup's contract), `docs/superpowers/` (the specs and plans behind larger changes).
- `todos/TODO_DD-MM-YY.md` (local only: ignored by git, not in the repo since 21 November 2026): the day's work, the owner's hand checks and deferred minors. Start from the newest.
- `tests/README.md`: what each test covers.
- **`agent-skills/`**: skills for agents (the Agent Skills format, a `SKILL.md` per folder). **Before building or changing anything the user sees, read `agent-skills/pistachio-shell-ui/SKILL.md`**: the look, Classic and TUI, the QML patterns, recipes for settings and launcher rows, and how to check it.
- **Design boards**, the visual source of truth: the separate repo `pistachio-shell-design`, checked out at `~/Desktop/pistachio/pistachio-shell-design/` (moved out of this repo on 21 November 2026). One HTML board per screen, `index.html` links them; `pistachio-shell-design/<board>` in comments and docs means a file there. Sibling apps (Pistachio FM, Text) live beside it under `~/Desktop/pistachio/`, each with its own instructions.

## The repo

```
src/            the shell: shell.qml, Theme.qml (every colour, size and motion), bar/ panels/ popups/ launcher/
                settings/ setup/ (first-run) lock/ components/ services/ (the only code touching system data)
rust/           Cargo workspace: psc (the CLI and the shell's on-demand helpers, rust/psc/) and the all-day helpers
                pistachio-auth (polkit agent), pistachio-devices (pairing agent, USB drives), pistachio-localsend
integrations/   what the shell sets up elsewhere: kitty/, neovim/, vscode/ (theme extension), sddm/, hypridle.conf
tests/          isolated suites with stand-ins (tests/run.sh runs every safe one) and a few live-system suites
tools/          dev-only generators (emoji list, notification sound, OLED Noir and other app themes)
agent-skills/   skills for coding agents: pistachio-shell-ui (designing and building the shell's UI)
legacy/psc      the old shell-script psc, install.sh's fallback
docs/           guides, README.LLM.md, decisions, gotchas, plan, images/, todos/, superpowers/
install.sh      links src/ into place, builds rust/, installs psc and the helpers into ~/.local/bin
```

## Running and testing it

- **One shell only.** Check `pgrep -ax qs` first; never start a second one. Talk to it with `psc <target> <function>` (or `qs -c pistachio ipc call …`; `psc ipc` lists them all).
- **Quickshell reloads on save.** After each QML edit, read `qs log -c pistachio --no-color` and confirm the "Configuration Loaded" count went up, with no new `ERROR`. Live reload only notices real in-place writes (not `touch`, `sed -i` or the same content); a replaced file can lose its watch: write in place, and if a reload is missed, write another QML file. A `.js`-only edit may not reload: touch an importing QML file too. Close Settings before editing QML you test through IPC (an open FloatingWindow blocks IPC across a reload).
- **After a Rust change:** from `rust/`, `cargo build --release -p psc`, then from the repo root `rm -f ~/.local/bin/psc && install -m 755 rust/target/release/psc ~/.local/bin/psc` (rm first: a running helper keeps its old file), then `psc restart` when the shell's helpers must pick it up. Install only what you changed; don't run the whole `install.sh`.
- **Tests:** `sh tests/run.sh` runs every suite that's safe on a running desktop (`--native` adds the ones that open windows); `cd rust && cargo test --workspace`. Single suites: `sh tests/js.sh`, `sh tests/settings.sh` (run it clear of live reloads: its guard checks the owner's config mtimes), `sh tests/layout.sh`, `sh tests/bar.sh`, `python3 -B tests/<name>.test.py`, `dbus-run-session -- python3 -B tests/clocks-action.test.py` (never on the real bus). Tests using `gi` need PyGObject (`dev-python/pygobject` on Gentoo, not installed on the owner's machine). **Live-system suites** (`tests/services.sh`, `compositor.sh`, `notifications.sh`) change real devices: never run them casually.
- **Fixtures:** a QML fixture that copies a real service which runs `$HOME/.local/bin/psc …` must swap that command for a stand-in or the repo build and assert the swap matched (see `tests/app-theming.test.py`), or it reaches the owner's real configs.

## How to work with the owner

**Work exactly this way.** The owner requires it of every agent on this repo; where it conflicts with your own defaults, this wins.

1. **Idea → talk first.** Propose new work in a few short points, recommend one direction, ask only the owner's genuine calls, and wait for "go". A direct request or an earlier "go" covers its agreed scope.
2. **Boards are the truth.** Match them; without a board, reuse existing components and Theme tokens, and say so. Board sample content is fake: wire real data.
3. **Verify before coding:** Quickshell types against https://quickshell.org/docs/v0.3.2/ (never another version), CLI flags against the installed `--help`, crate APIs for the versions in `Cargo.lock`, machine facts with live read-only checks. Never from memory.
4. **Build small, test first.** Reproduce a bug and get a failing check before the fix; write its cause into `docs/gotchas.md`.
5. **Test for real, then clean up:** the relevant suites, the real entry point, the shell's reload and log. Remove temporary fixtures and restore any preference you changed for a check.
6. **Write it down the same session:** the feature reference (`docs/README.LLM.md`), the short decision below, the full text in `docs/decisions.md` and `docs/gotchas.md`, and today's TODO (`todos/TODO_DD-MM-YY.md`, local, ignored by git) with the owner's hand checks as unticked boxes. **Never tick a hand check the owner didn't do.**
7. **Review before you report:** read your whole diff in a separate pass (behaviour a user would notice, process lifetimes, error paths). Fix real problems with a failing check first; list minor ones as deferred in the TODO.
8. **Report honestly:** what changed, what was tested and how (the commands), what failed, what wasn't checked. Then the commit message as text.

## Owner's preferences

- **Git:** the owner stages, commits and pushes. A "commit message" is text in chat: lowercase `new: …` / `fix: …`, in the style of `git log`. Never stage or commit unless asked. Preserve every uncommitted change you didn't make. Leave `CLAUDE.md`'s front matter alone.
- **Never edit `~/.config/hypr/*`** or tune the shell to it, unless the owner asks for that change. Runtime `hl.config` changes the shell makes (group tabs, borders, Zen gaps, game mode, Settings window, TUI corners) are fine.
- **One ecosystem:** every helper in Rust (owner, 19 November 2026); no Python at runtime (20 November); tests and `tools/` stay Python, dev-only.
- Talk plainly and briefly; write dates out.

## Decisions (already made, do not reopen; full text in docs/decisions.md)

**Platform**
- Quickshell 0.3.2 + QML; a from-scratch C++/Rust shell is a separate later project. Packaging (a binary or AppImage) is shelved (owner, 21 Nov: "lets ditch the packaging for now"); merging `experimental` into `main` doesn't wait for it any more. The shell installs from the repo with `install.sh`.
- Hyprland only, through the thin `Compositor` singleton (UI never imports a compositor module). Single monitor, desktop PC: no battery/UPower, wired Ethernet, no Wi-Fi.
- Rust helpers run all day (`pistachio-auth`, `pistachio-devices bluetooth|drives`, `pistachio-localsend`), exit when stdin closes or the shell dies. On-demand helpers are hidden `psc` commands, run by the shell as `$HOME/.local/bin/psc`: `prefs`, `theme`, `system`, `boot-entries`, `power`, `swatch`, `capture`, `mic-check`, `phone-timer`, `files`, `library`, `clocks`, `launcher-tools`, `chat`, `lens`, `events`. So Settings' health, export/import, theming, Quick chat, Lens and more need the Rust psc installed.
- `psc` (owner's call, 19 Nov; spec `docs/superpowers/specs/2026-11-19-psc-rust-design.md`): start/stop/call the shell, `status`, `log --errors`, `ipc`, `doctor` (mirrors `docs/requirements.md`: keep them in step; `--packages`, `--install` gives install.sh the pacman or emerge lines), `completions`, `setup`. Its tests use a stand-in `qs` (`QS=`).
- OpenRC/Gentoo (21 Nov): no systemd tools. Power menu = `psc power …` (logind over D-Bus, systemd-logind or elogind); Restart into… = `pkexec psc boot-entries set-oneshot ID` (writes `LoaderEntryOneShot`); doctor and install.sh give Gentoo atoms + USE flags from os-release; `/proc` children fall back to `/proc/*/stat`.
- Repo layout (20–21 Nov): `integrations/` and `tools/`; README is the public front page, `docs/README.LLM.md` the full reference; the design boards in their own repo; licence GPL-3.0-only like FM and Text.

**Bar and panels**
- Classic bar: floating centred pill at the bottom, 640×56, radius 28, 16 px up; auto-hides when a window overlaps (exclusive zone 0, bottom-edge reveal). Tray pill right of it, media pill left, minimised-windows pill right of tray; the bar stays centred.
- Bar content: workspaces + title, clock/date/notification dot, status chip (Ethernet, Bluetooth, volume). Clock right-click: timers, stopwatch, alarms (GNOME Clocks' alarms, rung by the shell).
- Quick settings, notification popups/centre + calendar (EDS events through `psc events`, weeks from Monday), OSD, power menu (+ Restart into… Limine entries), lock screen, polkit dialog, wallpaper switcher (the shell draws the wallpaper; images in `~/Pictures/Wallpapers`), Alt+Tab switcher, Overview (boards `pistachio-shell-design/Overview*.html`; Ctrl+1…0 / Ctrl+Shift by scan code; bar hides while open).
- Launcher replaces Vicinae: Apps, Windows, Workspaces, System, Bluetooth, plus `$`, `/`, `;` clipboard, `!`, `@`, `ask`, `kill`, `timer`/`alarm`/`stopwatch`, calc.js then qalc, tldr, projects (CLion/VS Code with Git branch and dirty dot), pins/aliases/presets, jobs. Arrows and Ctrl+H J K L; plain letters type.
- Settings window (1040×760, min 900×620; boards `pistachio-shell-design/settings/`): Personal / Connections / Shell pages, global search, page resets, export/import to `~/.config/pistachio/pistachio-shell/settings.toml` (one file, review before Apply; secrets and history left out).
- First-run setup (boards `pistachio-shell-design/FirstRun/`, `src/setup/`, service `FirstRun`; 19 Nov): a normal window (880 × 600), opens itself only on the very first start, `psc setup` reopens it; always Classic. Contract: `docs/first-run-frontend.md`.
- Settings → Experimental holds Game mode, Ambient clock and Dev features (21 Nov: opt-in only, off; launcher Dev tests / with windows / Shell errors / Rebuild psc as Background jobs via `services/DevTools.qml`, runner `tests/run.sh`; which parts move into their own categories is still to be talked about). Moved out on 21 Nov: Style + Hyprland integration, Cat coat (only while the cat is on) and Desktop widgets to Appearance, Phone preview to Focus (no reset there); in settings.toml too (`MOVED` in prefs.rs still reads old `[experimental]` keys). Colours, Theming integration, Monochrome wallpaper and Desktop cat are in Appearance; Clipboard history in Apps & places; Restart buttons in Shell health.

**Features**
- Frosted panels (Subtle 88 %/Glassy 72 %, off by default), Hyprland blur via layer rule on `pistachio-bar`/`pistachio-panel`; panel backgrounds use `Theme.surface`.
- Lens (`services/Lens.qml` + `psc lens`): snip → Claude Code or Codex CLI, read-only, schema answers, up to 3 images, one text file with diff/Apply, Ask both, coding presets only with consent; chats in `~/lens-chats/`.
- Quick chat (`services/Chat.qml` + `psc chat`, boards `pistachio-shell-design/QuickChat*.html`): 560 px panel above the bar, streaming Claude, Codex, Ask both; chats in `~/quick-chats/`.
- Screenshots: toolbar pill (board `NewScreenshotMenu.html`), Save/Copy/Both; recording setup (audio, countdown), pause via SIGUSR2, Trim to a new file; area helper frame outside the crop.
- Zen and Focus/Pomodoro (`services/FocusMode.qml`, no IPC): Zen hides the bar, desktop icons and toasts, gaps/border 0 at runtime. Phone timer preview (Focus page, off): LAN page with QR and Pause/Skip/End. Zen's Pomodoro pill has Hide → the bar's handle.
- Desktop widgets (Appearance, off): Clock/Weather/CPU-RAM (+ Now playing, Timers, Disk & GPU) on 52 px half-cells of the icons' grid, arranged in `popups/WidgetStudio.qml` (IPC `widgets`). Ambient clock (Experimental, off): `services/Ambient.qml` + `popups/AmbientClock.qml`; IPC `ambient preview` is temporary until the owner says. Visual settings carry a "Performance impact" note.
- Classic / TUI style (TUI boards `pistachio-shell-design/TUI/`): TUI bar 35 px high and full-width at the top, JetBrains Mono Nerd Font, radii 0; TUI Settings shows sidebar icons; Hyprland tab groups are square in TUI. TUI keeps the wallpaper and the optional desktop cat; desktop icons and file interactions are Classic-only.
- Noir colour scheme (board `pistachio-shell-design/noir-tones.html`): greys, light-grey active, one red for errors; Hyprland borders and group tabs follow at runtime. Monochrome wallpaper option in Noir.
- OLED black (Experimental, off; 22 Nov; preview `pistachio-shell-design/oled-tones.html`): Noir only (owner: it doesn't suit Pistachio Noir); `Theme.oled` bound to `ShellSettings.oledLive` (switch && Noir), `Theme.tone(pistachio, noir, oledNoir)`; true black bg, darker everything; outlines stay, shadows go, frosted held off (`ShellSettings.frostedLive`). Apps follow (22 Nov): `psc theme oled` writes `noir` to shared-theme (FM/Text read exactly that) plus a `pistachio/shared-oled` marker; Kitty, Neovim, VS Code have OLED Noir, Text and FM read the marker (their `SharedTheme.oled`) (Kitty/VS Code files made by `tools/make-oled-themes.py`).
- Theming integration (on by default; `AppTheming` + `psc theme`): Kitty, Neovim and VS Code follow Colours (VS Code: `integrations/vscode/` installed as a `.vsix` via `code --install-extension`, one marked `workbench.colorTheme` line in settings.json); since 28 Nov also GTK 3/4 (GTK 3 via adw-gtk3), Vesktop (QuickCSS block, written in place), btop, yazi and zathura (`theme/extra.rs`; their files from `src/Theme.qml` by `tools/make-app-themes.py`, `--check` in run.sh). An app's own theme is asked about first; switching off removes only the shell's own lines. Text, FM and Notes always follow the shared colour file.
- Game mode (Experimental, off): a fullscreen game → quiet toasts, animations and blur off at runtime, OSD on start/end.
- Desktop cat (Appearance, off) on desktops without tiled windows: coats Cream, Ginger and Midnight; pets, a laptop pose, a clock for running timers, headphones during playback; an About easter egg after ten presses.
- Alarms need GNOME Clocks (28 Nov): without it `psc clocks list` is `[]`, the shell doesn't call it, `alarm` says so; doctor lists it as optional.
- Minimising windows to `special:minimized`. LocalSend in quick settings while the LocalSend app is installed (port 53317 shared, the app must not run). Bluetooth devices paired from the shell are connected right after pairing. Integrations switches per other app (`ShellSettings.integration(id)`). Restart / Force restart in Shell health.

## Style rules

- Colours come only from `Theme.qml`. No hard-coded hex values elsewhere.
- Palette: bg #15170F, bgAlt #1D2016, overlay #2A2F1F, overlay2 #39412A, muted #626F51, subtext #A3B08F, text #E5E9D8, textBright #F6F8EF, pistachio #9FD88A (active state only), terracotta #DB8267, gold #E0B15E, sageBlue #7DA3B3, teal #7FC9A8, lavender #AC8ED0, clay #D9975A.
- `muted` is only ~3.4:1 on bg: never for small text; use `subtext`.
- Pistachio marks what is active (current workspace, toggles on, slider fills, cursor, selected-row chip with bg text). No accent borders, no large pistachio fills.
- Fonts: Manrope (500–800) for UI, JetBrains Mono for code-like text; tabular figures for numbers.
- Radius 28 for panels, 20 for chips/tiles, round icon buttons (0 in TUI).
- Panels and popups have the boards' drop shadows (`components/Shadow.qml`, switchable); bar and tray pill stay flat. A shadowed window needs room around the panel, masked so clicks pass through.
- Motion: one ease-out curve, 120 ms hover, ~200 ms fades/slides (TUI ~80 ms). Windows open/close through `components/Reveal.qml`: set `open`, never `visible`.

## Working rules

1. Services and the `Compositor` adapter are the only places that touch system data; UI files read from them. Services: `Ambient`, `Apps`, `AppTheming`, `Audio`, `Bluetooth`, `Clipboard`, `Network`, `Brightness`, `Media`, `NightLight`, `Notifs`, `Polkit`, `Session`, `ShellSettings`, `SettingsHub`, `Preferences`, `SettingsReset`, `SystemHealth`, `MicCheck`, `Showoff`, `Store`, `ScreenShare`, `Files`, `About`, `Cider`, `Clocks`, `Desktop`, `DesktopWidgets`, `DevTools`, `Drives`, `Events`, `FirstRun`, `FocusMode`, `GameMode`, `Lens`, `Library`, `LauncherTools`, `LocalSend`, `Processes`, `Screenshots`, `Tldr`, `SystemStats`, `Tray`, `Uptime`, `Wallpapers`, `Weather`. A service that must run from startup goes in `shell.qml`'s `background` list.
2. One notification daemon at a time; a KDE `plasmashell` on another TTY may own the bus name: ask before stopping it.
3. Lock screen: keep a TTY handy; if the shell dies while locked, `hyprctl --instance 0 eval 'hl.clear_crashed_lockscreen()'`. Three wrong passwords lock the account for 10 minutes (pam_faillock): at most one wrong try in a row.
4. Night light is `hyprsunset` (run by the shell); brightness is `ddcutil` (no backlight device).
5. **Safety:** never toggle Ethernet, disconnect in-use Bluetooth, change audio routing to test unrelated code, or use the owner's real alarms, notes, chats, calendars or files as fixtures. No real Claude/Codex requests in tests: fake `claude`/`codex` and a temporary `HOME`. Back up anything of the owner's before changing it.

## Gotchas that bite most often (full list in docs/gotchas.md)

- QML: don't name a property after an `Item` property (`left`, `top`: "Cannot override FINAL property"); an `id` hides a same-named property in its file (qualify with `root.`); don't name a singleton after a QtQuick type (hence `Store`); an inline `component` can fail as "not a type": move it to a file; a new sibling file may need an explicit `import qs.panels`/`qs.popups` on live reload.
- Quickshell's JS lacks `Object.fromEntries`, `Array.flatMap`, `Array.at` and object spread. It is slow at bulk work: big searches go to a helper process.
- A `var` holding a QObject turns null when destroyed, without a change signal: read null-safely. JsonAdapter lists are QVariant sequences: `Array.from` them.
- `Store` writes 300 ms after a change (with `blockWrites: true` against an async-write race); a reload in between loses it.
- A plain JS list as a Repeater model remakes every delegate on change: use `ScriptModel` with keys. Don't change a service's state inside a binding that reads it (`Qt.callLater`).
- Every `image://icon` Image must be `asynchronous: true` (sync + async on the same icon aborts the shell).
- `LazyLoader.component` changed while active keeps the old item; `Loader` is a focus scope (`focus: true`).
- Layers: a layer holding the keyboard exclusively must keep it until the focus dispatch lands; select on pointer movement, not hover-enter; `WlrLayer.Top` is below fullscreen windows (use Overlay); a launcher-like layer that grabs the keyboard closes on a click beside it itself (FocusGrab doesn't clear).
- IPC: don't name an IpcHandler function `show`; "Not ready to accept queries yet" means an old generation is alive (close Settings / restart). `qs ipc call` unwraps a bare JSON array argument: wrap lists in an object.
- The launcher draws rows by kind through its `sourceComponent` table: a new row kind needs an entry (Classic too).
- Settings is a FloatingWindow (normal toplevel): `Compositor.placeSettingsWindow` floats it once; `float({action="set"})` toggles an already-floating window. Rows that come and go (Cat coat, Desktop icons) rebuild the page: tests must find items again after such a switch.
- Hyprland: special workspaces have no id (minimised windows are id -1); runtime `hl.config` is undone by a config reload: reapply on `configreloaded`; run Lua dispatchers with `hyprctl dispatch`, not `eval`; `getoption` prints `bool` for on/off options.
- A process that ignores SIGPIPE (`pactl subscribe`) outlives the shell: start it via `setpriv --pdeathsig TERM`. `pkill -f <pattern>` kills your own shell command: use `pkill -x` or a pid.
- A shell restarted from a terminal has the terminal's environment: without `HYPRLAND_INSTANCE_SIGNATURE` it knows no windows, and its PATH hides PATH problems. The session's PATH lacks `~/.local/bin` (it's only in `~/.zshrc`): psc appends it for itself and what it starts; don't rely on it elsewhere.
- No systemd on the owner's machine: never call `systemctl`, `bootctl` or `journalctl` from the shell. gio's first D-Bus connection sets SIGPIPE to ignored: restore SIG_DFL in psc after it.
- Kitty refuses a file included twice and reports it as a bad line; it takes no comment after an `include` on the same line. VS Code lists only extensions in its `extensions.json` (install a `.vsix`), rewrites the installed `package.json`, and its settings.json is JSONC (block-comment markers only). GNOME Clocks 51 alarms use `ring_time` and need every raw field kept; Stop/Snooze go to its `stop-alarm`/`snooze-alarm` actions. LocalSend uploads may be chunked.
- Test with the app's own reader where it matters (Kitty's loader, Neovim headless, the real VS Code CLI in a throwaway HOME, real QML through QtTest): checking a file's text alone missed the Kitty bug.
