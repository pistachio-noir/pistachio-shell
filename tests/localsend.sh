#!/bin/bash
# Self-check of the LocalSend helper (src/services/localsend.py): two copies, on ports 53318 and 53319
# with their own certificates and folders, find each other by multicast and send to each other: files
# and a folder accepted, a request declined, a text message, a request the sender cancels, and sending
# to a device that doesn't receive. Touches nothing outside a temporary folder; can run while the shell
# runs (the shell's own helper may show up as a third device, which the checks ignore).
# HELPER_A and HELPER_B: the command for each copy (default: the one the shell runs), so two builds
# can be tested against each other.
set -euo pipefail
exec python3 -I - <<'PYEND'
import json, os, queue, shlex, subprocess, sys, tempfile, threading, time

DEFAULT = os.path.expanduser("~/.local/bin/pistachio-localsend")
HELPERS = {"test-a": os.environ.get("HELPER_A", DEFAULT), "test-b": os.environ.get("HELPER_B", DEFAULT)}
tmp = tempfile.mkdtemp()


class Peer:
    def __init__(self, name, port):
        self.name, self.folder, self.events = name, os.path.join(tmp, name + "-in"), queue.Queue()
        os.makedirs(self.folder)
        self.p = subprocess.Popen(shlex.split(HELPERS[name]) + ["--port", str(port), "--data", os.path.join(tmp, name + "-data")],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=sys.stderr, text=True)
        threading.Thread(target=self.read, daemon=True).start()
        self.fingerprint = self.wait("ready")["fingerprint"]
        self.cmd(cmd="config", alias=name, folder=self.folder, acceptKnown=False, known=[])

    def read(self):
        for line in self.p.stdout:
            self.events.put(json.loads(line))

    def cmd(self, **m):
        self.p.stdin.write(json.dumps(m) + "\n")
        self.p.stdin.flush()

    def wait(self, event, test=lambda m: True, seconds=10):
        end = time.time() + seconds
        while time.time() < end:
            try:
                m = self.events.get(timeout=max(0.05, end - time.time()))
            except queue.Empty:
                break
            if m["event"] == event and test(m):
                return m
        sys.exit(f"FAIL: {self.name} never said {event}")


def ok(label):
    print("ok:", label)


a, b = Peer("test-a", 53318), Peer("test-b", 53319)
for peer in (a, b):
    peer.cmd(cmd="receive", on=True)
    assert peer.wait("receive")["on"], peer.name
ok("both receive")

a.cmd(cmd="scan", legacy=False)
a.wait("device", lambda m: m["alias"] == "test-b" and m["port"] == 53319)
ok("a finds b by multicast")

src = os.path.join(tmp, "out")
os.makedirs(os.path.join(src, "album", "sub"))
blob = os.urandom(3 * 1024 * 1024 + 17)
open(os.path.join(src, "blob.bin"), "wb").write(blob)
open(os.path.join(src, "album", "sub", "note.txt"), "w").write("pistachio")

a.cmd(cmd="inspect", paths=[os.path.join(src, "blob.bin"), os.path.join(src, "album")])
items = a.wait("items")["items"]
assert [i["name"] for i in items] == ["blob.bin", "album"] and items[1]["dir"] and items[1]["count"] == 1, items
ok("inspect sizes files and folders")

a.cmd(cmd="send", device=b.fingerprint, paths=[os.path.join(src, "blob.bin"), os.path.join(src, "album")])
a.wait("send", lambda m: m["state"] == "waiting")
r = b.wait("request")
assert r["from"]["alias"] == "test-a" and len(r["files"]) == 2 and r["total"] == len(blob) + 9, r
ok("b is asked, with both files")
b.cmd(cmd="answer", session=r["session"], accept=True)
a.wait("send", lambda m: m["state"] == "done")
got = b.wait("received")
assert open(os.path.join(b.folder, "blob.bin"), "rb").read() == blob
assert open(os.path.join(b.folder, "album", "sub", "note.txt")).read() == "pistachio"
assert len(got["paths"]) == 2, got
ok("accepted: the file and the folder arrive intact")

a.cmd(cmd="send", device=b.fingerprint, paths=[os.path.join(src, "blob.bin")])
r = b.wait("request")
b.cmd(cmd="answer", session=r["session"], accept=False)
a.wait("send", lambda m: m["state"] == "declined")
assert not os.path.exists(os.path.join(b.folder, "blob (2).bin"))
ok("declined: a hears it, nothing saved")

b.cmd(cmd="scan", legacy=False)
b.wait("device", lambda m: m["alias"] == "test-a")
b.cmd(cmd="send", device=a.fingerprint, text="hello from b")
msg = a.wait("message")
assert msg["text"] == "hello from b" and msg["from"]["alias"] == "test-b", msg
b.wait("send", lambda m: m["state"] == "done")
ok("text message: shown, not saved")

a.cmd(cmd="send", device=b.fingerprint, paths=[os.path.join(src, "blob.bin")])
b.wait("request")
a.cmd(cmd="cancelSend")
a.wait("send", lambda m: m["state"] == "cancelled")
b.wait("requestGone")
ok("cancelled while asking: b's question goes")

# a device that doesn't play fair, straight at b's server
import http.client, ssl, urllib.parse
loose = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
loose.check_hostname, loose.verify_mode = False, ssl.CERT_NONE
API = "/api/localsend/v2"


def raw():
    return http.client.HTTPSConnection("127.0.0.1", 53319, timeout=10, context=loose)


def post(path, body=None, **query):
    c = raw()
    c.request("POST", API + path + ("?" + urllib.parse.urlencode(query) if query else ""), body=json.dumps(body) if body is not None else b"",
              headers={"Content-Type": "application/json"})
    r = c.getresponse()
    data = r.read()
    c.close()
    return r.status, data


def offer(*names):
    info = {"alias": "stranger", "version": "2.1", "deviceModel": "Test", "deviceType": "desktop", "fingerprint": "F" * 64, "port": 53320, "protocol": "https"}
    files = {f"id{i}": {"id": f"id{i}", "fileName": name, "size": 1000, "fileType": "application/octet-stream"} for i, name in enumerate(names)}
    return {"info": info, "files": files}


answers = queue.Queue()
threading.Thread(target=lambda: answers.put(post("/prepare-upload", offer("../../escape.bin", "second.bin"))), daemon=True).start()
r = b.wait("request", lambda m: m["from"]["alias"] == "stranger")
assert [f["name"] for f in r["files"]] == ["../../escape.bin", "second.bin"], r
assert post("/prepare-upload", offer("other.bin"))[0] == 409
ok("a second sender is told b is busy")
b.cmd(cmd="answer", session=r["session"], accept=True)
status, data = answers.get(timeout=10)
tokens = json.loads(data)["files"]
assert status == 200 and set(tokens) == {"id0", "id1"}, (status, data)

c = raw()
c.request("POST", API + "/upload?" + urllib.parse.urlencode({"sessionId": r["session"], "fileId": "id0", "token": "wrong"}), body=b"x" * 1000)
assert c.getresponse().status == 403
c.close()
assert post("/upload", sessionId="wrong", fileId="id0", token=tokens["id0"])[0] == 403
ok("a wrong token or session is refused")

c = raw()
c.request("POST", API + "/upload?" + urllib.parse.urlencode({"sessionId": r["session"], "fileId": "id0", "token": tokens["id0"]}), body=b"e" * 1000)
assert c.getresponse().status == 200
c.close()
assert open(os.path.join(b.folder, "escape.bin"), "rb").read() == b"e" * 1000
assert not os.path.exists(os.path.join(tmp, "escape.bin")) and not os.path.exists(os.path.join(os.path.dirname(tmp), "escape.bin"))
ok("a name with ../ lands inside the folder")
assert post("/upload", sessionId=r["session"], fileId="id0", token=tokens["id0"])[0] == 403
ok("a file can't be sent twice")

c = raw()
c.putrequest("POST", API + "/upload?" + urllib.parse.urlencode({"sessionId": r["session"], "fileId": "id1", "token": tokens["id1"]}))
c.putheader("Content-Length", "1000")
c.endheaders()
c.send(b"h" * 100)
time.sleep(0.3)
c.sock.shutdown(2)
c.close()
lost = b.wait("receiveFailed")
assert lost["reason"] == "lost" and lost["from"]["alias"] == "stranger", lost
time.sleep(0.2)
left = [n for _, _, names in os.walk(b.folder) for n in names if n.endswith(".part") or n.startswith("second")]
assert not left, left
ok("a sender that vanishes mid-file: told as lost, no half file kept")

threading.Thread(target=lambda: answers.put(post("/prepare-upload", offer("again.bin"))), daemon=True).start()
r = b.wait("request", lambda m: m["from"]["alias"] == "stranger")
b.cmd(cmd="answer", session=r["session"], accept=False)
assert answers.get(timeout=10)[0] == 403
ok("and b takes requests again afterwards")

assert post("/prepare-upload", {"info": "nonsense", "files": 3})[0] == 400
assert post("/prepare-upload", offer())[0] == 400
assert post("/nowhere")[0] == 404
c = raw()
c.request("GET", API + "/info")
assert json.loads(c.getresponse().read())["alias"] == "test-b"
c.close()
ok("garbled requests are answered 400, unknown ones 404, info is given")

import socket
idle = []
for _ in range(100):  # connections that never say anything
    try:
        idle.append(socket.create_connection(("127.0.0.1", 53319), timeout=2))
    except OSError:
        break
time.sleep(0.3)
assert b.p.poll() is None
for s in idle:
    s.close()
time.sleep(0.5)
c = raw()
c.request("GET", API + "/info")
assert json.loads(c.getresponse().read())["alias"] == "test-b"
c.close()
ok("a hundred idle connections: b lives, and serves again once they're gone")

b.cmd(cmd="receive", on=False)
assert not b.wait("receive")["on"]
a.cmd(cmd="send", device=b.fingerprint, paths=[os.path.join(src, "blob.bin")])
a.wait("send", lambda m: m["state"] == "failed")
ok("b off: sending fails")

for peer in (a, b):
    peer.p.stdin.close()
    peer.p.wait(5)
ok("both exit when stdin closes")
subprocess.run(["rm", "-rf", tmp])
print("all LocalSend checks passed")
PYEND
