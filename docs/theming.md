# Theming and colours

The shell publishes Colours to `$XDG_CONFIG_HOME/pistachio/shared-theme` (normally `~/.config/pistachio/shared-theme`), containing `pistachio` or `noir`. Pistachio Text, FM and Notes follow it live. Kitty also follows when its config includes `pistachio-shared.conf`; the shell writes the chosen colours (those of `pistachio-noir.conf` or `noir.conf`) into it, rather than an include, so a kitty.conf that includes one of those files itself gets no "already been included" error, and the publisher reloads running Kitty processes with SIGUSR1.

**Theming integration** (Settings → Appearance → Colours, on by default): the shell sets Kitty, Neovim and VS Code up itself to follow Colours. It backs up `kitty.conf` / `init.lua`, adds its line at the end, marked (Kitty: a `# pistachio-shell theming…` comment line above a plain `include pistachio-shared.conf`; Neovim: a line ending in `-- pistachio-shell theming`) and copies the theme files in. An app that already has its own theme is asked about in Settings first (Keep mine / Use Pistachio). Turning the switch off removes only those marked lines, so the app's own settings apply again. Neovim needs an `init.lua` (not `init.vim`). Text, FM and Notes follow Colours either way.

Neovim can follow the same choice with the files in `integrations/neovim`: its existing Pistachio Noir colourscheme has a matching Noir palette, and `pistachio-shared.lua` checks the shared choice while Neovim is open. `extras/neovim/install.sh` installs these into the matching Neovim config and backs up the current init and colourscheme; it expects the existing `vim.cmd("colorscheme pistachio-noir")` line. The fallback is Pistachio when the shared file is absent. In Noir its code keeps a few muted colours so syntax stays readable; the editor itself stays grey.

**VS Code** (since 21 November 2026) is the third app under Theming integration. Its theme is an extension, `integrations/vscode/pistachio-noir` (Pistachio Noir and Noir, the shell's palettes), which psc packages as a `.vsix` and installs with VS Code's own `code --install-extension`, so VS Code records it (a folder copied into `~/.vscode/extensions` by hand never shows up in the theme list). The shell then sets one line in `~/.config/Code/User/settings.json`, first in the file, marked with a block comment:

```jsonc
    "workbench.colorTheme": "Pistachio Noir" /* pistachio-shell theming */,
```

Every other byte of `settings.json` (comments, order, trailing commas) stays as you wrote it, and VS Code applies the change at once, so switching Colours recolours VS Code within a second. A theme you picked yourself is replaced only after you agree (the "Use Pistachio" question); the marker then keeps your old one (`(was "…")`), and switching Theming integration off puts it back, or removes the line if there was none. `settings.json` is backed up beside itself before the first change. VSCodium and Code - OSS are handled the same way (their own settings and extension folders). If VS Code follows the system's light/dark setting (`window.autoDetectColorScheme`), the row says so and nothing changes. The extension stays installed when you switch off; pick it by hand any time (Ctrl+K Ctrl+T).

Hyprland’s active window and group borders follow the shell’s Colours setting live: pistachio in Pistachio Noir, light grey in Noir; inactive borders stay transparent. Applied at runtime and after Hyprland reloads.

Settings → Appearance → Monochrome wallpaper optionally desaturates the desktop wallpaper and its live switcher preview while Noir is selected (off by default). The desktop cat keeps its selected coat colours in both schemes. Switching back restores the original colours; wallpaper files are never modified.
