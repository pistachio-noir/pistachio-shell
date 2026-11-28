#!/usr/bin/env python3
"""OLED Noir for the apps, made from their Noir files (owner, 22 November 2026: "integrate oled also inside
themes integrations"). Dev-only; run it again after changing a Noir file or the OLED tones:

    python3 -B tools/make-oled-themes.py

Writes integrations/kitty/kitty-oled-noir.conf and integrations/vscode/pistachio-noir/themes/oled-noir.json.
The shell's own greys map to Theme.qml's OLED Noir tones; any other colour (VS Code's muted syntax hues,
its odd dark tints) is scaled to 80 %, the same "about a fifth darker". Alpha is kept."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Noir → OLED Noir, as in src/Theme.qml's tone() calls
TONES = {
    "111111": "000000", "0B0B0B": "000000", "1A1A1A": "0A0A0A", "262626": "161616", "333333": "242424",
    "5E5E5E": "4A4A4A", "A6A6A6": "858585", "E6E6E6": "BABABA", "F7F7F7": "D0D0D0", "BDBDBD": "969696",
    "C9675C": "A5544B", "D2D2D2": "A8A8A8", "B4B4B4": "8F8F8F", "C8C8C8": "A0A0A0", "BEBEBE": "989898",
    "C4C4C4": "9D9D9D",
}


def darker(match):
    rgb, alpha = match.group(1).upper(), match.group(2) or ""
    if rgb in TONES:
        return "#" + TONES[rgb] + alpha
    scaled = "".join(f"{round(int(rgb[i:i + 2], 16) * 0.8):02X}" for i in (0, 2, 4))
    return "#" + scaled + alpha


def convert(text):
    return re.sub(r"#([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?\b", darker, text)


kitty = (ROOT / "integrations/kitty/kitty-noir.conf").read_text()
kitty = kitty.replace("# Noir for Kitty", "# OLED Noir for Kitty (made by tools/make-oled-themes.py from kitty-noir.conf)", 1)
(ROOT / "integrations/kitty/kitty-oled-noir.conf").write_text(convert(kitty))

vscode = (ROOT / "integrations/vscode/pistachio-noir/themes/noir.json").read_text()
vscode = re.sub(r'"name":\s*"Noir"', '"name": "OLED Noir"', vscode, count=1)
(ROOT / "integrations/vscode/pistachio-noir/themes/oled-noir.json").write_text(convert(vscode))
print("wrote kitty-oled-noir.conf and oled-noir.json")
