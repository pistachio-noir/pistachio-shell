# Pistachio Noir Shell: Quickshell plan

Oct 25, 2026 · @sxnvte

## Decisions so far

We are building a Quickshell (QML) shell for Hyprland in Pistachio Noir. The visual design is done on the [design boards](../design/); this doc plans the code. Nothing is built yet.

- **Toolkit:** Quickshell 0.3.2 with QML. A from-scratch shell in C++ or Rust is a separate, later project. mangowm is dropped for now in favour of tighter Hyprland integration.
- **Look:** a compact pill, centred and floating at the bottom, soft and rounded. Only Pistachio Noir colours, with pistachio reserved for what is active.
- **Bar:** workspaces/tags and window title; clock, date and notification indicator; tray with Ethernet, Bluetooth and volume (a desktop PC, so no battery).
- **Other parts:** quick settings, notification popups and centre, OSD, power menu, lock screen, and an app launcher with modes for apps, windows, workspaces and system controls.
- **Behaviour:** the bar auto-hides when a window overlaps it. Motion is smooth fades and slides. Single monitor only.
- **Launcher vs Vicinae:** we build ours, and it replaces Vicinae: it does everything the owner used Vicinae for (decided 27 October 2026).

## Architecture

The shell UI reads from exactly two places: the `Compositor` adapter and the system services. Everything compositor-specific stays behind the adapter.

```
Hyprland
   |
Compositor.qml  (thin adapter, Hyprland backend only)
   |                                   System services
   +--> Shell UI  <-------------------  Audio, Bluetooth, Network,
        (bar, panels, popups,           Brightness, NightLight, Notifs
         launcher, lock)
```

The adapter is thin today, with a Hyprland backend only. It exists so another compositor can be added later without touching the UI.

## Project layout

One config folder, split by what each file is for: a theme singleton, services that wrap data sources, and UI folders that only read from them. Checked at step 1: the repo's `src/` is this folder (symlinked). A singleton is a file with `pragma Singleton` whose root type is `Singleton`, with no qmldir. Neighbouring files use it by name; files in subfolders add `import qs`.

```
~/.config/quickshell/pistachio/
├─ shell.qml            entry point, loads the parts below
├─ Theme.qml            singleton: colours, radii, sizes, durations
├─ services/
│  ├─ Compositor.qml    singleton: the adapter (next section)
│  ├─ (backend files, once a second compositor exists; Hyprland code lives in Compositor.qml until then)
│  ├─ Audio.qml  Bluetooth.qml  Network.qml  Brightness.qml  NightLight.qml  Notifs.qml
│  ├─ ScreenShare.qml  apps sharing the screen through the portal (its PipeWire video nodes)
│  ├─ Screenshots.qml  where screenshots go, and the notification after one (notify-send)
│  ├─ Lens.qml  lens.py  Claude/Codex CLI requests, follow-ups, fallback and saved snip chats
│  ├─ Clipboard.qml  copying text and pictures (wl-copy), and the emoji copied lately
│  ├─ Wallpapers.qml  the images in ~/Pictures/Wallpapers, the one in use and each one's fit
│  ├─ Weather.qml  Open-Meteo: now, the next hours and days, for the city in Store
│  ├─ Polkit.qml  the polkit agent, through pistachio-auth from rust/ (Quickshell's own counts Cancel as a failed login)
│  ├─ SystemStats.qml  stats.sh  CPU, memory, GPU and disk readings for Settings → System monitor, and the warnings
│  ├─ Files.qml  files.py  the launcher's "/" search through the home folder
│  ├─ Showoff.qml  showoff mode: the stage workspace, fastfetch's config and its terminal
│  ├─ Desktop.qml  the Desktop folder's files and folders for the desktop icons, where each sits, and acting on them
│  ├─ Drives.qml  removable drives: pistachio-devices (rust/) mounts them, lsblk lists the mounted ones, eject
│  ├─ LocalSend.qml  LocalSend, through pistachio-localsend (rust/): devices nearby, sending, receiving (only while the app is installed)
│  ├─ SettingsHub.qml  settings-window navigation, validated text edits and folder/source actions
├─ bar/                 Bar, Workspaces, WindowTitle, ClockChip, StatusChip, TrayPill (+ TrayMenu), MediaPill
├─ panels/              QuickSettings, NotificationCentre, Calendar (+ calendar.js, MonthPage), PowerMenu, PolkitDialog, WindowSwitcher, Wallpaper (the desktop) and DesktopIcons, WallpaperSwitcher, WeatherPanel
├─ popups/              Toasts, Osd (+ PrivacyWatch, its mic and screen sharing cues), ScreenshotPicker, PistachioRain (the easter egg)
├─ launcher/            Launcher, ModeTabs (Apps, Windows, Workspaces, basic System controls)
├─ settings/            SettingsWindow, page content, search catalog, shared controls and edit/pairing dialogs
├─ lock/                Lock
└─ components/          Chip, IconButton, Slider, Switch, Pill, ActionButton (a notification's action, for toasts and the centre), NotificationPreview (a screenshot under its notification), WallpaperView (a cross-fading wallpaper)
```

TUI appearance (13 November 2026; plan `superpowers/plans/2026-11-13-tui-style.md`): `Theme.tui` switches every surface live. Where the layout differs a lot, a separate TUI file draws it and the Classic one stays as it was, chosen by a `LazyLoader`/`Loader` or by visibility, with one controller and one set of services: `bar/` ClassicBar and TuiBar (+ TuiBarButton), `panels/` TuiQuickSettings (+ TuiLocalSendSending), TuiOverview (+ TuiOverviewWindow), TuiNotificationList, TuiCalendar, TuiWeather, TuiWindowSwitcher, `launcher/` TuiLauncherRow, `popups/` TuiQuickChat (QuickChat.qml stays its controller), `components/` PanelFrame (the framed box with title tabs), TuiControlRow, TuiBracket ("[k] label"). Elsewhere a file keeps one layout with `Theme.tui` conditions (Lens, toasts, OSD, power menu, menus, lock, capture tools, Settings); Theme's radii are 0 in TUI.

Rule: files under `bar/`, `panels/`, `popups/`, `launcher/`, `settings/` and `lock/` never import a compositor module directly. They use `Compositor` and the services.

## Compositor adapter

The adapter is one thin singleton, `Compositor`, with a Hyprland backend only. The bar, launcher and auto-hide code use only its API, so adding another compositor later touches one file.

| Adapter API | Used by | Hyprland source |
| --- | --- | --- |
| `workspaces` (id, name, occupied, urgent, active) | bar, launcher | `Quickshell.Hyprland` module |
| `focusedWindow` (title, appId) | bar | `ToplevelManager.activeToplevel` from `Quickshell.Wayland`: `Hyprland.activeToplevel` stays null until the first focus change |
| `windows` (address, title, appId, workspace, urgent) | launcher Windows mode | `Hyprland.toplevels`; `appId` from each one's `wayland` handle |
| `windowBounds` | auto-hide | No live property. `HyprlandToplevel.lastIpcObject` is Hyprland's client JSON (`at` and `size` as `[x, y]` and `[w, h]`, checked in phase 2) and only updates after `Hyprland.refreshToplevels()` |
| `binds` (`loadBinds`) | launcher's cheat sheet | `hyprctl binds -j`: a bind's keys from its modmask and key (names for mouse and media keys), and what it does from its `description` (a Lua bind reports only `__lua`) |
| `exec(command, rules)` | showoff mode | `hl.dsp.exec_cmd(cmd, { float = true, size = { w, h }, move = { x, y }, workspace = "3" })` (hyprlang: `exec [float; size w h; move x y; workspace 3] cmd`): Hyprland applies the rules to the window of the process it starts, so it opens in place |
| `goto`, `moveWindow`, `sendWindow`, `toggleFloating`, `focus`, `close` | launcher | Hyprland dispatchers, Lua or hyprlang by `usingLua`; windows are targeted as `address:0x…`. `moveWindow` follows the window, as Hyprland does by default; `sendWindow` doesn't (`follow = false`, hyprlang's `movetoworkspacesilent`). `toggleFloating` is `hl.dsp.window.float({ action = "toggle" })`. Checked by `tests/compositor.sh` |

With Hyprland only, there is no protocol to parse: the built-in module and Hyprland's dispatchers should cover the whole table. Checked at step 1: `Hyprland.workspaces` (`id`, `name`, `active`, `focused`, `urgent`), `Hyprland.activeToplevel` and `Hyprland.toplevels` (`title`, `urgent`, `workspace`, and `appId` through the `wayland` handle), and `Hyprland.dispatch()`. Dispatcher syntax differs when `Hyprland.usingLua` is true.

Found at runtime in phase 2 (Hyprland 0.56.2, Lua config):

- Hyprland runs in Lua mode, so dispatchers are Lua: `hl.dsp.focus({ workspace = 2 })`, not `workspace 2`. `Compositor.goto()` picks the syntax from `usingLua`.
- `Hyprland.toplevels` holds `HyprlandToplevel` objects, though the docs label it `Toplevel`. Their `activated` reads false for the focused window at startup; the `wayland` handle's `activated` is right.
- The Hyprland, Networking and Bluetooth modules start empty and fill in a second or two after first use, so every binding must handle null and empty lists.

**Auto-hide rule.** The bar hides when any window on the current workspace intersects the bar's rectangle plus a small margin. A thin always-present strip at the bottom edge shows it again on hover. For this to work the bar must not reserve screen space (exclusive zone 0). There is no bottom gap, so tiled windows overlap the bar as well and it stays hidden while the workspace has windows. While the focused window is fullscreen (`Compositor.fullscreen`, the Wayland toplevel's own state: Hyprland's maximized mode reads as `maximized`, not fullscreen, checked) the strip goes and the handle fades, so a stray pointer at the edge can't bring the bar up over a game (owner's request, after phase 8); a panel opened by keybind still shows it.

## Theme and motion

`Theme.qml` is the only place with colours, sizes and durations; every other file reads from it. Values come from the design canvas.

| Token | Value | Role |
| --- | --- | --- |
| `bg` | #15170F | window and editor background |
| `bgAlt` | #1D2016 | bar, panels, popups, launcher |
| `overlay` | #2A2F1F | chips, tiles, hover |
| `overlay2` | #39412A | selected row, pressed chip, outlines |
| `muted` | #626F51 | inactive dots, disabled (not for small text) |
| `subtext` | #A3B08F | secondary text |
| `text` / `textBright` | #E5E9D8 / #F6F8EF | body / emphasis |







Motion rules, so everything feels the same:


- Popups fade in and rise about 12 px. Panels grow from the chip that opened them.


























































| 4 | Quick settings: audio, Bluetooth, Ethernet, brightness, night light | every slider and toggle changes the real system state |

| 6 | Launcher: apps first, then Windows, Workspaces and System modes | you can launch apps, switch windows and workspaces and set volume from it; decide here about Vicinae |

| 8 | Motion polish (auto-hide was pulled forward and built right after phase 3, at the owner's request) | every transition uses the one easing curve and the 120 / 200 ms durations; auto-hide still works with the panels from phases 4–7 open |

## Risks and open questions

Dropping mangowm removes the biggest integration risk. What remains is mostly API details not yet checked against the 0.3.2 docs.

- **Auto-hide needs window geometry** from Hyprland, which has no live property: refresh with `Hyprland.refreshToplevels()` on Hyprland events and read `at` and `size` from `lastIpcObject`.

- **One notification daemon at a time.** Stop any existing daemon before step 5.

- **Real app icons.** The mockups use placeholder glyphs; the launcher must resolve icons from the system icon theme.

Questions for you:

- [x] Which Vicinae features do you use besides app launching (clipboard history, calculator, snippets)? None the launcher lacks: it replaces Vicinae.


## Later: the from-scratch version

A full rewrite in C++ or Rust is out of scope now. To keep that door open, keep three things independent of QML: the design tokens (plain values in `Theme.qml`), the adapter's API table above, and the list of components and their data sources. A later Rust shell could reuse all three, and mangowm can come back as a second backend behind the adapter. A small Rust helper for the launcher's app index and fuzzy search is the natural first Rust piece, added only if doing that in QML feels slow or awkward.


## Selected feature extension — 11 November 2026

Owner-approved scope: `superpowers/specs/2026-11-11-selected-features-design.md`. Capture setup/countdown/pause/trim and output mode extend Screenshots; Lens adds owned multi-image snapshots and an explicit two-source/single-synthesis request. SystemHealth, MicCheck and SettingsReset back their existing Settings pages. LauncherTools owns saved pin/alias validation, preview/MIME operations, launch feedback and temporary background jobs; LauncherExtras/JobCard draw them. Magnifier paints a click-through live view and reads pointer/zoom state from Compositor. All use current Theme/Reveal motion; no Hyprland configuration is changed. Deferred preferences portability belongs to Claude; launcher multi-selection remains later.
