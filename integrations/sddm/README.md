# Pistachio Noir SDDM theme

A login screen for SDDM in the shell's style, after `pistachio-shell-design/sddm-session-menu.html` and `pistachio-shell-design/sddm-wrong-password.html`:

- **Centre:** clock and date, your picture (or a placeholder) and name, the password field. Enter logs in.
- **Messages:** "Wrong password. Try again." in terracotta, and "Caps Lock is on" in gold.
- **Bottom-left:** the session button opens the session menu (↑↓ also choose while it's open, Enter or Esc closes it). The keyboard layout button switches to the next layout.
- **Bottom-right:** suspend, reboot and shut down, each only if the machine supports it. They act at once: there's no session yet that could lose work.
- **Several users:** click the name to switch.

`pistachio-noir/` is the theme itself. It's self-contained, because SDDM runs as its own user and can't see the shell or your `~/.local` fonts. It has a copy of the palette and the icon component, and Manrope (`fonts/`, Google Fonts' variable TTF under the SIL Open Font License in `fonts/OFL.txt`). It needs SDDM's Qt 6 greeter (`QtVersion=6` in `metadata.desktop`).

## Install

The step-by-step installation is on the [login screen page](../../docs/login-screen.md): install SDDM, copy `pistachio-noir/` to `/usr/share/sddm/themes/`, select it in `/etc/sddm.conf.d/theme.conf`, check it with `sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/pistachio-noir`, and enable SDDM.

## Settings

`pistachio-noir/theme.conf`:

- `background=`: a wallpaper behind the login screen, relative to the theme folder or absolute. The `sddm` user must be able to read it, so put it in the theme folder or under `/usr/share`. Empty means the plain background.
- `clockFormat=hh:mm`: `h:mm AP` gives a 12-hour clock.

Your picture comes from `~/.face.icon`, if SDDM can read it, or from `/usr/share/sddm/faces/<user>.face.icon`. Without one, the placeholder shows.

## Preview without SDDM

```sh
integrations/sddm/preview.sh
```

This opens the theme in a window, with stand-ins for what SDDM provides: one user, three sessions and two keyboard layouts. The password `test` "logs in", and anything else shows the wrong-password message. The power buttons only print a line.

`preview.sh shot out.png [wrong|menu]` saves a picture instead; that's how `pistachio-noir/preview.png` was made. Add `QT_QPA_PLATFORM=offscreen` in front to save it without a window.
