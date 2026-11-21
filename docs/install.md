# Installation

1. **Install the packages:**

   ```sh
   sudo pacman -S --needed hyprland quickshell pipewire wireplumber pipewire-pulse \
       bluez bluez-utils networkmanager ddcutil hyprsunset kitty rust
   sudo systemctl enable --now bluetooth.service NetworkManager.service
   ```

   On Gentoo with OpenRC, the same set (enable the `guru` and `hyproverlay` repositories for Quickshell and the Hypr tools), with two USE flags first:

   ```sh
   printf '%s\n' 'sys-apps/util-linux caps' 'media-video/pipewire sound-server extra' | sudo tee /etc/portage/package.use/pistachio-shell
   sudo emerge -av --noreplace --changed-use gui-wm/hyprland gui-apps/quickshell media-video/pipewire media-video/wireplumber \
       net-wireless/bluez net-misc/networkmanager app-misc/ddcutil gui-apps/hyprsunset x11-terms/kitty dev-lang/rust sys-auth/elogind
   sudo rc-update add bluetooth default && sudo rc-service bluetooth start
   sudo rc-update add NetworkManager default && sudo rc-service NetworkManager start
   ```

   `rust` is needed: `psc` and the shell's helpers are Rust programs that `install.sh` builds. Python isn't needed. Optional: `gnome-calendar` (it brings `evolution-data-server`) for its events in the month calendar, and for copying text from the screen `sudo pacman -S tesseract tesseract-data-eng tesseract-data-pol`. `psc doctor` lists everything else, found or missing.


2. **Put the repo somewhere permanent**, for example `~/projects/pistachio-shell`. The shell runs straight from it, so if you move it later, run `./install.sh` again.

3. **Run the install script** from the repo:

   ```sh
   cd ~/projects/pistachio-shell
   ./install.sh
   ```

   It prints one line per step (✓ done, ! a note, ✗ an error, · would do), then a **Check** section from `psc doctor`: whether everything the shell needs is installed, and the exact `sudo pacman -S --needed …` line (on Gentoo: the USE flags to add, then a `sudo emerge` line) for anything missing, required and optional apart. It never installs packages itself. Colour is used only on a terminal (and never with `NO_COLOR` set), so a log stays plain text.

   Preview with `./install.sh dry`: it checks existing links and reports planned links, helper builds/installs and font installation without changing files, building helpers or downloading fonts.

   It links the repo's `src/` to `~/.config/quickshell/pistachio`, where Quickshell finds a config named `pistachio`, and installs `psc` (see [psc](ipc-and-keybinds.md#psc)) as `~/.local/bin/psc`. It builds `psc` and the helper programs in `rust/` with cargo and copies them to `~/.local/bin` (run it again after pulling changes to `rust/`, then `psc restart`). Without cargo, or if `psc` doesn't build, it keeps a `psc` installed before or links the old shell script `legacy/psc`, which only starts, stops and calls the shell (Settings' health, export/import and theming, Quick chat, Lens and the launcher's file tools need the Rust `psc`). It also installs the Manrope font (see Requirements). It warns if `~/.local/bin` isn't on your PATH or Quickshell isn't installed. Run it again after moving the repo to update the links. It never replaces a real file or folder that is in the way; it stops and tells you instead. By hand, it's:

   ```sh
   mkdir -p ~/.config/quickshell ~/.local/bin
   ln -s ~/projects/pistachio-shell/src ~/.config/quickshell/pistachio
   cargo build --release --manifest-path ~/projects/pistachio-shell/rust/Cargo.toml
   install -m 755 ~/projects/pistachio-shell/rust/target/release/{psc,pistachio-auth,pistachio-devices,pistachio-localsend} ~/.local/bin/
   ```

4. **Remove what the shell replaces.** Only one notification daemon can run at a time, so stop and uninstall or disable `mako`, `dunst`, `swaync` or similar. A KDE Plasma session running at the same time (for example on another TTY) also owns the notification service: stop it with `systemctl --user stop plasma-plasmashell.service`. Drop other bars such as Waybar too. Don't autostart `hyprsunset` yourself: the shell runs its own copy.

5. **Try it** from a terminal inside Hyprland:

   ```sh
   psc        # the same as qs -c pistachio
   ```

   On this very first start the first-run setup opens: it checks what's installed (the same list as `psc doctor`), then walks through the look, sound, notifications, connections, Lens and places, or restores a Settings export. Skip it if you like; `psc setup` brings it back.

   The log goes to that terminal. Errors show as `ERROR` lines. A warning starting `qt.qpa.wayland.textinput` is harmless.

6. **Start it with Hyprland.** In `~/.config/hypr/hyprland.lua`:

   ```lua
   hl.on("hyprland.start", function ()
     hl.exec_cmd("qs -c pistachio")
   end)
   ```

   With an older `hyprland.conf`, use `exec-once = qs -c pistachio`.

7. **Add the keybinds** from the next section.

## Updating and restarting

`main` is the stable branch (a fresh clone's); `experimental` is where new work lands first. Switch with `git switch experimental` (or back with `git switch main`), then run `./install.sh` and `psc restart`, as after any pull that changes `rust/`.

The shell reloads by itself when a file in `src/` changes, so pulling new code or editing it takes effect at once. To restart it fully, run `psc restart` or `psc shell restart`. Settings → Shell health offers Restart and Force restart with confirmation. Force restart immediately kills the shell and its child processes before starting it again; active timers, transfers and other ongoing shell tasks end. `psc log -f` follows the log of the running shell.
