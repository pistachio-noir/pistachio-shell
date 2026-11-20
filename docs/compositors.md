# Compositors: inventory of what is Hyprland-specific

Written 20 November 2026 (read-only pass; nothing was run against another compositor). Step one of "support for more
compositors" (TODO 20-11-26 item 3). Umbriel was dropped (owner, 20 Nov); niri is the candidate second
compositor, still a discussion (section 7), built on `experimental` with Hyprland behaviour unchanged.

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
| `services/ScreenShare.qml` | matches PipeWire nodes `xdg-desktop-portal-hyprland` / `xdph-streaming-*` | Another compositor's portal creates differently named nodes (niri's docs name `xdg-desktop-portal-gnome` for screencasting); names **not verified** |
| `services/Screenshots.qml`, `popups/ScreenshotPicker.qml` | `hyprpicker` (colour picker) | Likely wlroots-generic; **not verified** on niri |
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
  config, and it lives in the owner's config. Another compositor needs its own rule (niri has `layer-rule` with `background-effect { blur true }` matching `namespace`; see section 7)

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
2. First backend work: the **core** in section 5 for the second compositor over its IPC, with the rest behind
   `Compositor.has.<feature>` flags.
3. Verify before building (all marked "not verified" above): the new compositor's protocols, a `FocusGrab`
   equivalent, `hyprsunset`/`hyprpicker`/portal behaviour.
4. A fake backend for the isolated UI tests comes before any real second backend.
5. Hyprland stays the default and must not change: the existing suites (`layout`, `settings`, `bar`) are the guard.

## 7. niri as the second compositor (discussion, 20 November 2026; nothing built)

Facts from the niri wiki (README, IPC, Tabs, Window Effects, Layer-Shell Components, Application Issues) and the
Quickshell 0.3.2 docs. Marked **not stated** where the pages say nothing.

**Quickshell side**
- 0.3.2 has **no built-in niri module**: only `Quickshell.Hyprland` and `Quickshell.I3` (i3/Sway IPC, no niri).
  A third-party plugin exists (next section); otherwise a backend talks to niri's own IPC itself.
- Generic pieces that don't care about the compositor: `PanelWindow`/`WlrLayershell` (needs `zwlr_layer_shell_v1`),
  `WlSessionLock` (ext-session-lock), `IdleInhibitor`, `ScreencopyView` of a **monitor**.
- Generic but dependent on what niri implements (**not stated** by niri's docs): `ToplevelManager`/`Toplevel` needs
  `zwlr-foreign-toplevel-management-v1`; `WlSessionLock` needs ext-session-lock; `IdleMonitor`/`IdleInhibitor` need idle protocols.
- **Not available on niri:** `HyprlandFocusGrab` (no generic grab type in 0.3.2), and `ScreencopyView` of a single
  **window** (needs `hyprland-toplevel-export-v1`), which the Alt+Tab switcher's window pictures use.
- No ext-workspace type exists in Quickshell 0.3.2, so workspaces must come from niri's IPC.

**niri side**
- IPC: JSON over the socket in `$NIRI_SOCKET` (also `niri msg --json …`); `niri msg --json event-stream` sends the
  full state first, then updates. Field and variant names are promised not to be renamed or removed; parsers must
  tolerate new ones. The request names, event names and the Window/Workspace fields are in the `niri-ipc` rustdoc,
  which was **not read**; only an example `FocusedWindow` (`id`, `title`, `app_id`, `workspace_id`, `is_focused`) was seen.
- Detection: `$NIRI_SOCKET`. `XDG_CURRENT_DESKTOP` is **not stated**.
- Layer shell and screencopy are supported; foreign-toplevel, ext-workspace, session lock, idle: **not stated**.
- Blur: `layer-rule { match namespace="^pistachio-" background-effect { blur true } }` in the config. Our
  `pistachio-bar` / `pistachio-panel` namespaces work as the hook, as on Hyprland. The page marks this "Since: 26.04".
- Layer rules: a fullscreen window draws above the top layer; only the overlay layer shows over it (same as our
  existing gotcha). Bottom/background layers get on-demand keyboard focus, exclusive only on an empty workspace.
- Workspaces are dynamic, vertical and per monitor, with one empty workspace always at the end. That differs from
  Hyprland's numbered workspaces that `goto(id)`, `nameOf`, Ctrl+1…0, workspace presets and the bar's workspace
  buttons assume. A mapping decision is needed (index vs id).
- Tabs: `toggle-column-tabbed-display` (a tabbed **column**), not Hyprland's groups. The shell's tabbed-workspace
  feature (`setTabbed`, gather, group tab styling) doesn't map.
- Not stated: runtime changes to gaps/borders/animations (the config live-reloads on save), minimise/hidden/special
  workspaces, a binds listing. So Zen and Game mode layout changes, Minimised windows and the binds cheat sheet
  would hide or degrade, never error.
- Config is KDL at `~/.config/niri/config.kdl`; the "never edit the compositor's config" rule would carry over.
- niri can run as a window inside another desktop (its docs say "mainly for development"), which would allow trying
  a backend without leaving Hyprland. That is a statement from the docs; **not tried here**.
- niri's README names Noctalia and Dux (DMS) as shells people run with it.

**Open questions for the owner:** how far to go (core only, or the full feature list); the workspace mapping; and
whether Alt+Tab keeps window pictures on niri (the monitor capture can't supply them).

**The `qml-niri` plugin** (github.com/imiric/qml-niri, found by the owner; read 20 Nov, not built or run)
- A Qt 6 C++ QML module, `import Niri`, MIT, version 0.4.0 (tag of 24 Oct 2026), 73 commits, one main author. It
  wraps niri's IPC: `Niri` with `workspaces`, `windows`, `focusedWindow`, `keyboardLayouts`, `overview`, `casts`.
- `Window`: `id`, `title`, `appId`, `pid`, `workspaceId`, `isFocused`, `isFloating`, `isUrgent`, column/tile
  indexes and sizes, `tilePosX/Y` (NaN if unavailable), `iconPath`. `Workspace`: `id`, `index`, `name`, `output`,
  `isActive`, `isFocused`, `isUrgent`, `activeWindowId`. Actions: `focusWorkspace(index)`, `focusWorkspaceById`,
  `focusWorkspaceByName`, `focusWindow(id)`, `closeWindow(id)`, `sendRawAction(action)` (anything else), keyboard
  layout switching, `overview.toggle()`. Actions return `{ ok, error? }`. No output/monitor object.
- Quickshell is not a dependency (a plain Qt module found through `QML_IMPORT_PATH` or `/usr/lib/qt6/qml/Niri`);
  needs Qt 6.5+ and, per its README, a niri tested at v26.04. Quickshell version compatibility: **not stated**.
- Risks: pre-1.0 (the README already deprecates `toggleOverview()` for removal in 0.5.0); no CI, only five manual
  test scripts; the README says most code was written with LLM help and then reviewed; no AUR package was
  mentioned, so a user builds it with `cmake`/`just`; it is a C++ build dependency in a project that otherwise keeps
  its helpers in Rust (`sendRawAction`'s argument format was not read).
- Two ways to use it: (a) as an **optional** dependency, loaded only when niri is detected (a Loader around the niri
  backend file, so a Hyprland machine without the plugin never imports it; **not tested** that a missing module
  fails only that file); (b) skip it and write a Rust helper (`psc niri`, JSON lines like the other helpers) on
  niri's socket, which needs the `niri-ipc` docs read first. Both would sit behind the same `Compositor` backend interface.

