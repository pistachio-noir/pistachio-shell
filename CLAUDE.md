# Pistachio Noir Shell

A Quickshell (QML) desktop shell for Hyprland on a single-monitor desktop PC (Arch), in the Pistachio Noir colour scheme. All eight build phases (skeleton, bar content, Compositor adapter, quick settings, notifications, launcher, OSD/power menu/lock screen, motion polish) are done, and the bar auto-hides: the config lives in `src/`, linked to `~/.config/quickshell/pistachio`. The design is done and the plan is written; this repo is where the code gets built.

Read these first:

- `README.md`: requirements, installation, IPC commands and Hyprland keybinds, for the owner. Keep it in step when commands or requirements change.
- `docs/plan.md`: architecture, folder layout, theme tokens, components, build phases, risks.
- `docs/audio-bluetooth.md`: PipeWire, BlueZ, brightness and OSD design, with property names checked against the Quickshell 0.3.2 docs.
- `design/*.dc.html`: one HTML board per screen. Open `design/index.html` in a browser. These are the visual source of truth for sizes, radii, spacing and colours.

## Decisions (already made, do not reopen)

- Toolkit: Quickshell 0.3.2 with QML. A from-scratch shell in C++ or Rust is a separate, later project.
- Compositor: Hyprland only. mangowm is dropped for now. Keep a thin `Compositor` singleton so UI files never import a compositor module directly.
- Single monitor. Desktop PC: no battery, no UPower, no `Power.qml`. Wired network (Ethernet), no Wi-Fi.
- Bar: floating, centred pill at the bottom, 640 x 56, radius 28, 16 px above the bottom edge. It auto-hides when a window overlaps it (exclusive zone 0, thin bottom-edge strip reveals it on hover). No Hyprland bottom gap: tiled windows overlap the bar too, so it stays hidden while the workspace has windows (owner's call).
- Hyprland config: `~/.config/hypr/hyprland.lua` is Hyprland's stock default on a test install. The owner writes their own after a reinstall, so never edit it or tune the shell to it.
- Bar content: workspaces and window title, clock, date and notification indicator, status chip with Ethernet, Bluetooth and volume. Tray icons go in a second pill right of the bar, shown only while some app has one (owner's request, after phase 8). The bar stays centred by itself; the pair is not re-centred (owner's call).
- Other parts: quick settings (Ethernet, Bluetooth, Do not disturb, Night light tiles; volume, brightness and night light warmth sliders; uptime and power button), notification popups and centre, OSD, power menu, lock screen, app launcher, a polkit password dialog (owner's request, after phase 8; boards `design/polkit-*.html`), and a month calendar beside the notification centre (owner's request, after phase 8; board `design/calendar-notifications.html`; dates only, weeks from Monday).
- Launcher modes: Apps, Windows, Workspaces, System (volume, brightness, outputs), Bluetooth. It may replace Vicinae; decide after build phase 6.
- No overview (zoomed-out workspaces) in the shell: the owner uses a Hyprland plugin for that if needed. Window capture of every workspace works (checked), should this ever come back.
- Launcher keys: the arrows, plus Ctrl+H J K L as vim motions (owner's request, after phase 8). Keep both working, and keep plain letters typing into the search.
- Motion: smooth fades and slides, one easing curve (ease-out), 120 ms for hover and about 200 ms for fades and slides. Windows open and close through `components/Reveal.qml`: set the window's `open`, never its `visible`, so it stays up until its fade-out ends.

## Style rules

- Colours come only from `Theme.qml`. No hard-coded hex values elsewhere.
- Palette: bg #15170F, bgAlt #1D2016, overlay #2A2F1F, overlay2 #39412A, muted #626F51, subtext #A3B08F, text #E5E9D8, textBright #F6F8EF, pistachio #9FD88A (active state only), terracotta #DB8267, gold #E0B15E, sageBlue #7DA3B3, teal #7FC9A8, lavender #AC8ED0, clay #D9975A.
- `muted` is only about 3.4:1 on bg, so never use it for small text; use `subtext`.
- Pistachio marks what is active: current workspace, toggles that are on, slider fills, the cursor, and the selected-row chip (pistachio background with bg-coloured text). No accent borders and no large pistachio fills.
- Fonts: Manrope (weights 500 to 800) for the UI, JetBrains Mono for code-like text. Numbers use tabular figures.
- Shapes are soft: radius 28 for panels, 20 for chips and tiles, fully round for icon buttons.
- Panels and popups have the boards' drop shadows (`components/Shadow.qml`, sizes in `Theme.qml`), which the launcher's Shell settings can switch off; the bar and the tray pill stay flat. A window with a shadow needs room around its panel for it, masked so clicks pass through (see "Theme and motion" in `docs/plan.md`).

## Working rules for Claude Code

1. Verify any Quickshell module, type or property against https://quickshell.org/docs/v0.3.2/ before using it. Module and type names in `docs/plan.md` were checked in phase 1 (`SystemClock` and `DesktopEntries` are in `Quickshell`, `IpcHandler` in `Quickshell.Io`); check their properties when you first use them. `docs/audio-bluetooth.md` records how its open questions were settled (pairing agent, per-app volume filter, brightness IPC).
2. Follow the build phases in `docs/plan.md` in order, one at a time. After each, run the shell and check it against the matching board in `design/`.
3. Quickshell reloads on save. Run it with `qs -c pistachio` and read its log for QML errors before saying something works. The owner may already be running it (`qs -p src` or `qs -c pistachio`): check with `pgrep -ax qs` (the process is `qs`, not `quickshell`), because a second copy means two bars and only one can own the notification bus name. Reach an instance started with `-p src` via `qs -p src ipc call …` (`-c pistachio` looks up the symlinked path and misses it). `bin/psc` (linked as `~/.local/bin/psc`) wraps `qs -c pistachio`: `psc restart`, `psc <target> <function>`; `install.sh` links `src/` and `psc` into place; keep both and the README in step. Live reload only notices real writes: `touch`, `sed -i` (which replaces the file) and rewriting a file with the same content do not trigger it, so edit files in place. Even a real edit is sometimes missed (twice in one session, cause unknown): after each save, check the log for "Reloading configuration", especially when removing temporary test code.
4. Keep services (`Apps`, `Audio`, `Bluetooth`, `Network`, `Brightness`, `Media`, `NightLight`, `Notifs`, `Polkit`, `Session`, `ShellSettings`, `Store`, `Tray`, `Uptime`) and the `Compositor` adapter as the only places that touch system data. UI files only read from them.
5. Only one notification daemon can run at a time. Stop any existing one before testing notifications. On this test machine a KDE Plasma session may still be running on tty1; its `plasmashell` owns `org.freedesktop.Notifications` for both sessions (they share the user bus). Ask before stopping it (`systemctl --user stop plasma-plasmashell.service`; `start` brings it back).
6. Keep the existing screen locker bound as a fallback until the shell's lock screen is proven (the test machine has none, so the TTY is it). Keep a TTY available when testing the lock. If the shell dies while locked, run `hyprctl --instance 0 eval 'hl.clear_crashed_lockscreen()'` from the TTY. A live reload keeps the screen locked: singletons don't survive it, so `lock/Lock.qml` carries the lock state over with `PersistentProperties` (which doesn't work inside a singleton). Three wrong passwords lock the account for 10 min (pam_faillock), the TTY included.
7. The mockup sample content (window titles, device names, "1 Gbps", "3 h 12 min", "Until 07:00") is made up. Wire real data; do not copy the strings.
8. Night light uses `hyprsunset`, which the shell runs itself (CLI and IPC checked against the Hyprland wiki in phase 4; see `docs/audio-bluetooth.md`). Brightness uses `ddcutil` over DDC/CI, not `brightnessctl`: this desktop has no backlight device.
9. `node tests/fuzzy.test.js` and `node tests/calc.test.js` test the launcher's matcher and calculator, `node tests/calendar.test.js` the calendar's month grid. `tests/bluetooth-agent.sh` tests the pairing agent's protocol on the session bus, touching no Bluetooth state; `tests/polkit-agent.sh` does the same for the polkit agent and never starts PAM. `tests/compositor.sh`, `tests/services.sh` and `tests/notifications.sh` check the services against the live system; run them after changing a service. `notifications.sh` needs the notification bus name free, so stop the shell first. `services.sh` changes volume, per-app volume (on a silent `pw-cat` stream), Bluetooth power, monitor brightness and the night light schedule, checks that settings survive a restart of the test shell, and restores them; it never toggles Ethernet (that would cut the network).

## Gotchas found while building

- An inline `component` used inside the quick settings media card failed with "X is not a type", even with an empty body or declared first in the file; the same code as its own file (`components/MediaButton.qml`) works. It happened again with the calendar's `MonthPage` (now `panels/MonthPage.qml`), while `MonthButton` in the same file works. Cause unknown: if an inline component fails like that, move it to a file.
- Don't name a singleton after a QtQuick type: `State.saved` resolved to QtQuick's `State` and read as undefined (hence `Store`).
- Quickshell modules start tracking on first use: touch them at startup (the test harness does) or the first reads are empty. Mpris too.
- Tray menus are drawn by the shell (`bar/TrayMenu.qml`, `QsMenuOpener`). Don't go back to Qt platform menus (`QsMenuAnchor`, `display()`): they need `//@ pragma UseQApplication` and a restart, look unthemed, and a shell started in that mode hung while exiting. Keep an opener on every open menu level, or the app drops the entries of a submenu opened from it.
- Quickshell has no Bluetooth pairing agent. `services/bluetooth-agent.py` (python-gobject) is the shell's own, run by `Bluetooth.qml`. The system bus lets only root call an agent, so you can't fake BlueZ's questions to the real one: test with `--session` (as `tests/bluetooth-agent.sh` does), or run a copy of `src/` whose agent has that flag to see the launcher's questions.
- Quickshell's `PolkitAgent` starts PAM the moment a request arrives, so cancelling its dialog counted as a failed login for pam_faillock (checked); hence the shell's own agent, `services/polkit-agent.py`, which starts PAM only on submit. Testing with a real prompt (`pkexec /usr/bin/true`) costs a strike per wrong password: never more than one in a row (three lock the account for 10 min, the TTY included), and a correct password clears them. `faillock --user $USER` shows the count.
- `notify-send -i NAME` sends the icon name as the `image-path` hint (app icon empty), and Quickshell turns it into an unchecked `image://icon/NAME` image, which draws a magenta checkerboard when the icon theme lacks it; `Notifs.iconSource` checks such names with `Quickshell.iconPath(name, true)` first.
- Quickshell flags an app's playback stream as `isStream && isSink`, the opposite of what its docs suggest; a notification's `expireTimeout` arrives in milliseconds, though the docs say seconds.
- An item declared inside a `ListView` is not put in its `contentItem` (checked: `parent !== contentItem`), so it doesn't scroll with the rows; give it `parent: list.contentItem`. Compare on-screen positions (`mapToItem`) when checking such things: the launcher's selection chip matched its row in content coordinates while drawn `contentY` off.
- A Bluetooth adapter's `enabled` turns true the moment the shell writes it, while `state` is still `Disabled`; starting discovery then fails ("Resource Not Ready") and isn't retried. Wait for `Bluetooth.ready` (`state` is `Enabled`) before scanning.

## Open questions for the owner

- Which Vicinae features are used besides launching apps (clipboard history, calculator, snippets)?
