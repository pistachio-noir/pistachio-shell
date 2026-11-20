# Frosted panels

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
