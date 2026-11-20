#!/usr/bin/env python3
"""Rebuilds src/launcher/emoji.js, the emoji the launcher finds after a ":" (owner's request).

The list and names come from Unicode's emoji-test.txt, the search keywords from CLDR's English
annotations; skin-tone variants are left out (owner's call). Keep the Emoji version one the installed
Noto Color Emoji draws (16.0 for its 2.05x releases), or new ones show as boxes.

    python3 -I tools/make-emoji.py [emoji version]
"""
import json
import os
import sys
import urllib.request

VERSION = sys.argv[1] if len(sys.argv) > 1 else "16.0"
TEST = f"https://unicode.org/Public/emoji/{VERSION}/emoji-test.txt"
ANNOTATIONS = "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-annotations-full/annotations/en/annotations.json"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "launcher", "emoji.js")
SKIN = {chr(c) for c in range(0x1F3FB, 0x1F400)}


def fetch(url: str) -> str:
    with urllib.request.urlopen(url, timeout=30) as r:
        return r.read().decode("utf-8")


keywords = json.loads(fetch(ANNOTATIONS))["annotations"]["annotations"]
rows, group = [], ""
for line in fetch(TEST).splitlines():
    if line.startswith("# group:"):
        group = line.split(":", 1)[1].strip()
        continue
    if not line.strip() or line.startswith("#") or "; fully-qualified" not in line or group == "Component":
        continue
    emoji, _, rest = line.split("#", 1)[1].strip().partition(" ")  # "😀 E1.0 grinning face"
    name = rest.split(" ", 1)[1]  # without the "E1.0"
    if any(ch in SKIN for ch in emoji):
        continue
    words = keywords.get(emoji, keywords.get(emoji.replace("️", ""), {})).get("default", [])
    rows.append([emoji, name, ", ".join(w for w in words if w.lower() != name.lower())])

with open(OUT, "w", encoding="utf-8") as f:
    f.write(".pragma library\n\n")
    f.write("// The emoji the launcher finds after a \":\" (owner's request, after phase 8), as [emoji, name,\n")
    f.write(f"// keywords]: Unicode's emoji-test.txt {VERSION} (fully-qualified, no skin tones; Noto Color Emoji\n")
    f.write("// draws them all) with search keywords from CLDR's English annotations. Generated, not edited:\n")
    f.write("// tools/make-emoji.py rebuilds it.\n")
    f.write("var list = [\n")
    for r in rows:
        f.write("    " + json.dumps(r, ensure_ascii=False) + ",\n")
    f.write("];\n")
print(f"{len(rows)} emoji written to {os.path.normpath(OUT)}")
