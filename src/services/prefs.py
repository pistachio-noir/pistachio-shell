#!/usr/bin/env python3
"""Export and import the shell's preferences as TOML (services/Preferences.qml).

Owner's call, 15 November 2026: a one-off snapshot of every Settings preference and the launcher's
customisations in ~/.config/pistachio-shell/settings.toml. Never the Cider token, LocalSend's known
devices, notification or usage history, running state, the wallpaper or desktop icon positions.

  prefs.py export PATH JSON   JSON = {"values": {storeKey: value}}; writes PATH (the old file kept as
                         PATH.bak), atomically; prints {"ok": true, "path": PATH}
  prefs.py read PATH JSON     JSON = {"actions": [ids], "claudeModels": [...], "codexModels": [...]}
                         prints {"ok": true, "values": {storeKey: value}, "skipped": [{key, reason}]}
                         (only valid values; nothing is written)
Errors print {"ok": false, "error": "..."} and exit 1. JSON comes as an argument (stdin when left out):
Quickshell's Process can't reopen stdin once closed, and the helper needs it closed to finish reading.
"""
import json
import os
import re
import sys
import tempfile
import tomllib
from datetime import datetime

INTEGRATIONS = ["calendar", "clocks", "weather", "vscode", "clion", "steam", "sober", "cider", "claude", "qalc", "tldr"]
EFFORTS = ["low", "medium", "high"]
ALIAS = re.compile(r"^[a-z0-9_À-ɏ-]{1,32}$", re.I)


def bool_(v, _ctx):
    if isinstance(v, bool):
        return v
    raise ValueError("expected true or false")


def choice(options):
    def check(v, ctx):
        opts = options(ctx) if callable(options) else options
        if v in opts and type(v) is type(opts[0]):
            return v
        raise ValueError("expected one of " + ", ".join(json.dumps(o) for o in opts))
    return check


def text(limit, allow_empty=True):
    def check(v, _ctx):
        if not isinstance(v, str) or len(v) > limit or (not allow_empty and not v.strip()) or any(ord(c) < 32 for c in v):
            raise ValueError(f"expected text of at most {limit} characters")
        return v
    return check


def time(v, _ctx):
    if isinstance(v, str):
        m = re.fullmatch(r"(\d{1,2}):(\d{2})", v.strip())
        if m and int(m.group(1)) < 24 and int(m.group(2)) < 60:
            return int(m.group(1)) * 60 + int(m.group(2))
    raise ValueError('expected a time like "20:00"')


def integer(lo, hi):
    def check(v, _ctx):
        if isinstance(v, int) and not isinstance(v, bool) and lo <= v <= hi:
            return v
        raise ValueError(f"expected a whole number from {lo} to {hi}")
    return check


def folder(v, ctx):
    v = text(4096)(v, ctx)
    if v and not os.path.isdir(os.path.expanduser(v)):
        raise ValueError("that folder doesn't exist on this machine")
    return os.path.expanduser(v) if v else v


def names_list(limit):
    def check(v, _ctx):
        if isinstance(v, list) and len(v) <= limit and all(isinstance(x, str) and 0 < len(x) <= 200 for x in v):
            return list(dict.fromkeys(v))
        raise ValueError("expected a list of names")
    return check


def integrations(v, _ctx):
    v = names_list(len(INTEGRATIONS))(v, _ctx)
    unknown = [x for x in v if x not in INTEGRATIONS]
    if unknown:
        raise ValueError("unknown integration " + ", ".join(unknown))
    return v


def rules(v, _ctx):
    # only lasting rules travel: "no toasts" (a silence until a time is temporary)
    if not isinstance(v, dict) or len(v) > 500:
        raise ValueError("expected app = \"no toasts\" lines")
    out = {}
    for app, rule in v.items():
        if rule != "no toasts" or not app or len(app) > 200:
            raise ValueError(f"{app!r}: only \"no toasts\" can be imported")
        out[app] = {"noToasts": True}
    return out


def target(entry, ctx, aliasing=False):
    if not isinstance(entry, dict) or set(entry) != {"kind", "target"} or not isinstance(entry["target"], str) or not entry["target"] or len(entry["target"]) > 300:
        raise ValueError("expected { kind = ..., target = ... }")
    kind = entry["kind"]
    if kind == "action" and entry["target"] not in ctx.get("actions", []):
        raise ValueError(f"unknown shell action {entry['target']!r}")
    if kind not in (("app", "action") if aliasing else ("app", "preset", "action")):
        raise ValueError(f"kind {kind!r} can't be " + ("aliased" if aliasing else "pinned"))
    return {"kind": kind, "target": entry["target"]}


def pins(v, ctx):
    if not isinstance(v, list) or len(v) > 100:
        raise ValueError("expected a list of { kind, target }")
    out = []
    for entry in v:
        t = target(entry, ctx)
        if t not in out:
            out.append(t)
    return out


def aliases(v, ctx):
    if not isinstance(v, dict) or len(v) > 200:
        raise ValueError("expected alias = { kind, target } lines")
    out = {}
    for name, entry in v.items():
        if not ALIAS.match(name):
            raise ValueError(f"alias {name!r}: use 1–32 letters, numbers, _ or -")
        out[name.lower()] = target(entry, ctx, aliasing=True)
    return out


def presets(v, _ctx):
    if not isinstance(v, list) or len(v) > 50:
        raise ValueError("expected a list of presets")
    out, seen = [], set()
    for p in v:
        if not isinstance(p, dict) or not isinstance(p.get("name"), str) or not 0 < len(p["name"]) <= 40 or p["name"] in seen:
            raise ValueError("each preset needs a unique name")
        names, apps = p.get("names", {}), p.get("apps", {})
        ws = {str(n) for n in range(1, 11)}
        if not isinstance(names, dict) or not all(k in ws and isinstance(x, str) and len(x) <= 40 for k, x in names.items()):
            raise ValueError(f"preset {p['name']!r}: names are workspace = \"name\" (1–10)")
        if not isinstance(apps, dict) or not all(k in ws and isinstance(x, list) and len(x) <= 20 and all(isinstance(a, str) and 0 < len(a) <= 300 for a in x) for k, x in apps.items()):
            raise ValueError(f"preset {p['name']!r}: apps are workspace = [app ids] (1–10)")
        seen.add(p["name"])
        out.append({"name": p["name"], "names": dict(names), "apps": {k: list(x) for k, x in apps.items()}})
    return out


# (section, toml key, store key, check, how the value is written)
SCHEMA = [
    ("appearance", "frosted", "frosted", bool_), ("appearance", "frost_style", "frostStyle", choice(["subtle", "glassy"])),
    ("appearance", "shadows", "shadows", bool_), ("appearance", "desktop_icons", "desktopIcons", bool_),
    ("appearance", "workspace_osd", "workspaceOsd", bool_), ("appearance", "tabbed_osd", "tabbedOsd", bool_),
    ("experimental", "style", "appearanceStyle", choice(["classic", "tui"])),
    ("experimental", "colours", "colourScheme", choice(["pistachio", "noir"])),
    ("experimental", "tui_tray_open", "tuiTrayOpen", bool_),
    ("experimental", "phone_preview", "phonePreview", bool_),
    ("display", "night_light", "nightLight", bool_), ("display", "night_warmth", "temperature", integer(2500, 6500)),
    ("display", "night_schedule", "nightSchedule", bool_), ("display", "night_from", "nightFrom", time), ("display", "night_to", "nightTo", time),
    ("sound", "headphones_take_over", "headphonesTakeOver", bool_), ("sound", "volume_tick", "volumeTick", bool_),
    ("notifications", "do_not_disturb", "dnd", bool_), ("notifications", "quiet_schedule", "dndSchedule", bool_),
    ("notifications", "quiet_follows_night_light", "dndFollowsNight", bool_), ("notifications", "quiet_from", "dndFrom", time),
    ("notifications", "quiet_to", "dndTo", time), ("notifications", "quiet_in_fullscreen", "quietFullscreen", bool_),
    ("notifications", "quiet_during_calls", "quietCalls", bool_), ("notifications", "sound", "notificationSound", bool_),
    ("notifications", "rules", "notificationRules", rules),
    ("focus", "zen_pomodoro", "zenPomodoro", bool_), ("focus", "focus_pomodoro", "focusPomodoro", bool_),
    ("focus", "focus_minutes", "focusMinutes", choice([15, 25, 30, 45, 50, 60, 90, 120])), ("focus", "zen_during_focus", "focusZen", bool_),
    ("focus", "allowed_apps", "focusAllowed", names_list(200)), ("focus", "pomodoro_work", "pomodoroWork", choice([15, 20, 25, 30, 45, 50])),
    ("focus", "pomodoro_break", "pomodoroBreak", choice([3, 5, 10, 15])), ("focus", "pomodoro_long_break", "pomodoroLongBreak", choice([10, 15, 20, 30])),
    ("focus", "pomodoro_rounds", "pomodoroRounds", choice([2, 3, 4, 5, 6])),
    ("lens", "provider", "lensProvider", choice(["claude", "codex"])),
    ("lens", "claude_model", "lensClaudeModel", choice(lambda c: c["claudeModels"])), ("lens", "claude_effort", "lensClaudeEffort", choice(EFFORTS)),
    ("lens", "codex_model", "lensCodexModel", choice(lambda c: c["codexModels"])), ("lens", "codex_effort", "lensCodexEffort", choice(EFFORTS)),
    ("lens", "claude_fallback", "lensClaudeFallback", bool_), ("lens", "codex_fallback", "lensCodexFallback", bool_),
    ("lens", "suggest_coding_model", "lensSuggestCoding", bool_),
    ("lens", "claude_coding_model", "lensClaudeCodingModel", choice(lambda c: c["claudeModels"])), ("lens", "claude_coding_effort", "lensClaudeCodingEffort", choice(EFFORTS)),
    ("lens", "codex_coding_model", "lensCodexCodingModel", choice(lambda c: c["codexModels"])), ("lens", "codex_coding_effort", "lensCodexCodingEffort", choice(EFFORTS)),
    ("lens", "quick_chat_tile", "quickChatTile", bool_),
    ("capture", "screenshot_output", "screenshotOutput", choice(["save", "copy", "both"])),
    ("capture", "recording_audio", "recordingAudio", choice(["off", "system", "mic", "both"])),
    ("capture", "recording_countdown", "recordingCountdown", choice([0, 3, 5, 10])),
    ("apps", "terminal", "terminal", text(64)), ("apps", "weather_city", "weatherCity", text(100)),
    ("integrations", "off", "integrationsOff", integrations), ("integrations", "calendar_events", "calendarEvents", bool_),
    ("localsend", "receive", "localsendReceive", bool_), ("localsend", "name", "localsendName", text(64)),
    ("localsend", "folder", "localsendFolder", folder), ("localsend", "accept_known", "localsendAcceptKnown", bool_),
    ("launcher", "pins", "launcherPins", pins), ("launcher", "aliases", "launcherAliases", aliases),
    ("launcher", "presets", "workspacePresets", presets),
]
SECTIONS = {
    "appearance": "Settings → Appearance", "experimental": "Settings → Experimental", "display": "Settings → Display & night light",
    "sound": "Settings → Sound", "notifications": "Settings → Notifications (rules: app = \"no toasts\")",
    "focus": "Settings → Focus & Zen", "lens": "Settings → Lens and AI", "capture": "the screenshot menu and recording setup",
    "apps": "Settings → Apps & places (terminal \"\" = automatic)", "integrations": "Settings → Integrations (off = the switched-off ones)",
    "localsend": "Settings → LocalSend (name/folder \"\" = automatic)", "launcher": "the launcher's pins, aliases and workspace presets",
}


# --- writing TOML ----------------------------------------------------------------------------------

def key(k):
    return k if re.fullmatch(r"[A-Za-z0-9_-]+", k) else string(k)


def string(s):
    out = []
    for c in s:
        if c == '"' or c == "\\":
            out.append("\\" + c)
        elif c == "\n":
            out.append("\\n")
        elif c == "\t":
            out.append("\\t")
        elif ord(c) < 32 or ord(c) == 127:
            out.append(f"\\u{ord(c):04X}")
        else:
            out.append(c)
    return '"' + "".join(out) + '"'


def value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    if isinstance(v, str):
        return string(v)
    if isinstance(v, list):
        return "[" + ", ".join(value(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{ " + ", ".join(f"{key(k)} = {value(x)}" for k, x in v.items()) + " }" if v else "{}"
    raise TypeError(f"can't write {type(v).__name__}")


def plain(v):
    # QML hands numbers over as floats; whole ones go back to ints
    if isinstance(v, float) and v.is_integer():
        return int(v)
    if isinstance(v, list):
        return [plain(x) for x in v]
    if isinstance(v, dict):
        return {k: plain(x) for k, x in v.items()}
    return v


def to_toml(values):
    lines = [f"# Pistachio shell settings, exported {datetime.now().strftime('%-d %b %Y %H:%M')}.",
             "# Import them in Settings → About → Your settings; you'll see the changes before they apply.",
             "# Times are 24-hour \"HH:MM\". Left out on purpose: tokens, LocalSend's known devices, history."]
    for section, comment in SECTIONS.items():
        rows = [(tk, sk) for s, tk, sk, _ in SCHEMA if s == section and sk in values]
        if not rows:
            continue
        lines += ["", f"# {comment}", f"[{section}]"]
        tables = []
        for tk, sk in rows:
            v = plain(values[sk])
            if sk in ("nightFrom", "nightTo", "dndFrom", "dndTo") and isinstance(v, int):
                v = f"{v // 60:02d}:{v % 60:02d}"
            if sk == "notificationRules":
                v = {app: "no toasts" for app, r in (v or {}).items() if isinstance(r, dict) and r.get("noToasts")}
                tables.append((tk, v))
                continue
            if sk == "launcherAliases":
                tables.append((tk, v or {}))
                continue
            if sk == "workspacePresets" and v:
                tables.append(("presets", v))  # one [[launcher.presets]] each; none is `presets = []`
                continue
            lines.append(f"{key(tk)} = {value(v)}")
        for tk, v in tables:
            if isinstance(v, list):  # presets: one [[launcher.presets]] per preset
                for p in v:
                    lines += ["", f"[[{section}.{tk}]]"] + [f"{key(k)} = {value(x)}" for k, x in p.items()]
            else:
                lines += ["", f"[{section}.{tk}]"] + [f"{key(k)} = {value(x)}" for k, x in v.items()]
    return "\n".join(lines) + "\n"


# --- reading TOML ----------------------------------------------------------------------------------

def read(path, ctx):
    with open(path, "rb") as f:
        data = tomllib.load(f)
    values, skipped = {}, []
    known = {}
    for section, tk, sk, check in SCHEMA:
        known.setdefault(section, set()).add(tk)
        if section in data and isinstance(data[section], dict) and tk in data[section]:
            try:
                values[sk] = check(data[section][tk], ctx)
            except (ValueError, KeyError, TypeError) as e:
                skipped.append({"key": f"{section}.{tk}", "reason": str(e)})
    for section, table in data.items():
        if section not in known:
            skipped.append({"key": section, "reason": "unknown section"})
        elif isinstance(table, dict):
            for tk in table:
                if tk not in known[section]:
                    skipped.append({"key": f"{section}.{tk}", "reason": "unknown setting"})
    return values, skipped


def main(argv):
    if len(argv) not in (3, 4) or argv[1] not in ("export", "read"):
        print(json.dumps({"ok": False, "error": "usage: prefs.py export|read PATH [JSON]"}))
        return 1
    path = os.path.expanduser(argv[2])
    try:
        payload = json.loads((argv[3] if len(argv) == 4 else sys.stdin.read()) or "{}")
        if argv[1] == "export":
            body = to_toml(payload.get("values", {}))
            tomllib.loads(body)  # never leave a file that won't read back
            os.makedirs(os.path.dirname(path), exist_ok=True)
            if os.path.exists(path):
                os.replace(path, path + ".bak")
            fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".settings-", suffix=".toml")
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(body)
            os.chmod(tmp, 0o644)
            os.replace(tmp, path)
            print(json.dumps({"ok": True, "path": path}))
        else:
            if not os.path.exists(path):
                print(json.dumps({"ok": False, "error": "no settings file yet: export first"}))
                return 1
            values, skipped = read(path, payload)
            print(json.dumps({"ok": True, "values": values, "skipped": skipped}))
        return 0
    except tomllib.TOMLDecodeError as e:
        print(json.dumps({"ok": False, "error": f"the file isn't valid TOML: {e}"}))
    except (OSError, ValueError, TypeError) as e:
        print(json.dumps({"ok": False, "error": str(e)}))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
