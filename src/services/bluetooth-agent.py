#!/usr/bin/env python3
"""BlueZ pairing agent for the shell; services/Bluetooth.qml runs it.

Quickshell's Bluetooth module has no agent, so devices that show or ask for a code could not pair.
This registers an org.bluez.Agent1 object as BlueZ's default agent (again whenever bluetoothd
restarts) and passes each question to the shell as a JSON line on stdout. The shell answers on stdin.

  out  {"event": "ready"}                  registered as the default agent
  out  {"event": "lost"}                   bluetoothd went away, and the registration with it
  out  {"event": "request", "id": 1, "kind": "confirm", "device": "/org/bluez/hci0/dev_…", "code": "012345"}
  out  {"event": "cancel"}                 BlueZ dropped the question it asked last
  in   {"id": 1, "accept": true, "value": "0000"}     value only for "pin" and "passkey"

Kinds: confirm (do both sides show this code?), authorize (a device asks to pair), service (a paired
device asks to use a service, with "uuid"), pin and passkey (type the code the device shows), and
display-pin and display-passkey (show a code to type on the device, with "entered", the keys typed so
far, or -1). The display kinds are answered at once, so they carry id 0.

It exits when stdin closes, so it never outlives the shell. With --session it serves on the session
bus without BlueZ, so tests/bluetooth-agent.sh can ask it questions (the system bus lets only root
call an agent).
"""

import json
import os
import sys

from gi.repository import Gio, GLib

PATH = "/pistachio/agent"
INTERFACE = Gio.DBusNodeInfo.new_for_xml("""
<node>
  <interface name="org.bluez.Agent1">
    <method name="Release"/>
    <method name="RequestPinCode"><arg type="o" direction="in"/><arg type="s" direction="out"/></method>
    <method name="DisplayPinCode"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
    <method name="RequestPasskey"><arg type="o" direction="in"/><arg type="u" direction="out"/></method>
    <method name="DisplayPasskey"><arg type="o" direction="in"/><arg type="u" direction="in"/><arg type="q" direction="in"/></method>
    <method name="RequestConfirmation"><arg type="o" direction="in"/><arg type="u" direction="in"/></method>
    <method name="RequestAuthorization"><arg type="o" direction="in"/></method>
    <method name="AuthorizeService"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
    <method name="Cancel"/>
  </interface>
</node>""").interfaces[0]
KINDS = {
    "RequestConfirmation": "confirm",
    "RequestAuthorization": "authorize",
    "AuthorizeService": "service",
    "RequestPinCode": "pin",
    "RequestPasskey": "passkey",
    "DisplayPinCode": "display-pin",
    "DisplayPasskey": "display-passkey",
}

session = "--session" in sys.argv
loop = GLib.MainLoop()
pending = {}  # id -> (invocation, kind), questions waiting for the shell
last_id = 0
bluez = None  # bluetoothd's unique bus name while it runs


def send(**message):
    print(json.dumps(message), flush=True)


def log(text):
    print(text, file=sys.stderr, flush=True)


def drop_pending(error):
    for invocation, _ in pending.values():
        invocation.return_dbus_error(error, "The question was withdrawn")
    pending.clear()


def on_call(connection, sender, path, interface, method, params, invocation):
    global last_id
    if not session and sender != bluez:
        invocation.return_dbus_error("org.bluez.Error.Rejected", "Only BlueZ asks this agent")
        return
    args = params.unpack()
    if method == "Release":
        invocation.return_value(None)
        return
    if method == "Cancel":
        drop_pending("org.bluez.Error.Canceled")
        invocation.return_value(None)
        send(event="cancel")
        return
    kind = KINDS[method]
    message = {"event": "request", "kind": kind, "device": args[0]}
    if method in ("RequestConfirmation", "DisplayPasskey"):
        message["code"] = f"{args[1]:06d}"
    elif method == "DisplayPinCode":
        message["code"] = args[1]
    elif method == "AuthorizeService":
        message["uuid"] = args[1]
    if kind.startswith("display"):
        message["id"] = 0
        message["entered"] = args[2] if method == "DisplayPasskey" else -1
        invocation.return_value(None)
    else:
        last_id += 1
        message["id"] = last_id
        pending[last_id] = (invocation, kind)
    send(**message)


def answer(line):
    try:
        message = json.loads(line)
        invocation, kind = pending.pop(message["id"])
    except (ValueError, KeyError, TypeError):
        log(f"ignored answer: {line!r}")
        return
    value = str(message.get("value", ""))
    if not message.get("accept"):
        invocation.return_dbus_error("org.bluez.Error.Rejected", "Declined")
    elif kind == "pin" and 1 <= len(value) <= 16:
        invocation.return_value(GLib.Variant("(s)", (value,)))
    elif kind == "passkey" and value.isdigit() and int(value) <= 999999:
        invocation.return_value(GLib.Variant("(u)", (int(value),)))
    elif kind in ("pin", "passkey"):
        invocation.return_dbus_error("org.bluez.Error.Rejected", "Not a valid code")
    else:
        invocation.return_value(None)


buffer = b""


def on_stdin(fd, condition):
    global buffer
    data = os.read(fd, 4096)
    if not data:  # the shell is gone
        loop.quit()
        return False
    *lines, buffer = (buffer + data).split(b"\n")
    for line in lines:
        if line.strip():
            answer(line.decode())
    return True


def call_bluez(connection, method, args):
    connection.call_sync("org.bluez", "/org/bluez", "org.bluez.AgentManager1", method,
                         GLib.Variant(args[0], args[1]), None, Gio.DBusCallFlags.NONE, -1, None)


def on_bluez_appeared(connection, name, owner):
    global bluez
    bluez = owner
    try:
        call_bluez(connection, "RegisterAgent", ("(os)", (PATH, "KeyboardDisplay")))
        call_bluez(connection, "RequestDefaultAgent", ("(o)", (PATH,)))
    except GLib.Error as e:
        log(f"could not register with BlueZ: {e.message}")
        return
    send(event="ready")


def on_bluez_vanished(connection, name):
    global bluez
    if bluez is None:
        return  # not there at startup: nothing to lose
    bluez = None
    drop_pending("org.bluez.Error.Canceled")
    send(event="lost")


def main():
    bus = Gio.bus_get_sync(Gio.BusType.SESSION if session else Gio.BusType.SYSTEM, None)
    bus.register_object(PATH, INTERFACE, on_call, None, None)
    GLib.io_add_watch(sys.stdin.fileno(), GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, on_stdin)
    if session:
        send(event="ready", name=bus.get_unique_name())
    else:
        Gio.bus_watch_name_on_connection(bus, "org.bluez", Gio.BusNameWatcherFlags.NONE,
                                         on_bluez_appeared, on_bluez_vanished)
    loop.run()


if __name__ == "__main__":
    main()
