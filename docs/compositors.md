# Compositors: inventory of what is Hyprland-specific

Written 20 November 2026 (read-only pass; nothing was run against umbriel). Step one of "support for more
compositors" (TODO 20-11-26 item 3). Umbriel support will be **experimental** (owner, 20 Nov), built on
`experimental` after the `main` merge, with Hyprland behaviour unchanged.

Counts below are from `grep` on `src/` and `rust/` at commit `e0ad1e6`; line numbers drift, so search by name.

## The short answer

The seam is tighter than the 20 Nov TODO feared ("about 28 files"). The real coupling is in a few places:

- **Only two files import `Quickshell.Hyprland`:** `services/Compositor.qml` (617 lines, the adapter) and
  `services/FocusGrab.qml` (one line, `HyprlandFocusGrab {}`).
- 83 other mentions of Hyprland/hyprctl in 37 files: nearly all are **comments, labels and setting names**. Only
  two non-adapter files shell out to `hyprctl` (`NightLight.qml`, `About.qml`).
- The UI reads 33 members of `Compositor`; five of them carry most of the weight (see "Interface surface").
- Most of the shell is already compositor-neutral: `WlrLayershell` (71 uses), `PanelWindow` (34),
  `ScreencopyView` (9), `WlSessionLock` (2), `ToplevelManager` (2), `FloatingWindow` (3).

## 1. Inside `Compositor.qml` (the adapter, must be split per backend)

| Kind | What |
|---|---|
| Quickshell API | `Hyprland.usingLua` (8), `.toplevels` (4), `.refreshToplevels` (3), `.workspaces`, `.focusedWorkspace`, `.dispatch`, `.activeToplevel`; `onRawEvent` |
| `hyprctl` shell-outs | 6: game-layout and Zen-layout readers (`getoption`), the `hl(lua)` helper (`hyprctl eval`), binds reader |
| Lua/dispatch calls | about 30 (`hl.config`, `hl.dsp.*`, window rules, group tabs) |
| Raw events used | `configreloaded`, `openwindow`, `closewindow`, `activewindowv2`, `windowtitle*` |
| Hyprland-only data on each window | `lastIpcObject` (pid, floating, hidden, pinned, grouped, size/at, focusHistoryID); special workspace `special:minimized`; `address` is Hyprland's hex id |

Features that live here and are Hyprland by nature (need capability flags, hide or degrade elsewhere):

- tabbed groups (`setTabbed`, `isTabbed`, `styleGroups`, gather) and the group-tab styling
- minimise to `special:minimized` (`minimize`, `restore`, `restoreAll`, `minimized`)
- Zen layout and Game mode layout (`zenLayout`, `gameLayout`): runtime gaps, borders, animations, blur
- TUI square window corners (`styleTuiRounding`, `tuiHyprland` switch)
- `floatingPreset`, `togglePin`, `placeSettingsWindow`/`styleSettingsWindow` (window rules and dispatchers)
- the key-bind cheat sheet (`loadBinds`/`binds`, read from `hyprctl`)
- workspace presets (`savePreset`/`loadPreset`/`placeArrival`) and workspace names (`names`, kept in the shell's own file, so portable)
- `exit()` (the power menu's log out)

## 2. Outside the adapter: real touches

| Where | What | Notes |
|---|---|---|
| `services/FocusGrab.qml` | `HyprlandFocusGrab` | Used 7 times in 6 files: `Bar`, `TuiBar` (twice), `TrayPill`, `MediaPill`, `Launcher`, `panels/Wallpaper`. Needs a neutral fallback or a no-op; no `Quickshell.Wayland` equivalent was checked |
| `services/NightLight.qml` | `hyprctl hyprsunset temperature` and the `hyprsunset` process | `hyprsunset` is Hyprland's own tool; whether it works elsewhere is **not verified** |
| `services/About.qml` | `hyprctl version -j` for the version line | Easy: show the detected compositor instead |
| `services/SystemStats.qml` | a `hypr` row: the compositor process's CPU/RAM (Settings → System) | Process name needs to come from the backend |
| `services/ScreenShare.qml` | matches PipeWire nodes `xdg-desktop-portal-hyprland` / `xdph-streaming-*` | Umbriel has `xdg-desktop-portal-umbriel`; its node names are **not verified** |
| `services/Screenshots.qml`, `popups/ScreenshotPicker.qml` | `hyprpicker` (colour picker) | Likely wlroots-generic; **not verified** on umbriel |
| `rust/psc/src/doctor.rs` | `hyprctl` is a **Required** check ("nothing works: Hyprland only"); the test asserts the required set is `hyprctl, qs, wl-copy` | Must depend on the detected compositor |
| `rust/` otherwise | no other `hyprctl`/`HYPRLAND_*` use found by grep | `HYPRLAND_INSTANCE_SIGNATURE` appears only in `Compositor.qml` (`hyprInstance`) and CLAUDE.md's gotcha about restarts from a terminal |

## 3. Behaviours that depend on how Hyprland hands out focus

Comments in `WindowSwitcher.qml`, `Overview.qml`, `QuickChat.qml` and `Launcher.qml` record fixes for how Hyprland
returns keyboard focus and clears focus grabs ("with the keyboard held exclusively Hyprland's focus grab doesn't
clear", "Hyprland hands the keyboard back to the tab"). Another compositor may behave differently, so these are
**test items for the experimental backend**, not code to change now.

## 4. Settings, state and text (no behaviour; rename or gate)

- `tuiHyprland` (the "Hyprland integration" switch): `ShellSettings`, `Store`, `SettingsReset`, `prefs.rs`,
  `settings/catalog.js`, `SettingsContent`, `Launcher` (System → Experimental)
- `Store.saved.zenGaps`, `gameLayoutSaved`, `workspacePresets`: Hyprland values saved to put back
- Settings labels: System page "Hyprland", About page versions, `SettingsDialog` hint ("Find one with `hyprctl activewindow`")
- Text only: `WizardWelcome`, `Showoff` ("a shell for hyprland"), the quick chat's system prompt in `chat.rs`,
  `highlight.js` (a command list), `Lock.qml` (the recovery command in a comment), `ScreenShare`, `NightLight` and
  `GameMode` header comments
- About 12 repeated comment lines beside `WlrLayershell.namespace: "pistachio-bar|panel"` ("Hyprland blurs the
  shell's layers by name"). The layer names are a compositor-neutral hook; only the blur **rule** is Hyprland
  config, and it lives in the owner's config. Another compositor needs its own rule (umbriel has blur; not read)

## 5. Interface surface the UI actually uses

Members of `Compositor` read outside `Compositor.qml` (uses / files), most used first:

`windows` 27/15 · `nameOf` 20/9 · `activeWorkspace` 18/8 · `workspaces` 13/9 · `focusedWindow` 11/5 · `goto` 10/5 ·
`close` 9/4 · `fullscreen` 6/5 · `isTabbed` 6/4 · `focus` 5/4 · `sendWindow` 5/2 · `minimized` 5/2 · `setName` 4/2 ·
`restore` 3/3 · `toggleFloating` 3/2 · `placeSettingsWindow` 3/2 · `zenLayout` 3/1 · the rest 2 uses or fewer.

So the **core a backend must provide** is small: a window list, the focused window, the workspace list and active
workspace, goto/focus/close, names, and fullscreen. Everything else can be a capability flag.

## 6. What this means for the plan

1. The split is smaller than feared: one adapter file to divide, one more file to make neutral (`FocusGrab`), two
   shell-outs to move (`NightLight`, `About`), `doctor.rs` to make compositor-aware, then labels.
2. First backend work: the **core** in section 5 for umbriel over its IPC socket (`umbriel workspaces|windows|
   focused-window --json`, `umbriel subscribe`), with the rest behind `Compositor.has.<feature>` flags.
3. Verify before building (all marked "not verified" above): umbriel's `XDG_CURRENT_DESKTOP` value and whether it
   exposes foreign-toplevel/ext-workspace (decides whether `ToplevelManager` works there), `FocusGrab` equivalent,
   `hyprsunset`/`hyprpicker`/portal behaviour, how it blurs layers by namespace.
4. A fake backend for the isolated UI tests comes before any real second backend.
5. Hyprland stays the default and must not change: the existing suites (`layout`, `settings`, `bar`) are the guard.
