"""Recording service + actual overlay. Fake recorder by default, with all files under /tmp."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
if not os.environ.get("WAYLAND_DISPLAY"):
    print("skip: recording helper integration requires a live Wayland desktop")
    raise SystemExit

FAKE = '''#!/usr/bin/python3
import json,os,pathlib,signal,sys,time
with open(os.environ['PISTACHIO_RECORD_TEST_CALLS'],'a') as out: out.write(json.dumps(sys.argv[1:])+'\\n')
if pathlib.Path(os.environ['PISTACHIO_RECORD_TEST_FAIL']).exists():
    print('error: fixture recorder failure',file=sys.stderr);sys.exit(1)
signal.signal(signal.SIGINT,lambda *_:sys.exit(0))
while True: time.sleep(.05)
'''

def overlaps(a, b):
    return a["x"] < b["x"]+b["width"] and a["x"]+a["width"] > b["x"] and a["y"] < b["y"]+b["height"] and a["y"]+a["height"] > b["y"]

with tempfile.TemporaryDirectory(prefix="pistachio-recording-test-") as directory:
    base = Path(directory)
    for name in ("services", "bin", "videos", "pictures"):
        (base / name).mkdir()
    for name in ("popups", "components", "Theme.qml"):
        (base / name).symlink_to(ROOT / "src" / name)
    shutil.copy(ROOT / "src/services/Screenshots.qml", base / "services/Screenshots.qml")
    (base / "services/ShellSettings.qml").write_text('pragma Singleton\nimport Quickshell\nSingleton { property bool notificationSound: false }\n')
    for name, script in {
        "gpu-screen-recorder": FAKE,
        "notify-send": "#!/bin/sh\nexit 0\n",
        "xdg-user-dir": '#!/bin/sh\ncase "$1" in VIDEOS) printf "%s\\n" "$PISTACHIO_RECORD_TEST_VIDEOS";; PICTURES) printf "%s\\n" "$PISTACHIO_RECORD_TEST_PICTURES";; esac\n'
    }.items():
        (base / "bin" / name).write_text(script)
        (base / "bin" / name).chmod(0o755)
    shutil.copy(ROOT / "tests/recording-ui.qml", base / "shell.qml")
    calls_file, fail_file = base / "calls.jsonl", base / "fail"
    env = dict(os.environ, PATH=str(base/"bin")+":"+os.environ["PATH"], XDG_STATE_HOME=str(base/"state"), XDG_CACHE_HOME=str(base/"cache"),
               PISTACHIO_RECORD_TEST_CALLS=str(calls_file), PISTACHIO_RECORD_TEST_FAIL=str(fail_file),
               PISTACHIO_RECORD_TEST_VIDEOS=str(base/"videos"), PISTACHIO_RECORD_TEST_PICTURES=str(base/"pictures"))
    def call(method, *args):
        result = subprocess.run(["qs","-p",directory,"ipc","call","recordingTest",method,*map(str,args)],env=env,capture_output=True,text=True,timeout=8)
        assert result.returncode == 0, result.stdout + result.stderr
        return result.stdout.strip()
    def wait(predicate):
        deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            state=json.loads(call("state"))
            if predicate(state): return state
            time.sleep(.03)
        raise AssertionError(state)
    def calls(): return [json.loads(line) for line in calls_file.read_text().splitlines()] if calls_file.exists() else []
    with (base/"log").open("w+") as log:
        proc=subprocess.Popen(["qs","-p",directory],env=env,stdout=log,stderr=log)
        try:
            for _ in range(70):
                try:
                    if call("ready")=="true": break
                except AssertionError: pass
                time.sleep(.1)
            else: raise AssertionError("recording harness did not load")
            call("start",0)
            state=wait(lambda s:s["recording"] and s["visible"])
            assert {k:state["area"][k] for k in ("x","y","width","height")}=={"x":400,"y":300,"width":640,"height":362},state
            deadline=time.monotonic()+3
            while not calls() and time.monotonic()<deadline: time.sleep(.02)
            assert calls()[0][calls()[0].index("-region")+1]=="640x362+400+300",calls()
            before=len(calls());call("start",1)
            assert len(calls())==before and json.loads(call("state"))["area"]==state["area"],"second start must not change a running capture"
            time.sleep(1.1)
            state=json.loads(call("state"));assert state["time"]!="0:00",state
            if os.environ.get("PISTACHIO_RECORDING_TEST_IMAGE"):
                subprocess.run(["grim",os.environ["PISTACHIO_RECORDING_TEST_IMAGE"]],check=True)
            for which in range(6):
                if which:
                    call("start",which);state=wait(lambda s:s["recording"] and s["visible"])
                assert state["keyboard"],state
                for strip in state["frame"]: assert not overlaps(strip,state["area"]),state
                if which==5:
                    assert state["pill"] is None and not state["masked"],state
                else:
                    assert state["pill"] and not overlaps(state["pill"],state["area"]) and state["masked"],state
                    pill=state["pill"]
                    assert pill["x"]>=8 and pill["y"]>=8 and pill["x"]+pill["width"]<=state["width"]-8 and pill["y"]+pill["height"]<=state["height"]-8,state
                # Wait for the fixture CLI's signal handler before clicking Stop.
                time.sleep(.1)
                call("stop" if which==5 else "clickStop")
                wait(lambda s:not s["recording"] and not s["visible"])
            call("start",6);state=wait(lambda s:s["recording"])
            assert not state["visible"] and state["whole"],state
            time.sleep(.1);call("stop");wait(lambda s:not s["recording"])
            before=len(calls());call("start",7);time.sleep(.1)
            assert len(calls())==before and not json.loads(call("state"))["recording"],"invalid area must not start a recorder"
            fail_file.touch();call("start",0)
            deadline=time.monotonic()+3
            while len(calls())==before and time.monotonic()<deadline: time.sleep(.02)
            wait(lambda s:not s["recording"] and not s["visible"])
            output=(base/"log").read_text()
            assert "ERROR" not in output,output
            warnings=[line for line in output.splitlines() if "WARN scene:" in line and "fixture recorder failure" not in line]
            assert not warnings,warnings
            print("recording helper: exact encoder bounds, outside-only frame/pill, timer, Stop, screen edges, no-room fallback, whole-screen exclusion, invalid area and failure cleanup passed")
        except BaseException:
            print((base/"log").read_text());raise
        finally:
            proc.terminate();proc.wait(timeout=5)
