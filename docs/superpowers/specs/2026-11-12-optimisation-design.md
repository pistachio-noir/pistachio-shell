# Shell optimisation: design

12 November 2026. Talked through between the owner and Claude; to be built later on 12 November.

## Why

The shell (`qs -c pistachio`) reached about 1 GB in normal use: 828 MiB resident, 965 MiB peak, measured 30 minutes after a restart with the Overview and Settings opened, plus 179 MiB in its helper processes. On 11 November, before the Overview, Zen/Focus, calendar events and the Settings additions, it was 511 MiB + 185 MiB. The owner wants it lighter.

## Goal and the line not to cross

- **Success (owner):** the shell never crosses 1 GB. Builder's working target: shell + helpers stay well under 1 GB after a full day of use, the Overview and Settings included.
- **Hard rule (owner, IDEAS-10.11.26 and this talk):** nothing the owner sees or uses changes. Same looks, same motion, same features, same keys and IPC. Rarely used features stay.
- **Anti-goals:** a feature removed or behaving differently; a visible delay when opening something (a panel loaded on demand must still open within its usual ~200 ms motion); a regression in the tested helpers (pairing, polkit, LocalSend).

## The work, in order

### 1. Measure first, and after every step

Record resident memory (`/proc/<pid>/status`: VmRSS, VmHWM, RssAnon) of the shell and the sum of its children:
- right after a fresh start,
- after opening and closing the Overview, Settings (a few pages), the launcher, Lens, quick settings and the notification centre,
- after ~10 live reloads (does each reload leak?).

Keep the numbers in the day's TODO, before/after each step, so the owner can see what helped. Find the biggest owners before changing anything (e.g. by disabling one window at a time in a scratch copy of `src/`). Leave the owner's running shell alone while measuring; use a second test instance under `tests/harness`-style isolation or a copy, and only one production shell at a time.

### 2. Rarely used windows: load on demand, free when closed (owner's call)

Rarely used features stay, but cost nothing until opened. Candidates (the builder confirms with measurements): Overview, SettingsWindow, WallpaperSwitcher, LensCard, LauncherExtras (jobs/preview), ScreenshotPicker/ScreenshotMenu, RecordingTools, PolkitDialog, PistachioRain, Showoff pieces, AlarmPopup, LocalSend pages, MixerPage, WeatherPanel details.

- Wrap each in a `Loader` (or `LazyLoader`, checked against the Quickshell 0.3.2 docs) that is active while the window is open **and** while its `Reveal` fade-out runs; unload after.
- IPC handlers, signals and services that other parts call must keep working while the window isn't loaded: move the `IpcHandler` out of the loaded part (or into a small always-present stub) and have it activate the loader first.
- The opening motion must look exactly as now. If a window's first frame after loading lags (measure with grim at ~25 ms steps, as done for quick settings), preload it on hover/keybind or keep it resident: looks win over memory.
- **Overview specifically:** it is deliberately always mapped (empty input region while closed) so the bar stays above it (CLAUDE.md, Overview decision). Keep that mapping, but load its content (wallpaper copy, blur layer, `ScreencopyView`s, card delegates) only while open. Check the blur: a full-screen `MultiEffect` layer at 1.05–1.12 scale may allocate large textures; a smaller blurred copy scaled up must look the same.
- Mind the existing gotchas: live reload and `PersistentProperties`, the Settings window holding an old generation across a reload (close it before testing IPC), exclusive-keyboard layers releasing focus only after their fade.

### 3. QML audit: remove dead code, swap costly code (owner's call)

- **Remove** what nothing uses anymore: functions, properties, components, files, IPC functions no one calls, leftovers of removed features (e.g. the magnifier's), duplicated helpers. Check every candidate by search across `src/`, `tests/`, README and `bin/` before removing; removed IPC must not be documented in README.
- **Swap** code that does its job in a costly way for a cheaper equivalent with identical behaviour, e.g.: timers or polling that run while nothing is shown; bindings that rebuild whole lists every second (Settings' live pages, launcher rows); images decoded at full size where a `sourceSize` would do; `Repeater`s over large models where only a few items show; shadows/layers kept on invisible items.
- Nothing visible changes. When in doubt, keep it and list it for the owner.

### 4. Rust helpers (owner's call, from the 11 November talk)

Replace the always-running Python helpers and udiskie with one Rust workspace producing three binaries:

| Binary | Replaces | Notes |
|---|---|---|
| `pistachio-auth` | `services/polkit-agent.py` | Alone in its process: password handling never shares a process with a network server. PAM starts only on submit (the pam_faillock gotcha). |
| `pistachio-devices` | `services/bluetooth-agent.py`, `udiskie`, `udisksctl monitor` | Bluetooth pairing agent (Agent1) and UDisks automount/eject with the same notifications and behaviour. |
| `pistachio-localsend` | `services/localsend.py` | Same protocol, ports, prompts and saved settings. |

- Same command-line/JSON protocols as the Python helpers, so the QML services change only the command they start. Each swap lands only when its existing test passes against the Rust binary (`tests/polkit-agent.sh`, `tests/bluetooth-agent.sh`, `tests/localsend.sh`, plus the drives checks).
- `launcher-tools.py` may follow last if time allows. On-demand helpers (`files.py`, `lens.py`, `clocks.py`, `capture.py`, `events.py`, `system-tools.py`, `mic-check.py`, `library.py`, `swatch.py`) stay in Python: they cost nothing at rest. `hyprsunset` and `pactl subscribe` stay.
- Build: a `cargo build --release` step in `install.sh`; `cargo`/`rustc` become a build requirement in README. Crate choices (zbus, PAM bindings, an HTTPS server for LocalSend) are the builder's, kept small and with few dependencies.
- Estimated saving ~150 MiB (Python at ~18–31 MiB each, udiskie 56 MiB, to a few MiB each), to be confirmed by measurement.

## Owner's answers (12 November 2026, 00:44)

- **Restarting the running shell:** allowed while building and measuring (helpers that run once per login can only be proven by swapping the live ones). Keep a TTY in mind; one production shell at a time.
- **udiskie:** moved entirely into `pistachio-devices` ("if we're migrating helpers to Rust we should move it entirely"); scope left to Claude (below).

## Calls Claude made (owner can overrule)

- **udiskie scope (owner left it to Claude):** automount on plug-in, unmount/eject as today (Drives service, busy-holder listing kept), and udiskie's toasts: mounted (with an Open action that opens the folder via `xdg-open`), unmounted, removed, failed. Encrypted (LUKS) drives: not unlocked by the helper at first; a toast says the drive is encrypted and offers Open in the file manager, which can unlock it. Unlocking in the shell can come later as its own feature.

- **Python helpers after a swap:** deleted once the Rust binary passes its test (no fallback to maintain). The Rust workspace lives in `rust/` in the repo; `install.sh` builds it and installs the binaries to `~/.local/bin` (on PATH via the installed paths the QML uses; `src/` stays QML/Python only).
- **IPC:** no `IpcHandler` function is removed in the audit, even if nothing in the repo calls it: the owner's future Hyprland config may bind ones the README doesn't list. Dead code removal is limited to code with no IPC surface.
- **"Looks the same":** the builder compares grim captures before/after each visual change (Overview blur, lazy-loaded windows' first frames); each such change is also listed in the day's TODO as an owner hand check before the commit.

## Left to the builder

The measuring method, the order inside each step, which windows actually get lazy-loaded (by measurement), crate choices, and how the IPC stubs are structured. Anything that would change looks or behaviour goes to the owner first.

## When done

README (requirements, install), CLAUDE.md (decisions, new gotchas, the helper list), the day's TODO with before/after numbers and hand checks, the relevant tests run, and a commit message as text (the owner commits).
