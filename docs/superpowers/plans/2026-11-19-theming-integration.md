# Theming Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One Settings switch (on by default) under which the shell sets Kitty and Neovim up to follow Colours itself, asks before touching an app with its own theme, and removes its own lines when switched off.

**Architecture:** `services/shared-theme.py` grows a small app table (check / setup / undo per app) and a JSON-lines CLI; a new `services/AppTheming.qml` singleton owns the switch, the app states and the pending conflict; Settings → Appearance → Colours shows the switch and rows, and `SettingsDialog` asks about conflicts.

**Tech Stack:** Python 3 (stdlib only), Quickshell 0.3.2 QML.

**Spec:** `docs/superpowers/specs/2026-11-19-theming-integration-design.md`

## Global Constraints

- Switch `Store.saved.themingIntegration`, missing = on; kept apps `Store.saved.themingKeep` (list of app ids).
- App ids `kitty`, `neovim`; states `following`, `own`, `available`, `missing`, `unsupported` (`detail` carries the reason for `unsupported`).
- Marker on every line the shell adds: `# pistachio-shell theming` (Kitty), `-- pistachio-shell theming` (Lua). Undo removes only marked lines (and the legacy Neovim line, restored as `vim.cmd("colorscheme pistachio-noir")`).
- Backup before any change: `<file>.pistachio-bak-<YYYYMMDD-HHMMSS>`; atomic writes; respect `XDG_CONFIG_HOME`.
- Text, FM and Notes always follow (the shared-theme file is always published).
- Owner's live machine must end up `following` for both apps with `kitty.conf` and `init.lua` byte-identical.
- No staging or commits (owner commits). Quickshell types checked against v0.3.2.

## Review Focus

- Kitty config with `include current-theme.conf` (from `kitten themes`) → `own`, untouched until Use Pistachio; Task 1 test `kitty_kitten_theme_is_own`.
- Neovim colourscheme set inside a lazy.nvim plugin spec, not a `colorscheme` line → treated as `available`, our line appended last still wins; Task 1 test `neovim_without_colorscheme_line`.
- File edited by the user between status and setup → left alone, reported `unsupported` "changed while reading"; Task 1 test `changed_file_left_alone`.
- Switch toggled off then on → same final files as a single setup (no duplicate lines); Task 1 test `setup_twice_is_one_line`.
- Settings opened with two conflicts → asked one at a time, Keep on the first then the second shows; Task 3 fixture check.

---

### Task 1: Helper app table

**Files:**
- Modify: `src/services/shared-theme.py`
- Create: `extras/kitty-pistachio-noir.conf` (copy of the owner's `~/.config/kitty/pistachio-noir.conf`, the theme source for fresh installs)
- Test: `tests/shared-theme.test.py` (keep existing checks)

**Interfaces:**
- Produces: `status(config: Path) -> list[dict]` each `{"id","name","state","detail"}`; `setup(config: Path, app: str, extras: Path) -> dict`; `undo(config: Path, app: str) -> dict`; `publish(path, scheme)` unchanged. CLI: `shared-theme.py publish <scheme>` (and the old `shared-theme.py <scheme>`), `status`, `setup <app>`, `undo <app>`; each prints one JSON line `{"apps": status(...)}` after acting; exit 0, or 1 with `{"error": "..."}`.

- [ ] Step 1: tests in a temporary config folder: `fresh_kitty_is_available_then_following` (kitty.conf without theme → `available`; setup → marked include appended last, both theme files copied, `pistachio-shared.conf` written, backup present, state `following`); `kitty_kitten_theme_is_own` (`include current-theme.conf` → `own`; status leaves the file byte-identical); `owner_style_wired_kitty_is_following` (`include pistachio-shared.conf` on line 2, no marker → `following`, setup is a no-op); `kitty_undo_restores_bytes` (setup then undo → kitty.conf equals the original, `pistachio-shared.conf` gone); `neovim_without_colorscheme_line` (`available`, setup appends marked `pcall(...)` line, copies colors/ and lua/ files); `neovim_own_colorscheme` (`vim.cmd("colorscheme tokyonight")` → `own`); `neovim_legacy_undo` (`require("pistachio-shared").setup()` unmarked → undo makes it `vim.cmd("colorscheme pistachio-noir")`); `neovim_init_vim_only` (→ `unsupported`, detail mentions init.vim); `missing_apps` (no kitty folder and `kitty` not on PATH stubbed → `missing`); `setup_twice_is_one_line`; `changed_file_left_alone` (file changed between read and write → `unsupported`, file keeps the new content); CLI `status` prints one JSON line.
- [ ] Step 2: run `python3 -B tests/shared-theme.test.py` → FAIL (`status` missing).
- [ ] Step 3: implement. Installed check: Kitty `shutil.which("kitty")` or the config folder exists; Neovim `shutil.which("nvim")` or `~/.config/nvim` exists. Theme sources: Kitty `extras/kitty-pistachio-noir.conf`, `extras/kitty-noir.conf` → `pistachio-noir.conf`, `noir.conf`; Neovim `extras/neovim/colors/pistachio-noir.lua`, `extras/neovim/lua/pistachio-shared.lua`. Extras path = `Path(__file__).resolve().parents[2] / "extras"`.
- [ ] Step 4: run → PASS.

### Task 2: AppTheming service

**Files:**
- Create: `src/services/AppTheming.qml`
- Modify: `src/services/Store.qml` (`property bool themingIntegration: true`, `property var themingKeep: []`), `src/services/ShellSettings.qml` (publisher unchanged), `src/shell.qml` (add `AppTheming` to `background`)
- Test: `tests/app-theming.test.py` (real `AppTheming.qml`, stand-in `Store` with `saved`/`ready`, a stand-in `services/shared-theme.py` that records calls and prints states from a JSON file)

**Interfaces:**
- Consumes: Task 1 CLI.
- Produces: `AppTheming.enabled: bool`; `setEnabled(on: bool)`; `apps: var` (from the helper); `conflict: var` (first app with state `own` not in `themingKeep` while enabled, else null); `keep(id: string)`; `use(id: string)` (removes from keep, runs `setup`); `refresh()`.

- [ ] Step 1: tests: on start with Store ready → `status` run; an `available` app → `setup` called once; an `own` app → no setup, `conflict.id === "kitty"`; `keep("kitty")` → conflict null, stored; `use("kitty")` → `setup kitty`; `setEnabled(false)` → `undo` for each `following` app, conflict null; disabled at start → only `status`, nothing set up.
- [ ] Step 2: run → FAIL. Step 3: implement (one `Process` queue: commands run one after another). Step 4: run → PASS; production reload shows "Configuration Loaded" and the owner's apps report `following` with no file changed (compare `sha256sum` of `kitty.conf`, `init.lua` before/after).

### Task 3: Settings rows, dialog, reset, export, search

**Files:**
- Modify: `src/settings/SettingsContent.qml` (Colours group: `toggle("theming", "Theming integration", "Kitty and Neovim follow Colours. Your own app themes are asked about first.", () => AppTheming.enabled, AppTheming.setEnabled)` and one row per `AppTheming.apps` entry, id `theming-<id>`: subtitle by state — following "Follows Colours", own "Your own theme" + button "Use Pistachio", available "Not set up yet", missing "Not installed", unsupported the detail), `src/settings/SettingsDialog.qml` (mode `theming` while `SettingsHub.opened && AppTheming.conflict`: title "<Name> has its own theme", description "Use Pistachio Noir and Noir? Your config is backed up first.", buttons "Keep mine" → `AppTheming.keep(id)`, "Use Pistachio" → `AppTheming.use(id)`; below pairing/forget/restart in priority), `src/services/SettingsReset.qml` (appearance `themingIntegration:true, themingKeep:[]`, names), `src/services/Preferences.qml` (names), `src/services/prefs.py` (`("appearance","theming_integration","themingIntegration",bool_)`, `("appearance","theming_keep","themingKeep",` list of `kitty`/`neovim` only`)`), `src/settings/catalog.js` (`theming` row, Colours group, words "theme kitty neovim nvim apps integration")
- Test: `tests/settings-ui.qml` + `tests/settings.test.py` (AppTheming stand-in), `tests/prefs.test.py`

- [ ] Step 1: fixture checks: switch shows on by default; rows read the stand-in states; a conflict opens the dialog with the title; Keep mine → `kept` recorded, dialog closes, second conflict then shows; Use Pistachio → `used`. Step 2: run → FAIL. Step 3: implement. Step 4: `sh tests/settings.sh`, `python3 -B tests/prefs.test.py`, `sh tests/js.sh` → PASS.

### Task 4: Docs and live check

**Files:** `README.md`, `CLAUDE.md` (decision, owner's call 19 November 2026; service list in rule 4 gains `AppTheming`), `todos/TODO_19-11-26.md`.

- [ ] Step 1: live: Settings → Appearance shows both apps `following`; `kitty.conf` and `init.lua` hashes unchanged; no dialog. Step 2: docs. Step 3: final review, commit message as text.
