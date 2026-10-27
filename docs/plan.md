# Pistachio Noir Shell: Quickshell plan

Oct 25, 2026 · @sxnvte

## Decisions so far

We are building a Quickshell (QML) shell for Hyprland in Pistachio Noir. The visual design is done on the [design boards](../design/); this doc plans the code. Nothing is built yet.

- **Toolkit:** Quickshell 0.3.2 with QML. A from-scratch shell in C++ or Rust is a separate, later project. mangowm is dropped for now in favour of tighter Hyprland integration.
- **Look:** a compact pill, centred and floating at the bottom, soft and rounded. Only Pistachio Noir colours, with pistachio reserved for what is active.
- **Bar:** workspaces/tags and window title; clock, date and notification indicator; tray with Ethernet, Bluetooth and volume (a desktop PC, so no battery).
- **Other parts:** quick settings, notification popups and centre, OSD, power menu, lock screen, and an app launcher with modes for apps, windows, workspaces and system controls.
- **Behaviour:** the bar auto-hides when a window overlaps it. Motion is smooth fades and slides. Single monitor only.
- **Launcher vs Vicinae:** we build ours; whether it fully replaces Vicinae is decided after step 6 of the build phases.

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
│  ├─ bluetooth-agent.py  the pairing agent Bluetooth.qml runs (Quickshell has none)
│  ├─ Polkit.qml  polkit-agent.py  the polkit agent (Quickshell's own counts Cancel as a failed login)
├─ bar/                 Bar, Workspaces, WindowTitle, ClockChip, StatusChip
├─ panels/              QuickSettings, NotificationCentre, PowerMenu, PolkitDialog
├─ popups/              Toasts, Osd
├─ launcher/            Launcher, ModeTabs, providers/ (Apps, Windows, Workspaces, System, Bluetooth)
├─ lock/                Lock
└─ components/          Chip, IconButton, Slider, Switch, Pill
```

Rule: files under `bar/`, `panels/`, `popups/`, `launcher/` and `lock/` never import a compositor module directly. They use `Compositor` and the services.

## Compositor adapter

The adapter is one thin singleton, `Compositor`, with a Hyprland backend only. The bar, launcher and auto-hide code use only its API, so adding another compositor later touches one file.

| Adapter API | Used by | Hyprland source |
| --- | --- | --- |
| `workspaces` (id, name, occupied, urgent, active) | bar, launcher | `Quickshell.Hyprland` module |
| `focusedWindow` (title, appId) | bar | `ToplevelManager.activeToplevel` from `Quickshell.Wayland`: `Hyprland.activeToplevel` stays null until the first focus change |
| `windows` (address, title, appId, workspace, urgent) | launcher Windows mode | `Hyprland.toplevels`; `appId` from each one's `wayland` handle |
| `windowBounds` | auto-hide | No live property. `HyprlandToplevel.lastIpcObject` is Hyprland's client JSON (`at` and `size` as `[x, y]` and `[w, h]`, checked in phase 2) and only updates after `Hyprland.refreshToplevels()` |
| `goto`, `moveWindow`, `focus`, `close` | launcher | Hyprland dispatchers, Lua or hyprlang by `usingLua`; windows are targeted as `address:0x…`. `moveWindow` follows the window, as Hyprland does by default. Checked by `tests/compositor.sh` |

With Hyprland only, there is no protocol to parse: the built-in module and Hyprland's dispatchers should cover the whole table. Checked at step 1: `Hyprland.workspaces` (`id`, `name`, `active`, `focused`, `urgent`), `Hyprland.activeToplevel` and `Hyprland.toplevels` (`title`, `urgent`, `workspace`, and `appId` through the `wayland` handle), and `Hyprland.dispatch()`. Dispatcher syntax differs when `Hyprland.usingLua` is true.

Found at runtime in phase 2 (Hyprland 0.56.2, Lua config):

- Hyprland runs in Lua mode, so dispatchers are Lua: `hl.dsp.focus({ workspace = 2 })`, not `workspace 2`. `Compositor.goto()` picks the syntax from `usingLua`.
- `Hyprland.toplevels` holds `HyprlandToplevel` objects, though the docs label it `Toplevel`. Their `activated` reads false for the focused window at startup; the `wayland` handle's `activated` is right.
- The Hyprland, Networking and Bluetooth modules start empty and fill in a second or two after first use, so every binding must handle null and empty lists.

**Auto-hide rule.** The bar hides when any window on the current workspace intersects the bar's rectangle plus a small margin. A thin always-present strip at the bottom edge shows it again on hover. For this to work the bar must not reserve screen space (exclusive zone 0). There is no bottom gap, so tiled windows overlap the bar as well and it stays hidden while the workspace has windows.

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
| `pistachio` | #9FD88A | active only: current workspace, toggles on, slider fill, cursor |
| `terracotta`, `gold`, `sageBlue`, `teal`, `lavender`, `clay` | #DB8267, #E0B15E, #7DA3B3, #7FC9A8, #AC8ED0, #D9975A | status and small icons |

Sizes: bar 640 × 56, radius 28, 16 px above the bottom edge; chips 40 px high with radius 20; panels 380–400 px wide with radius 28; tiles radius 20. The wallpaper tone #0D0F09 in the mockups is a placeholder, not a theme token.

Motion rules, so everything feels the same:

- One easing curve (ease-out) and one duration scale: 120 ms for hover, about 200 ms for fades and slides.
- Popups fade in and rise about 12 px. Panels grow from the chip that opened them.
- The active workspace capsule animates its width between 8 and 26 px as focus moves.
- The bar hides by sliding down its own height plus margin while fading, and returns the same way.
- Closing runs the opening motion backwards. Each window has an `open` flag and a `Reveal` (`components/Reveal.qml`) that eases a 0–1 `progress` and keeps the window up until the fade-out ends; content binds its opacity and scale or offset to that progress. Toasts fade out sinking 12 px when they expire or are dismissed. The lock screen's content fades in over its plain background.
- Fonts: Manrope for the UI, JetBrains Mono for code-like text. Check both are installed; they are mockup choices.

## Components

Each piece, where its data comes from, and what is not built in. All module and type names were checked against the [0.3.2 module list](https://quickshell.org/docs/v0.3.2/types) at step 1.

| Component | Data source | Notes |
| --- | --- | --- |
| Bar window | `PanelWindow`, layer-shell via `Quickshell.Wayland` | anchored bottom, centred, exclusive zone 0 for auto-hide |
| Workspaces, window title | `Compositor` adapter | capsule animates; urgent dot in terracotta |
| Clock chip | `SystemClock` | opens the notification centre |
| Tray pill | `Tray` service (wraps `Quickshell.Services.SystemTray`) | `bar/TrayPill.qml`, a second pill 12 px right of the bar (owner's request; not on a board), only while some app has a tray icon. The bar stays centred on its own and the pair sits slightly right of centre, so the bar never moves when icons come and go (owner's call); passive icons are left out. The bar positions it and hides it with itself; its area counts for the overlap check and pointing at it keeps both up. Leaving either keeps both up for 400 ms more, so the pointer can cross the 12 px gap between them (without it both hid on the way, as the owner found), and an open tray menu keeps them up too. Left click activates (or opens the menu of a menu-only icon), right click opens the app's menu 12 px above the tray (`bar/TrayMenu.qml`: the app's entries read with `QsMenuOpener` and drawn by the shell in Pistachio colours, with separators, disabled entries, check boxes and radio dots; submenus open in place with a Back row; Esc or an outside click closes it, and an open menu keeps the bar up), middle click is the secondary action, scrolling goes to the app. KDE's `kded6` owned the watcher on the test machine; Quickshell registered with it |
| Status chip | `Quickshell.Services.Pipewire`, `Quickshell.Bluetooth`, `Quickshell.Networking` | opens quick settings. While a device that reports its battery is connected, its level (terracotta at 20 % or less) replaces the Bluetooth icon (owner's request); a crossed-out mic shows while the default input is muted |
| Quick settings | the same services, plus `Brightness` (`ddcutil`), `NightLight` (`hyprsunset`), `Notifs` (do not disturb) and `Uptime` (`/proc/uptime`) | a layer-shell `PanelWindow`, not a `PopupWindow`: grabbing popups fail unless opened by a click on the bar, so keybinds could not open it. `FocusGrab` (adapter wrapper of `HyprlandFocusGrab`) closes it on an outside click. Keybind: `qs -c pistachio ipc call quicksettings toggle`. A media card (owner's request; not on a board) sits between the tiles and the sliders while an MPRIS player has something: rounded cover art (`ClippingRectangle`), title, artist, previous / play-pause / next, dimmed when the player doesn't offer them; `Media` picks the player that is playing, else the one that played last. No progress bar: MPRIS position doesn't update on its own. Right-clicking the Night light tile opens its schedule over the panel (owner's request; not on a board): a switch and two `TimeStepper`s, 15-minute steps; `NightLight` switches only when the schedule's answer changes, so a manual toggle holds until the next change, and the tile reads "Until 07:00" / "From 20:00". The Bluetooth tile shows the connected device's battery. Clicking the volume icon mutes and unmutes. A search button left of the power button opens the launcher (owner's request). Right-clicking the Bluetooth tile opens quick connections over the panel (owner's request; not on a board): the power switch, up to five paired devices (click to connect or disconnect) and "Pair new devices…", which opens the launcher's Bluetooth view (the request goes through `Bar` to `shell.qml`, which owns the launcher). Both right-click cards use `components/Popover.qml` (the dimmed panel and the card), and `popup` makes sure only one shows. Checked by `tests/services.sh` |
| Remembered settings | `Store` (`FileView` + `JsonAdapter` in `Quickshell.statePath("state.json")`) | Do not disturb, night light on/off, warmth and schedule, and notification history, across restarts. `ready` turns true once the file is read (or found missing); nothing is saved before it, and saves wait 300 ms for a slider drag to settle. Named `Store`: a singleton called `State` is shadowed by QtQuick's `State` type. The test shell has its own state folder |
| Notifications | `Quickshell.Services.Notifications` | we become the notification daemon, so any other daemon must not run. `Notifs` holds the history, popups, seen/unread and do-not-disturb (which hides popups but keeps notifications). Body text is shown as plain text. Do not disturb lets critical notifications through. History survives restarts: notifications from before come back from `Store` as plain records (no actions, only file images), and ones a live reload already kept are matched by summary, body and app and not shown twice. Toasts sit centred over the bar, 16 px above it (owner's call: right-aligned looked off centre), newest nearest the bar, 5 s each (or the app's timeout, which arrives in milliseconds although the 0.3.2 docs say seconds); critical ones stay. Keybinds: `qs -c pistachio ipc call notifications toggle` / `toggleDnd`. Checked by `tests/notifications.sh` |
| OSD | `Audio` (PipeWire) and `Brightness` | `popups/Osd.qml`, 320 × 56, click-through, in the overlay layer. Volume shows on any PipeWire change, whoever made it, except in the first second and for a second after the output device changes; a new default output shows its name, a headphones or speaker icon and its volume, for 2.5 s (built after phase 8; not on the board); brightness only through IPC, because the monitor reports nothing. It sits where the pill is while the bar is hidden, else 16 px above the bar, and stays away while quick settings (same sliders) is open. Keybinds: `qs -c pistachio ipc call brightness up` / `down` (5 %); volume keys keep calling `wpctl` |
| Power menu | `Session` (`systemctl suspend` / `reboot` / `poweroff` via `Quickshell.execDetached`; Suspend locks first and waits for the lock to be confirmed, at most 2 s; `extras/hypridle.conf` covers idle locking and other suspends; log out through `Compositor.exit()`, Hyprland's exit dispatcher) | `panels/PowerMenu.qml`, full screen in the overlay layer, exclusive keyboard. The menu sits centred over a blurred, dimmed still of the screen (owner's request; not on the board): a `ScreencopyView` taken as it opens, blurred with `MultiEffect` (`QtQuick.Effects`) and dimmed with `bg` at 45 %. It waits for the still (at most 300 ms) so the still never contains the menu. Letter keys (L, E, S, R, P) act at once; ← → and Enter pick one; Esc or a click on the background closes. Opened by the power button in quick settings, or `qs -c pistachio ipc call power toggle` |
| Lock screen | `WlSessionLock` (`Quickshell.Wayland`), `PamContext` (`Quickshell.Services.Pam`) in `Session` | `lock/Lock.qml`. Hyprland supports the session-lock protocol (checked in phase 7). The password goes through PAM's `login` stack, as other lockers do, so pam_faillock applies: three wrong passwords in 15 min lock the account for 10 min, the TTY included. If the shell dies while locked, the screen stays locked; from a TTY run `hyprctl --instance 0 eval 'hl.clear_crashed_lockscreen()'` (tested). Keybind: `qs -c pistachio ipc call lock lock` |
| Polkit dialog | `Polkit`, which runs `services/polkit-agent.py` (python-gobject with polkit's `PolkitAgent` bindings) | Built after phase 8 (owner's request; boards `polkit-prompt`, `polkit-details`, `polkit-wrong-password`). Not Quickshell's `PolkitAgent`: it starts PAM the moment a request arrives, so even Cancel counted as a failed login for pam_faillock (checked: one strike per cancel). The shell's agent registers with polkit for the login session and starts PAM (polkit's setuid helper, through `PolkitAgent.Session`) only once a password is submitted, so Esc and Cancel cost nothing; Cancel waits while PAM checks a password, since stopping it then would count. The agent also names the app that asked (`polkit.subject-pid`, else `polkit.caller-pid`, from `/proc`) and the action's vendor (polkit's action list), which Quickshell's agent doesn't pass. `panels/PolkitDialog.qml`: full screen in the overlay layer, exclusive keyboard, the 440 px card over `bg` at 66 %; a click beside the card does nothing, so a stray one can't dismiss a request. Enter authenticates ("Checking…" while PAM decides), Esc cancels; a wrong password clears the field and shows PAM's own message if it sent one (e.g. the account is locked), else "Wrong password. Try again."; a second PAM question (e.g. a one-time code) replaces the placeholder. Requests queue and show one at a time. A live reload restarts the agent (singletons don't survive it). Checked by `tests/polkit-agent.sh` (no PAM) and by hand with `pkexec /usr/bin/true` |
| Launcher | `Apps` (wraps `DesktopEntries`), `Compositor`, the services | `launcher/Launcher.qml` builds each mode as a flat list of rows: All (quick controls, open windows; with a query: apps, windows, system), Apps, Windows, Workspaces (cards with a mini map of the real layout), System (cards for audio, night light and Bluetooth, app volumes, output devices), and Bluetooth inside System (power switch, paired devices with connect/disconnect, nearby named devices with pair; Ctrl+Backspace forgets, not plain Backspace, which edits the search). It scans only while the Bluetooth view is open, for at most a minute. Pairing questions from the agent (`Bluetooth.request`, built after phase 8; not on a board) take the place of the results like a power question and open the launcher in the Bluetooth view: a code to compare, a code to type on the device (with a pistachio cursor under the next key), or "Pair with …?" / "Let … use audio?", with Cancel or Decline chosen first; a PIN or passkey is typed into the search field, which takes only valid characters then and is read-only during the other questions; Tab is ignored until it's answered, and Esc or closing the launcher declines. Fuzzy match with highlighted letters in `launcher/fuzzy.js` (tested by `tests/fuzzy.test.js`). Windows and workspaces are snapshotted when it opens, so rows only change when you type or switch mode; the list is a plain array, because a `ScriptModel` left the previous mode's rows on screen. Terminal apps are wrapped in `$TERMINAL` (else kitty). System mode is built of cards (owner's request; the boards show plain rows): Audio (volume, brightness), Night light (a switch row with its status, warmth, a Schedule switch row and the two times) and Bluetooth (a switch row with the connected device and battery, and "Scan for devices", which opens the Bluetooth view). A card's rows stay separate list rows, each drawing its slice of the card's outline, so ↑↓, ←→ (warmth ±250 K, times ±15 min) and Enter (switches) work as everywhere else; a query shows a whole card when it matches its name or any row. It also lists each app playing sound under Apps, with its own volume slider (←→, Enter mutes). Power actions show under Power in All and System mode when the query matches their name or a common word for them (owner's request); all but Lock ask first: the results make way for a question with Cancel (chosen first) and the action, ←→ choose, Enter confirms, Esc or typing goes back. Ctrl+H J K L work like the arrow keys (vim motions, owner's request; plain letters still type). A query that is a calculation shows its answer at the top of All and Apps mode (`launcher/calc.js`, a small parser, no `eval`; tested by `tests/calc.test.js`); the answer is only shown, never copied (owner's call: no clipboard features). Keybinds: `qs -c pistachio ipc call launcher toggle`, `apps` / `windows` / `workspaces` / `system` / `bluetooth` (each opens its mode, or closes the launcher if it already shows it), `open <mode>`, `search <mode> <text>` |

## Audio, Bluetooth and brightness

Audio and Bluetooth each get one service singleton built on Quickshell's own PipeWire and BlueZ modules, with no command-line parsing. Quickshell has no Bluetooth pairing agent, so `Bluetooth.qml` runs a small one of its own (`services/bluetooth-agent.py`, Python on GLib's D-Bus) and talks JSON lines with it. Brightness uses `ddcutil`, and night light uses an external tool. The full design, with the property names checked against the 0.3.2 docs, is in the [Audio and Bluetooth doc](audio-bluetooth.md).

This is a desktop PC, so there is no battery and no `Power.qml` service: the status chip shows Ethernet, Bluetooth and volume only. The network tile means a wired link, with no Wi-Fi scanning or password prompts.

## Build phases

Eight steps, each ending in something you can see working. Everything targets Hyprland, whose integration is built into Quickshell.

| # | Phase | Done when |
| --- | --- | --- |
| 1 | Skeleton: `Theme.qml` and an empty pill; confirm folder name, singletons and module names | the pill floats 16 px above the bottom, centred, in the right colours, and reloads on save |
| 2 | Bar content: workspaces, window title, clock chip, status chip | it matches the Bar artboard and switching workspace moves the capsule |
| 3 | `Compositor` adapter: window list, window bounds and actions | the bar and the launcher's window data read from `Compositor`, never from the Hyprland module directly |
| 4 | Quick settings: audio, Bluetooth, Ethernet, brightness, night light | every slider and toggle changes the real system state |
| 5 | Notifications: popups, centre, do-not-disturb | `notify-send` shows a toast, the centre lists it, do-not-disturb silences new ones |
| 6 | Launcher: apps first, then Windows, Workspaces and System modes | you can launch apps, switch windows and workspaces and set volume from it; decide here about Vicinae |
| 7 | OSD, power menu, lock screen | lock and unlock work with your password, tested with a fallback way back in (a TTY) |
| 8 | Motion polish (auto-hide was pulled forward and built right after phase 3, at the owner's request) | every transition uses the one easing curve and the 120 / 200 ms durations; auto-hide still works with the panels from phases 4–7 open |

## Risks and open questions

Dropping mangowm removes the biggest integration risk. What remains is mostly API details not yet checked against the 0.3.2 docs.

- **Auto-hide needs window geometry** from Hyprland, which has no live property: refresh with `Hyprland.refreshToplevels()` on Hyprland events and read `at` and `size` from `lastIpcObject`.
- **Lock screen.** No other locker is installed on the test machine, so the TTY is the fallback until the shell's lock is proven; the crashed-lock recovery above was tested.
- **One notification daemon at a time.** Stop any existing daemon before step 5.
- **APIs.** Module and type names are checked; individual properties are still checked when each phase starts.
- **Real app icons.** The mockups use placeholder glyphs; the launcher must resolve icons from the system icon theme.

Questions for you:

- [ ] Which Vicinae features do you use besides app launching (clipboard history, calculator, snippets)?
- [x] Are you happy to set a Hyprland bottom gap of about 72 px so tiled windows stay clear of the bar? No: no gap, the bar auto-hides over any window.

## Later: the from-scratch version

A full rewrite in C++ or Rust is out of scope now. To keep that door open, keep three things independent of QML: the design tokens (plain values in `Theme.qml`), the adapter's API table above, and the list of components and their data sources. A later Rust shell could reuse all three, and mangowm can come back as a second backend behind the adapter. A small Rust helper for the launcher's app index and fuzzy search is the natural first Rust piece, added only if doing that in QML feels slow or awkward.
