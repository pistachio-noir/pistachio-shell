#!/usr/bin/env python3
"""Polkit authentication agent for the shell; services/Polkit.qml runs it.

Quickshell has an agent (Quickshell.Services.Polkit), but it starts PAM the moment a request comes in,
so dismissing its dialog counts as a failed login for pam_faillock (three lock the account for
10 minutes, the TTY included). This one registers with polkit for the shell's login session (again
whenever polkitd restarts) and passes each request to the shell as a JSON line on stdout. PAM starts
only once the shell sends a password, through polkit's own helper (PolkitAgent.Session), so
cancelling before that touches nothing.

  out  {"event": "ready"}                  registered with polkit for this session
  out  {"event": "lost"}                   polkitd went away, and the registration with it
  out  {"event": "request", "cookie": "…", "action": "org.freedesktop.policykit.exec", "message": "…",
        "user": "sx", "requester": "pamac-manager (pid 4182)", "vendor": "PackageKit"}
  out  {"event": "prompt", "cookie": "…", "text": "Verification code: ", "echo": true}
                                           PAM asks for more than the password; answered like one
  out  {"event": "failed", "cookie": "…", "error": "…"}   PAM said no; error is its own message, or ""
  out  {"event": "done", "cookie": "…"}    authorised
  out  {"event": "cancel", "cookie": "…"}  polkit withdrew the request (the app gave up)
  in   {"cookie": "…", "response": "…"}    the password, or the answer to a prompt
  in   {"cookie": "…", "cancel": true}     dismissed

requester (the app that asked) and vendor are "" when unknown. It exits when stdin closes, so it never
outlives the shell. With --session it serves on the session bus without polkit and never starts PAM
(a response fails at once), so tests/polkit-agent.sh can make requests.
"""

import json
import os
import pwd
import sys

import gi

gi.require_version("Polkit", "1.0")
gi.require_version("PolkitAgent", "1.0")
from gi.repository import Gio, GLib, Polkit, PolkitAgent

PATH = "/pistachio/PolkitAgent"
INTERFACE = Gio.DBusNodeInfo.new_for_xml("""
<node>
  <interface name="org.freedesktop.PolicyKit1.AuthenticationAgent">
    <method name="BeginAuthentication">
      <arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/>
      <arg type="a{ss}" direction="in"/><arg type="s" direction="in"/><arg type="a(sa{sv})" direction="in"/>
    </method>
    <method name="CancelAuthentication"><arg type="s" direction="in"/></method>
  </interface>
</node>""").interfaces[0]
CANCELLED = "org.freedesktop.PolicyKit1.Error.Cancelled"
FAILED = "org.freedesktop.PolicyKit1.Error.Failed"

session = "--session" in sys.argv
loop = GLib.MainLoop()
requests = {}  # cookie -> Request, waiting for the shell or for PAM
polkitd = None  # polkitd's unique bus name while it runs


class Request:
    def __init__(self, invocation, uid):
        self.invocation = invocation  # polkit's BeginAuthentication call, answered when it's over
        self.uid = uid
        self.pam = None  # the PolkitAgent.Session while PAM runs
        self.password = None  # sent before PAM asked for it
        self.waiting = False  # PAM asked something the shell hasn't answered yet
        self.error = ""  # PAM's last error message


def send(**message):
    print(json.dumps(message), flush=True)


def log(text):
    print(text, file=sys.stderr, flush=True)


def user_for(identities):
    """The user to authenticate as: this one if polkit allows it, else the first user it names."""
    uids = [int(details["uid"]) for kind, details in identities if kind == "unix-user" and "uid" in details]
    return os.getuid() if os.getuid() in uids else uids[0] if uids else None


def user_name(uid):
    try:
        return pwd.getpwuid(uid).pw_name
    except KeyError:
        return str(uid)


def process_name(pid):
    """comm, which the kernel cuts to 15 characters, unless argv has the full name."""
    try:
        with open(f"/proc/{pid}/comm") as f:
            comm = f.read().strip()
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            argv = f.read().decode(errors="replace").split("\0")
    except OSError:
        return ""
    return next((os.path.basename(a) for a in argv[:2] if comm and os.path.basename(a).startswith(comm)), comm)


def requester(details):
    for key in ("polkit.subject-pid", "polkit.caller-pid"):
        pid = details.get(key, "")
        name = process_name(pid) if pid.isdigit() else ""
        if name:
            return f"{name} (pid {pid})"
    return ""


def vendor(action):
    try:
        actions = Polkit.Authority.get_sync(None).enumerate_actions_sync(None)
    except GLib.Error as e:
        log(f"could not list polkit actions: {e.message}")
        return ""
    return next((d.get_vendor_name() or "" for d in actions if d.get_action_id() == action), "")


def on_call(connection, sender, path, interface, method, params, invocation):
    if not session and sender != polkitd:
        invocation.return_dbus_error(FAILED, "Only polkit asks this agent")
        return
    if method == "CancelAuthentication":
        cookie, = params.unpack()
        invocation.return_value(None)
        r = requests.pop(cookie, None)
        if r:
            if r.pam:
                r.pam.cancel()
            r.invocation.return_dbus_error(CANCELLED, "Withdrawn")
            send(event="cancel", cookie=cookie)
        return
    action, message, _icon, details, cookie, identities = params.unpack()
    uid = user_for(identities)
    if uid is None:
        invocation.return_dbus_error(FAILED, "No user to authenticate as")
        return
    requests[cookie] = Request(invocation, uid)
    send(event="request", cookie=cookie, action=action, message=message, user=user_name(uid),
         requester=requester(details), vendor=vendor(action))


def start_pam(cookie, r):
    r.pam = PolkitAgent.Session.new(Polkit.UnixUser.new(r.uid), cookie)
    r.pam.connect("request", on_pam_request, cookie)
    r.pam.connect("show-error", on_pam_error, cookie)
    r.pam.connect("show-info", lambda pam, text, cookie: log(f"PAM: {text}"), cookie)
    r.pam.connect("completed", on_pam_completed, cookie)
    r.pam.initiate()


def on_pam_request(pam, text, echo, cookie):
    r = requests.get(cookie)
    if not r or r.pam is not pam:
        return
    if r.password is not None:
        pam.response(r.password)
        r.password = None
    else:
        r.waiting = True
        send(event="prompt", cookie=cookie, text=text, echo=echo)


def on_pam_error(pam, text, cookie):
    r = requests.get(cookie)
    if r and r.pam is pam:
        r.error = text


def on_pam_completed(pam, gained, cookie):
    r = requests.get(cookie)
    if not r or r.pam is not pam:
        return
    r.pam, r.password, r.waiting = None, None, False
    if gained:
        del requests[cookie]
        r.invocation.return_value(None)
        send(event="done", cookie=cookie)
    else:
        send(event="failed", cookie=cookie, error=r.error)
        r.error = ""


def answer(line):
    try:
        message = json.loads(line)
        cookie = message["cookie"]
        r = requests[cookie]
    except (ValueError, KeyError, TypeError):
        log(f"ignored answer: {line!r}")
        return
    if message.get("cancel"):
        del requests[cookie]
        if r.pam:
            r.pam.cancel()  # only mid-PAM, e.g. at a second prompt: that one may count as a failure
        r.invocation.return_dbus_error(CANCELLED, "Dismissed")
        return
    response = str(message.get("response", ""))
    if r.waiting:
        r.waiting = False
        r.pam.response(response)
    elif r.pam:
        log("ignored answer: PAM is still checking the last one")
    elif session:
        send(event="failed", cookie=cookie, error="No PAM with --session")
    else:
        r.password = response
        start_pam(cookie, r)


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


def drop_requests():
    for r in requests.values():
        if r.pam:
            r.pam.cancel()
        r.invocation.return_dbus_error(CANCELLED, "The agent went away")
    requests.clear()


def session_id():
    try:
        return Polkit.UnixSession.new_for_process_sync(os.getpid(), None).get_session_id()
    except GLib.Error:
        return os.environ.get("XDG_SESSION_ID", "")


def on_polkit_appeared(connection, name, owner):
    global polkitd
    polkitd = owner
    sid = session_id()
    if not sid:
        log("could not register with polkit: the shell runs outside a login session")
        return
    subject = ("unix-session", {"session-id": GLib.Variant("s", sid)})
    try:
        connection.call_sync("org.freedesktop.PolicyKit1", "/org/freedesktop/PolicyKit1/Authority",
                             "org.freedesktop.PolicyKit1.Authority", "RegisterAuthenticationAgent",
                             GLib.Variant("((sa{sv})ss)", (subject, os.environ.get("LANG", "C"), PATH)),
                             None, Gio.DBusCallFlags.NONE, -1, None)
    except GLib.Error as e:
        log(f"could not register with polkit: {e.message}")
        return
    send(event="ready")


def on_polkit_vanished(connection, name):
    global polkitd
    if polkitd is None:
        return  # not there at startup: nothing to lose
    polkitd = None
    drop_requests()
    send(event="lost")


def main():
    bus = Gio.bus_get_sync(Gio.BusType.SESSION if session else Gio.BusType.SYSTEM, None)
    bus.register_object(PATH, INTERFACE, on_call, None, None)
    GLib.io_add_watch(sys.stdin.fileno(), GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, on_stdin)
    if session:
        send(event="ready", name=bus.get_unique_name())
    else:
        Gio.bus_watch_name_on_connection(bus, "org.freedesktop.PolicyKit1", Gio.BusNameWatcherFlags.AUTO_START,
                                         on_polkit_appeared, on_polkit_vanished)
    loop.run()
    drop_requests()


if __name__ == "__main__":
    main()
