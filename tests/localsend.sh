#!/bin/bash
# Self-check of the LocalSend helper (src/services/localsend.py): two copies, on ports 53318 and 53319
# with their own certificates and folders, find each other by multicast and send to each other: files
# and a folder accepted, a request declined, a text message, a request the sender cancels, and sending
# to a device that doesn't receive. Touches nothing outside a temporary folder; can run while the shell
# runs (the shell's own helper may show up as a third device, which the checks ignore).
set -euo pipefail
exec python3 -I - "$(cd "$(dirname "$0")/.." && pwd)/src/services/localsend.py" <<'PYEND'
import json, os, queue, subprocess, sys, tempfile, threading, time

HELPER = sys.argv[1]
tmp = tempfile.mkdtemp()


class Peer:
    def __init__(self, name, port):
        self.name, self.folder, self.events = name, os.path.join(tmp, name + "-in"), queue.Queue()
        os.makedirs(self.folder)
        self.p = subprocess.Popen(["python3", "-I", HELPER, "--port", str(port), "--data", os.path.join(tmp, name + "-data")],
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
