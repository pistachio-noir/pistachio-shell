---
title: Untitled
author: sx
date: 2026-11-17T08:59:29Z
---

# Pistachio Noir Shell

@CLAUDE-HANDOFF.md

A Quickshell 0.3.2 (QML) desktop shell for Hyprland on a single-monitor desktop (Gentoo with OpenRC and elogind since 21 Nov; Arch before, still supported), in the Pistachio Noir colour scheme. The config lives in `src/`, linked to `~/.config/quickshell/pistachio`. All build phases are done; work now is features and fixes on branch `experimental`.

Read these first:

- `README.md` (what you get) and the pages it links in `docs/`: `requirements.md`, `install.md`, `ipc-and-keybinds.md` (psc, IPC, keybinds), `frosted-panels.md`, `lock-screen.md`, `login-screen.md`, `theming.md`, `troubleshooting.md`, `repository-layout.md`; for the owner. Keep them in step with commands and requirements. `tests/README.md` says what each test covers; `integrations/` holds the Kitty, Neovim, SDDM and hypridle files, `tools/` the generators.
- `docs/plan.md`: architecture, folder layout, theme tokens, components, risks.
- `docs/decisions.md`: **every decision in full** (dates, reasons, details). The list below is the short form.
- `docs/gotchas.md`: **every gotcha in full**, with what was checked, plus what each test covers. Search it before debugging anything odd.
- `docs/audio-bluetooth.md`: PipeWire, BlueZ, brightness and OSD design.
- `design/*.html`: one board per screen (`design/index.html`), the visual source of truth.

CLAUDE.md was squashed on 19 November 2026 (owner's request: too big). Add a new decision or gotcha in full to its docs file, and here only as one or two lines.

## Decisions (already made, do not reopen; full text in docs/decisions.md)

**Platform**
- Quickshell 0.3.2 + QML; a from-scratch C++/Rust shell is a separate later project. Before merging `experimental` into `main`, talk packaging (binary/AppImage) or a rebuild (owner, 19 Nov).
- Hyprland only, through the thin `Compositor` singleton (UI never imports a compositor module). Single monitor, desktop PC: no battery/UPower, wired Ethernet, no Wi-Fi.
- Never edit `~/.config/hypr/*` or tune the shell to it, unless the owner explicitly asks for that change. Exceptions so far, each owner-asked: frost blur rule and `pistachio-motion` rule in `rules.lua`, `animations.lua`, bind descriptions (backups beside them). Runtime `hl.config` changes (group tabs, borders, Zen gaps, game mode, Settings window) are fine; config files stay untouched.
- Rust helpers run all day (`rust/`: `pistachio-auth`, `pistachio-devices bluetooth|drives`, `pistachio-localsend`), built by `install.sh` into `~/.local/bin`, exit when stdin closes or the shell dies. On-demand helpers are moving into `psc` too (owner, 19 November 2026: one ecosystem, every helper in Rust): done `prefs`, `theme`, `system`, `boot-entries`, `swatch`, `capture`, `mic-check`, `phone-timer`, `files`, `library`, `clocks`, `launcher-tools` (GLib through the `gio` crate), `chat`, `lens`, `events` (20 Nov; EDS loaded at run time). No Python at runtime (owner, 20 Nov); tests and `tools/` generators stay Python, dev-only. After editing `rust/`: build, copy, `psc restart`.

**Bar and panels**
- Classic bar: floating centred pill at the bottom, 640×56, radius 28, 16 px up; auto-hides when a window overlaps (exclusive zone 0, bottom-edge reveal). Tray pill right of it, media pill left, minimised-windows pill right of tray; the bar stays centred.
- Bar content: workspaces + title, clock/date/notification dot, status chip (Ethernet, Bluetooth, volume). Clock right-click: timers, stopwatch, alarms (GNOME Clocks' alarms, rung by the shell).
- Quick settings, notification popups/centre + calendar (EDS events, weeks from Monday), OSD, power menu (+ Restart into… Limine entries via `pkexec bootctl set-oneshot`), lock screen, polkit dialog, wallpaper switcher (the shell draws the wallpaper; images in `~/Pictures/Wallpapers`), Alt+Tab switcher, Overview (boards `design/Overview*.html`; Ctrl+1…0 / Ctrl+Shift by scan code; bar hides while open).
- Launcher replaces Vicinae: Apps, Windows, Workspaces, System, Bluetooth, plus `$`, `/`, `;` clipboard, `ask`, `kill`, `timer`/`alarm`/`stopwatch`, calc.js then qalc, tldr, projects (CLion/VS Code with Git branch and dirty dot), pins/aliases/presets, jobs. Arrows and Ctrl+H J K L; plain letters type.
- Settings window (1040×760, min 900×620; boards `design/settings/`): Personal / Connections / Shell pages, global search, page resets, export/import to `~/.config/pistachio/pistachio-shell/settings.toml` (one file, review before Apply; secrets and history left out).
- First-run setup (boards `design/FirstRun/`, `src/setup/`, service `FirstRun`; owner, 19 Nov): a normal window like Settings (880 × 600), opens itself only on the very first start (`Store.fresh`; existing state is marked `setupDone` quietly), `psc setup` reopens it. Check = `psc doctor --json` + bus owner, package names only. Pages use Settings' setters; Restore my settings reviews the export; All set shows psc keybind examples and a psc guide. Always Classic (own controls in `src/setup/`, `Classic.qml`); Settings → About → Run setup reopens it. Pieces and contract: `docs/first-run-frontend.md`.
- Settings → Experimental holds Style (Classic/TUI), opt-in Hyprland integration for square TUI window corners, Game mode and Phone preview (owner, 19 Nov). The integration is also in Launcher → System → Experimental. Colours, Theming integration, Monochrome wallpaper and Desktop cat are in Appearance; Clipboard history in Apps & places; Restart buttons in Shell health.

**Features (details in docs/decisions.md)**
- Frosted panels (Subtle 88 %/Glassy 72 %, off by default), Hyprland blur via layer rule on `pistachio-bar`/`pistachio-panel`; panel backgrounds use `Theme.surface`.
- Lens (`services/Lens.qml`, `lens.py`): snip → Claude Code or Codex CLI, read-only, schema answers, up to 3 images, one text file with diff/Apply, Ask both, coding presets only with consent; chats in `~/lens-chats/`.
- Quick chat (`services/Chat.qml`, `chat.py`, boards `design/QuickChat*.html`): 560 px panel above the bar, streaming Claude, Codex, Ask both; chats in `~/quick-chats/`.
- Screenshots: toolbar pill (board `NewScreenshotMenu.html`), Save/Copy/Both; recording setup (audio, countdown), pause via SIGUSR2, Trim to a new file; area helper frame outside the crop.
- Zen and Focus/Pomodoro (`services/FocusMode.qml`, no IPC): Zen hides the bar, desktop icons and toasts, gaps/border 0 at runtime. Phone timer preview (Experimental, off): LAN page with QR, styled, with Pause/Skip/End (20 Nov, no key: owner's call). Zen's Pomodoro pill has Hide → the bar's handle (per session).
- Desktop widgets (Experimental, off; 20 Nov): Clock/Weather/CPU-RAM (+ Now playing, Timers, Disk & GPU from the studio) on 52 px half-cells of the icons' grid (TUI: under the strip), centre cross in the studio (`services/DesktopWidgets.qml`, `panels/desktopGrid.js`, `DesktopWidgetLayer`), the cat's visibility rule, icons flow around them; arranged in `popups/WidgetStudio.qml` (Overlay, snap, ✕/+, Esc; IPC `widgets`). Layout local, switch exported. Ambient clock (feature 18) next. Ambient clock (Experimental, off; 20 Nov): `services/Ambient.qml` (IdleMonitor, 2/3/5 min, workspace with no windows) + `popups/AmbientClock.qml` (Overlay, no input, dims 94 %, clock/date/media/timer, drifts); IPC `ambient preview` is TEMP until the owner says. Visual settings carry a "Performance impact" note (`impact()` in SettingsContent, drawn by SettingsRow).
- TUI keeps the wallpaper and the optional desktop cat. Desktop icons, the context menu and desktop file interactions are Classic-only.
- Minimising windows to `special:minimized` (`window minimize|restore|restoreAll`).
- LocalSend device in quick settings, only while the LocalSend app is installed (port 53317 shared, app must not run).
- Classic / TUI style (TUI boards `design/TUI/`): TUI bar 35 px high and full-width at the top, hides in Zen/fullscreen/Overview with a 2 px reveal (not in Zen); JetBrains Mono Nerd Font; radii 0.
- TUI Settings shows sidebar icons beside the page names. Hyprland tabbed groups use square tabs in TUI and rounded tabs in Classic.
- Noir colour scheme (board `design/noir-tones.html`): greys, light-grey active, one red for errors; Hyprland borders and group tabs follow at runtime. Monochrome wallpaper option in Noir.
- Theming integration (on by default; `AppTheming` + `psc theme`): `pistachio-shared.conf` holds the colours themselves, never an include (Kitty refuses a file included twice). the shell sets Kitty and Neovim up to follow Colours, asks before touching an app's own theme, removes only its own lines when off. Text, FM and Notes always follow. Moved into `psc` on 19 November 2026.
- Game mode (Experimental, off): fullscreen game (Steam `steam_app_*`, Sober, gamescope, extra classes) → quiet toasts, animations and blur off at runtime, OSD on start/end.
- Desktop cat (Appearance, off) on desktops without tiled windows. Experimental offers Cream, Ginger and Midnight. Three quick pets trigger a purr and tail swish, and the idle cycle includes a laptop pose. About easter egg after ten presses.
- The desktop cat holds a clock for running timers, stopwatch and Focus/Pomodoro, uses his laptop for focused floating editors, and wears headphones during media playback.
- OpenRC/Gentoo (owner, 21 Nov): no systemd tools. Power menu = `psc power …` (logind over D-Bus, systemd or elogind); Restart into… = `pkexec psc boot-entries set-oneshot ID` (writes `LoaderEntryOneShot`); `psc doctor`/`--install` and `install.sh` give Gentoo atoms + USE flags from os-release; `/proc` children fall back to `/proc/*/stat`.
- Bluetooth: a device paired from the shell is connected right after pairing (owner's bug report, 20 Nov; pairing alone gave no audio).
- Repo layout (owner, 20 Nov): `integrations/` (kitty, neovim, sddm, hypridle) and `tools/` replace `extras/`; README is the front page, the rest is in `docs/` (see `docs/repository-layout.md`); `tests/README.md` indexes tests; `design/` stays tracked.
- Calendar events are `psc events` (20 Nov): libecal/libedataserver/libical-glib via dlopen, floating times read as local (events.py read them as UTC); `tests/events.test.py` runs a private EDS.
- Integrations switches (Settings → Integrations) per other app, read through `ShellSettings.integration(id)` in each service.
- Restart / Force restart (Shell health, confirmed; `psc restart`, `psc force-restart`).
- `psc` is a Rust binary (`rust/psc`, owner's call 19 November 2026, built on branch `psc-rust`): the script's commands unchanged plus `status`, `log --errors`, `ipc`, `doctor` (mirrors `docs/requirements.md`: keep them in step; `--packages required|optional` lists them, `--install` gives `install.sh` the pacman or emerge lines), `completions`. Its tests use a stand-in `qs` (`QS=` env). Spec `docs/superpowers/specs/2026-11-19-psc-rust-design.md`. Level 2 (19 November 2026, plan `docs/superpowers/plans/2026-11-19-psc-level2.md`): `prefs.py`, `shared-theme.py` and `system-tools.py` are `psc prefs|theme|system …` (hidden from `--help`), called by the shell as `$HOME/.local/bin/psc`, so Settings' health, export/import, theming and network/Bluetooth/eject details need the Rust psc installed. QML fixtures of those services must swap that command for a stand-in (see `tests/app-theming.test.py`), or they reach the owner's real configs.

## Style rules

- Colours come only from `Theme.qml`. No hard-coded hex values elsewhere.
- Palette: bg #15170F, bgAlt #1D2016, overlay #2A2F1F, overlay2 #39412A, muted #626F51, subtext #A3B08F, text #E5E9D8, textBright #F6F8EF, pistachio #9FD88A (active state only), terracotta #DB8267, gold #E0B15E, sageBlue #7DA3B3, teal #7FC9A8, lavender #AC8ED0, clay #D9975A.
- `muted` is only ~3.4:1 on bg: never for small text; use `subtext`.
- Pistachio marks what is active (current workspace, toggles on, slider fills, cursor, selected-row chip with bg text). No accent borders, no large pistachio fills.
- Fonts: Manrope (500–800) for UI, JetBrains Mono for code-like text; tabular figures for numbers.
- Radius 28 for panels, 20 for chips/tiles, round icon buttons (0 in TUI).
- Panels and popups have the boards' drop shadows (`components/Shadow.qml`, switchable); bar and tray pill stay flat. A shadowed window needs room around the panel, masked so clicks pass through.
- Motion: one ease-out curve, 120 ms hover, ~200 ms fades/slides (TUI ~80 ms). Windows open/close through `components/Reveal.qml`: set `open`, never `visible`.

## Working rules for Claude Code

1. Verify any Quickshell type or property against https://quickshell.org/docs/v0.3.2/ before using it; CLI flags against installed `--help`; machine facts with live read-only checks.
2. Talk a feature through first, build the agreed scope, match the boards; without a board, reuse existing components and say so.
3. Quickshell reloads on save. Check `pgrep -ax qs` (never start a second shell). Reach it with `psc <target> <function>` or `qs -c pistachio ipc call …`; read `qs log -c pistachio` and confirm the "Configuration Loaded" count went up after each edit. Live reload only notices real in-place writes (not `touch`/`sed -i`/same content); a replaced file can lose its watch: write in place, and if a reload is missed, write another QML file. A `.js`-only edit may not reload: touch an importing QML file too. Close Settings before editing QML you test through IPC (an open FloatingWindow blocks IPC across a reload).
4. Services and the `Compositor` adapter are the only places that touch system data; UI files read from them. Services: `Ambient`, `Apps`, `AppTheming`, `Audio`, `Bluetooth`, `Clipboard`, `Network`, `Brightness`, `Media`, `NightLight`, `Notifs`, `Polkit`, `Session`, `ShellSettings`, `SettingsHub`, `Preferences`, `SettingsReset`, `SystemHealth`, `MicCheck`, `Showoff`, `Store`, `ScreenShare`, `Files`, `About`, `Cider`, `Clocks`, `Desktop`, `DesktopWidgets`, `Drives`, `Events`, `FirstRun`, `FocusMode`, `GameMode`, `Lens`, `Library`, `LauncherTools`, `LocalSend`, `Processes`, `Screenshots`, `Tldr`, `SystemStats`, `Tray`, `Uptime`, `Wallpapers`, `Weather`. A service that must run from startup goes in `shell.qml`'s `background` list.
5. One notification daemon at a time; a KDE `plasmashell` on tty1 may own the bus name: ask before stopping it.
6. Lock screen: keep a TTY handy; if the shell dies while locked, `hyprctl --instance 0 eval 'hl.clear_crashed_lockscreen()'`. Three wrong passwords lock the account for 10 min (pam_faillock): at most one wrong try in a row.
7. Board sample content is fake: wire real data.
8. Night light is `hyprsunset` (run by the shell); brightness is `ddcutil` (no backlight device).
9. Tests (isolated unless noted; what each covers is in docs/gotchas.md): `sh tests/js.sh`, `sh tests/settings.sh`, `sh tests/layout.sh`, `sh tests/bar.sh`, `python3 -B tests/<name>.test.py` (prefs, game-mode, app-theming, neovim-theme, events, clocks, clocks-popup, phone-timer, restart, cat-interaction, chat, tui-launcher, overview-wallpaper, first-run, first-run-backend), `dbus-run-session -- python3 -B tests/clocks-action.test.py` (never on the real bus; `gi` tests need `dev-python/pygobject` on Gentoo), `sh tests/localsend.sh` (`HELPER_A/B=` for a fresh build), `cargo test --workspace` in `rust/`. Live-system suites (`tests/services.sh`, `compositor.sh`, `notifications.sh`) change real devices: never run them casually; `services.sh` never toggles Ethernet and skips Bluetooth power while a device is connected.
10. Owner's workflow: the owner commits and pushes (commit messages as text, lowercase `new:`/`fix:`); never stage or commit unless asked. Write decisions/gotchas/README/today's TODO (`todos/TODO_DD-MM-YY.md`, checkboxes; never tick unperformed hand checks) in the same session. Report honestly: what was tested how, what wasn't.
11. Safety: never toggle Ethernet, disconnect in-use Bluetooth, change audio routing to test unrelated code, or use the owner's real alarms/notes/files as fixtures.

## Gotchas that bite most often (full list in docs/gotchas.md)

- QML: don't name a property after an `Item` property (`left`, `top`: "Cannot override FINAL property"); an `id` hides a same-named property in its file (qualify with `root.`); don't name a singleton after a QtQuick type (hence `Store`); an inline `component` can fail as "not a type": move it to a file; a new sibling file may need an explicit `import qs.panels`/`qs.popups` on live reload.
- Quickshell's JS lacks `Object.fromEntries`, `Array.flatMap`, `Array.at`. It is slow at bulk work: big searches go to a helper process.
- A `var` holding a QObject turns null when destroyed, without a change signal: read null-safely. JsonAdapter lists are QVariant sequences: `Array.from` them.
- `Store` writes 300 ms after a change (with `blockWrites: true` against an async-write race); a reload in between loses it.
- A plain JS list as a Repeater model remakes every delegate on change: use `ScriptModel` with keys. Don't change a service's state inside a binding that reads it (`Qt.callLater`).
- Every `image://icon` Image must be `asynchronous: true` (sync + async on the same icon aborts the shell).
- `LazyLoader.component` changed while active keeps the old item; `Loader` is a focus scope (`focus: true`).
- Layers: a layer holding the keyboard exclusively must keep it until the focus dispatch lands; select on pointer movement, not hover-enter; `WlrLayer.Top` is below fullscreen windows (use Overlay); a launcher-like layer that grabs the keyboard closes on a click beside it itself (FocusGrab doesn't clear).
- IPC: don't name an IpcHandler function `show`; "Not ready to accept queries yet" means an old generation is alive (close Settings / restart).
- The launcher draws rows by kind through its `sourceComponent` table: a new row kind needs an entry (Classic too).
- Settings is a FloatingWindow (normal toplevel): `Compositor.placeSettingsWindow` floats it once; `float({action="set"})` toggles an already-floating window on this Hyprland.
- Hyprland: special workspaces have no id (minimised windows are id -1); runtime `hl.config` is undone by a config reload: reapply on `configreloaded`; run Lua dispatchers with `hyprctl dispatch`, not `eval`; `getoption` prints `bool` for on/off options.
- A process that ignores SIGPIPE (`pactl subscribe`) outlives the shell: start it via `setpriv --pdeathsig TERM`. `pkill -f <pattern>` kills your own shell command: use `pkill -x` or a pid.
- A shell restarted from a terminal without `HYPRLAND_INSTANCE_SIGNATURE` knows no windows.
- The session's PATH may lack `~/.local/bin` (it's in `~/.zshrc` only): psc appends it for itself and what it starts; don't rely on it elsewhere. A shell restarted from a terminal has the terminal's PATH.
- gio's first D-Bus connection sets SIGPIPE to ignored: restore SIG_DFL in psc after it. No systemd on the owner's box: never call `systemctl`/`bootctl`/`journalctl` from the shell.
- Kitty refuses a file included twice and reports it as a bad line (check `load_config(..., accumulate_bad_lines=[])`). Kitty takes no comment after an `include` on the same line; LocalSend uploads may be chunked; GNOME Clocks 51 alarms use `ring_time` and need every raw field kept; Stop/Snooze go to GNOME's `stop-alarm`/`snooze-alarm` actions.
- Test with the app's own reader where it matters (Kitty's loader, Neovim headless, real QML through QtTest): checking a file's text alone missed the Kitty bug.
