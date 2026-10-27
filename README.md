# Pistachio Noir Shell

A desktop shell for Hyprland, written in QML on [Quickshell](https://quickshell.org) 0.3.2, in the Pistachio Noir colours. It is made for a single-monitor desktop PC with wired networking.

What you get:

- **Bar:** a floating pill at the bottom with workspaces, the focused window, clock and notifications, and an Ethernet, Bluetooth and volume chip. It hides while a window overlaps it; point at the bottom edge of the screen to bring it back. Once you move the pointer away it waits a moment before hiding, so you can reach the tray pill.
- **Tray pill:** apps' tray icons in a second pill right of the bar, shown only while some app has one; it hides and returns with the bar.
- **Status chip:** Ethernet, Bluetooth and volume. While headphones or another device that reports its battery are connected, the Bluetooth icon shows the battery level instead (terracotta at 20 % or less); a crossed-out mic appears while the microphone is muted.
- **Quick settings:** Ethernet, Bluetooth (with the connected device's battery), Do not disturb and Night light tiles; a night light schedule (right-click the Night light tile); what's playing (cover, title, previous / play-pause / next) while a media player has something; volume (click the speaker icon to mute), brightness and night light warmth sliders; uptime, a launcher button and the power menu.
- **Notifications:** toasts above the bar and a notification centre with history, which survives restarts. Pointing at a card in the centre shows the app's actions (Open, Reply…) under it. Notifications are grouped by app, the newest group first: a group of two or more shows its newest card with the others folded behind it, and a click on its header (or Show all) opens or folds it; groups stay as you left them until the shell restarts. The header's ✕ clears just that app. A month calendar sits beside the centre (weeks from Monday, today marked); ‹ ›, the scroll wheel, ← → or h l change month, and Today or Home go back. The shell is the notification daemon. Do not disturb holds back toasts, except critical ones.
- **Remembered settings:** Do not disturb, night light (on/off, warmth, schedule), drop shadows and notification history are kept across restarts and reboots.
- **Launcher:** apps, windows, workspaces, system controls and Bluetooth devices, with fuzzy search. System mode has cards for audio, night light (on/off, warmth, schedule) and Bluetooth (on/off, battery, scanning), plus each app's volume, the output devices and Shell settings (drop shadows on or off, and Quiet in fullscreen: toasts wait while a fullscreen window, such as a game or a video, has focus, and go to the centre; on by default). Type a calculation such as `12*(3+4)` and the answer shows at the top.
- **Bluetooth pairing:** the shell is the pairing agent, so devices that show or ask for a code pair too (phones, keyboards). The question ("Pair with …?", the code to compare or to type) opens in the launcher.
- **OSD:** a volume and brightness indicator, which also names the new output device when the sound moves, e.g. to headphones as they connect.
- **Power menu:** lock, log out, suspend, reboot and shut down, over a blurred still of the screen.
- **Lock screen:** checks your password through PAM.
- **Admin password dialog:** the shell is the polkit agent, so apps that need admin rights (`pkexec`, GParted, an app managing system services) ask for your password in a dialog of its own, with details on which app asked and for what. Cancelling it never counts as a failed login.

## Requirements

Tested on Arch Linux with Hyprland 0.56.2 (Lua config) and Quickshell 0.3.2 on Qt 6.12. The shell also works with an older-style `hyprland.conf`.

| Need | Arch packages | Used for | If missing |
| --- | --- | --- | --- |
| Compositor | `hyprland` | everything; Hyprland only | nothing works |
| Shell runtime | `quickshell` (pulls in Qt 6, PAM, polkit) | everything | nothing works |
| Audio | `pipewire`, `wireplumber`, `pipewire-pulse` | volume, per-app volume, output devices, OSD; `wpctl` for the volume keys | no volume controls |
| Media | any player that speaks MPRIS (browsers, Spotify, mpv with `mpv-mpris`) | the media card in quick settings | the card stays hidden |
| Bluetooth | `bluez`, `bluez-utils`, with `bluetooth.service` running | Bluetooth tile, chip, launcher Bluetooth view | Bluetooth shows as off |
| Pairing agent | `python-gobject` | pairing devices that show or ask for a code, and devices asking to connect | only devices that need no code pair; the log says `bluetooth agent exited` |
| Polkit agent | `python-gobject`, `polkit` (its Python bindings come with it) | the admin password dialog | apps that need admin rights fail or hang; the log says `polkit agent` |
| Network | `networkmanager`, with `NetworkManager.service` running | Ethernet tile and chip (Quickshell only talks to NetworkManager) | Ethernet shows as unplugged |
| Brightness | `ddcutil`, and DDC/CI switched on in your monitor's own menu | brightness slider, brightness keys, OSD | the brightness slider is hidden |
| Night light | `hyprsunset` | Night light tile, warmth slider and schedule; the shell starts and stops it itself | the tile says "Not installed" |
| Idle lock (optional) | `hypridle`, with `extras/hypridle.conf` | locking after idle time, screen off, locking before any suspend | only the power menu's Suspend locks first |
| Power actions | `systemd` (already there) | suspend, reboot, shut down | |
| Terminal apps | `kitty`, or set `$TERMINAL` | launching apps marked `Terminal=true` | those apps don't start |
| Font | Manrope (weights 500 to 800), installed by `install.sh`; needs `curl` | all text | Qt falls back to another font |
| Mono font (optional) | `ttf-jetbrains-mono` | the details in the admin password dialog | another monospace font |

The `ddcutil` package already loads the `i2c-dev` module and gives the logged-in user access to the monitor, so it needs no group or module setup. Not every monitor supports DDC/CI; check with `ddcutil getvcp 10`.

Manrope isn't in the official repos, so `install.sh` downloads it: Google Fonts' variable TTF (every weight from 200 to 800 in one file) and its licence go into `~/.local/share/fonts/manrope/`. Not Fontsource's files: they name every weight "Manrope ExtraLight", so nothing matches "Manrope" and the shell falls back to another font. By hand: download `Manrope[wght].ttf` from [Google Fonts](https://fonts.google.com/specimen/Manrope) into that folder and run `fc-cache -f`.

For the tests in `tests/` you also need `nodejs` and `libnotify` (`notify-send`); `pw-cat` (part of `pipewire`) plays the silent test stream, and `gdbus` (part of `glib2`) asks the pairing and polkit agents their test questions.

## Installation

1. **Install the packages:**

   ```sh
   sudo pacman -S --needed hyprland quickshell pipewire wireplumber pipewire-pulse \
       bluez bluez-utils python-gobject networkmanager ddcutil hyprsunset kitty
   sudo systemctl enable --now bluetooth.service NetworkManager.service
   ```


2. **Put the repo somewhere permanent**, for example `~/projects/pistachio-shell`. The shell runs straight from it, so if you move it later, run `./install.sh` again.

3. **Run the install script** from the repo:

   ```sh
   cd ~/projects/pistachio-shell
   ./install.sh
   ```

   It links the repo's `src/` to `~/.config/quickshell/pistachio`, where Quickshell finds a config named `pistachio`, and `bin/psc` (see [psc](#psc)) to `~/.local/bin/psc`. It also installs the Manrope font (see Requirements). It warns if `~/.local/bin` isn't on your PATH or Quickshell isn't installed. Run it again after moving the repo to update the links. It never replaces a real file or folder that is in the way; it stops and tells you instead. By hand, it's:

   ```sh
   mkdir -p ~/.config/quickshell ~/.local/bin
   ln -s ~/projects/pistachio-shell/src ~/.config/quickshell/pistachio
   ln -s ~/projects/pistachio-shell/bin/psc ~/.local/bin/psc
   ```

4. **Remove what the shell replaces.** Only one notification daemon can run at a time, so stop and uninstall or disable `mako`, `dunst`, `swaync` or similar. A KDE Plasma session running at the same time (for example on another TTY) also owns the notification service: stop it with `systemctl --user stop plasma-plasmashell.service`. Drop other bars such as Waybar too. Don't autostart `hyprsunset` yourself: the shell runs its own copy.

5. **Try it** from a terminal inside Hyprland:

   ```sh
   psc        # the same as qs -c pistachio
   ```

   The log goes to that terminal. Errors show as `ERROR` lines. A warning starting `qt.qpa.wayland.textinput` is harmless.

6. **Start it with Hyprland.** In `~/.config/hypr/hyprland.lua`:

   ```lua
   hl.on("hyprland.start", function ()
     hl.exec_cmd("qs -c pistachio")
   end)
   ```

   With an older `hyprland.conf`, use `exec-once = qs -c pistachio`.

7. **Add the keybinds** from the next section.

### Updating and restarting

The shell reloads by itself when a file in `src/` changes, so pulling new code or editing it takes effect at once. To restart it fully, run `psc restart`. `psc log -f` follows the log of the running shell.

## psc

`psc` (Pistachio Shell Control, `bin/psc`) is a short form of `qs -c pistachio …`, in plain POSIX `sh`:

| Command | Does the same as |
| --- | --- |
| `psc` | `qs -c pistachio`: runs the shell in this terminal, with its log |
| `psc start` | `qs -c pistachio -n -d`: runs it in the background, unless it's already running |
| `psc stop` | `qs kill -c pistachio`, then waits until it has exited, forcing it after 5 s if it hangs |
| `psc restart` | `psc stop`, then `psc start` |
| `psc <target> <function> [args]` | `qs -c pistachio ipc call <target> <function> [args]`, e.g. `psc launcher toggle` |
| `psc ipc show`, `psc log -f`, `psc list`, `psc kill` | the same `qs` subcommand for this config |

`psc help` prints the list. `restart` waits for the old copy to exit before starting the new one, so the new one can take over the notification service.

## IPC commands

Everything a keybind needs goes through Quickshell's IPC:

```sh
qs -c pistachio ipc call <target> <function> [arguments]
```

`qs -c pistachio ipc show` (or `psc ipc show`) lists them all, and `psc <target> <function>` is the short form of each. They only reach a shell started with `qs -c pistachio` or `psc`; one started with `qs -p <path>` needs `qs -p <path> ipc call …` instead.

| Command | What it does |
| --- | --- |
| `launcher toggle` | opens the launcher in All mode, or closes it (whatever mode it shows) |
| `launcher apps`, `windows`, `workspaces`, `system`, `bluetooth` | opens the launcher in that mode, switches to it if the launcher shows another, or closes it if it already shows that mode; made for keybinds |
| `launcher open <mode>` | opens the launcher in a mode (`all`, `apps`, `windows`, `workspaces`, `system` or `bluetooth`) and never closes it |
| `launcher search <mode> <text>` | opens a mode with the search field filled in, e.g. `launcher search apps fire` |
| `quicksettings toggle` | opens or closes quick settings |
| `notifications toggle` | opens or closes the notification centre |
| `notifications toggleDnd` | turns Do not disturb on or off |
| `brightness up` / `brightness down` | changes monitor brightness by 5 % and shows the OSD |
| `power toggle` | opens or closes the power menu |
| `lock lock` | locks the screen |

Volume has no IPC command and needs none: keep the volume keys on `wpctl`. The OSD follows PipeWire, so it shows any volume change, whatever made it.

## Hyprland keybinds

A suggested set for `hyprland.lua`. The keys only avoid the stock config's binds; pick your own. `locked = true` keeps a bind working while the screen is locked, and `repeating = true` repeats it while held.

`shell` below uses the full `qs` command, which works everywhere. You can set it to `"psc "` instead if Hyprland's PATH includes `~/.local/bin`; this prints that PATH:

```sh
tr '\0' '\n' < /proc/$(pgrep -ix hyprland)/environ | grep '^PATH='
```

```lua
local mainMod = "SUPER"
local shell = "qs -c pistachio ipc call " -- or "psc "

-- launcher; or set the stock config's `local menu` to shell .. "launcher toggle" so SUPER + R opens it
hl.bind(mainMod .. " + space",       hl.dsp.exec_cmd(shell .. "launcher toggle"))
hl.bind(mainMod .. " + Tab",         hl.dsp.exec_cmd(shell .. "launcher windows"))
hl.bind(mainMod .. " + W",           hl.dsp.exec_cmd(shell .. "launcher workspaces"))
hl.bind(mainMod .. " + B",           hl.dsp.exec_cmd(shell .. "launcher bluetooth"))

-- panels
hl.bind(mainMod .. " + A",           hl.dsp.exec_cmd(shell .. "quicksettings toggle"))
hl.bind(mainMod .. " + N",           hl.dsp.exec_cmd(shell .. "notifications toggle"))
hl.bind(mainMod .. " + SHIFT + N",   hl.dsp.exec_cmd(shell .. "notifications toggleDnd"))

-- power menu and lock
hl.bind(mainMod .. " + Escape",      hl.dsp.exec_cmd(shell .. "power toggle"))
hl.bind(mainMod .. " + L",           hl.dsp.exec_cmd(shell .. "lock lock"))

-- brightness keys: replace the stock brightnessctl binds, which do nothing on a desktop monitor
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd(shell .. "brightness up"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(shell .. "brightness down"), { locked = true, repeating = true })

-- volume keys: keep the stock wpctl binds as they are
```

The same in an older `hyprland.conf` (`bindel` = repeating and working while locked):

```ini
bind = SUPER, space, exec, qs -c pistachio ipc call launcher toggle
bind = SUPER, A, exec, qs -c pistachio ipc call quicksettings toggle
bind = SUPER, N, exec, qs -c pistachio ipc call notifications toggle
bind = SUPER, Escape, exec, qs -c pistachio ipc call power toggle
bind = SUPER, L, exec, qs -c pistachio ipc call lock lock
bindel = , XF86MonBrightnessUp, exec, qs -c pistachio ipc call brightness up
bindel = , XF86MonBrightnessDown, exec, qs -c pistachio ipc call brightness down
```

Mouse and keyboard work inside each part too:

- **Bar:** click the clock for the notification centre and the status chip for quick settings. A click outside a panel closes it.
- **Tray pill:** left click opens or activates the app, right click opens its menu (in Pistachio colours; submenus open in place with a Back row, and Esc or a click outside closes it), middle click runs its secondary action, and scrolling goes to the app (e.g. a volume applet).
- **Quick settings:** click a tile to switch it on or off. Right-click the Bluetooth tile for quick connections: Bluetooth on/off and your paired devices (click one to connect or disconnect), plus "Pair new devices…", which opens the launcher's Bluetooth view. Right-click the Night light tile to set its schedule: a switch, and the times it turns on and off (− and + or the mouse wheel, in 15-minute steps). The schedule switches only at those two times, so switching by hand holds until the next one; the tile then reads "Until 07:00" or "From 20:00". Click the speaker icon to mute.
- **Launcher:** type to search; a calculation (`+ - * / ^`, brackets, `.` or `,` for decimals) in All or Apps mode shows its answer, which is only shown, not copied. Power actions come up by name or a common word for them (lock, log out / logout / sign out, suspend / sleep, reboot / restart, shut down / shutdown / power off / turn off). Lock happens at once; the others ask first ("Shut down?" with Cancel and Shut down), with Cancel chosen, so a second Enter does nothing. The keys are in the table below.
- **Bluetooth pairing:** pick a nearby device in the launcher's Bluetooth view, or let a device ask (the launcher opens for it). Depending on the device, it asks you to:
  - **compare a code:** pair only if the device shows the same 6 digits.
  - **type a code into the search field:** the PIN or 6-digit code the device shows (old devices often use 0000), then Enter.
  - **type a code on the device:** a keyboard shows the code to type on it, then Enter on that keyboard; a pistachio cursor follows the keys if the keyboard reports them.
  - **allow a connection:** a device that is paired but not trusted asks to use a service, such as audio.

  As with the power questions, Cancel or Decline is chosen first and ←→ choose. Esc or closing the launcher declines. Questions are declined while the screen is locked. Accepting a pairing also trusts the device, so it reconnects without asking.
- **Power menu:** L, E, S, R and P act at once; ←→ and Enter pick one; Esc or a click on the background closes it.

Launcher keys. The vim motions only work while Ctrl is held, so plain h j k l still type into the search, and the arrows keep working too:

| Keys | What they do |
| --- | --- |
| Tab, Shift+Tab | next or previous mode |
| ↑ ↓, or Ctrl+K Ctrl+J | move between results and rows |
| ← →, or Ctrl+H Ctrl+L | change a slider (volume, brightness, warmth, an app's volume) or a schedule time (15 min); move across the workspace grid or quick controls; elsewhere, move the cursor in the search |
| Enter | open, switch to or select the row; flips a switch row (Night light, Schedule, Bluetooth) |
| Shift+Enter | on a workspace: move the last focused window there |
| Ctrl+W | close the selected window |
| Ctrl+M | mute |
| Ctrl+Backspace | forget the selected Bluetooth device |
| Esc | close; on a power question, go back to the results; on a Bluetooth question, decline it |

## Lock screen

The lock screen checks your password with PAM's `login` stack, as other screen lockers do. That includes Arch's `pam_faillock`: three wrong passwords within 15 minutes lock the account for 10 minutes, the TTY included. A correct password resets the count.

Suspend in the power menu locks the screen first, so the machine wakes up locked. For locking after idle time, turning the screen off, and locking before every suspend (also `systemctl suspend` from a terminal), install `hypridle`, copy the repo's template and start it with Hyprland:

```sh
sudo pacman -S hypridle
cp ~/projects/pistachio-shell/extras/hypridle.conf ~/.config/hypr/hypridle.conf
```

```lua
-- in hyprland.lua's autostart block
hl.exec_cmd("hypridle")
```

The template locks after 10 minutes idle and turns the screen off after 15; change the `timeout` values to taste.

If the shell crashes while the screen is locked, Hyprland keeps the session locked and shows a red "lockscreen app died" screen. To get back in, switch to a TTY (Ctrl+Alt+F3), log in, and run:

```sh
hyprctl --instance 0 eval 'hl.clear_crashed_lockscreen()'
```

Then switch back to Hyprland with Ctrl+Alt+F and the TTY number shown in the top-left corner of the red screen, and restart the shell.

## Login screen

`extras/sddm/` has a login screen theme for SDDM in the same style:
- **Centre:** clock and date, your picture and name, and the password field.
- **Bottom-left:** a session menu and the keyboard layout.
- **Bottom-right:** suspend, reboot and shut down.

SDDM isn't part of the shell, and the theme works on its own: it brings its own copy of the colours and the Manrope font, because SDDM runs as a separate user that can't see your home folder. More detail is in [extras/sddm/README.md](extras/sddm/README.md).

1. **Try it first (optional).** This opens the theme in a window, without SDDM. Type `test` as the password to "log in"; anything else shows the wrong-password message:

   ```sh
   ~/projects/pistachio-shell/extras/sddm/preview.sh
   ```

2. **Install SDDM:**

   ```sh
   sudo pacman -S sddm
   ```

3. **Copy the theme into SDDM's theme folder:**

   ```sh
   sudo cp -r ~/projects/pistachio-shell/extras/sddm/pistachio-noir /usr/share/sddm/themes/
   ```

   SDDM reads only this copy, so after you change the theme in the repo, run the command again.

4. **Select it:**

   ```sh
   sudo mkdir -p /etc/sddm.conf.d
   printf '[Theme]\nCurrent=pistachio-noir\n' | sudo tee /etc/sddm.conf.d/theme.conf
   ```

5. **Check it in SDDM's test mode.** Login and the power buttons do nothing here:

   ```sh
   sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/pistachio-noir
   ```

6. **Make SDDM your login manager.** `systemctl status display-manager` shows the current one, if any. Turn that off and SDDM on, then reboot:

   ```sh
   sudo systemctl disable gdm   # or lightdm, ly, …: whichever the status showed
   sudo systemctl enable sddm
   ```

   At the login screen, pick **Hyprland** in the session menu (bottom left) once; SDDM remembers it.

7. **Your picture and a wallpaper (optional).**
   - **Picture:** save a square image as `/usr/share/sddm/faces/<your user name>.face.icon`. Without one, a placeholder shows.
   - **Wallpaper:** put an image in `/usr/share/sddm/themes/pistachio-noir/` and set `background=` to its file name in that folder's `theme.conf`.
   - **12-hour clock:** set `clockFormat=h:mm AP` in the same `theme.conf`.

**If the login screen doesn't come up:** switch to a TTY (Ctrl+Alt+F3), log in, and read the errors with `journalctl -b -u sddm`. To go back, run `sudo systemctl disable sddm`, re-enable your previous login manager, and reboot.

## Troubleshooting

- **No toasts:** another notification daemon owns the service. Check with `busctl --user status org.freedesktop.Notifications`, and see step 4.
- **Two bars:** two copies are running. `qs list --all` shows them; `psc restart` leaves one.
- **Brightness slider missing:** the monitor didn't answer. Run `ddcutil getvcp 10` and turn on DDC/CI in the monitor's menu.
- **Night light tile says "Not installed":** install `hyprsunset`.
- **A device that shows a code won't pair:** `psc log` shows a `bluetooth agent` line when the pairing agent can't start or register; install `python-gobject` if it says so. While the shell runs it is BlueZ's default agent, so it also takes over from another one, such as a KDE session's.
- **An app that needs admin rights fails or hangs without asking:** no polkit agent runs. `psc log` shows a `polkit agent` line when the shell's can't start or register: install `python-gobject` if it says so, and stop any other agent for this session (polkit takes one per session, e.g. `polkit-gnome` or `hyprpolkitagent` started from the Hyprland config).
- **An app's tray icon doesn't show:** the shell shows StatusNotifierItem icons, which most current apps use; apps with only the old X11 tray don't appear. Icons an app marks as passive (idle) are left out on purpose.
- **App icons missing in the launcher:** Qt couldn't find an icon theme. Install one, for example `papirus-icon-theme` or `breeze-icons`, and select it in `qt6ct`, which needs `hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")` in `hyprland.lua`.
- **A change in `src/` didn't show:** reloading occasionally misses a save; restart the shell (see "Updating and restarting").

## Repository layout

```
pistachio-shell/
├─ bin/psc     the control command
├─ install.sh  links src/ and bin/psc into place
├─ extras/     hypridle.conf (idle locking) and sddm/ (the login screen theme, see extras/sddm/README.md)
├─ src/        the shell: shell.qml, Theme.qml, and bar/ panels/ popups/ launcher/ lock/ components/ services/
├─ tests/      checks against the live system (see CLAUDE.md, working rule 9)
├─ design/     one HTML board per screen; open design/index.html. The visual source of truth
├─ docs/       plan.md (architecture, components, build phases) and audio-bluetooth.md
└─ CLAUDE.md   decisions and working rules for Claude Code
```
