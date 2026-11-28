#!/usr/bin/env python3
"""Theme files for the apps that follow the shell's Colours through `psc theme` (owner, 28 November 2026:
GTK 3/4, Vesktop, btop, yazi, zathura), made from src/Theme.qml, the one place the palette lives.
Dev-only; run it again after changing a tone in Theme.qml:

    python3 -B tools/make-app-themes.py           write the files
    python3 -B tools/make-app-themes.py --check   exit 1 if a written file is out of date (tests/run.sh)

Writes integrations/<app>/<scheme>.<ext> for the schemes pistachio-noir, noir and oled-noir; psc builds
them in (rust/psc/src/theme.rs). Kitty, Neovim and VS Code keep their own hand-made files."""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
THEME = (ROOT / "src/Theme.qml").read_text()
SCHEMES = ("pistachio-noir", "noir", "oled-noir")
NAMES = {"pistachio-noir": "Pistachio Noir", "noir": "Noir", "oled-noir": "OLED Noir"}


def palettes():
    found = re.findall(r'readonly property color (\w+): tone\("(#\w{6})", "(#\w{6})", "(#\w{6})"\)', THEME)
    out = {s: {} for s in SCHEMES}
    for name, *tones in found:
        for scheme, tone in zip(SCHEMES, tones):
            out[scheme][name] = tone.upper()
    need = {"bg", "bgAlt", "overlay", "overlay2", "muted", "subtext", "text", "textBright", "pistachio",
            "terracotta", "gold", "sageBlue", "teal", "lavender", "clay", "deep"}
    missing = need - set(out["noir"])
    assert not missing, f"Theme.qml has no tone() for {missing}: update tools/make-app-themes.py"
    # Noir's code greys (Theme.codeColours): `string: oled ? "#939393" : "#B8B8B8"`
    for key in ("string", "comment"):
        m = re.search(key + r': oled \? "(#\w{6})" : "(#\w{6})"', THEME)
        assert m, f"Theme.codeColours' Noir {key} changed: update tools/make-app-themes.py"
        out["noir"]["code_" + key], out["oled-noir"]["code_" + key] = m.group(2).upper(), m.group(1).upper()
    # the shell's UI font (Theme.fontUi in Classic: `tui ? fontTui : "Manrope"`), for Vesktop
    m = re.search(r'fontUi: tui \? fontTui : "([^"]+)"', THEME)
    assert m, "Theme.fontUi changed: update tools/make-app-themes.py"
    for scheme in SCHEMES:
        out[scheme]["fontUi"] = m.group(1)
    return out


def code(p, scheme):
    """Theme.codeColours: the colours of code, for yazi's previews."""
    if scheme == "pistachio-noir":
        return {"plain": p["textBright"], "keyword": p["lavender"], "string": p["teal"], "number": p["clay"],
                "comment": p["subtext"], "function": p["gold"], "type": p["sageBlue"], "variable": p["clay"]}
    return {"plain": p["text"], "keyword": p["textBright"], "string": p["code_string"], "number": p["gold"],
            "comment": p["code_comment"], "function": p["textBright"], "type": p["subtext"], "variable": p["text"]}


def rgba(hex_colour, alpha):
    r, g, b = (int(hex_colour[i:i + 2], 16) for i in (1, 3, 5))
    return f"rgba({r}, {g}, {b}, {alpha})"


def head(comment, scheme):
    return f"{comment} {NAMES[scheme]}, the Pistachio shell's Colours (made by tools/make-app-themes.py from src/Theme.qml)"


# --- GTK ------------------------------------------------------------------------------------------
# libadwaita's colours by name: (name, token or callable). GTK 4 (libadwaita 1.6+) takes them as CSS
# variables (:root { --window-bg-color }); GTK 3's adw-gtk3 as @define-color window_bg_color.
def gtk_colours(p):
    return [
        ("accent-bg", p["pistachio"]), ("accent-fg", p["bg"]), ("accent", p["pistachio"]),
        ("destructive-bg", p["terracotta"]), ("destructive-fg", p["bg"]), ("destructive", p["terracotta"]),
        ("success-bg", p["teal"]), ("success-fg", p["bg"]), ("success", p["teal"]),
        ("warning-bg", p["gold"]), ("warning-fg", p["bg"]), ("warning", p["gold"]),
        ("error-bg", p["terracotta"]), ("error-fg", p["bg"]), ("error", p["terracotta"]),
        ("window-bg", p["bg"]), ("window-fg", p["text"]),
        ("view-bg", p["bg"]), ("view-fg", p["text"]),
        ("headerbar-bg", p["bgAlt"]), ("headerbar-fg", p["text"]), ("headerbar-border", p["overlay"]),
        ("headerbar-backdrop", p["bgAlt"]),
        ("sidebar-bg", p["bgAlt"]), ("sidebar-fg", p["text"]), ("sidebar-backdrop", p["bgAlt"]),
        ("sidebar-border", p["overlay"]),
        ("secondary-sidebar-bg", p["bg"]), ("secondary-sidebar-fg", p["text"]),
        ("secondary-sidebar-backdrop", p["bg"]), ("secondary-sidebar-border", p["overlay"]),
        ("card-bg", p["bgAlt"]), ("card-fg", p["text"]),
        ("dialog-bg", p["bgAlt"]), ("dialog-fg", p["text"]),
        ("popover-bg", p["bgAlt"]), ("popover-fg", p["text"]),
        ("thumbnail-bg", p["overlay"]), ("thumbnail-fg", p["text"]),
        ("overview-bg", p["deep"]), ("overview-fg", p["text"]),
        ("scrollbar-outline", p["bg"]),
    ]


def gtk4(p, scheme):
    lines = [f"/* {head('', scheme).strip()}", "   for GTK 4 and libadwaita apps; restart an app to see a change */", ":root {"]
    lines += [f"  --{name}-color: {value};" for name, value in gtk_colours(p)]
    return "\n".join(lines) + "\n}\n"


def gtk3(p, scheme):
    lines = [f"/* {head('', scheme).strip()}", "   for GTK 3 apps with the adw-gtk3 theme; restart an app to see a change */"]
    lines += [f"@define-color {name.replace('-', '_')}_color {value};" for name, value in gtk_colours(p)]
    return "\n".join(lines) + "\n"


# --- btop -----------------------------------------------------------------------------------------
def btop(p, scheme):
    keys = [
        ("main_bg", p["bg"]), ("main_fg", p["text"]), ("title", p["textBright"]), ("hi_fg", p["pistachio"]),
        ("selected_bg", p["overlay"]), ("selected_fg", p["textBright"]), ("inactive_fg", p["muted"]),
        ("graph_text", p["subtext"]), ("meter_bg", p["overlay"]), ("proc_misc", p["pistachio"]),
        ("cpu_box", p["overlay2"]), ("mem_box", p["overlay2"]), ("net_box", p["overlay2"]), ("proc_box", p["overlay2"]),
        ("div_line", p["overlay"]),
        ("temp_start", p["sageBlue"]), ("temp_mid", p["gold"]), ("temp_end", p["terracotta"]),
        ("cpu_start", p["teal"]), ("cpu_mid", p["gold"]), ("cpu_end", p["terracotta"]),
        ("free_start", p["overlay2"]), ("free_mid", p["teal"]), ("free_end", p["pistachio"]),
        ("cached_start", p["overlay2"]), ("cached_mid", p["sageBlue"]), ("cached_end", p["teal"]),
        ("available_start", p["overlay2"]), ("available_mid", p["clay"]), ("available_end", p["gold"]),
        ("used_start", p["overlay2"]), ("used_mid", p["clay"]), ("used_end", p["terracotta"]),
        ("download_start", p["overlay2"]), ("download_mid", p["sageBlue"]), ("download_end", p["teal"]),
        ("upload_start", p["overlay2"]), ("upload_mid", p["lavender"]), ("upload_end", p["clay"]),
        ("process_start", p["teal"]), ("process_mid", p["gold"]), ("process_end", p["terracotta"]),
        ("proc_pause_bg", p["terracotta"]), ("proc_follow_bg", p["sageBlue"]), ("proc_banner_bg", p["overlay"]),
        ("proc_banner_fg", p["textBright"]), ("followed_bg", p["sageBlue"]), ("followed_fg", p["bg"]),
    ]
    return head("#", scheme) + "\n" + "".join(f'theme[{k}]="{v}"\n' for k, v in keys)


# --- yazi -----------------------------------------------------------------------------------------
def yazi(p, scheme):
    s = lambda **kw: "{ " + ", ".join(f'{k} = "{v}"' if isinstance(v, str) else f"{k} = {str(v).lower()}" for k, v in kw.items()) + " }"
    border = s(fg=p["overlay2"])
    sections = {
        "mgr": [("cwd", s(fg=p["teal"])), ("find_keyword", s(fg=p["gold"], bold=True, italic=True, underline=True)),
                ("find_position", s(fg=p["lavender"], bg="reset", bold=True, italic=True)),
                ("symlink_target", s(fg=p["subtext"], italic=True)),
                ("marker_copied", s(fg=p["pistachio"], bg=p["pistachio"])), ("marker_cut", s(fg=p["terracotta"], bg=p["terracotta"])),
                ("marker_marked", s(fg=p["sageBlue"], bg=p["sageBlue"])), ("marker_selected", s(fg=p["gold"], bg=p["gold"])),
                ("count_copied", s(fg=p["bg"], bg=p["pistachio"])), ("count_cut", s(fg=p["bg"], bg=p["terracotta"])),
                ("count_selected", s(fg=p["bg"], bg=p["gold"])), ("border_style", border)],
        "tabs": [("active", s(fg=p["bg"], bg=p["pistachio"], bold=True)), ("inactive", s(fg=p["subtext"], bg=p["overlay"]))],
        "mode": [("normal_main", s(fg=p["bg"], bg=p["pistachio"], bold=True)), ("normal_alt", s(fg=p["pistachio"], bg=p["overlay"])),
                 ("select_main", s(fg=p["bg"], bg=p["sageBlue"], bold=True)), ("select_alt", s(fg=p["sageBlue"], bg=p["overlay"])),
                 ("unset_main", s(fg=p["bg"], bg=p["terracotta"], bold=True)), ("unset_alt", s(fg=p["terracotta"], bg=p["overlay"]))],
        "indicator": [("parent", s(fg=p["text"], bg=p["overlay"])), ("current", s(fg=p["bg"], bg=p["pistachio"])),
                      ("preview", s(underline=True))],
        "status": [("overall", s(fg=p["text"], bg=p["bgAlt"])), ("perm_sep", s(fg=p["muted"])), ("perm_type", s(fg=p["sageBlue"])),
                   ("perm_read", s(fg=p["gold"])), ("perm_write", s(fg=p["terracotta"])), ("perm_exec", s(fg=p["teal"])),
                   ("progress_label", s(fg=p["textBright"], bold=True)), ("progress_normal", s(fg=p["pistachio"], bg=p["overlay"])),
                   ("progress_error", s(fg=p["terracotta"], bg=p["overlay"]))],
        "which": [("border", border), ("mask", s(bg=p["bgAlt"])), ("cand", s(fg=p["teal"])), ("rest", s(fg=p["subtext"])),
                  ("desc", s(fg=p["lavender"])), ("separator_style", s(fg=p["overlay2"]))],
        "confirm": [("border", border), ("title", s(fg=p["textBright"])), ("btn_yes", s(fg=p["bg"], bg=p["pistachio"]))],
        "spot": [("border", border), ("title", s(fg=p["textBright"])), ("tbl_col", s(fg=p["sageBlue"])),
                 ("tbl_cell", s(fg=p["bg"], bg=p["pistachio"]))],
        "notify": [("title_info", s(fg=p["teal"])), ("title_warn", s(fg=p["gold"])), ("title_error", s(fg=p["terracotta"]))],
        "pick": [("border", border), ("active", s(fg=p["pistachio"], bold=True))],
        "input": [("border", border), ("selected", s(fg=p["bg"], bg=p["pistachio"]))],
        "cmp": [("border", border), ("active", s(fg=p["bg"], bg=p["pistachio"]))],
        "tasks": [("border", border), ("hovered", s(fg=p["pistachio"], bold=True))],
        "help": [("border", border), ("chord", s(fg=p["teal"])), ("hovered", s(fg=p["bg"], bg=p["pistachio"], bold=True))],
    }
    out = [head("#", scheme), "# a yazi flavor: ~/.config/yazi/flavors/pistachio-shell.yazi/flavor.toml"]
    for name, keys in sections.items():
        out.append(f"\n[{name}]")
        out += [f"{k} = {v}" for k, v in keys]
    rules = [('mime = "**/image/*"', "gold"), ('mime = "**/{audio,video}/*"', "lavender"),
             ('mime = "**/application/{zip,rar,7z*,tar,gzip,xz,zstd,bzip*,lzma,compress,archive,cpio,arj,xar,ms-cab*}"', "clay"),
             ('mime = "**/application/{pdf,doc,rtf}"', "sageBlue"), ('mime = "vfs/{absent,stale}"', "muted")]
    out.append("\n[filetype]\nrules = [")
    out += [f'\t{{ {m}, fg = "{p[t]}" }},' for m, t in rules]
    out += [f'\t{{ url = "*", is = "orphan", bg = "{p["terracotta"]}" }},', f'\t{{ url = "*", is = "exec", fg = "{p["teal"]}" }},',
            f'\t{{ url = "*", is = "dummy", bg = "{p["terracotta"]}" }},', f'\t{{ url = "*/", is = "dummy", bg = "{p["terracotta"]}" }},',
            f'\t{{ url = "*/", fg = "{p["sageBlue"]}" }},', "]"]
    return "\n".join(out) + "\n"


def tmtheme(p, scheme):
    c = code(p, scheme)
    scopes = [("Comment", "comment", c["comment"]), ("String", "string", c["string"]),
              ("Number", "constant.numeric, constant.language, constant.character", c["number"]),
              ("Keyword", "keyword, storage, keyword.operator.word", c["keyword"]),
              ("Function", "entity.name.function, support.function, meta.function-call", c["function"]),
              ("Type", "entity.name.type, entity.name.class, support.type, support.class, storage.type", c["type"]),
              ("Variable", "variable, variable.parameter, entity.name.tag", c["variable"]),
              ("Invalid", "invalid", p["terracotta"])]
    entry = lambda name, scope, fg: (f"\t\t<dict>\n\t\t\t<key>name</key><string>{name}</string>\n\t\t\t<key>scope</key><string>{scope}</string>\n"
                                     f"\t\t\t<key>settings</key><dict><key>foreground</key><string>{fg}</string></dict>\n\t\t</dict>\n")
    general = (f"\t\t<dict>\n\t\t\t<key>settings</key>\n\t\t\t<dict>\n"
               f"\t\t\t\t<key>background</key><string>{p['bg']}</string>\n\t\t\t\t<key>foreground</key><string>{c['plain']}</string>\n"
               f"\t\t\t\t<key>caret</key><string>{p['pistachio']}</string>\n\t\t\t\t<key>selection</key><string>{p['overlay2']}</string>\n"
               f"\t\t\t\t<key>lineHighlight</key><string>{p['bgAlt']}</string>\n\t\t\t</dict>\n\t\t</dict>\n")
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            f"<!-- {head('', scheme).strip()}: code in yazi's previews -->\n"
            f'<plist version="1.0">\n<dict>\n\t<key>name</key><string>{NAMES[scheme]}</string>\n\t<key>settings</key>\n\t<array>\n'
            + general + "".join(entry(*s) for s in scopes) + "\t</array>\n</dict>\n</plist>\n")


# --- zathura --------------------------------------------------------------------------------------
def zathura(p, scheme):
    keys = [
        ("default-bg", p["bg"]), ("default-fg", p["text"]),
        ("statusbar-bg", p["bgAlt"]), ("statusbar-fg", p["subtext"]),
        ("inputbar-bg", p["bgAlt"]), ("inputbar-fg", p["textBright"]),
        ("notification-bg", p["bgAlt"]), ("notification-fg", p["text"]),
        ("notification-error-bg", p["terracotta"]), ("notification-error-fg", p["bg"]),
        ("notification-warning-bg", p["gold"]), ("notification-warning-fg", p["bg"]),
        ("completion-bg", p["bgAlt"]), ("completion-fg", p["text"]),
        ("completion-group-bg", p["bg"]), ("completion-group-fg", p["subtext"]),
        ("completion-highlight-bg", p["pistachio"]), ("completion-highlight-fg", p["bg"]),
        ("index-bg", p["bg"]), ("index-fg", p["text"]), ("index-active-bg", p["pistachio"]), ("index-active-fg", p["bg"]),
        ("render-loading-bg", p["bg"]), ("render-loading-fg", p["subtext"]),
        ("highlight-color", rgba(p["gold"], 0.35)), ("highlight-fg", p["bg"]), ("highlight-active-color", rgba(p["pistachio"], 0.5)),
        # Ctrl+R (recolor) draws pages in these: the shell's background and text
        ("recolor-lightcolor", p["bg"]), ("recolor-darkcolor", p["text"]),
    ]
    return head("#", scheme) + "\n" + "".join(f'set {k} "{v}"\n' for k, v in keys)


# --- Vesktop --------------------------------------------------------------------------------------
# Discord's own colour variables (its 2025 visual refresh and the older names), set on its dark themes.
# Profile themes (.custom-user-profile-theme) keep their own colours.
def vesktop(p, scheme):
    a = lambda t, x: rgba(p[t], x)
    keys = [
        ("background-base-lowest", p["deep"]), ("background-base-lower", p["bg"]), ("background-base-low", p["bg"]),
        ("background-surface-high", p["bgAlt"]), ("background-surface-higher", p["bgAlt"]), ("background-surface-highest", p["overlay"]),
        ("background-primary", p["bg"]), ("background-secondary", p["bgAlt"]), ("background-secondary-alt", p["bgAlt"]),
        ("background-tertiary", p["deep"]), ("background-floating", p["bgAlt"]), ("background-nested-floating", p["bgAlt"]),
        ("background-accent", p["overlay"]), ("background-mod-subtle", a("overlay", 0.5)), ("background-mod-normal", a("overlay", 0.8)),
        ("background-mod-strong", p["overlay2"]), ("background-mod-muted", a("overlay", 0.4)),
        ("background-modifier-hover", a("overlay", 0.5)), ("background-modifier-active", a("overlay", 0.8)),
        ("background-modifier-selected", p["overlay"]), ("background-modifier-accent", p["overlay"]),
        ("chat-background-default", p["bg"]), ("card-background-default", p["bgAlt"]), ("modal-background", p["bgAlt"]),
        ("input-background", p["bgAlt"]), ("channeltextarea-background", p["bgAlt"]),
        ("text-default", p["text"]), ("text-normal", p["text"]), ("text-strong", p["textBright"]), ("text-muted", p["subtext"]),
        ("text-subtle", p["subtext"]), ("header-primary", p["textBright"]), ("header-secondary", p["subtext"]),
        ("text-link", p["sageBlue"]), ("text-positive", p["teal"]), ("text-warning", p["gold"]), ("text-danger", p["terracotta"]),
        ("channels-default", p["subtext"]), ("channel-icon", p["subtext"]), ("icon-default", p["subtext"]), ("icon-muted", p["muted"]),
        ("interactive-normal", p["subtext"]), ("interactive-hover", p["text"]), ("interactive-active", p["textBright"]),
        ("interactive-muted", p["muted"]),
        ("interactive-text-default", p["subtext"]), ("interactive-text-hover", p["text"]), ("interactive-text-active", p["textBright"]),
        ("interactive-icon-default", p["subtext"]), ("interactive-icon-hover", p["text"]), ("interactive-icon-active", p["textBright"]),
        ("interactive-background-hover", a("overlay", 0.5)), ("interactive-background-active", p["overlay"]),
        ("interactive-background-selected", p["overlay"]),
        ("border-subtle", p["overlay"]), ("border-normal", p["overlay2"]), ("border-strong", p["overlay2"]), ("border-faint", p["overlay"]),
        ("brand-500", p["pistachio"]), ("brand-560", p["pistachio"]), ("brand-600", p["pistachio"]), ("background-brand", p["pistachio"]),
        ("control-brand-foreground", p["pistachio"]), ("control-brand-foreground-new", p["pistachio"]),
        ("control-primary-background-default", p["pistachio"]), ("control-primary-background-hover", p["pistachio"]),
        ("control-primary-background-active", p["pistachio"]), ("control-primary-text-default", p["bg"]),
        ("button-filled-brand-background", p["pistachio"]), ("button-filled-brand-background-hover", p["pistachio"]),
        ("button-filled-brand-text", p["bg"]),
        ("scrollbar-thin-thumb", p["overlay2"]), ("scrollbar-auto-thumb", p["overlay2"]), ("scrollbar-auto-track", "transparent"),
        ("status-danger", p["terracotta"]), ("status-warning", p["gold"]), ("status-positive", p["teal"]),
        ("mention-foreground", p["textBright"]), ("mention-background", a("gold", 0.12)),
        # the shell's font (owner, 28 November 2026: "change vesktop font to manrope"); code keeps Discord's
        *[(k, f'"{p["fontUi"]}", "gg sans", sans-serif') for k in ("font-primary", "font-display", "font-headline")],
    ]
    selector = ":root,\n.theme-dark:not(.custom-user-profile-theme),\n.theme-darker:not(.custom-user-profile-theme),\n.theme-midnight:not(.custom-user-profile-theme),\n.visual-refresh.theme-dark"
    return (f"/* {head('', scheme).strip()}, for Vesktop (Discord's colour and font variables) */\n{selector} {{\n"
            + "".join(f"  --{k}: {v} !important;\n" for k, v in keys) + "}\n")


FILES = [("gtk", "gtk4-{}.css", gtk4), ("gtk", "gtk3-{}.css", gtk3), ("btop", "{}.theme", btop),
         ("yazi", "{}.toml", yazi), ("yazi", "{}.tmtheme.xml", tmtheme), ("zathura", "{}", zathura), ("vesktop", "{}.css", vesktop)]


def main():
    check = "--check" in sys.argv[1:]
    stale = []
    for scheme, p in palettes().items():
        for folder, name, make in FILES:
            path = ROOT / "integrations" / folder / name.format(scheme)
            text = make(p, scheme)
            if check:
                if not path.exists() or path.read_text() != text:
                    stale.append(str(path.relative_to(ROOT)))
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
    if check:
        if stale:
            print("out of date (run python3 -B tools/make-app-themes.py):\n  " + "\n  ".join(stale))
            return 1
        print("app themes up to date")
        return 0
    print(f"wrote {len(FILES) * len(SCHEMES)} files in integrations/")
    return 0


sys.exit(main())
