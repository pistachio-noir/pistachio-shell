# Shell Optimisation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. No agent stages or commits: each task ends with a commit message as text for the owner.

**Goal:** Keep the shell (`qs -c pistachio`) and its helpers well under 1 GB after a full day of use, with nothing the owner sees or uses changed.

**Architecture:** Measure first with one script, find which windows own the memory, then load the rarely used ones on demand through one shared `OnDemand` component, each behind a small always-present host that keeps its IPC and signals. After that an audit removes dead QML and swaps costly code. The Rust helpers are Part B, with their own detailed plan and session.

**Tech Stack:** Quickshell 0.3.2 / QML, POSIX sh + Python standard library for the measuring tools, grim + ImageMagick `compare` for look checks. Part B: Rust 1.99 (cargo is installed).

**Spec:** `docs/superpowers/specs/2026-11-12-optimisation-design.md`

**Branch:** `experimental` (from e1afdd1). `main` is the rollback: `git switch main && psc restart`.

## Scope check

The spec holds two independent subsystems: the QML work (spec steps 1–3) and the Rust helpers (step 4). This plan details Part A (Tasks 1–8) and fixes only the decisions and gates of Part B (Tasks 9–12). Part B gets its own plan, `docs/superpowers/plans/2026-11-12-rust-helpers.md`, written at the start of its session after reading the three Python helpers line by line, and shown to the owner before any Rust is written.

## Starting numbers (12 November, 12:35, live shell pid 726, about 10 min after a restart, 3 reloads)

| | MiB |
|---|---|
| shell VmRSS | 810 |
| shell VmHWM (peak) | 844 |
| of which RssAnon / RssFile / RssShmem | 510 / 222 / 78 |
| helpers | 177 (udiskie 56, polkit-agent 31, bluetooth-agent 30, localsend 28, launcher-tools 19, udisksctl 8, pactl 5) |

Note: the shell is already at ~810 MiB ten minutes after a start, so most of it is there at rest, not built up over a day. Windows that are not `visible` are still built in full (every item, binding, image and timer); only their surface is missing.

## Global Constraints

- Nothing the owner sees or uses changes: same looks, motion, features, keys and IPC. Rarely used features stay.
- No `IpcHandler` function is removed or renamed, documented or not. `tests/ipc-surface.sh` (Task 1) proves it after every task.
- A window loaded on demand must still open within its usual ~200 ms motion. If its first frame comes later than before, it is preloaded or stays resident: looks win over memory.
- One production shell at a time. Scratch copies run only while the production shell is stopped (`psc stop` … `psc start`); the owner allowed restarts. Check `pgrep -ax qs` before starting anything.
- Verify every Quickshell type and property against the 0.3.2 docs before using it (`LazyLoader` first).
- Write QML in place; after each change check the "Configuration Loaded" count went up and the log has no new QML errors. After a task, `psc restart` and read the log again.
- Close the Settings window before testing IPC after a reload (old-generation gotcha).
- The lock screen is never loaded on demand. No Hyprland config edits. No device-changing suites (`tests/services.sh`) while the owner uses audio/Bluetooth.
- Colours and motion only from `Theme.qml`; system access only in `services/`.
- Numbers go into `todos/TODO_12-11-26.md` (checkboxes, Built/Verified labels) after every task; every visual change is listed there as an unchecked owner hand check.
- When in doubt whether something is dead or visible: keep it and list it for the owner.

## Review Focus

1. **A window asked for over IPC or a signal while it isn't loaded** (e.g. `settings search foo`, `wallpaper toggle`, `overview status`, `screenshot region`): it must load and do exactly what it did before; `status` functions must answer the same JSON as a closed window does today. → OnDemand test "call while unloaded" (Task 3) and a per-host IPC check (Tasks 4–5).
2. **A service that only started because a window used it** (the polkit agent "starts with the shell" through `PolkitDialog`; `Clocks` alarms through `AlarmPopup`): once the window is lazy, the service must still start at startup. → each host task lists the singletons its window was first to touch and adds them to `shell.qml`'s `background`; checked with `pgrep -f polkit-agent` and a `pkexec` prompt (one attempt, correct password).
3. **Reopening during the fade-out or the unload grace**: the same instance must come back, with no flicker and no lost state (Settings page and search, Lens conversation, wallpaper preview). → OnDemand test "reopen cancels unload" (Task 3).
4. **A live reload while a lazy window is open, and a lock while Settings is open**: same result as today (Settings closes on lock; a reload neither crashes nor leaves a generation stuck). → live check in Tasks 4–5, IPC answering after the reload.
5. **Memory not coming back after an unload** (the shell uses jemalloc; freed pages may stay resident): unloading is only kept where the measurement shows a gain at rest or after close; otherwise the gain claimed is the at-rest one only, and the TODO says so. → Task 2 and the measurement step of every task.

---

## Part A — QML

### Task 1: Measuring tools and the IPC guard

**Files:**
- Create: `tests/mem.sh`, `tests/ipc-surface.sh`, `tests/ipc-surface.txt`
- Create: `todos/TODO_12-11-26.md`

**Interfaces:**
- Produces: `sh tests/mem.sh [pid]` → one line `rss=<MiB> peak=<MiB> anon=<MiB> file=<MiB> shmem=<MiB> helpers=<MiB> total=<MiB>` (pid defaults to the single `qs` process; helpers = RSS of all descendants). `sh tests/mem.sh scenario [-c pistachio | -p <path>]` → runs the spec's sequence over IPC and prints a `mem.sh` line after each stage: `fresh`, `overview`, `settings` (4 pages), `launcher`, `quicksettings`, `notifications`, `wallpaper`, `power`, `screenshot` (open + cancel), `idle-30s`. Lens is opened by hand once (it needs a snip) and measured with the plain form. `sh tests/mem.sh reloads <n>` → writes a comment line in place into a scratch copy's `shell.qml` n times, waits for each "Configuration Loaded", prints a line after each.
- Produces: `sh tests/ipc-surface.sh` → compares `qs -c pistachio ipc show` (sorted) with `tests/ipc-surface.txt`; exit 1 and a diff when a target or function is missing or its signature changed; added functions are reported but pass. `sh tests/ipc-surface.sh --save` rewrites the snapshot.

- [ ] **Step 1:** Write `tests/ipc-surface.sh`, save the snapshot from the live shell (81 lines today), run it: PASS. Remove one line from a copy of the snapshot's source to see it FAIL, restore.
- [ ] **Step 2:** Write `tests/mem.sh` (reads `/proc/<pid>/status` and `/proc/<pid>/task/*/children` recursively; no dependencies). Run the plain form on pid 726: numbers match `grep Vm /proc/726/status`.
- [ ] **Step 3:** Create `todos/TODO_12-11-26.md` with a "Numbers" table (rows = stages, columns = Baseline, then one per task) and a "Hand checks for the owner" list.
- [ ] **Step 4:** Baseline: `psc restart`, wait 20 s, `sh tests/mem.sh scenario`, then leave the shell 10 min and take one more line. Record all in the TODO.
- [ ] **Step 5:** Commit text for the owner: `new: memory measuring script and ipc surface guard`.

### Task 2: Find the owners (no production code changes)

**Files:**
- Create (scratch, not in the repo): `$SCRATCH/src-*/` copies of `src/`, `$SCRATCH/empty/shell.qml`
- Modify: `todos/TODO_12-11-26.md`

All of this runs with the production shell stopped (`psc stop`); `psc start` when done. Scratch copies copy the QML (no symlinks, so nothing reloads mid-run) and run with `qs -p <copy>`.

- [ ] **Step 1: The floor.** Run a `shell.qml` holding only an empty `ShellRoot {}`, then one with a single empty `PanelWindow`. Record both: this is what Quickshell + Qt + the GPU driver cost before any of our code, and what no QML change can go under.
- [ ] **Step 2: One window at a time.** For each top-level entry of `shell.qml` (Wallpaper, Overview, Bar, Launcher, SettingsWindow, Lock, PolkitDialog, ScreenshotPicker, RecordingRegion, LensCard, LauncherExtras, RecordingTools, AlarmPopup, SessionPill, PistachioRain, WindowSwitcher, WallpaperSwitcher) and each window inside `Bar.qml` (MediaPill, TrayPill, QuickSettings, BarMenu, PowerMenu, NotificationCentre, Toasts, Osd): a copy with only that entry commented out (its callers stubbed), fresh start, 20 s, `mem.sh`. The difference from the full copy is that window's cost at rest. A script loops this; table into the TODO, biggest first.
- [ ] **Step 3: Inside the big resident ones.** For Launcher, QuickSettings and NotificationCentre (which stay resident), repeat one level down for their heavy parts: LocalSendPage, MixerPage, WeatherPanel, Calendar, MediaCard, the launcher's emoji table and row delegates.
- [ ] **Step 4: Open/close growth.** In the full copy: open and close each window five times, `mem.sh` after each round. Growth that doesn't level off is a leak to trace in Task 7; a one-time step is that window's "after first use" cost, which unloading may or may not give back (Review Focus 5).
- [ ] **Step 5: Reloads.** `sh tests/mem.sh reloads 10` on the full copy. If every reload adds memory, find what keeps the old generation (open FloatingWindow, running Process, Timer) and record it; a leak inside Quickshell itself is reported to the owner, not worked around.
- [ ] **Step 6: Overview peak.** Open the Overview on a workspace with several windows and read VmHWM: the blur layer and the live window pictures decide the peak, and the peak is what crosses 1 GB.
- [ ] **Step 7: Decide and write down** in the TODO which windows become lazy. Rule: lazy when the window costs 3 MiB or more at rest, or keeps a timer/animation/image alive while closed, and it is not on the resident list. **Resident whatever the numbers:** Bar, Wallpaper, Lock, Launcher (its own parts may be lazy), WindowSwitcher (Alt+Tab must be instant), Toasts, Osd. Show the owner the table before Task 3.

No commit (nothing in the repo changed but the ignored TODO).

### Task 3: `OnDemand`, the shared loader

**Files:**
- Create: `src/components/OnDemand.qml`
- Test: `tests/ondemand.sh`, `tests/ondemand-ui.qml`
- Modify: `docs/plan.md` (a short "Windows loaded on demand" section)

**Interfaces:**
- Produces, for every later task:

```qml
// OnDemand.qml — a Scope around Quickshell's LazyLoader (checked against the 0.3.2 docs first;
// plain QtQuick Loader for parts that aren't windows)
property bool wanted                    // set by the host: the window should exist now
default property Component component    // the window
readonly property var item              // the loaded window, or null
readonly property bool loaded           // item !== null
property int grace: 5000                // ms kept after the fade-out before unloading
function call(fn: var): void            // loads now if needed (synchronously), then fn(item)
```

- Contract for a loaded window: it exposes `readonly property bool shown` (true while open or fading; they all have a `Reveal` already). OnDemand is active while `wanted || item.shown`, then for `grace` more ms; `wanted` or `call()` during the grace cancels the unload and keeps the same instance. It never reads `item.shown` in the binding that creates `item` (binding loop): a `Connections` on the item restarts the grace timer.

- [ ] **Step 1:** quickshell-docs check: `LazyLoader` (`active`, `loading`, `item`, `component`, `activeAsync`), whether setting `active` builds synchronously, and its documented behaviour on reload.
- [ ] **Step 2:** Write `tests/ondemand-ui.qml` + `tests/ondemand.sh` (QtTest, same isolation as `tests/settings.sh`: private runtime/state/cache, copied QML, stops its own pid). A fake window component with `open`, a 200 ms Reveal and a counter of constructions. Tests, with `grace: 300`:
  - `test_not_built_until_wanted`: constructions === 0, `item === null`.
  - `test_wanted_builds_once`: wanted → constructions === 1, `item.shown` after open.
  - `test_stays_through_fade`: wanted=false while `item.shown` → `loaded` still true until shown is false.
  - `test_unloads_after_grace`: shown false + 300 ms → `item === null`.
  - `test_reopen_cancels_unload`: reopen at 150 ms into the grace → same instance (constructions unchanged), a property set on it before is still there.
  - `test_call_while_unloaded`: `call(w => w.open = true)` on an unloaded one → built, fn ran, returns after the item exists.
  - `test_destroyed_item_is_null_safe`: after unload, reading `item?.shown ?? false` gives false and the log has no TypeError.
- [ ] **Step 3:** Run `sh tests/ondemand.sh`: FAIL (OnDemand is not a type).
- [ ] **Step 4:** Implement `src/components/OnDemand.qml`.
- [ ] **Step 5:** Run `sh tests/ondemand.sh`: PASS, no QML warnings in its log.
- [ ] **Step 6:** Commit text: `new: on-demand loader for rarely used windows`.

### Task 4: Overview — keep the layer, load the content

**Files:**
- Modify: `src/panels/Overview.qml` (the content under `Reveal`, from `backdrop` on, ~line 172 to the end)
- Create: `src/panels/OverviewContent.qml` only if the inline `Loader` can't hold the content cleanly (an inline `component` has failed twice in this repo: use a file)

The `PanelWindow`, its mask, keyboard rule, `IpcHandler`, `Reveal` and all root state (`open`, `mode`, `query`, `list`, `selected`, …) stay as they are, so the layer is still mapped before the bar and `overview status` still answers while closed. Only the items (backdrop, blur, strip, cards, `ScreencopyView`s, key handling item) move behind a `Loader { active: root.open || root.shown }`.

- [ ] **Step 1:** Before: `hyprctl layers` (Overview under the bar, same level), grim series of the opening at 25 ms steps on a workspace with 3 windows and on an empty one, All windows, a search; `overview status` closed and open. Save under `$SCRATCH/looks/before/`.
- [ ] **Step 2:** Move the content behind the loader. Key events and focus must reach the loaded item on the first open (it takes focus in `onLoaded`/`Component.onCompleted`, the layer already holds the keyboard).
- [ ] **Step 3:** Root functions that touch content items (scrolling, focusing the search) go through `loader.item?.…`; nothing in `root`'s bindings reads a content item.
- [ ] **Step 4: Blur cost.** Measure VmHWM with the blur as now. Then try the blurred wallpaper at half the screen size (`sourceSize`/`layer.textureSize` halved, `blurMax` 24, scaled up by the item) and `compare -metric AE` the two captures plus a look by eye. Adopt only if indistinguishable; otherwise keep the full-size blur and record the number. Either way it is an owner hand check.
- [ ] **Step 5:** After: the same grim series, `hyprctl layers`, `overview toggle/open/close/status`, Ctrl+1…0, drag to a workspace, Tab, type-to-search, Esc. First card frame not later than before.
- [ ] **Step 6:** `sh tests/ipc-surface.sh`, `sh tests/js.sh`; `psc restart`; `sh tests/mem.sh scenario`; numbers into the TODO; hand checks listed.
- [ ] **Step 7:** Commit text: `fix: overview builds its content only while open`.

### Task 5: Hosts for the windows Task 2 chose

One sub-task per window, in the order of the Task 2 table (biggest first), each measured and checked alone. Expected set (confirmed or cut by Task 2): SettingsWindow, WallpaperSwitcher, LensCard, LauncherExtras, ScreenshotPicker (+ ScreenshotMenu, CaptureSetup inside it), RecordingTools, PolkitDialog, AlarmPopup, PistachioRain, and if they measure above the rule RecordingRegion and SessionPill.

**Files (per window `X` in folder `d`):**
- Create: `src/d/XHost.qml`
- Modify: `src/d/X.qml` (its `IpcHandler` moves to the host; add `readonly property bool shown` where missing), `src/shell.qml` (`XHost { id: … }` in place of `X { … }`, `background` list), the test fixture that drove the window through IPC (`tests/screenshots-ui.qml`, `tests/settings-ui.qml`, `tests/lens-native.qml`, `tests/recording-ui.qml`, `tests/launcher-tools-ui.qml`)

**Interfaces:**
- Consumes: `OnDemand` (Task 3).
- Produces: `XHost` is a `Scope` with the same ids, signals and functions `shell.qml` uses today (`wallpaperSwitcher.show()`, `settings.showPage(page, control)`, `rain.start()`), each forwarding with `loader.call(w => w.show())`. It holds the window's `IpcHandler` with identical target and signatures. `wanted` is bound to the state that opens the window:

| Window | `wanted` |
|---|---|
| SettingsWindow | `SettingsHub.opened` |
| LensCard | `Lens.open` |
| PolkitDialog | a request is pending in `Polkit` |
| AlarmPopup | a timer is done or an alarm rings in `Clocks` |
| RecordingTools | countdown or trim open in `Screenshots`/its own state |
| LauncherExtras | `LauncherTools.present` fired / its `open` |
| WallpaperSwitcher, ScreenshotPicker, PistachioRain | set by the host's `show()`/IPC call, cleared when the window's own `open`/`mode`/`raining` goes back to closed |

- `status`-style IPC functions answer from the item when loaded, else the JSON a closed window gives today (e.g. settings: `open:false, page:SettingsHub.page, minimized:false, search:"", results:0, scanning:Bluetooth.scanning, watching:SystemStats.watching`).

Steps for each window:

- [ ] **Step 1:** Before: grim series of its opening (25 ms steps) and of each state it has; its IPC functions called closed and open, outputs saved.
- [ ] **Step 2:** List every singleton the window was the first to touch (grep its imports and bindings); those that must run from startup go into `shell.qml`'s `background` (`Polkit` certainly).
- [ ] **Step 3:** Write the host, move the `IpcHandler`, switch `shell.qml`; point the fixture at the host where it used IPC.
- [ ] **Step 4:** After: the same grim series and IPC calls, outputs identical; first frame not later than before (else `loading: true` preloading on the trigger, or the window stays resident and the TODO says why).
- [ ] **Step 5:** Review Focus checks that apply: IPC while unloaded; reopen during fade and during grace; a reload while open then `psc settings status` answers; lock while Settings is open closes it.
- [ ] **Step 6:** The window's own suite (`tests/settings.sh`, `tests/screenshots.sh`, `tests/recording.sh`, `tests/lens.sh` + `tests/lens-native.sh`, `tests/launcher-tools.sh`, `tests/polkit-agent.sh`), `sh tests/ipc-surface.sh`, the log.
- [ ] **Step 7:** `psc restart`, `sh tests/mem.sh scenario`, numbers into the TODO; hand check listed.
- [ ] **Step 8:** Commit text: `fix: <window> loads when opened`.

Special cases, decided now:
- **PolkitDialog:** one real `pkexec /usr/bin/true` with the correct password, never a wrong one; the dialog must appear as fast as today.
- **SettingsWindow:** it is a `FloatingWindow` that `Compositor.placeSettingsWindow` floats and centres once when mapped; a freshly loaded window must be placed the same way every time it is opened (check with `hyprctl clients -j`: floating, 1040 × 760, centred, not grouped, border 0, rounding 28).
- **LensCard:** two overlay windows and a held `ItemGrabResult` (`Lens.still`); the host unloads only after `Lens.open` is false and the fade ended, and `Lens.pickingFile` (zenity up, card hidden through Reveal) counts as wanted.
- **ScreenshotPicker:** PrtSc must show the frozen screen with no added delay: measured with the grim series; if loading costs a frame, it stays resident.

### Task 6: Lazy parts inside resident windows

**Files:** as Task 2, Step 3 points to; expected `src/panels/QuickSettings.qml` (LocalSendPage, MixerPage, WeatherPanel), `src/panels/NotificationCentre.qml` (WeatherPanel details), `src/launcher/Launcher.qml` (rarely used modes' views).

- [ ] **Step 1:** For each part above the Task 2 rule: wrap it in a plain `Loader` active while its page/mode shows or its slide/fade runs. A page whose height eases inside quick settings must not resize the layer per frame (existing gotcha): keep the outer size owner as it is.
- [ ] **Step 2:** grim before/after of each page's opening; `sh tests/layout.sh`, `sh tests/localsend.sh`, `sh tests/js.sh`; log.
- [ ] **Step 3:** `psc restart`, scenario, TODO, hand checks.
- [ ] **Step 4:** Commit text: `fix: quick settings and launcher pages build when shown`.

### Task 7: Audit — dead code out, costly code swapped

**Files:** decided by the scans below; the scan script lives in `$SCRATCH`, not the repo.

- [ ] **Step 1: Dead-code candidates.** A script lists every `function`, `property`, `signal`, `id`, QML file (type name), `.js` export and `Icons.qml` glyph in `src/` whose name occurs nowhere else in `src/`, `tests/`, `bin/`, `README.md`. Functions inside an `IpcHandler` are excluded outright. Known leads: the removed magnifier's leftovers in `Compositor.qml` (pointer polling), `README` and tests; Vicinae/hyprpaper remnants; superseded Lens choice screens.
- [ ] **Step 2:** Read each candidate in place (a name built from a string, a `sourceComponent` table, an `objectName` lookup or a `Store.saved` key is not dead). Sure → remove; unsure → the "Kept, owner's call" list in the TODO. After each file: reload count, log.
- [ ] **Step 3: Costly-code scan,** each finding fixed alone with identical behaviour:
  - `Timer`s and `SystemClock`s that run while their window is closed (`grep -n "running:\|repeat: true\|SystemClock"`): bind `running` to the window being shown; seconds precision only where seconds are drawn.
  - Polling `Process`es (stats, uptime, weather, Cider, media position) that run with nothing showing them.
  - `Image`s without `sourceSize` showing large files small (wallpaper thumbnails, notification pictures, album art, app icons), and `cache`/`asynchronous` settings.
  - Bindings that rebuild whole lists on a tick (Settings' live pages, launcher rows, `Compositor.windows.filter(…)` chains evaluated in closed windows).
  - `Repeater`s over long models where a `ListView` with the same look would build only what shows — only where spacing, order and motion stay pixel-identical; otherwise leave.
  - `layer.enabled`, `MultiEffect` and `Shadow`s on items that are not visible.
  - Animations with `loops: Animation.Infinite` running while hidden.
- [ ] **Step 4:** For every swap: grim before/after of the affected view; the suite that covers the file; a line in the TODO (what, why, number if measurable).
- [ ] **Step 5:** `sh tests/ipc-surface.sh` (must be unchanged), `sh tests/js.sh`, `tests/settings.sh`, `tests/layout.sh`, `tests/lens.sh`, `tests/screenshots.sh`, `tests/recording.sh`, `tests/launcher-tools.sh`, `tests/system.sh`; `psc restart`; scenario; TODO.
- [ ] **Step 6:** Commit texts: `fix: remove unused shell code` and `fix: stop timers and polling while nothing shows them` (split as the changes fall).

### Task 8: Part A wrap-up

- [ ] **Step 1:** Long run: after `psc restart`, the scenario three times over, then 30 min idle, then a line; peak under the goal with room. Numbers into the TODO as the Part A result.
- [ ] **Step 2:** Docs: `CLAUDE.md` (a dated decision "windows loaded on demand", the resident list and why, new gotchas found), `docs/plan.md`, `README.md` only if a command changed (none should).
- [ ] **Step 3:** style-reviewer agent on the whole diff; fix its findings.
- [ ] **Step 4:** Report to the owner: before/after table, what was kept resident and why, the hand-check list, what remains untested. Full commit message as text.

---

## Part B — Rust helpers (own session, own detailed plan)

Decisions fixed here; the detailed plan comes first in that session and is shown to the owner.

- Workspace `rust/` with three binary crates: `pistachio-auth` (replaces `polkit-agent.py`; alone in its process; PAM only on submit), `pistachio-devices` (replaces `bluetooth-agent.py`, `udiskie`, `udisksctl monitor`; udiskie scope as the spec's "Calls Claude made": automount, the four toasts with Open, LUKS toast without unlocking), `pistachio-localsend` (replaces `localsend.py`; same port 53317, protocol, prompts, saved settings). `launcher-tools.py` only if time allows; every on-demand Python helper stays.
- Same stdin/stdout JSON protocol and flags as each Python helper (`--session` for the agents' tests), so the QML service changes only its `command`.
- `install.sh` runs `cargo build --release --manifest-path rust/Cargo.toml` and copies the binaries to `~/.local/bin`; the services start them by absolute path (`$HOME/.local/bin/…`), not through PATH. README: cargo/rustc as build requirements. `rust/target/` into `.gitignore`.
- Crates kept few: zbus for D-Bus; PAM and the LocalSend HTTPS server chosen in the Part B plan after reading the helpers.

### Task 9: Tests take the helper as a parameter
`tests/polkit-agent.sh`, `tests/bluetooth-agent.sh`, `tests/localsend.sh` read `HELPER` (default: the Python file) and pass unchanged against Python. New `tests/drives.sh` for automount/eject/toasts against a loop device or a mocked UDisks on the session bus, written against udiskie's behaviour first.

### Task 10: `pistachio-auth` → `tests/polkit-agent.sh` passes with `HELPER=rust/target/release/pistachio-auth`, one real `pkexec` (correct password), `faillock` count unchanged by a cancel; swap `Polkit.qml`, `psc restart`, measure, delete `polkit-agent.py`.

### Task 11: `pistachio-devices` → `tests/bluetooth-agent.sh` and `tests/drives.sh` pass; swap `Bluetooth.qml` and `Drives.qml`, measure, delete `bluetooth-agent.py`; README drops udiskie. Real pairing and a real USB stick are owner hand checks.

### Task 12: `pistachio-localsend` → `tests/localsend.sh` passes (two helpers on 53318/53319), also Rust against Python both ways; swap `LocalSend.qml`, measure, delete `localsend.py`. A phone transfer is an owner hand check.

Each swap lands only when its test passes; the Python file is deleted in the same step; numbers and hand checks go into the day's TODO; commit text per helper (`new: pistachio-auth replaces the python polkit agent`, …).
