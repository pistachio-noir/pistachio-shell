# Tests

An index of what is in this folder (written 20 November 2026). The rules for running them are in `CLAUDE.md`
(working rule 9), and `docs/gotchas.md` has what each suite covers in full. The files stay flat in this folder
because the docs, the scripts and the shell's own tools cite them by name.

Run the isolated ones from the repo root. They use temporary homes, stand-in programs and fixture files, and
never touch the owner's devices, settings, chats, calendars or accounts. **The live suites in the last section
change the real system: don't run them casually.**

## Isolated suites (safe to run)

| Run | What it checks |
|---|---|
| `sh tests/js.sh` | all `*.test.js`, with node if installed, else in Quickshell's own JS engine (`qsjs/`) |
| `sh tests/settings.sh` | the Settings window with QtTest input and system-service stand-ins (`settings.test.py`, `settings-ui.qml`, `settings.test.js`) |
| `sh tests/layout.sh` | real Qt layout of the panels, no services (`layout.test.py`, `layout-ui.qml`) |
| `sh tests/bar.sh` | the real bar/control QML with service stand-ins (`bar.test.py`, `bar-ui.qml`) |
| `sh tests/tui-launcher.sh` | native TUI launcher and switcher drawing and input (`tui-launcher.test.py`, `tui-launcher.qml`) |
| `sh tests/tui-panels.sh` | Overview, notification centre, calendar and weather in TUI (`tui-panels.test.py`, `tui-panels.qml`) |
| `sh tests/launcher-tools.sh` | `psc launcher-tools` unit cases, preview bounds and cancellation, native tools panel |
| `sh tests/install.test.sh` | `install.sh` in a throwaway home with stand-in `cargo`/`curl` |
| `sh tests/lens.sh`, `sh tests/lens-native.sh` | Lens against fake `claude`/`codex` CLIs; the second opens real Wayland Lens windows |
| `sh tests/recording.sh`, `sh tests/screenshots.sh` | recording state with a fake encoder; the screenshot picker with temporary crops only |
| `sh tests/system.sh` | Shell health and the settings pages with hardware stand-ins |
| `sh tests/bluetooth-agent.sh` | the pairing agent's protocol on the **session** bus (`pistachio-devices bluetooth --session`) |
| `sh tests/polkit-agent.sh` | the polkit agent's protocol; never starts PAM |
| `sh tests/drives.sh` | the drive mounter against a stand-in UDisks on the session bus |
| `sh tests/localsend.sh` | two LocalSend helpers on ports 53318 and 53319 against each other |
| `python3 -B tests/events.test.py` | `psc events` against a private Evolution Data Server (its own bus, temporary home, `TZ=Europe/Warsaw`): repeats across the summer-time switch, UTC, all-day, floating times, a calendar that can't open; checks no EDS process is left |
| `dbus-run-session -- python3 -B tests/clocks-action.test.py` | the GNOME Clocks action stand-in; **never on the real bus** |

Some of these headers still name the old Python helper (`bluetooth-agent.py`, `polkit-agent.py`, `localsend.py`):
those helpers are Rust now (`rust/devices`, `rust/auth`, `rust/localsend`). The headers were left as written.

### `python3 -B tests/<name>.test.py`

| Test | What it checks |
|---|---|
| `app-theming` | the real `AppTheming` service with a stand-in Store and a stand-in `psc theme` |
| `neovim-theme` | Neovim, headless, follows the shared theme live (uses `integrations/neovim`) |
| `game-mode` | the real `GameMode` service with stand-in Compositor and ShellSettings |
| `clocks`, `clocks-popup` | the Clocks helper; Stop and Snooze closing the alarm popup |
| `phone-timer` | `psc phone-timer`, run the way FocusMode runs it: state page, Pause/Skip/End POSTs passed on as actions |
| `ambient-clock` | the ambient clock (Experimental): real service and layer with stand-ins and idle set by hand: switch, idle and empty-desktop rule, no input taken, media and timer lines, a fast fade-out, delay choices, preview, TUI font (native, shows briefly) |
| `desktop-widgets` | desktop widgets (Experimental): the real layer, studio and service with stand-ins: half-cell default layout, the centre cross and a centred drop, all six blocks from +, the TUI grid under the strip, hidden with a tiled window or in Zen, CPU/RAM readings only while shown, the studio's drag/snap, refused drop, ✕, +, Esc, IPC status (native, shows briefly); the grid rules are `desktop-grid.test.js` |
| `session-pill` | Zen's Pomodoro pill: Hide, Keep shown, the 4 px handle strip, Hide forgotten when Zen ends (native, shows briefly) |
| `prefs` | settings export/import (`psc prefs`) in a temporary folder |
| `capture-helper` | `psc capture` with real FFmpeg: trimming keeps the source and rejects unsafe ranges |
| `mic-check` | the microphone check helper |
| `restart` | restart and force restart |
| `cat-interaction` | the desktop cat, reusing the `tui-launcher` fixture's stand-ins |
| `chat`, `lens` | the Quick chat and Lens helpers against fake `claude`/`codex` programs |
| `first-run`, `first-run-backend` | the first-run view with fixture values; its backend and controller |
| `overview-wallpaper` | native Wayland pixel regression, temporary images only |
| `launcher-preview`, `launcher-tools-ui` | launcher preview process ownership; native tools panel |
| `recording`, `screenshots` | the recording service and overlay; the screenshot picker and crops |

`tests/*.qml` are the fixtures the `.test.py` and `.sh` files load; they aren't run on their own.

### JS unit tests (`*.test.js`, run by `js.sh`)

`calc`, `calendar`, `fuzzy`, `highlight`, `launcher-editing`, `recording` (pill placement), `settings`
(the settings search catalog), `bluetooth-pairing` (which paired devices to connect after pairing) and
`desktop-grid` (desktop widgets' sizes, fits, free spots, fitted layouts and the icons going around them).

### Rust

`cd rust && cargo test --workspace`: the helpers' and `psc`'s own unit tests (theme, doctor with Gentoo atoms and os-release, set-oneshot bytes, `/proc` children, tools and the rest), plus `psc/tests/power.rs`: `psc power` against a fake logind on a private `dbus-daemon` it starts itself (it first proves psc can't reach the real system bus).

## Live-system suites (they use the running shell or change real devices)

| Run | What it does |
|---|---|
| `sh tests/services.sh` | changes real volume, per-app volume, Bluetooth power (skipped while a device is connected), monitor brightness and the Do not disturb and night light schedules, then restores them; never toggles Ethernet |
| `sh tests/compositor.sh` | checks `Compositor.qml` against the running Hyprland session |
| `sh tests/notifications.sh` | needs the notification bus name free: stop the shell first (`psc stop`, then `psc start`) |
| `sh tests/mem.sh` | reads the memory of the running shell and helpers; changes nothing |
| `sh tests/ipc-surface.sh` | read-only, but needs the running shell: compares its IPC targets and functions with `ipc-surface.txt` (the owner's keybinds call them); `--save` rewrites the snapshot |

`harness/` is a small shell config that links `src/services` and `Theme.qml` so a test can load real services.
