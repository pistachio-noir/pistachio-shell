"""The real Clocks service with a stand-in clocks.py: Stop and Snooze close the alarm popup whether
GNOME Clocks answers or fails, and Snooze queues the shell's own re-ring. No bus, no real alarms."""
import os, pathlib, shutil, subprocess, tempfile, time
ROOT = pathlib.Path(__file__).resolve().parents[1]
FAKE = '''import json, os, sys
cmd = sys.argv[1]
if cmd in ("stop", "snooze"):
    open(os.environ["CALLS"], "a").write(cmd + " " + sys.argv[2] + "\\n")
    sys.exit(int(os.environ.get("FAIL", "0")))
print("[]")
'''
SHELL = '''import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
ShellRoot {
    IpcHandler {
        target: "clocksTest"
        function ring(): void { Clocks.ringing = { kind: "alarm", label: "Test", time: "07:00", id: "a1" }; }
        function stop(): void { Clocks.stopRinging(); }
        function snooze(): void { Clocks.snooze(); }
        function state(): string { return JSON.stringify({ ringing: Clocks.ringing !== null, snoozed: Clocks.snoozed.length }); }
    }
}
'''
def check(fail):
    with tempfile.TemporaryDirectory(prefix="pistachio-clocks-") as d:
        base = pathlib.Path(d); (base / "services").mkdir(); (base / "runtime").mkdir(mode=0o700)
        # Clocks runs `$HOME/.local/bin/psc clocks …`: its copy here runs the stand-in, never the real psc
        service = (ROOT / "src/services/Clocks.qml").read_text()
        real = '[Quickshell.env("HOME") + "/.local/bin/psc", "clocks"'
        assert service.count(real) == 2, "Clocks' psc command changed: update this fixture"
        (base / "services/Clocks.qml").write_text(service.replace(real, '["python3", Quickshell.shellPath("services/clocks.py")'))
        (base / "services/clocks.py").write_text(FAKE)
        for name, body in {"Apps": "property var list: []", "ShellSettings": "function integration(id) { return true; }"}.items():
            (base / f"services/{name}.qml").write_text("pragma Singleton\nimport Quickshell\nimport QtQuick\nSingleton { " + body + " }\n")
        (base / "shell.qml").write_text(SHELL)
        calls = base / "calls"
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=str(base / "runtime"),
                   XDG_STATE_HOME=str(base / "state"), XDG_CACHE_HOME=str(base / "cache"), CALLS=str(calls), FAIL="1" if fail else "0")
        env.pop("WAYLAND_DISPLAY", None)
        with (base / "log").open("w+") as log:
            proc = subprocess.Popen(["qs", "-p", d], env=env, stdout=log, stderr=log)
            ipc = lambda f: subprocess.run(["qs", "-p", d, "ipc", "call", "clocksTest", f], env=env, capture_output=True, text=True, timeout=5).stdout.strip()
            def wait(want):
                for _ in range(60):
                    if ipc("state") == want: return
                    time.sleep(0.05)
                raise AssertionError(f"fail={fail}: wanted {want}, got {ipc('state')}\n" + log.read())
            try:
                for _ in range(60):
                    if ipc("state").startswith("{"): break
                    time.sleep(0.05)
                ipc("ring"); wait('{"ringing":true,"snoozed":0}')
                ipc("stop"); wait('{"ringing":false,"snoozed":0}')
                ipc("ring"); ipc("snooze"); wait('{"ringing":false,"snoozed":1}')
                assert calls.read_text().split("\n")[:2] == ["stop a1", "snooze a1"], calls.read_text()
            finally:
                proc.terminate(); proc.wait(timeout=5)
            log.seek(0); out = log.read()
            assert "ERROR" not in out, out
    print(f"ok: Stop and Snooze close the popup and reach GNOME Clocks ({'GNOME fails' if fail else 'GNOME answers'})")
check(False)
check(True)
