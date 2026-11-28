"""The real Clipboard service with stand-in cliphist, wl-paste and wl-copy (a temporary PATH, runtime and
cache folder): the text and picture watchers follow the two switches, `cliphist list` lines become
text and picture entries, pictures get thumbnails in the runtime folder (stale ones go), a picture is
copied back with its own type, and Clear wipes the history and the thumbnails. No owner state."""
import json, os, pathlib, shutil, subprocess, tempfile, time
ROOT = pathlib.Path(__file__).resolve().parents[1]
MOCKS = {
    "ShellSettings": "property bool clipboardHistory: true; property bool clipboardPictures: false",
    "Store": "property var saved: ({ recentEmoji: [] })",
}
SHELL = '''import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
ShellRoot {
    IpcHandler {
        target: "clipTest"
        function setSwitches(history: bool, pictures: bool): void { ShellSettings.clipboardHistory = history; ShellSettings.clipboardPictures = pictures; }
        function load(): void { Clipboard.loadHistory(); }
        function restore(id: string): void { Clipboard.restoreHistory(id); }
        function clear(): void { Clipboard.clearHistory(); }
        function state(): string { return JSON.stringify({ history: Clipboard.history, thumbDir: Clipboard.thumbDir }); }
    }
}
'''
# the fakes log each call to $FAKE_LOG; wl-paste stays running like a watcher
FAKES = {
    "wl-paste": 'echo "wl-paste $*" >> "$FAKE_LOG"; exec sleep 60\n',
    "wl-copy": 'echo "wl-copy${*:+ $*} <$(cat)>" >> "$FAKE_LOG"\n',
    "cliphist": '''echo "cliphist $*" >> "$FAKE_LOG"
case "$1" in
    list) [ -e "$FAKE_LOG.wiped" ] || printf '9\\t[[ binary data 48 KiB png 800x600 ]]\\n8\\thello there\\n7\\t[[ binary data 1.2 MiB jpeg 1920x1080 ]]\\n6\\t[[ not a picture ]]\\n' ;;
    decode) id=${2:-$(cat)}; printf 'BYTES-%s' "$id" ;;  # the id as an argument or on stdin, as cliphist
    wipe) : > "$FAKE_LOG.wiped" ;;
esac
''',
}
with tempfile.TemporaryDirectory(prefix="pistachio-clip-") as d:
    base = pathlib.Path(d); (base / "services").mkdir(); (base / "runtime").mkdir(mode=0o700); (base / "bin").mkdir()
    shutil.copy(ROOT / "src/services/Clipboard.qml", base / "services/Clipboard.qml")
    for name, body in MOCKS.items():
        (base / f"services/{name}.qml").write_text("pragma Singleton\nimport Quickshell\nimport QtQuick\nSingleton { " + body + " }\n")
    for name, body in FAKES.items():
        (base / "bin" / name).write_text("#!/bin/sh\n" + body); (base / "bin" / name).chmod(0o755)
    (base / "shell.qml").write_text(SHELL)
    fake_log = base / "calls"; fake_log.write_text("")
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=str(base / "runtime"),
               XDG_STATE_HOME=str(base / "state"), XDG_CACHE_HOME=str(base / "cache"),
               PATH=f"{base / 'bin'}:{os.environ['PATH']}", FAKE_LOG=str(fake_log))
    env.pop("WAYLAND_DISPLAY", None)
    log = (base / "log").open("w+")
    proc = subprocess.Popen(["qs", "-p", d], env=env, stdout=log, stderr=log)
    def ipc(*args):
        return subprocess.run(["qs", "-p", d, "ipc", "call", "clipTest", *args], env=env, capture_output=True, text=True, timeout=5).stdout.strip()
    state = lambda: json.loads(ipc("state"))
    calls = lambda: fake_log.read_text().splitlines()
    def check(cond, what):
        if not cond:
            log.seek(0); raise AssertionError(what + "\n" + "\n".join(calls()) + "\n" + log.read())
        print("ok:", what)
    def wait(cond, seconds=3):
        end = time.time() + seconds
        while time.time() < end and not cond(): time.sleep(0.05)
    try:
        for _ in range(80):
            if ipc("state").startswith("{"): break
            time.sleep(0.05)
        wait(lambda: any("--type text" in c for c in calls()))
        check([c for c in calls() if c.startswith("wl-paste")] == ["wl-paste --type text --watch cliphist store"], "with pictures off only the text watcher runs")
        ipc("setSwitches", "true", "true")
        wait(lambda: any("--type image" in c for c in calls()))
        check("wl-paste --type image --watch cliphist store" in calls(), "Keep pictures adds the image watcher")

        thumbs = pathlib.Path(state()["thumbDir"])
        check(str(thumbs).startswith(str(base / "runtime")), "thumbnails live in the runtime folder")
        thumbs.mkdir(parents=True, exist_ok=True); (thumbs / "3.png").write_text("stale")
        ipc("load")
        wait(lambda: any(e.get("thumb") for e in state()["history"]))
        h = {e["id"]: e for e in state()["history"]}
        check(list(h) == ["9", "8", "7", "6"], "every entry is listed, newest first")
        check(h["8"] == {"id": "8", "text": "hello there"}, "a text entry stays as it was")
        check(h["6"]["text"] == "[[ not a picture ]]" and not h["6"].get("picture"), "text that only looks odd is still text")
        p = h["9"]
        check(p.get("picture") and p["format"] == "png" and p["width"] == 800 and p["height"] == 600 and p["size"] == "48 KiB", "a picture entry carries its format, size and bytes")
        check(p["text"] == "Picture 800 × 600", "a picture is named by its size, so `;picture` finds it")
        check(h["7"]["format"] == "jpeg" and h["7"]["size"] == "1.2 MiB", "a JPEG with a fractional size parses")
        wait(lambda: (thumbs / "9.png").exists() and (thumbs / "7.jpeg").exists())
        check((thumbs / "9.png").read_text() == "BYTES-9" and p["thumb"] == str(thumbs / "9.png"), "the picture's thumbnail is decoded into the runtime folder")
        check(not (thumbs / "3.png").exists(), "a thumbnail of an entry no longer in the history is removed")
        before = len([c for c in calls() if c.startswith("cliphist decode")])
        ipc("load"); wait(lambda: len([c for c in calls() if c == "cliphist list"]) >= 2); time.sleep(0.4)
        check(len([c for c in calls() if c.startswith("cliphist decode")]) == before, "thumbnails already there are not decoded again")

        ipc("restore", "9"); wait(lambda: any(c.startswith("wl-copy") for c in calls()))
        check("wl-copy --type image/png <BYTES-9>" in calls(), "a picture is copied back as image/png")
        ipc("restore", "8"); wait(lambda: len([c for c in calls() if c.startswith("wl-copy")]) >= 2)
        check("wl-copy <BYTES-8>" in calls(), "text is copied back as before")

        ipc("clear"); wait(lambda: not thumbs.exists())
        check("cliphist wipe" in calls() and not thumbs.exists(), "Clear wipes the history and the thumbnails")

        ipc("setSwitches", "false", "true"); time.sleep(0.3)
        n = len(calls()); ipc("load"); time.sleep(0.3)
        check(not any(c == "cliphist list" for c in calls()[n:]), "with history off nothing is read")
    finally:
        proc.terminate(); proc.wait(timeout=5)
    log.seek(0); out = log.read()
    assert "ERROR" not in out, out
