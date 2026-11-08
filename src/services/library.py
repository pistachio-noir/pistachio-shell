#!/usr/bin/env python3
"""What the launcher offers from other apps, as one JSON line on stdout (services/Library.qml runs it
each time the launcher opens): CLion's recent projects, newest first, from CLion's own list, and the
Steam games installed in every library folder, with their covers from Steam's cache (runtimes,
Proton and redistributables left out).

  {"clion": [{"name", "path", "opened"}], "steam": [{"appid", "name", "cover"}]}
"""

import glob
import json
import os
import re
import xml.etree.ElementTree as ET

HOME = os.path.expanduser("~")
STEAM = os.path.join(HOME, ".local/share/Steam")
NOT_GAMES = re.compile(r"Steam Linux Runtime|Steamworks|Proton|Redistributable|SteamVR", re.I)


def clion():
    lists = sorted(glob.glob(f"{HOME}/.config/JetBrains/CLion*/options/recentProjects.xml"))
    if not lists:
        return []
    try:
        root = ET.parse(lists[-1]).getroot()
    except (ET.ParseError, OSError):
        return []
    projects = []
    for entry in root.iter("entry"):
        path = entry.get("key", "").replace("$USER_HOME$", HOME)
        if not path or not os.path.isdir(path):
            continue
        opened = 0
        for option in entry.iter("option"):
            if option.get("name") == "projectOpenTimestamp":
                opened = int(option.get("value") or 0)
        projects.append({"name": os.path.basename(path.rstrip("/")), "path": path, "opened": opened})
    return sorted(projects, key=lambda p: -p["opened"])


def steam():
    folders = [STEAM]
    try:
        with open(os.path.join(STEAM, "steamapps/libraryfolders.vdf")) as f:
            folders = list(dict.fromkeys(re.findall(r'"path"\s+"([^"]+)"', f.read()) + [STEAM]))
    except OSError:
        pass
    games = []
    for folder in folders:
        for manifest in glob.glob(os.path.join(folder, "steamapps/appmanifest_*.acf")):
            try:
                with open(manifest, errors="replace") as f:
                    text = f.read()
            except OSError:
                continue
            appid = re.search(r'"appid"\s+"(\d+)"', text)
            name = re.search(r'"name"\s+"([^"]+)"', text)
            if not appid or not name or NOT_GAMES.search(name.group(1)):
                continue
            cache = os.path.join(STEAM, "appcache/librarycache", appid.group(1))
            covers = [os.path.join(cache, n) for n in ("library_600x900.jpg", "header.jpg")] + glob.glob(os.path.join(cache, "*/library_600x900.jpg"))
            cover = next((c for c in covers if os.path.exists(c)), "")
            games.append({"appid": appid.group(1), "name": name.group(1), "cover": cover})
    return sorted(games, key=lambda g: g["name"].lower())


print(json.dumps({"clion": clion(), "steam": steam()}))
