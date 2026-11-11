"""Actual screenshot picker and screen crops; fixture services keep every action local."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
if not os.environ.get("WAYLAND_DISPLAY"):
    print("skip: screenshot picker integration requires a live Wayland desktop")
    raise SystemExit

MOCKS = {
    "ShellSettings": 'property string lensProvider: "codex"; property bool shadows: true; property bool frosted: false;',
    "Lens": '''id: root; property bool open; property string path; property var area; property var still;
        function begin(file,rect,capture) {path=file;area=rect;still=capture;open=true;}
        function close() {open=false;still=null;}''',
    "Compositor": '''property var workspaces: [{id:1,active:true}];
        property var windows: [{workspace:1,bounds:Qt.rect(100,250,400,180),recency:1,title:"Fixture window"}];''',
    "Screenshots": '''id: root; property bool hasPicker:true; property bool hasRecorder:true; property bool recording;
        property int serial; property string lastPath; property int picked; property int recorded; property bool recordWhole;
        function prepare() {} function shutter() {}
        function nextPath() {serial++;return OUTPUT+"/image-"+serial+".png";}
        function nextTextPath() {return OUTPUT+"/text.png";}
        function nextLensPath() {return OUTPUT+"/lens.png";}
        function saved(path) {lastPath=path;} function readText(path) {lastPath=path;}
        function pickColour() {picked++;}
        function record(area,whole,monitor) {recorded++;recordWhole=whole;}
        function stopRecording() {}'''
}

with tempfile.TemporaryDirectory(prefix="pistachio-screenshot-test-") as directory:
    base = Path(directory)
    (base / "services").mkdir()
    (base / "output").mkdir()
    for name in ("popups", "components", "Theme.qml"):
        (base / name).symlink_to(ROOT / "src" / name)
    for name, body in MOCKS.items():
        body = body.replace("OUTPUT", json.dumps(str(base / "output")))
        (base / f"services/{name}.qml").write_text("pragma Singleton\nimport Quickshell\nimport QtQuick\nSingleton {\n" + body + "\n}\n")
    shutil.copy(ROOT / "tests/screenshots-ui.qml", base / "shell.qml")
    env = dict(os.environ, XDG_STATE_HOME=str(base / "state"), XDG_CACHE_HOME=str(base / "cache"))
    def call(method):
        result = subprocess.run(["qs", "-p", directory, "ipc", "call", "screenshotTest", method], env=env, capture_output=True, text=True, timeout=35)
        assert result.returncode == 0 and not result.stdout.startswith("FAIL:"), result.stdout + result.stderr
        value = result.stdout.strip()
        assert method in ("ready", "pickerMode") or value.startswith(("{", "[")), repr(value)
        return value
    with (base / "log").open("w+") as log:
        proc = subprocess.Popen(["qs", "-p", directory], env=env, stdout=log, stderr=log)
        try:
            for _ in range(70):
                try:
                    if call("ready") == "true": break
                except AssertionError:
                    pass
                time.sleep(.1)
            else:
                raise AssertionError("picker harness did not load")
            ipc = subprocess.run(["qs", "-p", directory, "ipc", "call", "screenshot", "menu"], env=env, capture_output=True, text=True)
            assert ipc.returncode == 0, ipc.stdout + ipc.stderr
            for _ in range(100):
                if call("pickerMode") == "menu": break
                time.sleep(.02)
            else:
                raise AssertionError("screenshot menu IPC did not receive a screen still")
            preview = json.loads(call("preview"))
            if os.environ.get("PISTACHIO_SCREENSHOT_TEST_IMAGE"):
                subprocess.run(["grim", os.environ["PISTACHIO_SCREENSHOT_TEST_IMAGE"]], check=True)
            print("screenshot toolbar:", preview)
            for capture in json.loads(call("run")):
                with Image.open(capture["path"]) as image:
                    assert image.size == (capture["width"], capture["height"]), capture
                print(f'screenshot {capture["kind"]}: {capture["width"]} × {capture["height"]} crop passed')
            output = (base / "log").read_text()
            assert "ERROR" not in output and "WARN scene:" not in output, output
            print("screenshots: shortcuts, pointer selection, tooltip, optional tools, outside click, fade and capture routing passed")
        except BaseException:
            print((base / "log").read_text())
            raise
        finally:
            proc.terminate()
            proc.wait(timeout=5)
