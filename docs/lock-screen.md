# Lock screen

The lock screen checks your password with PAM's `login` stack, as other screen lockers do. That includes Arch's `pam_faillock`: three wrong passwords within 15 minutes lock the account for 10 minutes, the TTY included. A correct password resets the count.

Suspend in the power menu locks the screen first, so the machine wakes up locked. For locking after idle time, turning the screen off, and locking before every suspend (also `systemctl suspend` from a terminal), install `hypridle`, copy the repo's template and start it with Hyprland:

```sh
sudo pacman -S hypridle
cp ~/projects/pistachio-shell/integrations/hypridle.conf ~/.config/hypr/hypridle.conf
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
