# Login screen

`integrations/sddm/` has a login screen theme for SDDM in the same style:
- **Centre:** clock and date, your picture and name, and the password field.
- **Bottom-left:** a session menu and the keyboard layout.
- **Bottom-right:** suspend, reboot and shut down.

SDDM isn't part of the shell, and the theme works on its own: it brings its own copy of the colours and the Manrope font, because SDDM runs as a separate user that can't see your home folder. More detail is in [integrations/sddm/README.md](../integrations/sddm/README.md).

1. **Try it first (optional).** This opens the theme in a window, without SDDM. Type `test` as the password to "log in"; anything else shows the wrong-password message:

   ```sh
   ~/projects/pistachio-shell/integrations/sddm/preview.sh
   ```

2. **Install SDDM:**

   ```sh
   sudo pacman -S sddm
   ```

3. **Copy the theme into SDDM's theme folder:**

   ```sh
   sudo cp -r ~/projects/pistachio-shell/integrations/sddm/pistachio-noir /usr/share/sddm/themes/
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
