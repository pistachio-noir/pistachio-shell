#!/bin/bash
# Self-check of the drives helper (pistachio-devices drives, rust/devices/src/drives.rs): a stand-in
# UDisks on the session bus adds, mounts, fails and removes drives, and the helper (run with
# --session, so it talks to the stand-in and prints its notifications instead of showing them) must
# mount what udiskie mounted and say what udiskie said. Touches no real drive; can run while the
# shell runs. HELPER="<command>" tests another build (default: the one the shell runs).
set -euo pipefail
exec python3 -I - <<'PYEND'
import json, os, queue, shlex, subprocess, sys, threading, time
from gi.repository import Gio, GLib

HELPER = shlex.split(os.environ.get("HELPER", os.path.expanduser("~/.local/bin/pistachio-devices drives")))
ROOT = "/org/freedesktop/UDisks2"
XML = Gio.DBusNodeInfo.new_for_xml("""
<node>
  <interface name="org.freedesktop.DBus.ObjectManager">
    <method name="GetManagedObjects"><arg type="a{oa{sa{sv}}}" direction="out"/></method>
    <signal name="InterfacesAdded"><arg type="o"/><arg type="a{sa{sv}}"/></signal>
    <signal name="InterfacesRemoved"><arg type="o"/><arg type="as"/></signal>
  </interface>
  <interface name="org.freedesktop.UDisks2.Filesystem">
    <method name="Mount"><arg type="a{sv}" direction="in"/><arg type="s" direction="out"/></method>
  </interface>
</node>""")
ay = lambda text: GLib.Variant("ay", text.encode() + b"\0")
objects = {}      # path -> {interface: {property: Variant}}
registered = {}   # path -> registration id of its Filesystem interface
mounts = queue.Queue()  # the paths the helper asked to mount
fail = set()      # paths whose Mount fails
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)


def block(dev, label="", system=False, usage="filesystem", table=None, backing="/", mounted=None):
    o = {"org.freedesktop.UDisks2.Block": {
        "Device": ay(dev), "PreferredDevice": ay(dev), "IdLabel": GLib.Variant("s", label), "IdUUID": GLib.Variant("s", ""),
        "IdUsage": GLib.Variant("s", usage), "HintIgnore": GLib.Variant("b", False), "HintSystem": GLib.Variant("b", system),
        "HintIconName": GLib.Variant("s", ""), "Drive": GLib.Variant("o", "/"), "CryptoBackingDevice": GLib.Variant("o", backing)}}
    if usage == "filesystem":
        o["org.freedesktop.UDisks2.Filesystem"] = {"MountPoints": GLib.Variant("aay", [m.encode() + b"\0" for m in mounted or []])}
    if usage == "crypto":
        o["org.freedesktop.UDisks2.Encrypted"] = {}
    if table:
        o["org.freedesktop.UDisks2.Partition"] = {"Table": GLib.Variant("o", table)}
    return o


def on_call(connection, sender, path, interface, method, params, invocation):
    if method == "GetManagedObjects":
        invocation.return_value(GLib.Variant("(a{oa{sa{sv}}})", (objects,)))
    elif method == "Mount":
        mounts.put(path)
        if path in fail:
            invocation.return_dbus_error("org.freedesktop.UDisks2.Error.DeviceBusy", "Error mounting: the device is busy")
            return
        folder = "/run/media/test/" + path.rsplit("/", 1)[1]
        set_mounts(path, [folder])
        invocation.return_value(GLib.Variant("(s)", (folder,)))


def set_mounts(path, folders):
    value = GLib.Variant("aay", [f.encode() + b"\0" for f in folders])
    objects[path]["org.freedesktop.UDisks2.Filesystem"]["MountPoints"] = value
    bus.emit_signal(None, path, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                    GLib.Variant("(sa{sv}as)", ("org.freedesktop.UDisks2.Filesystem", {"MountPoints": value}, [])))


def add(path, o, announce=True):
    objects[path] = o
    if "org.freedesktop.UDisks2.Filesystem" in o:
        registered[path] = bus.register_object(path, XML.interfaces[1], on_call, None, None)
    if announce:
        bus.emit_signal(None, ROOT, "org.freedesktop.DBus.ObjectManager", "InterfacesAdded", GLib.Variant("(oa{sa{sv}})", (path, o)))


def remove(path):
    o = objects.pop(path)
    if path in registered:
        bus.unregister_object(registered.pop(path))
    bus.emit_signal(None, ROOT, "org.freedesktop.DBus.ObjectManager", "InterfacesRemoved", GLib.Variant("(oas)", (path, list(o))))


def on_loop(f, *a):
    """Runs f on the bus's thread and waits for it."""
    done = threading.Event()
    def run():
        f(*a)
        done.set()
    GLib.idle_add(run)
    assert done.wait(5)


B = ROOT + "/block_devices/"
# before the helper starts: a system disk, a stick that isn't mounted, and one that is
add(B + "nvme0n1", block("/dev/nvme0n1", system=True), announce=False)
add(B + "nvme0n1p2", block("/dev/nvme0n1p2", "root", table=B + "nvme0n1"), announce=False)
add(B + "sda", block("/dev/sda", usage=""), announce=False)
add(B + "sda1", block("/dev/sda1", "EARLY", table=B + "sda"), announce=False)
add(B + "sdz", block("/dev/sdz", usage=""), announce=False)
add(B + "sdz1", block("/dev/sdz1", "THERE", table=B + "sdz", mounted=["/run/media/test/THERE"]), announce=False)
bus.register_object(ROOT, XML.interfaces[0], on_call, None, None)
owned = threading.Event()
Gio.bus_own_name_on_connection(bus, "org.freedesktop.UDisks2", Gio.BusNameOwnerFlags.NONE, lambda *a: owned.set(), lambda *a: sys.exit("FAIL: the session bus already has a UDisks"))
threading.Thread(target=GLib.MainLoop().run, daemon=True).start()
assert owned.wait(5)

helper = subprocess.Popen(HELPER + ["--session"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=sys.stderr, text=True)
events = queue.Queue()
threading.Thread(target=lambda: [events.put(json.loads(line)) for line in helper.stdout], daemon=True).start()


def wait(event, test=lambda m: True, seconds=5):
    end = time.time() + seconds
    while time.time() < end:
        try:
            m = events.get(timeout=max(0.05, end - time.time()))
        except queue.Empty:
            break
        if m["event"] == event and test(m):
            return m
    sys.exit(f"FAIL: the helper never said {event}")


def toast(summary, body, actions=()):
    m = wait("toast", lambda m: m["summary"] == summary)
    assert m["body"] == body and m["actions"] == list(actions), m


def mounted(path):
    try:
        got = mounts.get(timeout=5)
    except queue.Empty:
        sys.exit(f"FAIL: {path} was never mounted")
    assert got == path, got


def quiet(label, seconds=0.7):
    time.sleep(seconds)
    extra = []
    while not events.empty():
        m = events.get()
        if m["event"] == "toast":
            extra.append(m)
    assert not extra and mounts.empty(), (label, extra)


def ok(label):
    print("ok:", label)


wait("ready")
mounted(B + "sda1")
toast("Device mounted", "/dev/sda1: EARLY mounted on /run/media/test/sda1", ["Browse directory"])
wait("changed")
quiet("startup")
ok("a drive in at startup is mounted and told; a mounted one and the system disk are left alone")

on_loop(add, B + "sdb", block("/dev/sdb", usage=""))
on_loop(add, B + "sdb1", block("/dev/sdb1", "FILES", table=B + "sdb"))
toast("Device added", "device appeared on /dev/sdb")
mounted(B + "sdb1")
toast("Device mounted", "/dev/sdb1: FILES mounted on /run/media/test/sdb1", ["Browse directory"])
ok("a drive plugged in is announced, mounted and told, with Browse")

on_loop(set_mounts, B + "sdb1", [])
toast("Device unmounted", "/dev/sdb1: FILES unmounted")
quiet("after unmount")
ok("unmounting is told, and the drive isn't mounted again")

on_loop(remove, B + "sdb1")
on_loop(remove, B + "sdb")
toast("Device removed", "device disappeared on /dev/sdb")
ok("pulling it out is told")

fail.add(B + "sdc1")
on_loop(add, B + "sdc", block("/dev/sdc", usage=""))
on_loop(add, B + "sdc1", block("/dev/sdc1", "BUSY", table=B + "sdc"))
mounted(B + "sdc1")
toast("Job failed", "failed to mount /dev/sdc1:\nError mounting: the device is busy", ["Retry"])
assert helper.poll() is None
ok("a mount that fails is told with Retry, and the helper carries on")

on_loop(add, B + "sdd", block("/dev/sdd", usage=""))
on_loop(add, B + "sdd1", block("/dev/sdd1", "VAULT", usage="crypto", table=B + "sdd"))
toast("Encrypted drive", "/dev/sdd1: VAULT is encrypted. Open it in the file manager to unlock it.", ["Open file manager"])
quiet("encrypted")
ok("an encrypted drive is told, not unlocked or mounted")

on_loop(add, B + "nvme1n1", block("/dev/nvme1n1", system=True))
on_loop(add, B + "nvme1n1p1", block("/dev/nvme1n1p1", "DATA", table=B + "nvme1n1"))
wait("changed")
quiet("system disk")
ok("a system disk appearing is left alone, but the shell hears of the change")

helper.stdin.close()
try:
    helper.wait(timeout=3)
except subprocess.TimeoutExpired:
    helper.kill()
    sys.exit("FAIL: the helper is still running after stdin closed")
ok("the helper exits when the shell goes")
print("all passed")
PYEND
