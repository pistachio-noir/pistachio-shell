#!/usr/bin/env python3
"""GNOME Clocks' alarms for the shell (services/Clocks.qml), through Clocks' own settings
(org.gnome.clocks alarms), so the shell's and Clocks' lists are the same. One JSON line on stdout.

  clocks.py list                      [{"id", "name", "hour", "minute", "days", "active"}]
  clocks.py add HOUR MINUTE [NAME]    a one-time alarm, active
  clocks.py set ID active|inactive
  clocks.py stop ID                    stop the matching GNOME alarm, if running
  clocks.py snooze ID                  snooze the matching GNOME alarm, if running
  clocks.py remove ID
"""

import json
import sys
import uuid

from gi.repository import Gio, GLib

settings = Gio.Settings.new("org.gnome.clocks")


def read():
    out = []
    alarms = settings.get_value("alarms")
    for index, a in enumerate(alarms.unpack()):
        raw = {}
        entry = alarms.get_child_value(index)
        for field in range(entry.n_children()):
            pair = entry.get_child_value(field)
            raw[pair.get_child_value(0).get_string()] = pair.get_child_value(1).get_variant()
        out.append({"id": a.get("id", ""), "name": a.get("name", ""), "hour": int(a.get("hour", 0)), "minute": int(a.get("minute", 0)),
                    "days": list(a.get("days", [])), "active": "ring_time" in a or bool(a.get("active", False)), "raw": raw})
    return out


def write(alarms):
    items = []
    for a in alarms:
        raw = dict(a["raw"])
        raw.update({"id": GLib.Variant("s", a["id"]), "name": GLib.Variant("s", a["name"]),
                    "hour": GLib.Variant("i", a["hour"]), "minute": GLib.Variant("i", a["minute"]),
                    "days": GLib.Variant("ai", a["days"]), "active": GLib.Variant("b", a["active"])})
        if not a["active"]:
            raw.pop("ring_time", None)
        items.append(raw)
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
elif cmd in ("stop", "snooze"):
    alarm_id = sys.argv[2]
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    owner = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                          "NameHasOwner", GLib.Variant("(s)", ("org.gnome.clocks",)), GLib.VariantType("(b)"),
                          Gio.DBusCallFlags.NONE, 1000, None).unpack()[0]
    if owner:
        bus.call_sync("org.gnome.clocks", "/org/gnome/clocks", "org.gtk.Actions", "Activate",
                      GLib.Variant("(sava{sv})", (cmd + "-alarm", [GLib.Variant("s", alarm_id)], {})),
                      None, Gio.DBusCallFlags.NONE, 2000, None)
    elif cmd == "stop":
        for a in alarms:
            if a["id"] == alarm_id and not a["days"]:
                a["active"] = False
                write(alarms)
                break
elif cmd == "remove":
    write([a for a in alarms if a["id"] != sys.argv[2]])
print(json.dumps([{k: v for k, v in a.items() if k != "raw"} for a in read()]))
