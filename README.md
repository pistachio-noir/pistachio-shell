# Pistachio Noir Shell

A desktop shell for Hyprland, written in QML on [Quickshell](https://quickshell.org) 0.3.2, in the Pistachio Noir colours. It is made for a single-monitor desktop PC with wired networking.

What you get:

- **Bar:** a floating pill at the bottom with workspaces, the focused window, clock and notifications, and an Ethernet, Bluetooth and volume chip. It hides while a window overlaps it; point at the bottom edge of the screen to bring it back. Once you move the pointer away it waits a moment before hiding, so you can reach the tray pill. While a fullscreen window (a game, a video; not a maximized one) has focus, the bottom edge doesn't bring it back, so a stray pointer can't pop it up mid-game. When the shell starts, the wallpaper fades in and then the bar grows out of its handle (not on a live reload).
- **Tray pill:** apps' tray icons in a second pill right of the bar, shown only while some app has one; it hides and returns with the bar.
- **Media pill:** what's playing (cover, title, artist and a play/pause button) in a pill left of the bar, while a player has a track, paused too; it hides and returns with the bar. Click it for the media card above it, scroll over it to skip tracks, middle-click to play or pause. The media card (here, in quick settings and on the lock screen) shows the time played and the track's length under a bar you can click or drag to jump. When your Bluetooth headphones disconnect or run flat, whatever is playing pauses instead of carrying on out of the speakers (switching outputs by hand doesn't pause).
- **Status chip:** Ethernet, Bluetooth and volume. While headphones or another device that reports its battery are connected, the Bluetooth icon shows the battery level instead (terracotta at 20 % or less); a crossed-out mic appears while the microphone is muted, and a mic in orange (clay) while an app is recording from it; a screen in clay shows while an app shares your screen.
- **Quick settings:** Ethernet, Bluetooth (with the connected device's battery), Do not disturb and Night light tiles; a night light schedule (right-click the Night light tile); what's playing (cover, title, previous / play-pause / next) while a media player has something; volume (click the speaker icon to mute), microphone (click its icon to mute), brightness and night light warmth sliders; uptime, a launcher button and the power menu.
- **Notifications:** toasts above the bar and a notification centre with history, which survives restarts. Pointing at a card in the centre shows the app's actions (Open, Reply…) under it. Notifications are grouped by app, the newest group first: a group of two or more shows its newest card with the others folded behind it, and a click on its header (or Show all) opens or folds it; groups stay as you left them until the shell restarts. The header's ✕ clears just that app. A month calendar sits beside the centre (weeks from Monday, today marked); ‹ ›, the scroll wheel, ← → or h l change month, and Today or Home go back. The shell is the notification daemon. Do not disturb holds back toasts, except critical ones. A thin bar along each toast shows the time it has left, and pointing at the toast holds it. Right-click a toast or a card to silence its app for an hour or stop its toasts (they still reach the centre); launcher → System → Notification rules undoes that. Bluetooth devices that report their battery warn at 20 %, and urgently at 10 %, and headphones say so when they connect ("AirPods Pro connected · 80 %"). Notifications older than a week go by themselves; find an older one with `!` in the launcher (see Launcher). When one app sends three or more within a few seconds (a busy chat), they fold into one toast, "VESKTOP · 5 NEW" over the newest; the centre keeps each. A soft sound plays with each toast (once for a flood, never while toasts are held back); switch it off in launcher → System → Shell settings.
- **Remembered settings:** Do not disturb (on/off, schedule), night light (on/off, warmth, schedule), drop shadows and notification history (the last 200, for a week) are kept across restarts and reboots.
- **Launcher:** apps, windows, workspaces, system controls and Bluetooth devices, with fuzzy search. A click anywhere beside it closes it (that click only closes it; it doesn't reach the window under it), and so does anything else taking the keyboard (Alt+Tab, a screenshot). System mode has cards for audio, night light (on/off, warmth, schedule) and Bluetooth (on/off, battery, scanning), plus each app's volume, the output and input devices (an input with nothing plugged into it is greyed out: PipeWire won't switch to it), a System monitor card (CPU, memory and GPU load, temperatures, and free disk space, in terracotta under 10 %; live while it's on screen) and Shell settings (Frosted panels and its Glassy style, see [Frosted panels](#frosted-panels); drop shadows on or off, Showoff mode, Wallpapers, desktop icons on or off, the notification sound, the weather's location: Enter on it, type a city, Enter again, and it's looked up before it's saved, so a misspelt one isn't; Quiet in fullscreen: toasts wait while a fullscreen window, such as a game or a video, has focus, and go to the centre; on by default; Quiet during calls: the same while an app records from the microphone, such as a Discord call, so no toast or sound interrupts it; on by default; Headphones take over: Bluetooth headphones get the sound as they connect, even if you'd picked another output (PipeWire otherwise keeps the one you picked last, and a USB interface can outrank them); on by default; Volume tick: a short click as the volume changes, at the new level, so you hear it as you press the volume keys (not while you drag a slider; when nothing has played for a few seconds it comes a moment later, since a sleeping output mutes briefly as it wakes); on by default; and Terminal: the one for `$` commands, apps marked `Terminal=true` and showoff mode's fastfetch; Enter lists the terminals installed, as Bluetooth's Scan for devices lists devices, and Enter on one uses it (Esc goes back); at first `$TERMINAL`, else kitty). While a USB drive is mounted, a Drives section lists it; Enter ejects it (unmounts it and powers it off, then a notification says it can be removed). Apps mode starts with the apps you launch most and most lately (Frequent), and they also rise among equally good matches when you search. Search ignores accents: `zolty` finds "Żółty", and the other way round. In Windows mode, keys close, float or move the selected window (see the key table). → on an app with actions of its own (Helium's New incognito window, for one) lists them under it. And there's an easter egg: the Konami code (↑ ↑ ↓ ↓ ← → ← → B A) in the launcher. Type `?` for a cheat sheet: the search prefixes, the launcher's keys and your Hyprland binds, searchable (a bind says what it does if you give it a `description` in `hyprland.lua`: `hl.bind(keys, action, { description = "…" })`). The Audio card also has a microphone slider (Enter mutes it). Type a calculation such as `12*(3+4)` and the answer shows at the top; harder maths goes to libqalculate (`qalc`, optional): equations, functions, units, currencies and bases, either after `=` (`= solve(x^2 = 4)`, `= 30 EUR to PLN`, `= 0x1F to bin`) or by itself when the plain calculator can't read something that is clearly maths (`5 km to mi`, `sqrt(2)^10`), never for plain names; Enter copies its answer; type `:` and a name (`:fire`) for emoji, which Enter copies (a bare `:` lists the ones you copied lately first); type `$` and a command (`$btop`) to run it in your terminal (see Shell settings), which stays open to show what it printed (Shift+Enter runs it in the background, and a notification says when it's finished or failed, with the last line it printed; a bare `$` lists your recent commands); type `/` and a name (`/invoice`) to find files and folders in your home folder, which Enter opens (Shift+Enter opens the folder it's in; hidden folders, `node_modules` and cache folders are left out, and a query with a `/` in it, such as `/proj/main`, matches the path); type `!` and a word to find a notification by its title, text or app, which Enter shows in the notification centre (a bare `!` lists them all under Clear all, which asks first); type `@` and some words (`@hyprland window rules`) to search the web with DuckDuckGo in your browser; with Claude Desktop installed, type `claude` and a question (`claude what is a pistachio`) for an Ask Claude row on top, which opens a new chat in Claude Desktop with it (your usual results stay under it).
- **Bluetooth pairing:** the shell is the pairing agent, so devices that show or ask for a code pair too (phones, keyboards). The question ("Pair with …?", the code to compare or to type) opens in the launcher.
- **OSD:** a volume and brightness indicator, which also names the new output device when the sound moves, e.g. to headphones as they connect, and says when the desktop icons are shown or hidden. It names the apps that start recording from the microphone or sharing your screen, and says when they've all stopped (privacy cues, so they show even in Do not disturb and fullscreen).
- **Power menu:** lock, log out, suspend, reboot and shut down, over a blurred still of the screen.
- **Lock screen:** checks your password through PAM, over a blurred still of the desktop (kept in memory, never written to disk), with what's playing and its controls, and how many notifications came that you haven't seen ("3 new notifications": only the count, nothing they say). The password shows as dots that pop in as you type; a wrong one shakes the field. An empty Enter is ignored, so it can't cost a failed-login strike.
- **Weather:** above the calendar in the notification centre: now, today's high and low, and five days; the chevron opens the next hours (with the chance of rain) and the feels-like temperature, wind, humidity and sunset. From Open-Meteo for your city: set it in the launcher (System → Shell settings → Weather location) or with `weather city <name>`; the shell remembers it.
- **Desktop icons:** the files and folders in your Desktop folder, on the wallpaper (so wherever no window covers it), as rounded tiles with a glyph coloured by kind (folders sage blue, pictures show themselves, apps their icon). Click to select, double-click to open, drag to move (the place is kept; dropping on another icon swaps them). Drag out a box on the desktop to select several, or Ctrl+click to add or take away one (on a workspace without windows: elsewhere the desktop doesn't hear Ctrl); a drag then moves them all, and their menu opens or trashes them all. Drag icons onto a window (a Discord message, a browser's upload box) to hand it the files; drop files from another app (hyprfm) on the desktop to copy them there (copied, never moved; nothing there is overwritten). Right-click one for Open, Rename, Move to trash and Show in file manager; right-click the desktop for New folder, Open Desktop folder and Wallpapers. Renaming and naming a folder ask in the launcher. Hidden in showoff mode; switch them off in launcher → System → Shell settings → Desktop icons, or with `desktop toggle` (bind it to a key); the OSD says which.
- **LocalSend:** send files to phones and other computers on your network, and receive from them, from quick settings (only while the LocalSend app is installed; the shell does it itself, so the app itself shouldn't be running). Open the LocalSend row: add files (+), a folder, or paste copied files or text, or drop files on the page, then click a device under Nearby; the page shows the transfer and Cancel. With Receive files on (off until you switch it on, on the page or by clicking the row's icon, and remembered), devices see this PC under its hostname; each request waits in a toast for Accept or Decline, text messages show in the toast with Copy, and what arrives goes to `~/Downloads` with a notification to open the folder. The sliders on the page change the name, the folder, and whether devices you accepted before can send without asking. Right-click desktop icons for Send with LocalSend.
- **Workspaces:** scroll over the bar's dots for the next or previous workspace. Each switch shows the workspace OSD (its name or number, what's on it, and the dots; never over a fullscreen window; Shell settings → Workspace OSD). Name a workspace with F2 on its card in the launcher's Workspaces mode, or `workspace name <text>` for the one you're on (empty clears it): names show in the OSD, on the cards and in the dots' tooltip, and last until you log out. Type a name in the launcher to go there. Presets keep every workspace for good: in Workspaces mode, "Save workspaces as preset…" (their names) or "Save workspaces and apps as preset…" (also the apps open on every workspace); Enter on a preset (in Workspaces mode, or found by name in All) puts its names back and opens its apps on their workspaces in the background, skipping ones already there; → on a preset shows Delete (it asks first), as does Ctrl+Backspace. `workspace preset <name>` loads one from a keybind.
- **Peek at the bar:** `bar peek` brings the hidden bar out for 2 s, for a keybind (e.g. `hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("psc bar peek"))`).
- **Weather at a glance:** today's temperature and sky under the date on the lock screen, and in the clock's tooltip.
- **Keys on the desktop:** after a click on the desktop (on a workspace without windows), the arrows move the selection, Enter opens, Delete moves to trash, F2 renames, Ctrl+A selects all, Esc lets go.
- **About:** launcher → System → Shell settings → About (or `launcher open about`): the shell's version and last commit, Quickshell, Hyprland and Qt versions, and the source on GitHub (Enter opens it).
- **The shell's own use:** a Shell row in the launcher's System monitor: the CPU the shell and its helpers use (the meter, of the whole machine) and their memory.
- **Launcher scroll bar:** while you use the mouse over a long list, a thin bar at its right edge shows where you are; drag it or click its track to scroll. It fades a second after the mouse rests. Shell settings come in groups: Look, Sound, Quiet, Apps and places, More.
- **Launcher with the mouse:** right-click a row or a workspace card for what it offers: an app's own actions (a browser's New incognito window), a window's Switch, Float or tile and Close, a workspace's Go, Move the last window here, Name or Rename, Clear its name and Close its windows (asks first), a preset's Load and Delete, a device's Connect and Forget, a file's Open and Show in folder. The key hints at the bottom are buttons too (↵, Esc, Tab, →, Ctrl W…), and text cut short with "…" shows whole in a tooltip when you rest the pointer on it.
- **Cider:** with Cider's app token pasted in launcher → System → Shell settings → Cider token (make one in Cider: Settings → Connectivity → Manage External Application Access), the media card shows Up next (a click plays from there), and `m <words>` in the launcher searches Apple Music: Enter plays, Shift+Enter plays next, → adds to the queue.
- **More in the launcher:** your recent CLion projects and your games (Steam's, with covers, and Sober) come up as you type their names (`clion` lists every project, `games` every game); `kill <name>` lists your programs, busiest first, and ends one (asks first; Force quit in its right-click menu); `tldr <command>` shows tldr's description and examples (Enter copies one), and a row that opens the full manual (`man`) in your terminal.
- **Windows:** right-click a window row for Pin on top (Ctrl+P; it floats and stays above everything, on every workspace), and a workspace card for Move its windows to another workspace.
- **Tabbed workspaces, i3-style:** a workspace card's right-click menu → Tabbed (or `workspace tabbed` for the one you're on): its windows gather into one group under Hyprland's own tab bar, which the shell styles in the Pistachio look (pill tabs, the shown one pistachio, Manrope; set at runtime, your Hyprland config is untouched, and again after each config reload); new windows join it; click a tab to show it, middle-click to close it; the same entry tiles them again. It lasts until you log out. Right-click the bar for the same switch, and to name the workspace. An OSD says when tabs go on or off (Shell settings → Tabbed OSD). Alt+` is Alt+Tab for the tabs alone (`switcher tabs`; hold Alt, ` steps, Shift+` back, let go to show the one picked); bind it with `hl.bind("ALT + grave", hl.dsp.exec_cmd(shell .. "switcher tabs"))`. Keybind: `hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(shell .. "workspace tabbed"))`. The group's border takes your window border's colours.
- **Screenshot menu:** Colour (hyprpicker: click anywhere, the hex code is copied and shown with a swatch) and Record (gpu-screen-recorder: drag out an area, or click for the whole screen; the sound playing is recorded too; a red dot and the time on the bar while it runs, click it to stop; the video goes to `~/Videos`). The screenshot notification has Edit (satty: arrows, boxes, blur; saving writes over the picture).
- **Sound mixer:** the mixer button at the bottom of quick settings (or `quicksettings mixer`): a volume slider for each app playing sound, those on your workspace first; click an app's icon to mute it.
- **Wallpaper:** the shell draws it (hyprpaper isn't needed). While night light is on, it dims a little, so the desktop isn't the brightest thing on screen late at night (the desktop icons stay as they are). Launcher → Wallpapers opens a switcher with the images in `~/Pictures/Wallpapers`: the screen behind it previews the one you pick, and each image keeps its own fit (Fill, Fit, Center, Tile). New wallpapers fade in.
- **Window switcher:** Alt+Tab shows every open window, on any workspace, with a picture of each, most recently used first; let go of Alt to switch.
- **Showoff mode:** for screenshots of your setup. It moves to an empty workspace, opens the notification centre (with the calendar and the weather) on the left and quick settings on the right, sliding in one after the other while the wallpaper settles, and fastfetch in your terminal between them, with the shell's own config: a pistachio and your system, without your user name, host name or anything else that names the machine. Private things are hidden meanwhile: notifications (the centre shows Inbox zero, and no toast shows, not even a critical one; they all reach the centre), window titles, the weather's city and Bluetooth device names. What's playing stays visible (cover, title, artist), as in most setup screenshots. Take the screenshot with your usual key. Esc, a click on the wallpaper, closing the terminal, going to another workspace or starting it again ends it and takes you back. Start it from launcher → System → Shell settings → Showoff mode, or `showoff toggle`.
- **System warnings:** a notification when a disk has under 10 % free, or the CPU or GPU has been at 85 °C or more for a minute (checked every 30 seconds in the background).
- **Screenshots:** freeze the screen and drag out an area, or pick Region, Window, Screen or Text from a small menu. The picture goes to `~/Pictures/Screenshots/` and a notification shows it: click it to copy the picture, or Open or Delete it (to the trash). It shows even in Do not disturb. A soft pop sounds as the picture is taken (with the notification sound's switch; the notification itself then stays silent). Text copies the words in the area you drag out (an error in a game, a video's subtitle), read by tesseract in Polish and English; the notification shows the area and the start of the text, and a click copies it again.
- **USB drives:** mounted the moment you plug them in (by udiskie, which the shell runs), with a notification that has Browse. Eject them from the launcher's System mode.
- **Admin password dialog:** the shell is the polkit agent, so apps that need admin rights (`pkexec`, GParted, an app managing system services) ask for your password in a dialog of its own, with details on which app asked and for what. Cancelling it never counts as a failed login.

## Requirements

Tested on Arch Linux with Hyprland 0.56.2 (Lua config) and Quickshell 0.3.2 on Qt 6.12. The shell also works with an older-style `hyprland.conf`.

| Need | Arch packages | Used for | If missing |
| --- | --- | --- | --- |
| Compositor | `hyprland` | everything; Hyprland only | nothing works |
| Shell runtime | `quickshell` (pulls in Qt 6, PAM, polkit) | everything | nothing works |
| Audio | `pipewire`, `wireplumber`, `pipewire-pulse` (its `pactl` tells which inputs have something plugged in; `setpriv` from `util-linux` keeps it from outliving the shell) | volume, per-app volume, output and input devices, microphone, OSD; `wpctl` for the volume keys | no volume controls; without `pactl`, no input is greyed out |
| Media | any player that speaks MPRIS (browsers, Spotify, mpv with `mpv-mpris`) | the media pill and its card, the media card in quick settings and on the lock screen | the pill and the cards stay hidden |
| Bluetooth | `bluez`, `bluez-utils`, with `bluetooth.service` running | Bluetooth tile, chip, launcher Bluetooth view | Bluetooth shows as off |
| File search | `python` (already there with `python-gobject`), `xdg-utils` | the launcher's `/` search through your home folder, opening what it finds | `/` finds nothing |
| Pairing agent | `python-gobject` | pairing devices that show or ask for a code, and devices asking to connect | only devices that need no code pair; the log says `bluetooth agent exited` |
| Screenshots | `libnotify` (`notify-send`), `wl-clipboard` (also copies emoji), `xdg-utils`, `glib2` (`gio`); `xdg-user-dirs` optional | the notification after a screenshot, Copy, Open and Delete; the Pictures folder in your language | no notification (the picture is still saved); `~/Pictures/Screenshots` |
| Weather | a network connection (Open-Meteo, no account; only your city's coordinates are sent, every 30 min) | the weather panel | no weather panel |
| Screen sharing | `xdg-desktop-portal-hyprland` | sharing your screen from Discord, browsers or OBS, and the shell's screen-sharing indicator | apps can't share the screen at all |
| Polkit agent | `python-gobject`, `polkit` (its Python bindings come with it) | the admin password dialog | apps that need admin rights fail or hang; the log says `polkit agent` |
| Network | `networkmanager`, with `NetworkManager.service` running | Ethernet tile and chip (Quickshell only talks to NetworkManager) | Ethernet shows as unplugged |
| Brightness | `ddcutil`, and DDC/CI switched on in your monitor's own menu | brightness slider, brightness keys, OSD | the brightness slider is hidden |
| Night light | `hyprsunset` | Night light tile, warmth slider and schedule; the shell starts and stops it itself | the tile says "Not installed" |
| Idle lock (optional) | `hypridle`, with `extras/hypridle.conf` | locking after idle time, screen off, locking before any suspend | only the power menu's Suspend locks first |
| GPU readings (optional) | the NVIDIA driver's `nvidia-smi` | the GPU row of the launcher's System monitor | no GPU row (CPU and memory come from `/proc`, the CPU temperature from its `coretemp` or `k10temp` sensor) |
| Power actions | `systemd` (already there) | suspend, reboot, shut down | |
| Terminal | `kitty` (or `ghostty`, `foot`, `alacritty`, `wezterm`, `konsole`: pick it in Shell settings, or set `$TERMINAL`) | launching apps marked `Terminal=true`, `$` commands | those don't start |
| Desktop icons | `glib2` (`gio`, for Move to trash), `xdg-utils`, `xdg-user-dirs` optional | the Desktop folder's icons: opening, trashing, the folder in your language | no trash from the desktop's menu; `~/Desktop` |
| Notification sound | `pipewire`'s `pw-play` (already there) | the sound with each toast (the shell brings its own, `src/sounds/notification.wav`) | silent toasts |
| Showoff mode (optional) | `fastfetch` | the terminal in showoff mode | the panels open without it |
| LocalSend | `localsend` (the AUR's `localsend-bin`, or Flathub's) installed but not running; `python`, `openssl` (already there); `zenity` for the Add files and Add folder buttons; `wl-clipboard` for Paste | sending and receiving in quick settings | no LocalSend row; without `zenity`, add files by dropping or pasting them |
| Screen tools (optional) | `hyprpicker`, `gpu-screen-recorder`, `satty` | the screenshot menu's Colour and Record, and Edit on the screenshot notification | those choices aren't offered |
| Launcher extras (optional) | `libqalculate` (`qalc`); `tldr`; Cider (with its app token); CLion; Steam | `tldr`, `m`, CLion projects, games | that part of the launcher stays empty |
| USB drives | `udiskie`; `udisks2` (already there) | mounting drives as they're plugged in; Eject | drives don't mount by themselves; Eject still works |
| Text from the screen (optional) | `tesseract`, `tesseract-data-eng`, `tesseract-data-pol` | the screenshot menu's Text | "Couldn't read the text: tesseract isn't installed" |
| Font | Manrope (weights 500 to 800), installed by `install.sh`; needs `curl` | all text | Qt falls back to another font |
| Mono font (optional) | `ttf-jetbrains-mono` | the details in the admin password dialog | another monospace font |

The `ddcutil` package already loads the `i2c-dev` module and gives the logged-in user access to the monitor, so it needs no group or module setup. Not every monitor supports DDC/CI; check with `ddcutil getvcp 10`.

Manrope isn't in the official repos, so `install.sh` downloads it: Google Fonts' variable TTF (every weight from 200 to 800 in one file) and its licence go into `~/.local/share/fonts/manrope/`. Not Fontsource's files: they name every weight "Manrope ExtraLight", so nothing matches "Manrope" and the shell falls back to another font. By hand: download `Manrope[wght].ttf` from [Google Fonts](https://fonts.google.com/specimen/Manrope) into that folder and run `fc-cache -f`.

For the tests in `tests/` you also need `libnotify` (`notify-send`); `tests/js.sh` runs the launcher's and calendar's unit tests with `nodejs` if it's installed, else in Quickshell's own JavaScript engine; `pw-cat` (part of `pipewire`) plays the silent test stream, `gst-plugin-pipewire` and `gst-plugins-base` stand in for a screencast (skipped without them), and `gdbus` (part of `glib2`) asks the pairing and polkit agents their test questions.

## Installation

1. **Install the packages:**

   ```sh
   sudo pacman -S --needed hyprland quickshell pipewire wireplumber pipewire-pulse \
       bluez bluez-utils python-gobject networkmanager ddcutil hyprsunset kitty udiskie
   sudo systemctl enable --now bluetooth.service NetworkManager.service
   ```

   Optional, for copying text from the screen: `sudo pacman -S tesseract tesseract-data-eng tesseract-data-pol`.


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
| `screenshot region` | freezes the screen to drag out an area to save |
| `screenshot menu` | freezes the screen and asks: Region, Window, Screen or Text |
| `screenshot text` | freezes the screen to drag over some text, which is read and copied |
| `weather city <name>` | sets the weather's city (e.g. `weather city Kraków`) and fetches it; `weather refresh` fetches now |
| `wallpaper toggle` | opens or closes the wallpaper switcher |
| `wallpaper random` / `wallpaper set <path>` | sets a random image from the folder, or that image |
| `switcher next` / `switcher prev` | opens the window switcher on the previous window (`prev`: the oldest), or steps once it's open; for Alt+Tab and Alt+Shift+Tab |
| `showoff toggle` | starts or ends showoff mode (see "What you get") |
| `desktop toggle` / `desktop on` / `desktop off` | shows or hides the desktop icons, with the OSD saying which |
| `workspace name <text>` | names the workspace you're on (empty clears it; names last until you log out) |
| `workspace preset <name>` | loads a workspace preset (its names, and its apps if saved with them) |
| `bar peek` | shows the hidden bar for 2 s |
| `workspace tabbed` | turns tabbed (i3-style) on or off for the workspace you're on |
| `switcher tabs` / `switcher tabsPrev` | the window switcher with only the tabs of the group you're in |
| `quicksettings mixer` | opens quick settings at the sound mixer |
| `screenshot record` / `screenshot colour` | starts recording the whole screen, or stops the recording; picks a colour |
| `localsend add <path>` / `localsend open` | adds a file or folder to LocalSend's list and opens its page in quick settings (one path a call; only while the LocalSend app is installed) |
| `switcher commit` / `switcher cancel` | switches to the chosen window, or closes the switcher; letting go of Alt does the first by itself |

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

-- window switcher: hold Alt, tap Tab, let go
hl.bind("ALT + Tab",                 hl.dsp.exec_cmd(shell .. "switcher next"))
hl.bind("ALT + SHIFT + Tab",         hl.dsp.exec_cmd(shell .. "switcher prev"))

-- screenshots
hl.bind("Print",                     hl.dsp.exec_cmd(shell .. "screenshot region"))
hl.bind("SHIFT + Print",             hl.dsp.exec_cmd(shell .. "screenshot menu"))

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
bind = , Print, exec, qs -c pistachio ipc call screenshot region
bind = SHIFT, Print, exec, qs -c pistachio ipc call screenshot menu
bind = ALT, Tab, exec, qs -c pistachio ipc call switcher next
bind = ALT SHIFT, Tab, exec, qs -c pistachio ipc call switcher prev
bindel = , XF86MonBrightnessUp, exec, qs -c pistachio ipc call brightness up
bindel = , XF86MonBrightnessDown, exec, qs -c pistachio ipc call brightness down
```

Mouse and keyboard work inside each part too:

- **Bar:** click the clock for the notification centre and the status chip for quick settings. A click outside a panel closes it. Rest the pointer on the clock, the status chip, a workspace dot or a tray icon for a tooltip: the full date and what's new, each connection and the sound devices, the apps on that workspace, or the app's name.
- **Wallpaper switcher:** the arrows or h j k l preview, Enter or a click sets the wallpaper, R previews a random one, Esc leaves it as it was; Fill, Fit, Center and Tile under the images set the chosen image's fit. With no images yet, Open folder (or Enter) creates and opens the folder.
- **Window switcher:** keep Alt down and tap Tab (Shift+Tab goes back), or use the arrows or h j k l; let go of Alt, press Enter or click a window to switch to it (and its workspace). Q closes the chosen window, Esc or a click outside cancels.
- **Screenshots:** drag out an area (Region), or click a window (Window); the menu takes R, W, S or T, or ← → and Enter. Esc cancels. On the notification, a click copies the picture; Open shows it, Delete moves it to the trash. A live reload or restart leaves older screenshot notifications without their buttons.
- **Media pill:** a click opens the media card above it (previous, play/pause, next; a click or a drag on its bar jumps; Esc or a click outside closes it), the scroll wheel skips to the next track (down or right) or the previous one (up or left), and a middle click or its own button plays or pauses.
- **Tray pill:** left click opens or activates the app, right click opens its menu (in Pistachio colours; submenus open in place with a Back row, and Esc or a click outside closes it), middle click runs its secondary action, and scrolling goes to the app (e.g. a volume applet).
- **Quick settings:** click a tile to switch it on or off. Right-click the Bluetooth tile for quick connections: Bluetooth on/off and your paired devices (click one to connect or disconnect), plus "Pair new devices…", which opens the launcher's Bluetooth view. Right-click the Night light tile to set its schedule: a switch, and the times it turns on and off (− and + or the mouse wheel, in 15-minute steps). The schedule switches only at those two times, so switching by hand holds until the next one; the tile then reads "Until 07:00" or "From 20:00". Right-click the Do not disturb tile for its schedule, which works the same way: its own times, or night light's (the "Night light's times" switch). Click the speaker icon to mute. Scroll over a slider to change it: 5 % a notch, 250 K for warmth.
- **Launcher:** type to search; a calculation (`+ - * / ^`, brackets, `.` or `,` for decimals) in All or Apps mode shows its answer, which is only shown, not copied. Power actions come up by name or a common word for them (lock, log out / logout / sign out, suspend / sleep, reboot / restart, shut down / shutdown / power off / turn off). Lock happens at once; the others ask first ("Shut down?" with Cancel and Shut down), with Cancel chosen, so a second Enter does nothing. Scrolling over a slider changes it, as ← → do. The keys are in the table below.
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
| Shift+Enter | on a workspace: move the last focused window there; on a file: open the folder it's in; on a `$` command: run it in the background |
| Ctrl+W or Ctrl+Q | close the selected window |
| Ctrl+F | float the selected window, or tile it again |
| Ctrl+1 … Ctrl+9 | move the selected window to that workspace; you stay where you are and the launcher stays open |
| → (with the cursor at the end of the search) | on an app: list its own actions; ← goes back to the app |
| `?` (typed first) | the cheat sheet: the search prefixes (`/ ! $ :`), these keys and your Hyprland binds |
| Ctrl+M | mute |
| Ctrl+Backspace | forget the selected Bluetooth device |
| Esc | close; on a power question, go back to the results; on a Bluetooth question, decline it |

## Frosted panels

Launcher → System → Shell settings → Frosted panels makes the bar, its pills and the panels (quick settings, the notification centre with the calendar and the weather, the launcher, menus, toasts, the OSD, the media card) see-through, with what's behind them blurred; Glassy, under it, makes them more see-through (72 % opaque instead of 88 %). Drop shadows go while it's on. The blur is Hyprland's, so it needs this rule in your config (e.g. `~/.config/hypr/lua/rules.lua`, or your own file); without it the panels are see-through but not blurred, which is why the setting starts off:

```lua
-- Pistachio shell: blur behind the bar and the panels (frosted panels)
hl.layer_rule({
    name         = "pistachio-frost",
    match        = { namespace = "^pistachio-(bar|panel)$" },
    blur         = true,
    ignore_alpha = 0.66, -- not the clear room around a panel, nor a solid panel's drop shadow
})
```

To try it without editing the config, add it to the running Hyprland (it's gone at the next config reload):

```sh
hyprctl eval 'hl.layer_rule({ name = "pistachio-frost", match = { namespace = "^pistachio-(bar|panel)$" }, blur = true, ignore_alpha = 0.66 })'
```

How strong the blur is comes from your `decoration.blur` settings (size, passes, brightness), which apply to every blurred window.


The shell's windows animate themselves, so it's best if Hyprland doesn't fade them as well. Add this layer rule next to the blur rule:

```lua
hl.layer_rule({ name = "pistachio-motion", match = { namespace = "^pistachio-" }, no_anim = true })
```

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
- **The wallpaper flickers or the old one shows:** hyprpaper (or another wallpaper program) still runs on the background layer; take it out of your autostart (`hl.exec_cmd("hyprpaper")`).
- **PrtSc doesn't trigger the Print binds:** some keyboards send PrtSc as the Windows "snip" shortcut, Shift+Super+S, so Hyprland never sees Print (`wev` shows Shift and Super going down in the same millisecond). Bind that instead: `mainMod .. " + SHIFT + S"` for `screenshot region`, and `mainMod .. " + ALT + SHIFT + S"` for `screenshot menu` (Alt+PrtSc). Remapping the key to Print Screen in the keyboard's firmware (VIA, QMK) works too.
- **Screen sharing fails, or the app finds nothing to share:** `xdg-desktop-portal-hyprland` is missing, or the portal service started before it was installed. Restart it with `systemctl --user restart xdg-desktop-portal` (or log in again).
- **An app that needs admin rights fails or hangs without asking:** no polkit agent runs. `psc log` shows a `polkit agent` line when the shell's can't start or register: install `python-gobject` if it says so, and stop any other agent for this session (polkit takes one per session, e.g. `polkit-gnome` or `hyprpolkitagent` started from the Hyprland config).
- **An app's tray icon doesn't show:** the shell shows StatusNotifierItem icons, which most current apps use; apps with only the old X11 tray don't appear. Icons an app marks as passive (idle) are left out on purpose.
- **App icons missing in the launcher:** Qt couldn't find an icon theme. Install one, for example `papirus-icon-theme` or `breeze-icons`, and select it in `qt6ct`, which needs `hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")` in `hyprland.lua`.
- **Flatpak apps missing in the launcher:** the shell finds apps through `XDG_DATA_DIRS`, and Flatpak adds its folders (`/var/lib/flatpak/exports/share`, `~/.local/share/flatpak/exports/share`) to it only at login. After installing Flatpak itself, log out and in again; apps installed later show up without that.
- **LocalSend says "The LocalSend app is running":** the app and the shell both need port 53317. Quit the app (and take it out of your autostart); the shell then receives. A phone that doesn't see this PC: Receive files has to be on, and both on the same network; a firewall must let TCP and UDP 53317 through.
- **A change in `src/` didn't show:** reloading occasionally misses a save; restart the shell (see "Updating and restarting").

## Repository layout

```
pistachio-shell/
├─ bin/psc     the control command
├─ install.sh  links src/ and bin/psc into place
├─ extras/     hypridle.conf (idle locking), sddm/ (the login screen theme, see extras/sddm/README.md), make-emoji.py (rebuilds the launcher's emoji list) and make-sound.py (rebuilds the notification sound)
├─ src/        the shell: shell.qml, Theme.qml, and bar/ panels/ popups/ launcher/ lock/ components/ services/
├─ tests/      checks against the live system (see CLAUDE.md, working rule 9)
├─ design/     one HTML board per screen; open design/index.html. The visual source of truth
├─ docs/       plan.md (architecture, components, build phases) and audio-bluetooth.md
└─ CLAUDE.md   decisions and working rules for Claude Code
```
