#!/usr/bin/env python3
"""LocalSend for the shell; services/LocalSend.qml runs it while the LocalSend app is installed.

The shell is a LocalSend device of its own (protocol v2: https://github.com/localsend/protocol): it
finds devices by multicast on 224.0.0.167:53317 (asking every address on the network when nobody
answers), receives over HTTPS on port 53317 with its own certificate, and sends to the devices it found.
The LocalSend app can't run beside it, since both need that port. Python's standard library only; the
certificate is made once with openssl. JSON lines on stdout, commands on stdin:

  out  {"event": "ready", "fingerprint": "…", "host": "arch"}
  out  {"event": "receive", "on": true, "busy": false}       busy: another program has the port
  out  {"event": "scan", "running": true}                    a scan began ("clear" before it) or ended
  out  {"event": "clear"}
  out  {"event": "device", "fingerprint", "alias", "model", "type", "ip", "port", "protocol"}
  out  {"event": "items", "items": [{"path", "name", "size", "count", "dir", "mime"}]}
  out  {"event": "paste", "paths": […]} or {"event": "paste", "text": "…"} or {"event": "paste"}
  out  {"event": "send", "state", "device", "done", "total", "speed", "files": [{"name", "size", "state"}]}
         state: waiting (for them to accept), sending, done, declined, busy, pin, failed, cancelled
  out  {"event": "request", "session", "from": {device}, "files": [{"name", "size", "mime"}], "total", "auto"}
  out  {"event": "message", "from": {device}, "text": "…"}
  out  {"event": "requestGone", "session"}                   the sender gave up before an answer
  out  {"event": "receiving", "session", "done", "total", "speed", "file", "index", "count"}
  out  {"event": "received", "session", "from", "folder", "paths": […]}
  out  {"event": "receiveFailed", "session", "from", "reason"}   reason: cancelled (by them), stopped (by you), lost
  in   {"cmd": "config", "alias", "folder", "acceptKnown", "known": [fingerprints]}
  in   {"cmd": "receive", "on": true}
  in   {"cmd": "scan", "legacy": true}
  in   {"cmd": "inspect", "paths": […]}
  in   {"cmd": "paste"}
  in   {"cmd": "send", "device": fingerprint, "paths": […], "text": "…"}
  in   {"cmd": "cancelSend"}
  in   {"cmd": "answer", "session", "accept": true}
  in   {"cmd": "cancelReceive"}

It exits when stdin closes, so it never outlives the shell. --port and --data let tests/localsend.sh run
two of them side by side.
"""

import argparse
import hashlib
import http.client
import http.server
import json
import mimetypes
import os
import secrets
import select
import socket
import ssl
import struct
import subprocess
import sys
import threading
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor

GROUP = "224.0.0.167"
MULTICAST_PORT = 53317
API = "/api/localsend/v2"
CHUNK = 256 * 1024

args = None
port = MULTICAST_PORT
fingerprint = ""
client_tls = None
server_tls = None
udp = None
lock = threading.RLock()
out_lock = threading.Lock()
config = {"alias": socket.gethostname(), "folder": os.path.expanduser("~/Downloads"), "acceptKnown": False, "known": set()}
devices = {}  # fingerprint -> device
server = None
session = None  # the transfer being received, or the request waiting for an answer
job = None  # the transfer being sent


def emit(**message):
    with out_lock:
        try:
            sys.stdout.write(json.dumps(message) + "\n")
            sys.stdout.flush()
        except (BrokenPipeError, ValueError):
            pass  # the shell is gone; stdin's end stops the helper next


def info():
    return {"alias": config["alias"], "version": "2.1", "deviceModel": "Linux", "deviceType": "desktop",
            "fingerprint": fingerprint, "port": port, "protocol": "https", "download": False}


def certificate(folder):
    os.makedirs(folder, mode=0o700, exist_ok=True)
    cert, key = os.path.join(folder, "cert.pem"), os.path.join(folder, "key.pem")
    if not (os.path.exists(cert) and os.path.exists(key)):
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert,
                        "-days", "3650", "-subj", "/CN=LocalSend User"], check=True, capture_output=True)
        os.chmod(key, 0o600)
    with open(cert) as f:
        der = ssl.PEM_cert_to_DER_cert(f.read())
    return cert, key, hashlib.sha256(der).hexdigest().upper()


def device(data, ip):
    return {"fingerprint": str(data.get("fingerprint") or ""), "alias": str(data.get("alias") or "Unknown device"),
            "model": str(data.get("deviceModel") or ""), "type": str(data.get("deviceType") or "desktop"), "ip": ip,
            "port": int(data.get("port") or MULTICAST_PORT), "protocol": "http" if data.get("protocol") == "http" else "https"}


def seen(data, ip):
    d = device(data, ip)
    if not d["fingerprint"] or d["fingerprint"] == fingerprint:
        return
    with lock:
        if devices.get(d["fingerprint"]) == d:
            return
        devices[d["fingerprint"]] = d
    emit(event="device", **d)


# discovery

def open_multicast():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if hasattr(socket, "SO_REUSEPORT"):
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    s.bind(("", MULTICAST_PORT))
    s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, struct.pack("4s4s", socket.inet_aton(GROUP), socket.inet_aton("0.0.0.0")))
    return s


def announce(flag):
    if udp:
        try:
            udp.sendto(json.dumps(dict(info(), announce=flag)).encode(), (GROUP, MULTICAST_PORT))
        except OSError as e:
            print("can't announce:", e, file=sys.stderr)


def listen():
    while True:
        try:
            data, (ip, _) = udp.recvfrom(65535)
            message = json.loads(data)
        except (OSError, ValueError):
            continue
        if not isinstance(message, dict) or message.get("fingerprint") == fingerprint:
            continue
        seen(message, ip)
        if message.get("announce") and server:  # answer only while others may send here
            threading.Thread(target=answer, args=(device(message, ip),), daemon=True).start()


def answer(d):
    try:
        call(d, "/register", info(), timeout=3)
    except (OSError, http.client.HTTPException):
        announce(False)


def own_address():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))  # sends nothing; picks the outgoing interface
        return s.getsockname()[0]
    except OSError:
        return None
    finally:
        s.close()


def probe(ip):
    try:
        status, body = call({"ip": ip, "port": MULTICAST_PORT, "protocol": "https"}, "/register", info(), timeout=1.5)
        if status == 200:
            seen(json.loads(body), ip)
    except (OSError, ValueError, http.client.HTTPException):
        pass


def scan(legacy):
    with lock:
        devices.clear()
    emit(event="clear")
    emit(event="scan", running=True)
    for wait in (0, 1, 2):
        time.sleep(wait)
        announce(True)
    if legacy and not devices:  # nobody answered the multicast: ask every address on the network
        own = own_address()
        if own:
            prefix = own.rsplit(".", 1)[0]
            with ThreadPoolExecutor(64) as pool:
                pool.map(probe, [f"{prefix}.{i}" for i in range(1, 255) if f"{prefix}.{i}" != own])
    emit(event="scan", running=False)


# sending

def connect(d, timeout):
    if d["protocol"] == "http":
        return http.client.HTTPConnection(d["ip"], d["port"], timeout=timeout)
    return http.client.HTTPSConnection(d["ip"], d["port"], timeout=timeout, context=client_tls)


def call(d, path, body=None, query=None, timeout=5):
    c = connect(d, timeout)
    try:
        c.request("POST", API + path + ("?" + urllib.parse.urlencode(query) if query else ""),
                  body=json.dumps(body).encode() if body is not None else b"", headers={"Content-Type": "application/json"})
        r = c.getresponse()
        return r.status, r.read()
    finally:
        c.close()


def collect(paths, text):
    files = []
    for path in paths:
        path = os.path.abspath(path)
        if os.path.isdir(path):
            top = os.path.dirname(path)
            for folder, _, names in os.walk(path):
                for name in sorted(names):
                    full = os.path.join(folder, name)
                    if os.path.isfile(full):
                        files.append({"path": full, "name": os.path.relpath(full, top)})
        elif os.path.isfile(path):
            files.append({"path": path, "name": os.path.basename(path)})
    for f in files:
        f["size"] = os.path.getsize(f["path"])
        f["mime"] = mimetypes.guess_type(f["name"])[0] or "application/octet-stream"
    if text:
        data = text.encode()
        files.append({"data": data, "name": "message.txt", "size": len(data), "mime": "text/plain", "preview": text if not files else None})
    for i, f in enumerate(files):
        f["id"] = f"{i}-{secrets.token_hex(4)}"
        f["state"] = "waiting"
    return files


class Job:
    def __init__(self, d, files):
        self.device, self.files, self.state = d, files, "waiting"
        self.done, self.speed, self.cancelled = 0, 0.0, False
        self.total = sum(f["size"] for f in files)
        self.conn, self.session, self.reported, self.mark = None, None, 0.0, (time.monotonic(), 0)

    def report(self, force=False):
        now = time.monotonic()
        if not force and now - self.reported < 0.12:
            return
        then, before = self.mark
        if now - then >= 0.5:
            self.speed = (self.done - before) / (now - then) if not self.speed else 0.6 * self.speed + 0.4 * (self.done - before) / (now - then)
            self.mark = (now, self.done)
        self.reported = now
        emit(event="send", state=self.state, device=self.device, done=self.done, total=self.total, speed=round(self.speed),
             files=[{"name": f["name"], "size": f["size"], "mime": f["mime"], "state": f["state"]} for f in self.files])

    def finish(self, state):
        self.state = state
        self.report(True)


def run_send(j):
    j.report(True)
    files = {f["id"]: {"id": f["id"], "fileName": f["name"], "size": f["size"], "fileType": f["mime"], "sha256": None,
                       "preview": f.get("preview"), "metadata": None} for f in j.files}
    try:
        c = j.conn = connect(j.device, None)  # waits as long as they take to answer
        c.request("POST", API + "/prepare-upload", body=json.dumps({"info": info(), "files": files}).encode(),
                  headers={"Content-Type": "application/json"})
        r = c.getresponse()
        body = r.read()
        c.close()
    except (OSError, http.client.HTTPException):
        return j.finish("cancelled" if j.cancelled else "failed")
    if j.cancelled:
        return j.finish("cancelled")
    if r.status == 204:
        for f in j.files:
            f["state"] = "sent"
        j.done = j.total
        return j.finish("done")
    if r.status != 200:
        return j.finish({401: "pin", 403: "declined", 409: "busy", 429: "busy"}.get(r.status, "failed"))
    try:
        answer = json.loads(body)
        j.session, tokens = answer["sessionId"], answer["files"]
    except (ValueError, KeyError, TypeError):
        return j.finish("failed")
    j.state = "sending"
    for f in j.files:
        if f["id"] not in tokens:
            f["state"] = "skipped"  # they picked some of the files
            j.total -= f["size"]
    try:
        for f in j.files:
            if f["state"] == "skipped":
                continue
            if j.cancelled:
                break
            f["state"] = "sending"
            j.report(True)
            c = j.conn = connect(j.device, 60)
            c.putrequest("POST", API + "/upload?" + urllib.parse.urlencode({"sessionId": j.session, "fileId": f["id"], "token": tokens[f["id"]]}))
            c.putheader("Content-Length", str(f["size"]))
            c.putheader("Content-Type", "application/octet-stream")
            c.endheaders()
            if "data" in f:
                c.send(f["data"])
                j.done += f["size"]
            else:
                with open(f["path"], "rb") as source:
                    while not j.cancelled and (chunk := source.read(CHUNK)):
                        c.send(chunk)
                        j.done += len(chunk)
                        j.report()
            if j.cancelled:
                break
            r = c.getresponse()
            r.read()
            c.close()
            if r.status != 200:
                raise OSError(f"upload answered {r.status}")
            f["state"] = "sent"
    except (OSError, http.client.HTTPException) as e:
        if not j.cancelled:
            print("send failed:", e, file=sys.stderr)
            return j.finish("failed")
    if j.cancelled:
        try:
            call(j.device, "/cancel", query={"sessionId": j.session}, timeout=3)
        except (OSError, http.client.HTTPException):
            pass
        return j.finish("cancelled")
    j.finish("done")


def start_send(fp, paths, text):
    global job
    with lock:
        d = devices.get(fp)
        if not d or (job and job.state in ("waiting", "sending")):
            return
        files = collect(paths, text)
        if not files:
            return
        job = Job(d, files)
    threading.Thread(target=run_send, args=(job,), daemon=True).start()


def cancel_send():
    j = job
    if not j or j.state not in ("waiting", "sending"):
        return
    j.cancelled = True
    try:
        if j.conn and j.conn.sock:
            j.conn.sock.shutdown(socket.SHUT_RDWR)  # wakes the thread waiting for an answer
    except OSError:
        pass


# receiving

class Session:
    def __init__(self, sender, files):
        self.id, self.sender, self.files = secrets.token_hex(8), sender, files
        self.answered, self.accepted, self.cancelled, self.gone = threading.Event(), False, False, False
        self.total, self.done, self.speed, self.current = sum(f["size"] for f in files.values()), 0, 0.0, ""
        self.saved, self.reported, self.mark = [], 0.0, (time.monotonic(), 0)

    def report(self, force=False):
        now = time.monotonic()
        if not force and now - self.reported < 0.12:
            return
        then, before = self.mark
        if now - then >= 0.5:
            self.speed = (self.done - before) / (now - then) if not self.speed else 0.6 * self.speed + 0.4 * (self.done - before) / (now - then)
            self.mark = (now, self.done)
        self.reported = now
        finished = sum(1 for f in self.files.values() if f.get("finished"))
        emit(event="receiving", session=self.id, done=self.done, total=self.total, speed=round(self.speed), file=self.current,
             index=min(finished + 1, len(self.files)), count=len(self.files))


def end(s, event, **extra):
    global session
    with lock:
        if session is not s:
            return
        session = None
    emit(event=event, session=s.id, **extra)


def safe_path(folder, name):
    parts = [p for p in name.replace("\\", "/").split("/") if p not in ("", ".", "..")] or ["file"]
    path = os.path.join(folder, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    root, ext = os.path.splitext(path)
    n = 2
    while os.path.exists(path) or os.path.exists(path + ".part"):
        path = f"{root} ({n}){ext}"
        n += 1
    return path


def peer_gone(sock):
    try:
        if not select.select([sock], [], [], 0)[0]:
            return False
        sock.settimeout(0.2)
        return sock.recv(1) == b""
    except (ssl.SSLWantReadError, socket.timeout):
        return False
    except OSError:
        return True
    finally:
        try:
            sock.settimeout(60)
        except OSError:
            pass


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def setup(self):
        self.request.settimeout(60)
        self.request.do_handshake()
        super().setup()

    def log_message(self, *_):
        pass

    def reply(self, status, body=None):
        data = json.dumps(body).encode() if body is not None else b""
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def json_body(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length > 4 * 1024 * 1024:
            raise ValueError("too big")
        return json.loads(self.rfile.read(length) or b"{}")

    def do_GET(self):
        if urllib.parse.urlsplit(self.path).path == API + "/info":
            return self.reply(200, info())
        self.reply(404)

    def do_POST(self):
        url = urllib.parse.urlsplit(self.path)
        query = dict(urllib.parse.parse_qsl(url.query))
        try:
            if url.path == API + "/register":
                seen(self.json_body(), self.client_address[0])
                return self.reply(200, info())
            if url.path == API + "/prepare-upload":
                return self.prepare(self.json_body())
            if url.path == API + "/upload":
                return self.upload(query)
            if url.path == API + "/cancel":
                return self.cancel(query)
        except (ValueError, KeyError, TypeError, AttributeError):
            return self.reply(400)
        self.reply(404)

    def prepare(self, body):
        global session
        sender = device(body["info"], self.client_address[0])
        files = {}
        for key, f in body["files"].items():
            files[str(f.get("id") or key)] = {"name": str(f["fileName"]), "size": int(f.get("size") or 0),
                                             "mime": str(f.get("fileType") or ""), "preview": f.get("preview")}
        if not files:
            return self.reply(400)
        only = next(iter(files.values()))
        if len(files) == 1 and only["mime"].startswith("text/") and isinstance(only["preview"], str):
            emit(event="message", **{"from": sender, "text": only["preview"]})
            return self.reply(204)
        with lock:
            if session:
                return self.reply(409)
            s = session = Session(sender, files)
        auto = config["acceptKnown"] and sender["fingerprint"] in config["known"]
        emit(event="request", session=s.id, files=[{"name": f["name"], "size": f["size"], "mime": f["mime"]} for f in files.values()],
             total=s.total, auto=auto, **{"from": sender})
        if auto:
            s.accepted = True
        else:
            deadline = time.monotonic() + 600
            while not s.answered.wait(0.5):
                if s.gone or peer_gone(self.request) or time.monotonic() > deadline:
                    end(s, "requestGone")
                    self.close_connection = True
                    return
        if not s.accepted or s.cancelled:
            end(s, "requestGone") if s.gone else None
            with lock:
                if session is s:
                    session = None
            return self.reply(403)
        for f in files.values():
            f["token"] = secrets.token_hex(16)
        s.report(True)
        self.reply(200, {"sessionId": s.id, "files": {key: f["token"] for key, f in files.items()}})

    def upload(self, query):
        s = session
        f = s.files.get(query.get("fileId", "")) if s else None
        if not s or not s.accepted or s.id != query.get("sessionId") or self.client_address[0] != s.sender["ip"] \
                or not f or f.get("token") != query.get("token") or f.get("started"):
            return self.reply(403)
        f["started"] = True
        length = int(self.headers.get("Content-Length") or f["size"])
        path = safe_path(config["folder"], f["name"])
        part = path + ".part"
        s.current = os.path.basename(path)
        try:
            with open(part, "wb") as target:
                left = length
                while left > 0:
                    if s.cancelled:
                        raise InterruptedError()
                    chunk = self.rfile.read(min(CHUNK, left))
                    if not chunk:
                        raise ConnectionError("the sender went away")
                    target.write(chunk)
                    left -= len(chunk)
                    with lock:
                        s.done += len(chunk)
                    s.report()
            os.replace(part, path)
        except (OSError, InterruptedError) as e:
            try:
                os.remove(part)
            except OSError:
                pass
            if not s.cancelled:
                end(s, "receiveFailed", reason="lost", **{"from": s.sender})
            self.close_connection = True
            return self.reply(409) if isinstance(e, InterruptedError) else None
        f["finished"] = True
        s.saved.append(path)
        self.reply(200)
        if all(x.get("finished") for x in s.files.values() if x.get("token")):
            s.report(True)
            end(s, "received", folder=config["folder"], paths=s.saved, **{"from": s.sender})

    def cancel(self, query):
        s = session
        if s and self.client_address[0] == s.sender["ip"] and query.get("sessionId", s.id) == s.id:
            s.gone = s.cancelled = True
            if s.accepted:
                end(s, "receiveFailed", reason="cancelled", **{"from": s.sender})
            s.answered.set()
        self.reply(200)


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def handle_error(self, request, client_address):
        pass  # a failed handshake or a dropped connection; nothing to tell


def set_receive(on):
    global server
    with lock:
        if on and not server:
            try:
                s = Server(("", port), Handler)
            except OSError:
                return emit(event="receive", on=False, busy=True)
            s.socket = server_tls.wrap_socket(s.socket, server_side=True, do_handshake_on_connect=False)
            server = s
            threading.Thread(target=s.serve_forever, daemon=True).start()
            emit(event="receive", on=True, busy=False)
            announce(True)  # devices with LocalSend open see this one at once
        elif not on and server:
            s, server = server, None
            s.shutdown()
            s.server_close()
            emit(event="receive", on=False, busy=False)


def cancel_receive():
    s = session
    if not s:
        return
    s.cancelled = True
    s.answered.set()
    if s.accepted:
        end(s, "receiveFailed", reason="stopped", **{"from": s.sender})


def answer_request(sid, accept):
    s = session
    if s and s.id == sid and not s.answered.is_set():
        s.accepted = accept
        s.answered.set()


# the shell's other requests

def inspect(paths):
    items = []
    for path in paths:
        path = os.path.abspath(path)
        if os.path.isdir(path):
            size = count = 0
            for folder, _, names in os.walk(path):
                for name in names:
                    try:
                        size += os.path.getsize(os.path.join(folder, name))
                        count += 1
                    except OSError:
                        pass
            items.append({"path": path, "name": os.path.basename(path), "size": size, "count": count, "dir": True, "mime": "inode/directory"})
        elif os.path.isfile(path):
            items.append({"path": path, "name": os.path.basename(path), "size": os.path.getsize(path), "count": 1, "dir": False,
                          "mime": mimetypes.guess_type(path)[0] or "application/octet-stream"})
    emit(event="items", items=items)


def paste():
    def read(kind):
        r = subprocess.run(["wl-paste", "--no-newline", "--type", kind], capture_output=True, timeout=3)
        return r.stdout.decode(errors="replace") if r.returncode == 0 else ""
    try:
        types = subprocess.run(["wl-paste", "--list-types"], capture_output=True, timeout=3).stdout.decode().split()
        for kind in ("text/uri-list", "x-special/gnome-copied-files"):
            if kind in types:
                paths = [urllib.parse.unquote(urllib.parse.urlsplit(line.strip()).path) for line in read(kind).splitlines()
                         if line.strip().startswith("file://")]
                if paths:
                    return emit(event="paste", paths=paths)
        if any(t.startswith("text/plain") or t in ("UTF8_STRING", "STRING", "TEXT") for t in types):
            text = read("text/plain;charset=utf-8") or read("text/plain")
            if text.strip():
                return emit(event="paste", text=text)
    except (OSError, subprocess.SubprocessError):
        pass
    emit(event="paste")


def handle(m):
    cmd = m.get("cmd")
    if cmd == "config":
        config["alias"] = str(m.get("alias") or socket.gethostname())
        config["folder"] = os.path.expanduser(str(m.get("folder") or "~/Downloads"))
        config["acceptKnown"] = bool(m.get("acceptKnown"))
        config["known"] = set(m.get("known") or [])
    elif cmd == "receive":
        set_receive(bool(m.get("on")))
    elif cmd == "scan":
        threading.Thread(target=scan, args=(m.get("legacy", True),), daemon=True).start()
    elif cmd == "inspect":
        threading.Thread(target=inspect, args=(list(m.get("paths") or []),), daemon=True).start()
    elif cmd == "paste":
        threading.Thread(target=paste, daemon=True).start()
    elif cmd == "send":
        start_send(m.get("device"), list(m.get("paths") or []), m.get("text") or "")
    elif cmd == "cancelSend":
        cancel_send()
    elif cmd == "answer":
        answer_request(m.get("session"), bool(m.get("accept")))
    elif cmd == "cancelReceive":
        cancel_receive()


def main():
    global args, port, fingerprint, client_tls, server_tls, udp
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=MULTICAST_PORT)
    parser.add_argument("--data", default=os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "pistachio-shell", "localsend"))
    args = parser.parse_args()
    port = args.port
    cert, key, fingerprint = certificate(args.data)
    server_tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    server_tls.load_cert_chain(cert, key)
    client_tls = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    client_tls.check_hostname = False
    client_tls.verify_mode = ssl.CERT_NONE  # LocalSend devices use self-made certificates
    client_tls.load_cert_chain(cert, key)
    try:
        udp = open_multicast()
        threading.Thread(target=listen, daemon=True).start()
    except OSError as e:
        print("no multicast, devices are found by asking every address:", e, file=sys.stderr)
    emit(event="ready", fingerprint=fingerprint, host=socket.gethostname())
    for line in sys.stdin:
        try:
            handle(json.loads(line))
        except (ValueError, AttributeError) as e:
            print("bad command:", line.strip(), e, file=sys.stderr)
    set_receive(False)
    os._exit(0)


if __name__ == "__main__":
    main()
