# Desktop widgets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clock, Weather and CPU/RAM blocks on the desktop, arranged on a snapped grid in a full-screen studio; Experimental, off by default.

**Architecture:** A pure JS grid helper (`src/panels/desktopGrid.js`) decides sizes, fits, free spots and the icons' layout around widgets; a `DesktopWidgets` service owns the switch, layout and `arranging`; `panels/DesktopWidgets.qml` draws the blocks in the wallpaper window under the icons; `popups/WidgetStudio.qml` is an Overlay layer for arranging.

**Tech Stack:** Quickshell 0.3.2 QML, plain JS (node + Quickshell's JS engine), Rust `psc prefs`.

**Spec:** `docs/superpowers/specs/2026-11-20-desktop-widgets-design.md`

## Global Constraints

- Grid: 104 px cells, 24 px margin, rows clear of the bar (`DesktopIcons` formula). Sizes: clock 3×2, weather 2×2, stats 2×2.
- Default layout: clock, weather, stats down the right edge from the top.
- Store keys `desktopWidgets` (bool, false) and `widgetLayout` (`[{kind, col, row}]`); export key `[experimental] desktop_widgets`.
- Shown: switch on, active workspace without tiled windows, not fullscreen, not Zen.
- Colours from Theme only; no pistachio fills; TUI square + JetBrains Mono; Reveal for the studio.
- No `Object.fromEntries`, `Array.flatMap`, `Array.at` in JS.

## Review Focus

- A smaller screen or a resolution change leaves a saved widget off the grid: it moves to the first free spot, not off-screen (`fitLayout` test).
- An icon saved under a widget: it reflows to a free cell and returns when the widget is removed (`iconLayout` test).
- Two widgets dropped onto overlapping cells: refused, the dragged one goes back (`fits` test).
- No room left for a new block: `+` buttons for it are disabled, nothing is placed (`firstFree` → null test).
- Settings closing while the stats block is visible must not stop its readings (two watcher flags).

---

### Task 1: Grid helper

**Files:** Create `src/panels/desktopGrid.js`; Test `tests/desktop-grid.test.js`.

**Produces:** `SIZES` (`{clock:[3,2], weather:[2,2], stats:[2,2]}`); `cellsOf(w) -> string[]` ("c,r"); `fits(layout, index, kind, col, row, columns, rows) -> bool` (ignores `layout[index]`, -1 for a new one); `firstFree(layout, kind, columns, rows) -> [col,row] | null` (scans columns right to left, rows top down); `defaultLayout(columns, rows)`; `fitLayout(layout, columns, rows)` (drops unknown kinds and duplicates, moves misfits to `firstFree`, drops what can't fit); `iconLayout(names, positions, columns, rows, blocked) -> {name: [c,r]}` (today's DesktopIcons algorithm with `blocked` cells pre-taken).

- [ ] Write the tests: sizes; fits at edges and overlap; firstFree on an empty and a full 4×4 grid; defaultLayout on 18×8; fitLayout on a shrunk grid; iconLayout with an icon saved under a widget and with no widgets equal to today's result.
- [ ] `sh tests/js.sh` fails (no file); implement; passes.

### Task 2: Service, settings, export

**Files:** Create `src/services/DesktopWidgets.qml`; modify `Store.qml`, `ShellSettings.qml`? (no: the service owns it), `SystemStats.qml`, `SettingsContent.qml`, `catalog.js`, `Preferences.qml`, `SettingsReset.qml`, `rust/psc/src/prefs.rs`, `shell.qml` (nothing: a singleton loads on use).

**Produces:** `DesktopWidgets.enabled`, `setEnabled(bool)`, `layout` (raw), `arranging`, `arrange()`, `done()`, `place(index, col, row) -> bool`, `add(kind) -> bool`, `remove(index)`, `shownOn` (desktop visibility rule), `grid(columns, rows)` → fitted layout; `SystemStats.setWidgetsWatching(bool)`.

- [ ] prefs test first (`cargo test -p psc prefs`): `desktop_widgets` round-trips; then add the row; passes.
- [ ] Settings → Experimental group "Desktop widgets": toggle + action "Arrange…"; catalog entry; reset default false; labels.
- [ ] `sh tests/settings.sh` passes.

### Task 3: Blocks on the desktop

**Files:** Create `src/panels/DesktopWidget.qml` (one block by `kind`, Classic/TUI), `src/panels/DesktopWidgets.qml` (Repeater over the fitted layout); modify `Wallpaper.qml` (between wallpaper dim and icons), `DesktopIcons.qml` (`blocked` from the widgets; refuse drops on blocked cells; desktop menu "Arrange widgets…").

- [ ] Native fixture `tests/desktop-widgets.test.py` + `tests/desktop-widgets-ui.qml`: blocks at their cells, hidden with a tiled window / Zen / switch off, stats watching only while the stats block shows, TUI square.
- [ ] Live reload clean.

### Task 4: Studio

**Files:** Create `src/popups/WidgetStudio.qml`; modify `shell.qml` (instance), `Launcher.qml` (switch + "Arrange desktop widgets" row), docs.

- [ ] Fixture extends Task 3's: arrange opens, drag snaps, refused overlap returns, ✕ removes, + adds at firstFree, Esc closes, IPC `widgets arrange|done`.
- [ ] README, decisions, gotchas, CLAUDE.md line, tests/README, TODO.
