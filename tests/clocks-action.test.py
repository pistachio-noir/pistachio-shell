"""Run with dbus-run-session so the fake Clocks action never sees the user's bus."""
import os
import subprocess
import tempfile
from pathlib import Path
import time

from gi.repository import Gio, GLib


PSC = os.environ.get("PSC") or str(Path(__file__).resolve().parents[1] / "rust/target/release/psc")  # `psc clocks`
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
              "RequestName", GLib.Variant("(su)", ("org.gnome.clocks", 0)), GLib.VariantType("(u)"),
              Gio.DBusCallFlags.NONE, 1000, None)
node = Gio.DBusNodeInfo.new_for_xml("<node><interface name='org.gtk.Actions'><method name='Activate'>"
                                     "<arg type='s' direction='in'/><arg type='av' direction='in'/>"
                                     "<arg type='a{sv}' direction='in'/></method></interface></node>")
calls = []
hang = False


def activate(_bus, _sender, _path, _interface, _method, args, reply):
    calls.append(args.unpack())
    if not hang:
        reply.return_value(None)


bus.register_object("/org/gnome/clocks", node.interfaces[0], activate, None, None)


SETTINGS = tempfile.TemporaryDirectory()


def run(*args):
    start = time.monotonic()
    # GSettings in a throwaway keyfile: the owner's real alarms are never read or written
    env = dict(os.environ, GSETTINGS_BACKEND="keyfile", XDG_CONFIG_HOME=SETTINGS.name)
    with subprocess.Popen([PSC, "clocks", *args], env=env,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as proc:
        deadline = start + 8
        while proc.poll() is None and time.monotonic() < deadline:
            GLib.MainContext.default().iteration(False)
            time.sleep(0.01)
        proc.communicate(timeout=1)
        return proc.returncode, time.monotonic() - start


code, _ = run("stop", "test-id")
assert code == 0 and calls[-1][:2] == ("stop-alarm", ["test-id"]), calls
print("ok: Stop activates GNOME's matching alarm")

code, _ = run("snooze", "test-id")
assert code == 0 and calls[-1][:2] == ("snooze-alarm", ["test-id"]), calls
print("ok: Snooze activates GNOME's matching alarm")

hang = True
code, took = run("stop", "test-id")
assert code != 0 and took < 6, (code, took)
print("ok: a hung Clocks makes the helper fail within its timeout, so the popup can close")
