# Pistachio Noir Shell

A desktop shell for Hyprland, written in QML on [Quickshell](https://quickshell.org) 0.3.2, in the Pistachio Noir colours. It is made for a single-monitor desktop PC with wired networking.

What you get:

- **Bar:** a floating pill at the bottom with workspaces, the focused window, clock and notifications, and an Ethernet, Bluetooth and volume chip. It hides while a window overlaps it; point at the bottom edge of the screen to bring it back. Once you move the pointer away it waits a moment before hiding, so you can reach the tray pill. While a fullscreen window (a game, a video; not a maximized one) has focus, the bottom edge doesn't bring it back, so a stray pointer can't pop it up mid-game. When the shell starts, the wallpaper fades in and then the bar grows out of its handle (not on a live reload).
- **Tray pill:** apps' tray icons in a second pill right of the bar, shown only while some app has one; it hides and returns with the bar.
- **Media pill:** what's playing (cover, title, artist and a play/pause button) in a pill left of the bar, while a player has a track, paused too; it hides and returns with the bar. Click it for the media card above it, scroll over it to skip tracks, middle-click to play or pause. The media card (here, in quick settings and on the lock screen) shows the time played and the track's length under a bar you can click or drag to jump. When your Bluetooth headphones disconnect or run flat, whatever is playing pauses instead of carrying on out of the speakers (switching outputs by hand doesn't pause).
- **Status chip:** Ethernet, Bluetooth and volume. While headphones or another device that reports its battery are connected, the Bluetooth icon shows the battery level instead (terracotta at 20 % or less); a crossed-out mic appears while the microphone is muted, and a mic in orange (clay) while an app is recording from it; a screen in clay shows while an app shares your screen.
- **Quick settings:** Ethernet, Bluetooth (with the connected device's battery), Do not disturb and Night light tiles; a night light schedule (right-click the Night light tile); what's playing (cover, title, previous / play-pause / next) while a media player has something; volume (click the speaker icon to mute), microphone (click its icon to mute), brightness and night light warmth sliders; uptime, a launcher button and the power menu.
- **Notifications:** toasts above the bar and a notification centre with history, which survives restarts. Pointing at a card in the centre shows the app's actions (Open, Reply…) under it. Notifications are grouped by app, the newest group first: a group of two or more shows its newest card with the others folded behind it, and a click on its header (or Show all) opens or folds it; groups stay as you left them until the shell restarts. The header's ✕ clears just that app. A month calendar sits beside the centre (weeks from Monday, today marked); ‹ ›, the scroll wheel, ← → or h l change month, and Today or Home go back. With GNOME Calendar installed it also shows your events from every calendar GNOME Calendar knows (read-only, from Evolution Data Server): a dot under each day that has some, and under the grid the events of today or the day you click (time, title, the calendar's colour); a click on an event opens GNOME Calendar. Switch it off in Settings → Integrations. The shell is the notification daemon. Do not disturb holds back toasts, except critical ones. A thin bar along each toast shows the time it has left, and pointing at the toast holds it. Right-click a toast or a card to silence its app for an hour or stop its toasts (they still reach the centre); Settings → Notifications → App rules undoes that. Bluetooth devices that report their battery warn at 20 %, and urgently at 10 %, and headphones say so when they connect ("AirPods Pro connected · 80 %"). Notifications older than a week go by themselves; find an older one with `!` in the launcher (see Launcher). When one app sends three or more within a few seconds (a busy chat), they fold into one toast, "VESKTOP · 5 NEW" over the newest; the centre keeps each. A soft sound plays with each toast (once for a flood, never while toasts are held back); switch it off in Settings → Notifications.
- **Remembered settings:** Do not disturb (on/off, schedule), night light (on/off, warmth, schedule), drop shadows and notification history (the last 200, for a week) are kept across restarts and reboots.
- **Launcher:** apps, windows, workspaces, system controls and Bluetooth devices, with fuzzy search. Apps are also found by the program they run, as you'd type it in a terminal (`baobab` finds Disk Usage Analyzer, `nautilus` finds Files; for a Flatpak its command), with the program named under the app. A click anywhere beside it closes it (that click only closes it; it doesn't reach the window under it), and so does anything else taking the keyboard (Alt+Tab, a screenshot). System keeps output volume, brightness, Bluetooth power and a device link, Night light, Do not disturb and a Settings entry. Detailed controls live in the Settings window. Apps mode starts with the apps you launch most and most lately (Frequent), and they also rise among equally good matches when you search. Search ignores accents: `zolty` finds "Żółty", and the other way round. In Windows mode, keys close, float or move the selected window (see the key table). → on an app with actions of its own (Helium's New incognito window, for one) lists them under it. And there's an easter egg: the Konami code (↑ ↑ ↓ ↓ ← → ← → B A) in the launcher. Type `?` for a cheat sheet: the search prefixes, the launcher's keys and your Hyprland binds, searchable (a bind says what it does if you give it a `description` in `hyprland.lua`: `hl.bind(keys, action, { description = "…" })`). Type a calculation such as `12*(3+4)` and the answer shows at the top; harder maths goes to libqalculate (`qalc`, optional): equations, functions, units, currencies and bases, either after `=` (`= solve(x^2 = 4)`, `= 30 EUR to PLN`, `= 0x1F to bin`) or by itself when the plain calculator can't read something that is clearly maths (`5 km to mi`, `sqrt(2)^10`), never for plain names; Enter copies its answer; type `:` and a name (`:fire`) for emoji, which Enter copies (a bare `:` lists the ones you copied lately first); type `$` and a command (`$btop`) to run it in your terminal (see Settings → Apps & places), which stays open to show what it printed (Shift+Enter runs it in the background, and a notification says when it's finished or failed; Background jobs has its output; a bare `$` lists your recent commands); type `/` and a name (`/invoice`) to find files and folders in your home folder, which Enter opens (Shift+Enter opens the folder it's in; hidden folders, `node_modules` and cache folders are left out, and a query with a `/` in it, such as `/proj/main`, matches the path); type `!` and a word to find a notification by its title, text or app, which Enter shows in the notification centre (a bare `!` lists them all under Clear all, which asks first); type `@` and some words (`@hyprland window rules`) to search the web with DuckDuckGo in your browser; with Claude Desktop installed, type `claude` and a question (`claude what is a pistachio`) for an Ask Claude row on top, which opens a new chat in Claude Desktop with it (your usual results stay under it).
- **Recent project Git status:** the launcher’s recent CLion and VS Code project folders show their Git branch and a dot when there are uncommitted changes, including untracked files. Status is read when the launcher opens; unavailable repositories and workspace files without a single folder show no Git label. Git is optional.
- **Desktop cat:** Settings → Experimental → Desktop cat enables a small pixel cat on workspaces without tiled windows, including those with floating windows. It stays behind windows and desktop icons, blinks and flicks its tail; hover for a heart or click to pet it. When visible, it occasionally says a few words and perks up with a short bubble for finished timers, ringing alarms and completed Focus or Pomodoro phases. Desktop icons keep their normal clicks, and the cat stops animating when hidden. It is off by default.
- **Launcher pins and aliases:** right-click an app, workspace preset or shell action to pin it; Move pin up/down changes its saved order. Pins appear before Frequent in All/Apps; All retains quick controls at the top. Search for Settings pages, Screenshot menu, Record screen, Lens or Background jobs to find pinnable actions. Set alias gives an app or shell action an exact short name; Enter activates it. Aliases accept 1–32 Latin letters, numbers, `_` and `-`; clearing one removes it. Folders, presets and arbitrary commands cannot have aliases.
- **File tools:** Space previews a selected file in launcher `/` results or on the desktop; Esc closes. Images and UTF-8 text/code are read-only; text is limited to 256 KiB, PDF shows its first page when `pdftoppm` is installed, and other files show metadata. Open with in either context menu chooses an application for one opening. Remember for this file type is off by default; turn it on explicitly to change the MIME default.
- **Background jobs:** Shift+Enter on a launcher `$` command tracks it under Background jobs (`psc jobs open`), with elapsed time, recent output, Cancel and Run again. Terminal commands and apps are excluded. Jobs survive shell reloads; temporary runtime storage keeps active jobs and the last 20 completed jobs until logout. Output shows its most recent 64 KiB. Each job shows its state (a pulsing dot while it runs, ✓ done, ✕ failed), the command, how long it took and its exit code; Output opens its latest output in a code block. Launching an app shows Starting… briefly and suppresses duplicate opens while pending; a confirmed startup failure offers details and Retry. Slow startup alone is never treated as failure.
- **Floating sizes:** a floating window's launcher context menu offers 1280 × 720, 960 × 600 and Centre. These affect that window at runtime.
- **Style (Settings → Experimental):** Settings → Experimental → Style switches between Classic and TUI immediately and remembers the choice. TUI uses JetBrainsMono Nerd Font (`ttf-jetbrains-mono-nerd`), square frames, bracket switches and block meters. Phases 1–3 cover shared controls, Settings, the full-width 41 px top strip/control, the launcher and Alt+Tab. TUI launcher uses flat 576 px rows; Alt+Tab uses a 520 px list, including a single-window state. Existing search prefixes, pins/aliases, actions, Alt release and grouped-tab refocus remain. Bluetooth basics stay in the TUI launcher; detailed Bluetooth settings remain in Settings. TUI's strip reserves its space but hides in Zen, over fullscreen windows and under the Overview (touch the top edge to bring it back); tray icons and minimised windows sit behind one ‹ arrow; CPU/memory refresh while Settings is closed. Click vol for control, use ↑/↓, Space, ←/→ and Esc; LocalSend opens beside it. bt opens Settings → Bluetooth; the strip has no Ethernet reading. The notification centre (bell) and calendar (clock) open centred under the strip. The Overview, notifications, calendar, LocalSend, polkit, wallpaper switcher (type to filter, ↑/↓, Tab for the fit, Ctrl+R random), toasts, OSD, power menu (↑/↓ too), menus, media card and capture tools are drawn in TUI as well; Lens, quick chat and the capture menu are drawn in TUI too (quick chat: Ctrl+H recent chats, Ctrl+N new chat; capture menu: ↑/↓). Classic retains its rounded look. Settings defaults to 1040 × 800 in TUI and 1040 × 760 in Classic.
- **Colours:** Settings → Experimental → Colours switches between Pistachio Noir (the default) and Noir: neutral greys, light grey for what's active, and one red for errors and danger. It applies live to Classic and TUI and to every part of the shell (and to Hyprland's window tabs); app icons, window pictures and your wallpaper keep their own colours.
- **Restart into…:** in the power menu (I), lists the other entries of your Limine menu (1, 2, …) and Firmware setup (F). Picking an entry asks for your password (it sets Limine's next boot with `bootctl set-oneshot`), then restarts; that boot only, Limine's default stays. Firmware setup needs no password. Needs Limine (12.9 or later publishes its entries) on UEFI.
- **Export and import settings:** Settings → About → Your settings. Export writes every preference and the launcher's pins, aliases and workspace presets to `~/.config/pistachio-shell/settings.toml` (sections like the Settings pages, times as "HH:MM"; the previous file is kept as `settings.toml.bak`). Import reads that file and lists what would change (old → new) and anything it skipped, and changes nothing until you press Apply. Never in the file: your Cider token, LocalSend's known devices, notification and usage history, the wallpaper and desktop icon positions. Needs Python 3.11+ (it reads TOML with Python's own `tomllib`).
- **About surprise:** there is a playful, temporary surprise in the Settings sidebar, with the real build and version details and the usual source and settings actions; closing Settings puts it away.
- **Settings:** a normal movable, resizable window, opened from System in the launcher, the sliders button in quick settings, or `psc settings open`. The sidebar holds Appearance; Display & night light; Sound (devices and application volumes, with this workspace first); Notifications; Bluetooth; wired Network status; LocalSend (when installed); Lens; Apps & places; System monitor; Shell health; About. Switches and levels apply immediately. Text edits use Save/Cancel; weather cities and Cider tokens are checked before saving. Sound includes microphone level/mute, headphones takeover and volume tick; unplugged devices cannot be selected. System monitor lists removable drives with Eject. Wallpaper and LocalSend send buttons reuse their existing panels. Ctrl+F searches all settings; Enter on a result opens its page and scrolls to the control. Tab and Shift+Tab move between controls; Ctrl+W or Esc closes (Esc first clears search, cancels a reset review or cancels a dialog). Drag the title bar to move, its corner to resize, or double-click the title bar to maximise. Outside clicks leave it open. Settings uses solid surfaces; Appearance's frost setting still controls the shell's layer panels.
- **Shell health:** Settings → Shell health (`psc settings section health`) checks installed dependencies, helper sources and the number of errors in the last 200 shell log lines. Check sign-in runs only `claude auth status` and `codex login status`; it never sends a paid model request. Copy diagnostics includes status labels/counts, with no raw logs, identities, tokens, paths or network addresses.
- **Page reset:** Reset page preferences opens a review of the changed shell preferences before applying. Available on Appearance, Display (schedule only), Sound, Notifications, Lens, Apps & places and LocalSend. Device choices, levels, connections, pairings, credentials and saved content are kept. Esc or Cancel discards the review.
- **Microphone check:** Settings → Sound → Devices has Start meter, Record 5 seconds and Play sample. Access begins only on an explicit Start/Record; recording closes the microphone after five seconds and playback requires Play. Stop & discard, leaving Devices, changing input, minimising or closing Settings stops access and removes the temporary sample.
- **Connection details:** wired Network shows IPv4/IPv6 addresses, gateways and DNS with Copy buttons. It remains status only. Bluetooth devices show the active audio profile, codec and sample rate when PipeWire reports them; those details are read-only.
- **Media selection:** Settings → Sound → Media player chooses Auto or one MPRIS player for the bar/cards during this shell session. If the chosen player disappears, Auto is used temporarily; the choice resumes when that player returns. It is not saved.
- **Bluetooth pairing:** the shell is the pairing agent, so devices that show or ask for a code pair too (phones, keyboards). The question ("Pair with …?", the code to compare or to type) opens in Settings.
- **OSD:** a volume and brightness indicator, which also names the new output device when the sound moves, e.g. to headphones as they connect, and says when the desktop icons are shown or hidden. It names the apps that start recording from the microphone or sharing your screen, and says when they've all stopped (privacy cues, so they show even in Do not disturb and fullscreen).
- **Power menu:** lock, log out, suspend, reboot and shut down, over a blurred still of the screen.
- **Lock screen:** checks your password through PAM, over a blurred still of the desktop (kept in memory, never written to disk), with what's playing and its controls, and how many notifications came that you haven't seen ("3 new notifications": only the count, nothing they say). The password shows as dots that pop in as you type; a wrong one shakes the field. An empty Enter is ignored, so it can't cost a failed-login strike.
- **Weather:** above the calendar in the notification centre: now, today's high and low, and five days; the chevron opens the next hours (with the chance of rain) and the feels-like temperature, wind, humidity and sunset. From Open-Meteo for your city: set it in Settings → Apps & places → Weather location or with `weather city <name>`; the shell remembers it.
- **Desktop icons:** the files and folders in your Desktop folder, on the wallpaper (so wherever no window covers it), as rounded tiles with a glyph coloured by kind (folders sage blue, pictures show themselves, apps their icon). Click to select, double-click to open, drag to move (the place is kept; dropping on another icon swaps them). Drag out a box on the desktop to select several, or Ctrl+click to add or take away one (on a workspace without windows: elsewhere the desktop doesn't hear Ctrl); a drag then moves them all, and their menu opens or trashes them all. Drag icons onto a window (a Discord message, a browser's upload box) to hand it the files; drop files from another app (hyprfm) on the desktop to copy them there (copied, never moved; nothing there is overwritten). Right-click one for Open, Rename, Move to trash and Show in file manager; right-click the desktop for New folder, Open Desktop folder, Wallpapers and Hide desktop icons (while they're hidden, the same menu has Show desktop icons). Renaming and naming a folder ask in the launcher. Hidden in showoff mode; switch them off in launcher → System → Settings → Appearance → Desktop icons, or with `desktop toggle` (bind it to a key); the OSD says which.
- **LocalSend:** send files to phones and other computers on your network, and receive from them, from quick settings (only while the LocalSend app is installed; the shell does it itself, so the app itself shouldn't be running). Open the LocalSend row: add files (+), a folder, or paste copied files or text, or drop files on the page, then click a device under Nearby; the page shows the transfer and Cancel. With Receive files on (off until you switch it on, on the page or by clicking the row's icon, and remembered), devices see this PC under its hostname; each request waits in a toast for Accept or Decline, text messages show in the toast with Copy, and what arrives goes to `~/Downloads` with a notification to open the folder. The sliders on the page change the name, the folder, and whether devices you accepted before can send without asking. Right-click desktop icons for Send with LocalSend.
- **Workspaces:** scroll over the bar's dots for the next or previous workspace. Each switch shows the workspace OSD (its name or number, what's on it, and the dots; never over a fullscreen window; Settings → Appearance → Workspace OSD). Name a workspace with F2 on its card in the launcher's Workspaces mode, or `workspace name <text>` for the one you're on (empty clears it): names show in the OSD, on the cards and in the dots' tooltip, and last until you log out. Type a name in the launcher to go there. Presets keep every workspace for good: in Workspaces mode, "Save workspaces as preset…" (their names) or "Save workspaces and apps as preset…" (also the apps open on every workspace); Enter on a preset (in Workspaces mode, or found by name in All) puts its names back and opens its apps on their workspaces in the background, skipping ones already there; → on a preset shows Delete (it asks first), as does Ctrl+Backspace. `workspace preset <name>` loads one from a keybind.
- **Peek at the bar:** `bar peek` brings the hidden bar out for 2 s, for a keybind (e.g. `hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("psc bar peek"))`).
- **Weather at a glance:** today's temperature and sky under the date on the lock screen, and in the clock's tooltip.
- **Keys on the desktop:** after a click on the desktop (on a workspace without windows), the arrows move the selection, Enter opens, Delete moves to trash, F2 renames, Ctrl+A selects all, Esc lets go.
- **About:** Settings → About (or `psc settings section about`; `launcher open about` also opens it): the branch the shell runs from (main is marked stable with a shield, any other branch experimental with a flask: it may be unstable), the shell's version and last commit, Quickshell, Hyprland and Qt versions, and the source on GitHub (View source opens it).
- **The shell's own use:** Settings → System monitor shows the CPU (a share of the whole machine) and memory the shell and its helpers use, Hyprland's, and the two together.
- **Launcher scroll bar:** while you use the mouse over a long list, a thin bar at its right edge shows where you are; drag it or click its track to scroll. It fades a second after the mouse rests.
- **Launcher with the mouse:** right-click a row or a workspace card for what it offers: an app's own actions (a browser's New incognito window), a window's Switch, Float or tile and Close, a workspace's Go, Move the last window here, Name or Rename, Clear its name and Close its windows (asks first), a preset's Load and Delete, a device's Connect and Forget, a file's Open and Show in folder. The key hints at the bottom wrap to fit, with the results list reserving room for every line. They are buttons too (↵, Esc, Tab, →, Ctrl W…), and text cut short with "…" shows whole in a tooltip when you rest the pointer on it.
- **Cider:** with Cider's app token pasted in Settings → Apps & places → Cider token (make one in Cider: Settings → Connectivity → Manage External Application Access), the media card shows Up next (a click plays from there), and `m <words>` in the launcher searches Apple Music: Enter plays, Shift+Enter plays next, → adds to the queue.
- **More in the launcher:** your recent CLion projects, your recent VS Code folders and workspaces, and your games (Steam's, with covers, and Sober) come up as you type their names (`clion` lists every CLion project, `vscode` or `code` every VS Code one, `games` every game); `kill <name>` lists your programs, busiest first, one row per program with all its processes, and ends them all at once, like killall (asks first; the shell and its own helpers are never included; Force quit in its right-click menu); `tldr <command>` shows tldr's description and examples (Enter copies one), and a row that opens the full manual (`man`) in your terminal.
- **Windows:** right-click a window row for Pin on top (Ctrl+P; it floats and stays above everything, on every workspace), and a workspace card for Move its windows to another workspace.
- **Minimising windows:** `window minimize` (bind it to a key) hides the focused window in a special workspace the shell never shows. A pill right of the bar (right of the tray pill, if there is one) shows the minimised windows' app icons while there are any; click one to bring it back onto the workspace you're on. It stays in Zen mode, which hides the bar: smaller, at the bottom of the screen, beside Zen's Pomodoro pill if one runs (not over a fullscreen game or video). The launcher's Windows list shows them too, marked minimised (Enter brings one back); Alt+Tab and the Overview leave them out.
- **Tabbed workspaces, i3-style:** a workspace card's right-click menu → Tabbed (or `workspace tabbed` for the one you're on): its windows gather into one group under Hyprland's own tab bar, which the shell styles in the Pistachio look (pill tabs, the shown one pistachio, Manrope; set at runtime, your Hyprland config is untouched, and again after each config reload); new windows join it; click a tab to show it, middle-click to close it; the same entry tiles them again. It lasts until you log out. Right-click the bar for the same switch, and to name the workspace. An OSD says when tabs go on or off (Settings → Appearance → Tabbed OSD). Alt+` is Alt+Tab for the tabs alone (`switcher tabs`; hold Alt, ` steps, Shift+` back, let go to show the one picked); bind it with `hl.bind("ALT + grave", hl.dsp.exec_cmd(shell .. "switcher tabs"))`. Keybind: `hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(shell .. "workspace tabbed"))`. The group's border takes your window border's colours.
- **Screenshot menu:** Colour (hyprpicker: click anywhere, the hex code is copied and shown with a swatch) and Record (gpu-screen-recorder). Record opens setup: remember Audio Off/System/Mic/Both and countdown Off/3/5/10 seconds, then select an area or Full screen. Defaults are System audio, microphone off, countdown off. Mic uses the current Sound input. Esc cancels the countdown. The recording pill has Pause/Resume and Stop; the bar stops on left click and pauses/resumes on right click. Elapsed excludes paused time. Videos go to `~/Videos`; the saved notification offers Trim when FFmpeg is installed. Trim takes start/end seconds and saves a new `_trimmed.mp4` beside the original, without overwriting it. Area recordings retain their click-through frame and outside control pill; if it cannot fit, use the bar. The screenshot notification has Edit (satty: arrows, boxes, blur; saving writes over the picture).
- **Sound mixer:** the mixer button at the bottom of quick settings (or `quicksettings mixer`): a volume slider for each app playing sound, those on your workspace first; click an app's icon to mute it.
- **Overview:** your workspaces and windows at a glance, over the wallpaper (blurred, settling from a slight zoom as it opens, with the cards arriving one after another). The bar hides meanwhile, and switching workspaces in it shows no workspace OSD. Along the top, each workspace as a sketch of its windows (click one to go there; New makes the next one); under it, this workspace's windows as live pictures (a tabbed group is one card with its tabs). Click or Enter focuses a window, Ctrl+W closes it, Ctrl+F floats it (as in the launcher's Windows mode, so every letter types into the search); Ctrl+1…9 or 0 goes to workspace 1–10 and Ctrl+Shift+1…9 or 0 sends the selected window there; drag a window onto a workspace above to send it there. Tab shows All windows, a column per workspace; just type to search every window by title, app or workspace (↑↓←→ and Enter; Backspace erases; Esc clears, then leaves). An empty workspace offers Open launcher and Load a preset. Open it with `overview toggle` on a key of your choice (see the keybinds), or `overview` in the launcher.
- **Integrations:** Settings → Integrations has a switch for each other app the shell works with: GNOME Calendar's events, GNOME Clocks' alarms (off: Clocks rings them itself), the weather, and in the launcher VS Code, CLion, Steam games, Sober, Cider, Claude Desktop, libqalculate and tldr. Off, the shell acts as if that app weren't installed.
- **Zen and Focus:** in the launcher (search `zen` or `focus`, or System's quick controls) and Settings → Focus & Zen. Zen mode is distraction-free: no bar, pills or desktop icons, no gaps or window borders (Hyprland's, changed at runtime and put back as they were; your config files are never touched), and toasts wait. A Focus session holds toasts for one stretch (15 min to 2 h) or as a Pomodoro (work 25 min, break 5, a long break after 4 rounds; all adjustable), with toasts held only while working; apps you allow in Settings still reach you (not in Zen). Zen can run a Pomodoro too, and Focus can turn Zen on for the session. A Pomodoro also runs on its own (launcher `pomodoro`, or Settings → Focus & Zen → Pomodoro): just the rounds, the pill and the chimes, nothing held back. The time left shows as a pill beside the clock (or, in Zen, where the bar would be): click to pause or resume; right-click the clock pill (or use the Zen pill's buttons) to skip to the next phase or end it. A soft chime and the OSD mark each change. No IPC (the launcher and Settings are the way in).
- **Phone timer preview:** turn on Settings → Experimental → Phone timer preview (off by default). While Focus or a Pomodoro runs, the start toast and the phone button beside the timer open a QR code and local address. Scan it on a phone on the same network to see the live phase and countdown, including pauses. The page is read-only; the local server stops when the session ends or you turn the switch off. `qrencode` provides the QR code; without it the address still appears. The preview uses a private wired or wireless IPv4 address and does not change firewall or router settings.
- **Timers, stopwatch and alarms:** right-click the clock pill: Timer… (type `25m tea`, `1h 30m`, `90s`), Start a stopwatch (Lap, Pause, Stop), Alarm… (`7:30 wake up`, `6pm`), your alarms with on/off, Open Clocks. A running timer or stopwatch shows as a pill beside the clock (click pauses or resumes, right-click for the menu). Alarms are GNOME Clocks' own (`gnome-clocks`; same list in both); the shell rings them and timers with its own card (Snooze 10 min, Stop; Enter stops, S snoozes; a soft chime until answered, through Do not disturb), so Clocks' own alarm toasts are hidden. Timers and the stopwatch end with a shell restart. Keybinds: `clocks timer "25m tea"`, `clocks stopwatch`, `clocks stop`.
- **Wallpaper:** the shell draws it (hyprpaper isn't needed). While night light is on, it dims a little, so the desktop isn't the brightest thing on screen late at night (the desktop icons stay as they are). Launcher → Wallpapers opens a switcher with the images in `~/Pictures/Wallpapers`: the screen behind it previews the one you pick, and each image keeps its own fit (Fill, Fit, Center, Tile). New wallpapers fade in.
- **Window switcher:** Alt+Tab shows every open window, on any workspace, with a picture of each, most recently used first; let go of Alt to switch.
- **Showoff mode:** for screenshots of your setup. It moves to an empty workspace, opens the notification centre (with the calendar and the weather) on the left and quick settings on the right, sliding in one after the other while the wallpaper settles, and fastfetch in your terminal between them, with the shell's own config: a pistachio and your system, without your user name, host name or anything else that names the machine. Private things are hidden meanwhile: notifications (the centre shows Inbox zero, and no toast shows, not even a critical one; they all reach the centre), window titles, the weather's city and Bluetooth device names. What's playing stays visible (cover, title, artist), as in most setup screenshots. Take the screenshot with your usual key. Esc, a click on the wallpaper, closing the terminal, going to another workspace or starting it again ends it and takes you back. Start it from `psc showoff toggle` (bind it to a key if you use it often).
- **System warnings:** a notification when a disk has under 10 % free, or the CPU or GPU has been at 85 °C or more for a minute (checked every 30 seconds in the background).
- **Screenshots:** freeze the screen and drag out an area, or choose from a compact toolbar near the top of the screen: Region, Window, Screen, Text and Lens, with Colour and Record when installed. Hover a choice or select it with the arrows for a help card with its shortcut or IPC command; Lens names your preferred agent. The toolbar remembers Save (default), Copy or Both. Save/Both write to `~/Pictures/Screenshots/`; Copy uses only the runtime folder and never archives a picture there. Copy/Both put the image on the clipboard immediately. A notification shows the picture: click it to copy the picture, or Open or Delete it (to the trash). It shows even in Do not disturb. A soft pop sounds as the picture is taken (with the notification sound's switch; the notification itself then stays silent). Text copies the words in the area you drag out (an error in a game, a video's subtitle), read by tesseract in Polish and English; the notification shows the area and the start of the text, and a click copies it again.
- **Pistachio Lens:** screenshot menu → Lens (**L**), or `psc screenshot lens`: drag out an area, then ask about it. Explain, Fix it, Translate, Summarise and Extract text send at once. Enter sends, Shift+Enter adds a line, Esc closes; clicking outside does not close it. Stop cancels a request; an error keeps the snip and question for Try again or Edit question. Answers have selectable Markdown, code-copy buttons and a follow-up field. Suggested searches open in your browser only when clicked; other suggestions send a follow-up. Settings → **Lens** has a preferred-provider switch and separate Claude / ChatGPT cards (through their installed CLIs). Model and Effort open anchored option lists with mouse and keyboard selection. Each provider keeps its own Model and Effort: Claude defaults to Haiku 5.5 / medium, Codex to GPT-6 Luna / low. Two separate switches can use the other provider if one is unavailable (off by default; one fallback attempt). The card names the provider that answered. Each chat saves automatically under `~/lens-chats/<date time first-question>/`, with `snip.png` and `chat.md`; the image is linked at the top and the Markdown is rewritten after each answer. No history UI; closing ends that card's conversation. Pin and Open in Claude Desktop are deferred.
- **Quick chat:** type `ask` in the launcher (or `ask` and your question), pick Quick chat · Ask AI, the Quick chat tile in quick settings (beside LocalSend; Settings → Lens and AI can leave it out, and LocalSend takes the whole row again), or `chat toggle` / `chat ask "…"` for a key: a chat above the bar for short questions, with Claude Code or Codex, as chosen in Settings → Lens and AI (the same models and efforts). Claude's answers appear as they're written; Codex's arrive whole. The name in its header switches this chat to Claude, ChatGPT or Ask both (each answers, then your preferred one writes one answer from the two). Text you have selected when it opens comes along as a card (✕ leaves it out); the paperclip's Include adds a picture of the window you were in or the clipboard, and Snip a region goes on to Lens: the chat closes, you drag out an area, and what you'd typed becomes Lens's question (Esc gives it back to the chat). Answers show code blocks, coloured by language (as in Lens), with Copy, and under the latest Copy, Ask again and Continue in Claude Desktop or the ChatGPT app. Esc stops an answer being written, else closes, and so does a click beside it; Recent (the clock) lists earlier chats, searchable, Enter opens one to continue it. Chats are saved in `~/quick-chats/` (chat.md to read, with each provider's own answer for Ask both).
  **Add snip / Add image** attaches up to three images with numbered, removable thumbnails. Image files need `zenity` and can be PNG, JPEG, WebP, GIF or BMP, up to 32 MiB each. Follow-ups reuse the attached images. Files are copied before sending, so later changes to the originals do not change that question. Removing an image before its first request keeps it out of the saved chat; previously sent images remain linked there.
  **Ask both** sends the question to Claude and ChatGPT, then asks your preferred provider to combine their replies into **one answer**. This uses **three model requests**, plus any coding retries you already accepted. Each provider uses its own settings; the preferred provider stays unchanged. Both source responses and the combined answer are saved in `chat.md`, with image files beside it. Source file suggestions never get Apply: only the final combined replacement is diffed against the original file snapshot for explicit Apply/Discard. Stop or a failed combination never applies a source proposal. Ask both does not substitute one provider for the other when one fails.
  The toolbar groups Add snip, Add image and Attach file together; answer-agent actions share their own row above the follow-up input. Image-add buttons stay visible but disabled at three images. **Attach file** adds one UTF-8 text file (up to 32 KiB; needs `zenity`). With a file attached, **Fix it** proposes changes and explains them. Review the diff, then **Apply changes** or **Discard**; the agent itself stays read-only. Apply refuses to overwrite a file whose contents changed since the request. Change file / Remove clears an unreviewed proposal. On an answer or error, **Ask ChatGPT instead / Ask Claude instead** sends the same question, attached images, file snapshot and completed conversation to the other agent using its own model/effort. This manual transfer leaves the preferred provider unchanged and does not fall back automatically. Both answers and proposal review status are saved in `chat.md`; a transferred proposal needs its own Apply. A new question reads the current attached file again.
  **Suggest a coding model** (Settings → Lens and AI, on by default) asks once per snip after the normal model recognises a coding question. **Keep current answer** or Esc declines; **Use coding model** retries the same question, snip and file snapshot. Arrow keys or Tab choose, Enter confirms; Keep is selected first. Separate **Coding only** Model/Effort presets default to Sonnet / high and GPT-6.1 Sol / high. Accepting applies to coding questions in that conversation only, without changing normal settings. Every new question first uses the normal model to identify its task; accepted coding questions then make a second request with the coding preset. Translate, Summarise and Extract text always use the normal preset, even over code; typed requests are classified by the agent. Both the actual model and effort are shown and saved. A failed or stopped retry keeps the previous answer and proposal; generated edits still need Apply.
- **USB drives:** mounted the moment you plug them in (by the shell's own helper), with a notification that has Browse directory. An encrypted drive isn't unlocked by the shell: a notification offers the file manager, which can. Eject them from Settings → System monitor. A failed eject opens the applications still using the drive, when their processes are visible, with Return to app for matching windows and Try eject again. The shell never force-closes an app or forces an unmount.
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
| File preview / Open with | `python`, `python-gobject`, `glib2`; optional `poppler` (`pdftoppm`) | read-only previews and installed MIME handlers | PDF falls back to metadata without Poppler |
| File search | `python` (already there with `python-gobject`), `xdg-utils` | the launcher's `/` search through your home folder, opening what it finds | `/` finds nothing |
| Pairing agent | the shell's helpers, built by `install.sh` (see Helpers below) | pairing devices that show or ask for a code, and devices asking to connect | only devices that need no code pair; the log says `bluetooth agent exited` |
| Screenshots | `libnotify` (`notify-send`), `wl-clipboard` (also copies emoji), `xdg-utils`, `glib2` (`gio`); `xdg-user-dirs` optional | the notification after a screenshot, Copy, Open and Delete; the Pictures folder in your language | no notification (the picture is still saved); `~/Pictures/Screenshots` |
| Weather | a network connection (Open-Meteo, no account; only your city's coordinates are sent, every 30 min) | the weather panel | no weather panel |
| Screen sharing | `xdg-desktop-portal-hyprland` | sharing your screen from Discord, browsers or OBS, and the shell's screen-sharing indicator | apps can't share the screen at all |
| Polkit agent | the shell's helpers, built by `install.sh`; `polkit` | the admin password dialog | apps that need admin rights fail or hang; the log says `polkit agent` |
| Network | `networkmanager`, `iproute2`, with `NetworkManager.service` running | Ethernet tile/chip; `ip` and `nmcli` supply read-only address, gateway and DNS details | Ethernet shows as unplugged |
| Brightness | `ddcutil`, and DDC/CI switched on in your monitor's own menu | brightness slider, brightness keys, OSD | the brightness slider is hidden |
| Night light | `hyprsunset` | Night light tile, warmth slider and schedule; the shell starts and stops it itself | the tile says "Not installed" |
| Idle lock (optional) | `hypridle`, with `extras/hypridle.conf` | locking after idle time, screen off, locking before any suspend | only the power menu's Suspend locks first |
| GPU readings (optional) | the NVIDIA driver's `nvidia-smi` | the GPU row of the launcher's System monitor | no GPU row (CPU and memory come from `/proc`, the CPU temperature from its `coretemp` or `k10temp` sensor) |
| Power actions | `systemd` (already there) | suspend, reboot, shut down | |
| Terminal | `kitty` (or `ghostty`, `foot`, `alacritty`, `wezterm`, `konsole`: pick it in Settings → Apps & places, or set `$TERMINAL`) | launching apps marked `Terminal=true`, `$` commands | those don't start |
| Desktop icons | `glib2` (`gio`, for Move to trash), `xdg-utils`, `xdg-user-dirs` optional | the Desktop folder's icons: opening, trashing, the folder in your language | no trash from the desktop's menu; `~/Desktop` |
| Microphone check (optional) | `pipewire` (`pw-record`, `pw-play`), `python` | explicit input meter, temporary five-second sample and playback | the card explains unavailable audio tools |
| Notification sound | `pipewire`'s `pw-play` (already there) | the sound with each toast (the shell brings its own, `src/sounds/notification.wav`) | silent toasts |
| Showoff mode (optional) | `fastfetch` | the terminal in showoff mode | the panels open without it |
| LocalSend | `localsend` (the AUR's `localsend-bin`, or Flathub's) installed but not running; the shell's helpers, built by `install.sh`; `openssl` (already there); `zenity` for the Add files and Add folder buttons; `wl-clipboard` for Paste | sending and receiving in quick settings | no LocalSend row; without `zenity`, add files by dropping or pasting them |
| Screen tools (optional) | `hyprpicker`, `gpu-screen-recorder`, `satty`; `ffmpeg`/`ffprobe` for Trim | Colour and Record, Edit on screenshot notifications, Trim on recording notifications | missing tool's choice is hidden |
| Calendar events (optional) | `gnome-calendar` (with `evolution-data-server`), `python-gobject` | events in the month calendar | the calendar shows dates only |
| Launcher extras (optional) | `libqalculate` (`qalc`); `tldr`; Cider (with its app token); CLion; VS Code; Steam | `tldr`, `m`, CLion and VS Code projects, games | that part of the launcher stays empty |
| USB drives | the shell's helpers, built by `install.sh`; `udisks2` (already there). Don't run `udiskie` beside the shell: it would do the same job twice | mounting drives as they're plugged in; Eject | drives don't mount by themselves; Eject still works |
| Helpers | `rust` (`cargo`) and `openssl` to build them; `install.sh` builds `rust/` and copies `pistachio-auth`, `pistachio-devices` and `pistachio-localsend` to `~/.local/bin` | the polkit agent, the pairing agent, USB drives, LocalSend | those four don't work; the log names the one that's missing and says to run `install.sh` |
| Text from the screen (optional) | `tesseract`, `tesseract-data-eng`, `tesseract-data-pol` | the screenshot menu's Text | "Couldn't read the text: tesseract isn't installed" |
| Lens and quick chat (optional) | `python`; Claude Code CLI (`claude`) and/or Codex CLI (`codex`), logged in with access to the selected model; `zenity` for text/image file attachments | Lens answers and follow-ups; uses the CLIs' existing authentication, no API key setting in the shell | the card explains the unavailable provider, or tries the other if fallback is on; Lens's Extract text uses the selected agent, not tesseract |
| Font | Manrope (weights 500 to 800), installed by `install.sh`; needs `curl` | all text | Qt falls back to another font |
| Mono font (optional) | `ttf-jetbrains-mono` | the details in the admin password dialog | another monospace font |

The `ddcutil` package already loads the `i2c-dev` module and gives the logged-in user access to the monitor, so it needs no group or module setup. Not every monitor supports DDC/CI; check with `ddcutil getvcp 10`.

Manrope isn't in the official repos, so `install.sh` downloads it: Google Fonts' variable TTF (every weight from 200 to 800 in one file) and its licence go into `~/.local/share/fonts/manrope/`. Not Fontsource's files: they name every weight "Manrope ExtraLight", so nothing matches "Manrope" and the shell falls back to another font. By hand: download `Manrope[wght].ttf` from [Google Fonts](https://fonts.google.com/specimen/Manrope) into that folder and run `fc-cache -f`.

`python3 -B tests/cat-interaction.test.py` checks desktop hover, petting, the timed reaction, icon click priority and Zen using isolated stand-ins. Set `PISTACHIO_CAT_NATIVE=1` to exercise the same controls on Wayland.

`sh tests/layout.sh` checks footer wrapping/clicks at 640, 480 and 320 px, plus natural and bounded action-button sizing, with real Qt controls and no system services. Native Lens checks also cover header-button bounds and long-answer/action layouts.

`sh tests/launcher-tools.sh` checks preview bounds/UTF-8, explicit MIME-default changes with a stand-in, job output/exit/cancellation, PDF child cleanup, and the real native launcher extras panel with isolated settings/runtime. It also checks pin/alias and temporary job history persistence across restart. It needs a live Wayland session, Python with GObject, Quickshell and QtTest; it never launches owner apps or changes owner MIME defaults.

`sh tests/system.sh` checks read-only detail parsing, safe eject failures, bounded/redacted diagnostics and actual microphone-helper process cleanup, then runs the Settings suite below, including stale-save and reset/restart persistence regressions. Hardware commands use temporary stand-ins; no desktop devices, credentials or model requests are touched.

`sh tests/tui-launcher.sh` checks native launcher/switcher drawing, input, style loading, pins/aliases, scanning/pairing handoff through stand-ins, and advanced rows. Optional grim captures: `PISTACHIO_LAUNCHER_SHOTS=/tmp/launcher-shots sh tests/tui-launcher.sh` (create the directory first). It launches no owner apps, pairs no devices and uses isolated settings/runtime. `sh tests/bar.sh` checks the native bar/control on Hyprland with device stand-ins. `sh tests/settings.sh` tests the actual Settings controls with QtTest mouse/keyboard input and isolated service stand-ins. It changes no desktop devices or owner settings. It needs Python, Quickshell and the QtTest QML module from `qt6-declarative`. Native visual checks: `PISTACHIO_SETTINGS_NATIVE=1 PISTACHIO_SETTINGS_SHOTS=/tmp/settings-shots sh tests/settings.sh` (create the output directory first). This uses a disposable window and service stand-ins on the live Hyprland session, captures with grim and cleans its process/state; it never pairs devices or sends model requests. The regular offscreen suite checks both styles, Appearance selection, model filtering, validation, search controls and restart persistence.

`sh tests/screenshots.sh` briefly opens the actual picker on a live Wayland desktop and checks its toolbar, tooltip, shortcuts and screen/region/window/text/Lens crop sizes. Captures stay under a temporary directory and are removed afterwards. Clipboard, OCR, colour and recording actions use fixture services. It needs Python with Pillow (`python-pillow`), Quickshell and the QtTest QML module.

`sh tests/lens.sh` runs fake-provider helper checks and offscreen Qt mouse/keyboard tests for image attachments, combined answers, sessions, cancellation and explicit Apply. It makes no model requests and isolates saved chats under a temporary home. `sh tests/lens-native.sh` briefly opens the real Lens windows on Wayland with fake providers, checks three-image/combined-answer states and saves temporary grim screenshots under `/tmp`; it reports transient Qt Wayland text-input warnings separately from QML errors. These need Quickshell, Python, QtTest, and grim for the native check.

`sh tests/recording.sh` tests the capture service and real controls on Wayland with a fake recorder: Save/Copy/Both paths, audio arguments, pause elapsed, countdown start/Escape, exact encoder bounds, area placement and Stop/failure cleanup. It also uses real FFmpeg on a temporary synthetic video to verify Trim saves a new file. `python3 -B tests/capture-helper.test.py` checks precise trims, invalid ranges and unique targets. These require FFmpeg and write only temporary files; clipboard and notifications are simulated. `tests/js.sh` also checks that the helper’s control never overlaps the recorded rectangle.



For the other tests in `tests/` you also need `libnotify` (`notify-send`); `tests/js.sh` runs the launcher, calendar and settings-search unit tests with `nodejs` if it's installed, else in Quickshell's own JavaScript engine; `pw-cat` (part of `pipewire`) plays the silent test stream, `gst-plugin-pipewire` and `gst-plugins-base` stand in for a screencast (skipped without them), and `gdbus` (part of `glib2`) asks the pairing and polkit agents their test questions.

## Installation

1. **Install the packages:**

   ```sh
   sudo pacman -S --needed hyprland quickshell pipewire wireplumber pipewire-pulse \
       bluez bluez-utils python-gobject networkmanager ddcutil hyprsunset kitty rust
   sudo systemctl enable --now bluetooth.service NetworkManager.service
   ```

   Optional, for copying text from the screen: `sudo pacman -S tesseract tesseract-data-eng tesseract-data-pol`.


2. **Put the repo somewhere permanent**, for example `~/projects/pistachio-shell`. The shell runs straight from it, so if you move it later, run `./install.sh` again.

3. **Run the install script** from the repo:

   ```sh
   cd ~/projects/pistachio-shell
   ./install.sh
   ```

   Preview with `./install.sh dry`: it checks existing links and reports planned links, helper builds/installs and font installation without changing files, building helpers or downloading fonts.

   It links the repo's `src/` to `~/.config/quickshell/pistachio`, where Quickshell finds a config named `pistachio`, and `bin/psc` (see [psc](#psc)) to `~/.local/bin/psc`. It also builds the helper programs in `rust/` with cargo and copies them to `~/.local/bin` (run it again after pulling changes to `rust/`, then `psc restart`), and installs the Manrope font (see Requirements). It warns if `~/.local/bin` isn't on your PATH or Quickshell isn't installed. Run it again after moving the repo to update the links. It never replaces a real file or folder that is in the way; it stops and tells you instead. By hand, it's:

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
| `desktop toggle` / `desktop on` / `desktop off` | shows or hides the desktop icons, with the OSD saying which |
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

## Frosted panels

Settings → Appearance → Frosted panels makes the bar, its pills and the panels (quick settings, the notification centre with the calendar and the weather, the launcher, menus, toasts, the OSD, the media card) see-through, with what's behind them blurred; Glassy in that selector makes them more see-through (72 % opaque instead of 88 %). Drop shadows go while it's on. The blur is Hyprland's, so it needs this rule in your config (e.g. `~/.config/hypr/lua/rules.lua`, or your own file); without it the panels are see-through but not blurred, which is why the setting starts off:

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
- **A device that shows a code won't pair:** `psc log` shows a `bluetooth agent` line when the pairing agent can't start or register; run `./install.sh` if it says so (it builds the agent). While the shell runs it is BlueZ's default agent, so it also takes over from another one, such as a KDE session's.
- **The wallpaper flickers or the old one shows:** hyprpaper (or another wallpaper program) still runs on the background layer; take it out of your autostart (`hl.exec_cmd("hyprpaper")`).
- **PrtSc doesn't trigger the Print binds:** some keyboards send PrtSc as the Windows "snip" shortcut, Shift+Super+S, so Hyprland never sees Print (`wev` shows Shift and Super going down in the same millisecond). Bind that instead: `mainMod .. " + SHIFT + S"` for `screenshot region`, and `mainMod .. " + ALT + SHIFT + S"` for `screenshot menu` (Alt+PrtSc). Remapping the key to Print Screen in the keyboard's firmware (VIA, QMK) works too.
- **Screen sharing fails, or the app finds nothing to share:** `xdg-desktop-portal-hyprland` is missing, or the portal service started before it was installed. Restart it with `systemctl --user restart xdg-desktop-portal` (or log in again).
- **An app that needs admin rights fails or hangs without asking:** no polkit agent runs. `psc log` shows a `polkit agent` line when the shell's can't start or register: run `./install.sh` if it says so (it builds the agent), and stop any other agent for this session (polkit takes one per session, e.g. `polkit-gnome` or `hyprpolkitagent` started from the Hyprland config).
- **An app's tray icon doesn't show:** the shell shows StatusNotifierItem icons, which most current apps use; apps with only the old X11 tray don't appear. Icons an app marks as passive (idle) are left out on purpose.
- **App icons missing in the launcher:** Qt couldn't find an icon theme. Install one, for example `papirus-icon-theme` or `breeze-icons`, and select it in `qt6ct`, which needs `hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")` in `hyprland.lua`.
- **Flatpak apps missing in the launcher:** the shell finds apps through `XDG_DATA_DIRS`, and Flatpak adds its folders (`/var/lib/flatpak/exports/share`, `~/.local/share/flatpak/exports/share`) to it only at login. After installing Flatpak itself, log out and in again; apps installed later show up without that.
- **LocalSend says "The LocalSend app is running":** the app and the shell both need port 53317. Quit the app (and take it out of your autostart); the shell then receives. A phone that doesn't see this PC: Receive files has to be on, and both on the same network; a firewall must let TCP and UDP 53317 through.
- **A change in `src/` didn't show:** reloading occasionally misses a save; restart the shell (see "Updating and restarting").

## Repository layout

```
pistachio-shell/
├─ bin/psc     the control command
├─ install.sh  links src/ and bin/psc into place, builds rust/
├─ rust/       the helpers that run beside the shell all day: pistachio-auth (polkit agent), pistachio-devices (pairing agent, USB drives), pistachio-localsend
├─ extras/     hypridle.conf (idle locking), sddm/ (the login screen theme, see extras/sddm/README.md), make-emoji.py (rebuilds the launcher's emoji list) and make-sound.py (rebuilds the notification sound)
├─ src/        the shell: shell.qml, Theme.qml, and bar/ panels/ popups/ launcher/ settings/ lock/ components/ services/
├─ tests/      checks against the live system (see CLAUDE.md, working rule 9)
├─ design/     one HTML board per screen; open design/index.html. The visual source of truth
├─ docs/       plan.md (architecture, components, build phases) and audio-bluetooth.md
└─ CLAUDE.md   decisions and working rules for Claude Code
```
