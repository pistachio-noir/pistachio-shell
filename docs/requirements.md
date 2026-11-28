# Requirements

Tested on Arch Linux with Hyprland 0.56.2 (Lua config) and Quickshell 0.3.2 on Qt 6.12, and on Gentoo with OpenRC and elogind with Hyprland 0.57.2 (since 21 November 2026). The shell also works with an older-style `hyprland.conf`. It needs no systemd: suspend, reboot and shut down go to logind over D-Bus, which systemd-logind and elogind both provide.

The table gives Arch's package names. On Gentoo, `psc doctor` prints the atoms instead (from `::gentoo`, `::guru` and `::hyproverlay`), and a few things need a USE flag:

| Gentoo package | USE flag | For |
| --- | --- | --- |
| `sys-apps/util-linux` | `caps` | `setpriv`: audio device updates, screenshot and recording notifications, screen recording |
| `media-video/pipewire` | `extra` | `pw-play` and `pw-record`: notification and timer sounds, the microphone check |
| `app-text/tessdata_fast` | `l10n_en` | English for Text from the screen |
| `media-fonts/nerdfonts` (`::guru`) | `jetbrainsmono` | the TUI style's font |

`sys-auth/elogind` provides logind, `loginctl` and the session that the polkit agent and lock screen use. Start the Bluetooth and NetworkManager services with `rc-update add bluetooth default` and `rc-update add NetworkManager default`.

| Need | Arch packages | Used for | If missing |
| --- | --- | --- | --- |
| Compositor | `hyprland` | everything; Hyprland only | nothing works |
| Shell runtime | `quickshell` (pulls in Qt 6, PAM, polkit) | everything | nothing works |
| Audio | `pipewire`, `wireplumber`, `pipewire-pulse` (its `pactl` tells which inputs have something plugged in; `setpriv` from `util-linux` keeps it from outliving the shell; on Gentoo util-linux needs USE `caps`) | volume, per-app volume, output and input devices, microphone, OSD; `wpctl` for the volume keys | no volume controls; without `pactl`, no input is greyed out |
| Media | any player that speaks MPRIS (browsers, Spotify, mpv with `mpv-mpris`) | the media pill and its card, the media card in quick settings and on the lock screen | the pill and the cards stay hidden |
| Bluetooth | `bluez`, `bluez-utils`, with the `bluetooth` service running | Bluetooth tile, chip, launcher Bluetooth view | Bluetooth shows as off |
| File preview / Open with | Rust `psc`, `glib2`; optional `poppler` (`pdftoppm`) | read-only previews and installed MIME handlers | PDF falls back to metadata without Poppler |
| File search | Rust `psc`, `xdg-utils` | the launcher's `/` search through your home folder, opening what it finds | `/` finds nothing |
| Pairing agent | the shell's helpers, built by `install.sh` (see Helpers below) | pairing devices that show or ask for a code, and devices asking to connect | only devices that need no code pair; the log says `bluetooth agent exited` |
| Screenshots | `libnotify` (`notify-send`), `wl-clipboard` (also copies emoji), `xdg-utils`, `glib2` (`gio`); `xdg-user-dirs` optional | the notification after a screenshot, Copy, Open and Delete; the Pictures folder in your language | no notification (the picture is still saved); `~/Pictures/Screenshots` |
| Weather | a network connection (Open-Meteo, no account; only your city's coordinates are sent, every 30 min) | the weather panel | no weather panel |
| Screen sharing | `xdg-desktop-portal-hyprland` | sharing your screen from Discord, browsers or OBS, and the shell's screen-sharing indicator | apps can't share the screen at all |
| Polkit agent | the shell's helpers, built by `install.sh`; `polkit` | the admin password dialog | apps that need admin rights fail or hang; the log says `polkit agent` |
| Network | `networkmanager`, `iproute2`, with the `NetworkManager` service running | Ethernet tile/chip; `ip` and `nmcli` supply read-only address, gateway and DNS details | Ethernet shows as unplugged |
| Brightness | `ddcutil`, and DDC/CI switched on in your monitor's own menu | brightness slider, brightness keys, OSD | the brightness slider is hidden |
| Night light | `hyprsunset` | Night light tile, warmth slider and schedule; the shell starts and stops it itself | the tile says "Not installed" |
| Idle lock (optional) | `hypridle`, with `integrations/hypridle.conf` | locking after idle time, screen off, locking before any suspend | only the power menu's Suspend locks first |
| GPU readings (optional) | the NVIDIA driver's `nvidia-smi` | the GPU row of the launcher's System monitor | no GPU row (CPU and memory come from `/proc`, the CPU temperature from its `coretemp` or `k10temp` sensor) |
| Power actions | logind: `systemd` (already there), or `elogind` with OpenRC | suspend, reboot, shut down, Firmware setup (`psc power` asks logind over D-Bus) | those buttons do nothing |
| Terminal | `kitty` (or `ghostty`, `foot`, `alacritty`, `wezterm`, `konsole`: pick it in Settings → Apps & places, or set `$TERMINAL`) | launching apps marked `Terminal=true`, `$` commands | those don't start |
| Desktop icons | `glib2` (`gio`, for Move to trash), `xdg-utils`, `xdg-user-dirs` optional | the Desktop folder's icons: opening, trashing, the folder in your language | no trash from the desktop's menu; `~/Desktop` |
| Microphone check (optional) | `pipewire` (`pw-record`, `pw-play`; on Gentoo USE `extra`), Rust `psc` | explicit input meter, temporary five-second sample and playback | the card explains unavailable audio tools |
| Notification sound | `pipewire`'s `pw-play` (already there on Arch; Gentoo needs USE `extra`) | the sound with each toast (the shell brings its own, `src/sounds/notification.wav`) | silent toasts |
| Showoff mode (optional) | `fastfetch` | the terminal in showoff mode | the panels open without it |
| LocalSend | `localsend` (the AUR's `localsend-bin`, or Flathub's) installed but not running; the shell's helpers, built by `install.sh`; `openssl` (already there); `zenity` for the Add files and Add folder buttons; `wl-clipboard` for Paste | sending and receiving in quick settings | no LocalSend row; without `zenity`, add files by dropping or pasting them |
| Screen tools (optional) | `hyprpicker`, `gpu-screen-recorder`, `satty`; `ffmpeg`/`ffprobe` for Trim | Colour and Record, Edit on screenshot notifications, Trim on recording notifications | missing tool's choice is hidden |
| Clipboard history (optional) | `cliphist` (Gentoo `app-misc/cliphist`), `wl-clipboard` | the launcher's `;` history, text and, with Keep pictures too, copied pictures | `;` lists nothing |
| Alarms (optional) | `gnome-clocks` | alarms in the clock's menu and the launcher's `alarm` (they are GNOME Clocks' own alarms, rung by the shell) | no alarms; timers and the stopwatch work without it |
| WebP wallpapers (optional) | Qt's image formats plugin (`qt6-imageformats`; Gentoo `dev-qt/qtimageformats`) | `.webp` files in the wallpaper switcher (PNG and JPEG need nothing) | a `.webp` wallpaper shows nothing; the log says `Unsupported image format` |
| App theming (optional) | `adw-gtk3` (Gentoo `x11-themes/adw-gtk3` in `::guru`) for GTK 3 apps | GTK 3 apps following Colours (GTK 4, Vesktop, btop, yazi and zathura need nothing extra) | GTK 3 apps keep Adwaita's colours |
| System monitor (optional) | `btop` | a click on the CPU/RAM desktop widget or the TUI bar's cpu/mem opens it in your terminal | those clicks open Settings → System |
| Show in Files (optional) | Pistachio FM (its own repo), installed | the launcher's Show in Files opens a file's folder there with the file selected | Show in folder opens the folder with `xdg-open` |
| emerge in Background jobs (Gentoo) | your user in the `portage` group (`sudo gpasswd -a $USER portage`, then log in again) for `/var/log/emerge.log` | "3 of 12" and how a running emerge ended | the job shows what it builds and "Ended" |
| Calendar events (optional) | `gnome-calendar` (with `evolution-data-server`; `psc events` loads its libraries) | events in the month calendar | the calendar shows dates only |
| Launcher extras (optional) | `libqalculate` (`qalc`); `tldr`; Cider (with its app token); CLion; VS Code; Steam | `tldr`, `m`, CLion and VS Code projects, games | that part of the launcher stays empty |
| USB drives | the shell's helpers, built by `install.sh`; `udisks2` (already there). Don't run `udiskie` beside the shell: it would do the same job twice | mounting drives as they're plugged in; Eject | drives don't mount by themselves; Eject still works |
| Helpers | `rust` (`cargo`) and `openssl` to build them; `install.sh` builds `rust/` and copies `psc`, `pistachio-auth`, `pistachio-devices` and `pistachio-localsend` to `~/.local/bin` | psc and the shell's on-demand helpers in it (see [psc](ipc-and-keybinds.md#psc)); the polkit agent, the pairing agent, USB drives, LocalSend | those four don't work; the log names the one that's missing and says to run `install.sh` |
| Text from the screen (optional) | `tesseract`, `tesseract-data-eng`, `tesseract-data-pol` | the screenshot menu's Text | "Couldn't read the text: tesseract isn't installed" |
| Lens and quick chat (optional) | Rust `psc`; Claude Code CLI (`claude`) and/or Codex CLI (`codex`), logged in with access to the selected model; `zenity` for text/image file attachments | Lens answers and follow-ups; uses the CLIs' existing authentication, no API key setting in the shell | the card explains the unavailable provider, or tries the other if fallback is on; Lens's Extract text uses the selected agent, not tesseract |
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
