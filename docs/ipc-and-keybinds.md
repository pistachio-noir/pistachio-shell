# psc

`psc` (Pistachio Shell Control) is a Rust program built from `rust/psc` (since 19 November 2026). Every command the old shell script had works the same, so keybinds don't change. The script itself is kept as `legacy/psc`, a fallback for starting, stopping and calling the shell if the Rust one can't be built: `install.sh` links it only when there's no `psc` at all.

After changing anything in `rust/`, rebuild and reinstall psc, then restart the shell:

```sh
cd rust && cargo build --release -p psc
rm -f ~/.local/bin/psc && install -m 755 target/release/psc ~/.local/bin/psc   # rm first: a running helper keeps its old file
psc restart
```

| Command | Does |
| --- | --- |
| `psc` | runs the shell in this terminal, with its log (`qs -c pistachio`) |
| `psc start` | runs it in the background, unless it's already running |
| `psc stop` | stops it and waits until it has really exited: 5 s for a clean exit, then SIGTERM, then SIGKILL, so a new copy can take over the notification service |
| `psc restart` | `psc stop`, then `psc start` |
| `psc force-restart` | kills the shell and its helpers at once, then starts it |
| `psc status` | running or not, its PID, uptime and memory, and each helper with its memory (`--json` too); exit status 1 when it isn't running |
| `psc log [-f] [--errors]` | the shell's log; `--errors` keeps errors and warnings only, without the usual Qt text-input noise |
| `psc ipc` | every IPC target with its functions; `psc ipc show`, `psc ipc call …` still go to `qs` |
| `psc <target> <function> [args]` | a call to the shell, e.g. `psc launcher toggle` (`qs -c pistachio ipc call …`) |
| `psc doctor` | the tools, fonts, helpers and services the shell needs (the Requirements table), found or missing, with the package to install and what stops working without it (`--json` too; `--packages required|optional` prints only the missing packages, for `install.sh`); exit status 1 if something required is missing |
| `psc setup` | opens the first-run setup again (it opens by itself only on the shell's very first start); `psc setup close` and `psc setup status` call its other IPC functions |
| `psc completions zsh\|bash\|fish` | tab completion, e.g. `psc completions zsh > ~/.local/share/zsh/site-functions/_psc` |
| `psc list`, `psc kill`, `psc msg` | the same `qs` subcommand for this config |

`psc help` (or `psc <command> --help`) explains each command. The shell itself also runs `psc prefs …` (settings export and import), `psc theme …` (theming integration) and `psc system …` (Shell health, network and Bluetooth details, safe eject), `psc files` (the launcher's `/` search), `psc library` (recent projects and games), `psc capture` (recording trim), `psc mic-check`, `psc phone-timer`, `psc boot-entries` (Restart into…), `psc swatch` (the colour picker's swatch), `psc clocks` (GNOME Clocks' alarms), `psc launcher-tools` (background jobs, file previews, Open with), `psc chat` (Quick chat), `psc lens` (Lens) and `psc events` (the month calendar's GNOME Calendar events). These helpers moved from Python on 19 and 20 November 2026 and are hidden from `--help`; the shell calls them as `~/.local/bin/psc`. Nothing the shell runs is Python any more. Settings, Quick chat, Lens and the launcher's file tools need the Rust `psc` installed. Bare `psc chat` starts the helper. `psc chat toggle`, `psc chat ask` and other chat IPC calls still reach the shell.

# IPC commands

Everything a keybind needs goes through Quickshell's IPC:

```sh
qs -c pistachio ipc call <target> <function> [arguments]
```

`qs -c pistachio ipc show` (or `psc ipc show`) lists them all, and `psc <target> <function>` is the short form of each. They only reach a shell started with `qs -c pistachio` or `psc`; one started with `qs -p <path>` needs `qs -p <path> ipc call …` instead.

| Command | What it does |
| --- | --- |
| `launcher toggle` | opens the launcher in All mode, or closes it (whatever mode it shows) |
| `launcher apps`, `windows`, `workspaces`, `system` | opens the launcher in that mode, switches to it if the launcher shows another, or closes it if it already shows that mode; made for keybinds |
| `launcher open <mode>` | opens the launcher in a mode (`all`, `apps`, `windows`, `workspaces`, `system`; `bluetooth` and `about` open their Settings pages) and never closes it |
| `launcher search <mode> <text>` | opens a mode with the search field filled in, e.g. `launcher search apps fire` |
| `launcher bluetooth` | opens Settings → Bluetooth (compatibility command) |
| `jobs open` / `jobs close` / `jobs status` / `jobs cancel <id>` | opens or closes background jobs, returns session job state or cancels an owned job |
| `settings open` / `settings toggle` / `settings close` | opens, toggles or closes the normal Settings window |
| `settings section <name>` | opens a page: `appearance`, `display`, `sound`, `notifications`, `bluetooth`, `network`, `localsend`, `lens`, `apps`, `system`, `health`, `about`; unavailable/unknown pages return to Appearance |
| `settings search <text>` | opens Settings with a global search; Enter opens its first result |
| `settings status` | reports the page, visibility, search and watcher state as JSON |
| `quicksettings toggle` | opens or closes quick settings |
| `notifications toggle` | opens or closes the notification centre |
| `notifications toggleDnd` | turns Do not disturb on or off |
| `brightness up` / `brightness down` | changes monitor brightness by 5 % and shows the OSD |
| `power toggle` | opens or closes the power menu |
| `lock lock` | locks the screen |
| `screenshot region` | freezes the screen to drag out an area to save |
| `screenshot menu` | freezes the screen and asks: Region, Window, Screen or Text |
| `screenshot text` | freezes the screen to drag over some text, which is read and copied |
| `screenshot lens` | freezes the screen to select an area and ask Claude or ChatGPT about it |
| `chat toggle` / `chat open` / `chat close` | the quick chat above the bar |
| `chat ask "<question>"` | opens the quick chat and asks the question |
| `chat status` | the quick chat's state, as JSON |
| `weather city <name>` | sets the weather's city (e.g. `weather city Kraków`) and fetches it; `weather refresh` fetches now |
| `wallpaper toggle` | opens or closes the wallpaper switcher |
| `wallpaper random` / `wallpaper set <path>` | sets a random image from the folder, or that image |
| `overview toggle` / `overview open` / `overview close` | the Overview; bind toggle to a key of your choice |
| `switcher next` / `switcher prev` | opens the window switcher on the previous window (`prev`: the oldest), or steps once it's open; for Alt+Tab and Alt+Shift+Tab |
| `showoff toggle` | starts or ends showoff mode (see "What you get") |
| `desktop toggle` / `desktop on` / `desktop off` | shows or hides desktop icons in Classic and reports the change in the OSD |
| `widgets arrange` / `widgets done` / `widgets status` | opens or closes the desktop widgets' studio (Experimental; arranging switches them on); status prints the switch, the grid and the layout as JSON |
| `workspace name <text>` | names the workspace you're on (empty clears it; names last until you log out) |
| `workspace preset <name>` | loads a workspace preset (its names, and its apps if saved with them) |
| `bar peek` | shows the hidden bar for 2 s |
| `clocks timer <text>` / `clocks stopwatch` / `clocks stop` | starts a timer ("25m tea"); starts or stops the stopwatch; stops a ringing alarm or timer |
| `workspace tabbed` | turns tabbed (i3-style) on or off for the workspace you're on |
| `window minimize` / `window restore` / `window restoreAll` | minimises the focused window; brings back the last one minimised, or all of them, onto the workspace you're on |
| `window status` | the minimised windows, as JSON |
| `switcher tabs` / `switcher tabsPrev` | the window switcher with only the tabs of the group you're in |
| `quicksettings mixer` | opens quick settings at the sound mixer |
| `screenshot record` / `screenshot colour` | opens recording setup; while recording, stops; during countdown, cancels; picks a colour |
| `screenshot pause` / `screenshot cancel` | pause/resume the active recording; cancel the countdown/picker |
| `localsend add <path>` / `localsend open` | adds a file or folder to LocalSend's list and opens its page in quick settings (one path a call; only while the LocalSend app is installed) |
| `switcher commit` / `switcher cancel` | switches to the chosen window, or closes the switcher; letting go of Alt does the first by itself |

Volume has no IPC command and needs none: keep the volume keys on `wpctl`. The OSD follows PipeWire, so it shows any volume change, whatever made it.

# Hyprland keybinds

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

-- the Overview (choose an unused key)
hl.bind("SUPER + O",                 hl.dsp.exec_cmd(shell .. "overview toggle"))

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
- **Screenshots:** drag out an area (Region), or click a window (Window); the menu takes R, W, S, T or L (Lens), C for Colour and V for Record when installed, or ← → and Enter. Esc cancels the picker/countdown. Recording setup chooses audio/countdown, then area/full screen; right-click the bar recording pill to pause/resume, left-click to stop. On the notification, a click copies the picture; Open shows it, Delete moves it to the trash. A live reload or restart leaves older screenshot notifications without their buttons. Lens takes Enter to ask, Shift+Enter for a new line and Esc to close.
- **Media pill:** a click opens the media card above it (previous, play/pause, next; a click or a drag on its bar jumps; Esc or a click outside closes it), the scroll wheel skips to the next track (down or right) or the previous one (up or left), and a middle click or its own button plays or pauses.
- **Tray pill:** left click opens or activates the app, right click opens its menu (in Pistachio colours; submenus open in place with a Back row, and Esc or a click outside closes it), middle click runs its secondary action, and scrolling goes to the app (e.g. a volume applet).
- **Quick settings:** the footer has Settings, Mixer (waveform), Launcher and power buttons. Click a tile to switch it on or off. Right-click the Bluetooth tile for quick connections: Bluetooth on/off and your paired devices (click one to connect or disconnect), plus "Pair new devices…", which opens Settings → Bluetooth. Right-click the Night light tile to set its schedule: a switch, and the times it turns on and off (− and + or the mouse wheel, in 15-minute steps). The schedule switches only at those two times, so switching by hand holds until the next one; the tile then reads "Until 07:00" or "From 20:00". Right-click the Do not disturb tile for its schedule, which works the same way: its own times, or night light's (the "Night light's times" switch). Click the speaker icon to mute. Scroll over a slider to change it: 5 % a notch, 250 K for warmth.
- **Launcher:** type to search; a calculation (`+ - * / ^`, brackets, `.` or `,` for decimals) in All or Apps mode shows its answer, which is only shown, not copied. Power actions come up by name or a common word for them (lock, log out / logout / sign out, suspend / sleep, reboot / restart, shut down / shutdown / power off / turn off). Lock happens at once; the others ask first ("Shut down?" with Cancel and Shut down), with Cancel chosen, so a second Enter does nothing. Scrolling over a slider changes it, as ← → do. The keys are in the table below.
- **Bluetooth pairing:** choose Add a device in Settings → Bluetooth, or let a device ask (Settings opens for it). Depending on the device, it asks you to:
  - **compare a code:** pair only if the device shows the same 6 digits.
  - **type a code into the dialog:** the PIN or 6-digit code the device shows (old devices often use 0000), then Enter.
  - **type a code on the device:** a keyboard shows the code to type on it, then Enter on that keyboard; the dialog shows how many digits were entered if the keyboard reports them.
  - **allow a connection:** a device that is paired but not trusted asks to use a service, such as audio.

  Cancel is focused first. Tab moves between controls; Enter activates the focused choice. Esc or closing Settings declines. Forget asks for confirmation. Questions are declined while the screen is locked. Accepting a pairing also trusts the device, so it reconnects without asking.
- **Power menu:** L, E, S, R and P act at once; ←→ and Enter pick one; Esc or a click on the background closes it.

Launcher keys. The vim motions only work while Ctrl is held, so plain h j k l still type into the search, and the arrows keep working too:

| Keys | What they do |
| --- | --- |
| Tab, Shift+Tab | next or previous mode |
| ↑ ↓, or Ctrl+K Ctrl+J | move between results and rows |
| ← →, or Ctrl+H Ctrl+L | change a slider (volume, brightness, warmth, an app's volume) or a schedule time (15 min); move across the workspace grid or quick controls; elsewhere, move the cursor in the search |
| Enter | open, switch to or select the row; flips a switch row (Night light, Do not disturb, Bluetooth) |
| Shift+Enter | on a workspace: move the last focused window there; on a file: open the folder it's in; on a `$` command: run it in the background |
| Ctrl+W or Ctrl+Q | close the selected window |
| Ctrl+F | float the selected window, or tile it again |
| Ctrl+1 … Ctrl+9 | move the selected window to that workspace; you stay where you are and the launcher stays open |
| → (with the cursor at the end of the search) | on an app: list its own actions; ← goes back to the app |
| `?` (typed first) | the cheat sheet: the search prefixes (`/ ! $ :`), these keys and your Hyprland binds |
| Ctrl+M | mute |
| Esc | close; on a power question, go back to the results |
