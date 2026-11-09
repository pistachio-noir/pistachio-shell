#!/usr/bin/env python3
"""GNOME Clocks' alarms for the shell (services/Clocks.qml), through Clocks' own settings
(org.gnome.clocks alarms), so the shell's and Clocks' lists are the same. One JSON line on stdout.

  clocks.py list                      [{"id", "name", "hour", "minute", "days", "active"}]
  clocks.py add HOUR MINUTE [NAME]    a one-time alarm, active
  clocks.py set ID active|inactive
  clocks.py remove ID
"""

import json
import sys
import uuid

from gi.repository import Gio, GLib

settings = Gio.Settings.new("org.gnome.clocks")


def read():
    out = []
    for a in settings.get_value("alarms").unpack():
        out.append({"id": a.get("id", ""), "name": a.get("name", ""), "hour": int(a.get("hour", 0)), "minute": int(a.get("minute", 0)),
                    "days": list(a.get("days", [])), "active": bool(a.get("active", True)), "raw": a})
    return out


def write(alarms):
    items = []
    for a in alarms:
        raw = dict(a["raw"])
        raw.update({"id": a["id"], "name": a["name"], "hour": a["hour"], "minute": a["minute"], "days": a["days"], "active": a["active"]})
        items.append({k: GLib.Variant({"id": "s", "name": "s", "hour": "i", "minute": "i", "days": "ai", "active": "b",
                                       "snooze_minutes": "i", "ring_minutes": "i"}.get(k, "s"), v) for k, v in raw.items()
                      if k in ("id", "name", "hour", "minute", "days", "active", "snooze_minutes", "ring_minutes")})
    settings.set_value("alarms", GLib.Variant("aa{sv}", items))
    Gio.Settings.sync()


cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
alarms = read()
if cmd == "add":
    alarms.append({"id": uuid.uuid4().hex, "name": " ".join(sys.argv[4:]) or "Alarm", "hour": int(sys.argv[2]), "minute": int(sys.argv[3]),
                   "days": [], "active": True, "raw": {}})
    write(alarms)
elif cmd == "set":
    for a in alarms:
        if a["id"] == sys.argv[2]:
            a["active"] = sys.argv[3] == "active"
    write(alarms)
elif cmd == "remove":
    write([a for a in alarms if a["id"] != sys.argv[2]])
print(json.dumps([{k: v for k, v in a.items() if k != "raw"} for a in read()]))
