#!/usr/bin/env python3
"""What the launcher offers from other apps, as one JSON line on stdout (services/Library.qml runs it
each time the launcher opens): CLion's recent projects, newest first, from CLion's own list, VS Code's
recent folders and workspaces (newest first, from the per-project folders VS Code keeps in
workspaceStorage: 1.145 keeps no recently-opened list in its database), and the
Steam games installed in every library folder, with their covers from Steam's cache (runtimes,
Proton and redistributables left out).

  {"clion": [{"name", "path", "opened"}], "vscode": [{"name", "path", "opened"}],
   "steam": [{"appid", "name", "cover"}]}
"""

import glob
import json
import os
import re
import urllib.parse
import xml.etree.ElementTree as ET

HOME = os.path.expanduser("~")
STEAM = os.path.join(HOME, ".local/share/Steam")
NOT_GAMES = re.compile(r"Steam Linux Runtime|Steamworks|Proton|Redistributable|SteamVR", re.I)


def vscode():
    """Local folders and .code-workspace files VS Code opened, newest first; VS Code's own files (its
    agent-sessions workspace) and paths that are gone are left out."""
    storage = f"{HOME}/.config/Code/User/workspaceStorage"
    own = f"{HOME}/.config/Code/"
    found = {}
    for meta in glob.glob(f"{storage}/*/workspace.json"):
        try:
            with open(meta) as f:
                d = json.load(f)
        except (OSError, ValueError):
            continue
        uri = d.get("folder") or d.get("workspace") or ""
        if not uri.startswith("file://"):
            continue  # remote, WSL and untitled workspaces
        path = urllib.parse.unquote(urllib.parse.urlparse(uri).path)
        if path.startswith(own) or not os.path.exists(path):
            continue
        folder = os.path.dirname(meta)
        state = os.path.join(folder, "state.vscdb")
        opened = int(os.path.getmtime(state if os.path.exists(state) else folder) * 1000)
        name = os.path.basename(path.rstrip("/"))
        if name.endswith(".code-workspace"):
            name = name[: -len(".code-workspace")]
        if path not in found or found[path]["opened"] < opened:
            found[path] = {"name": name, "path": path, "opened": opened}
    return sorted(found.values(), key=lambda p: -p["opened"])[:30]


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


print(json.dumps({"clion": clion(), "vscode": vscode(), "steam": steam()}))
