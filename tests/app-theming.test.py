"""The real AppTheming service with a stand-in Store and a stand-in for `psc theme` (a script that records what it is
asked and answers states from a file: start-up check, quiet setup, conflicts, keep/use, switching off."""
import json, os, pathlib, shutil, subprocess, tempfile, time
ROOT = pathlib.Path(__file__).resolve().parents[1]
FAKE = r'''import json, os, sys
open(os.environ["CALLS"], "a").write(" ".join(sys.argv[1:]) + "\n")
states = json.load(open(os.environ["STATES"]))
if sys.argv[1] == "use" or sys.argv[1] == "setup" and states[sys.argv[2]] != "own": states[sys.argv[2]] = "following"
if sys.argv[1] == "undo": states[sys.argv[2]] = "available"
json.dump(states, open(os.environ["STATES"], "w"))
print(json.dumps({"apps": [{"id": k, "name": k.title(), "state": v, "detail": ""} for k, v in states.items()]}))
'''
SHELL = '''import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
ShellRoot {
    IpcHandler {
        target: "themingTest"
        function state(): string { return JSON.stringify({ enabled: AppTheming.enabled, apps: AppTheming.apps.map(a => a.id + ":" + a.state), conflict: AppTheming.conflict ? AppTheming.conflict.id : "", kept: AppTheming.kept }); }
        function keep(id: string): void { AppTheming.keep(id); }
        function use(id: string): void { AppTheming.use(id); }
        function off(): void { AppTheming.setEnabled(false); }
        function storeOff(): void { Store.saved.themingIntegration = false; }
        function on(): void { AppTheming.setEnabled(true); }
    }
}
'''
def run(states, enabled=True):
    d = tempfile.mkdtemp(prefix="pistachio-theming-")
    base = pathlib.Path(d); (base / "services").mkdir(); (base / "runtime").mkdir(mode=0o700)
    # the service runs `psc theme …`; its copy here runs the stand-in instead, never the real psc (which
    # would act on the owner's own Kitty and Neovim configs)
    service = (ROOT / "src/services/AppTheming.qml").read_text()
    real = '[Quickshell.env("HOME") + "/.local/bin/psc", "theme"]'
    assert service.count(real) == 1, "AppTheming's psc command changed: update this fixture"
    (base / "services/AppTheming.qml").write_text(service.replace(real, '["python3", Quickshell.shellPath("services/shared-theme.py")]'))
    (base / "services/shared-theme.py").write_text(FAKE)
    (base / "services/Store.qml").write_text("pragma Singleton\nimport Quickshell\nimport QtQuick\nSingleton { property bool ready: true; property QtObject saved: QtObject { property bool themingIntegration: %s; property var themingKeep: [] } }\n" % ("true" if enabled else "false"))
    (base / "shell.qml").write_text(SHELL)
    (base / "states.json").write_text(json.dumps(states))
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=str(base / "runtime"), XDG_STATE_HOME=str(base / "state"),
               XDG_CACHE_HOME=str(base / "cache"), CALLS=str(base / "calls"), STATES=str(base / "states.json"))
    env.pop("WAYLAND_DISPLAY", None)
    log = (base / "log").open("w+")
    proc = subprocess.Popen(["qs", "-p", d], env=env, stdout=log, stderr=log)
    ipc = lambda *a: subprocess.run(["qs", "-p", d, "ipc", "call", "themingTest", *a], env=env, capture_output=True, text=True, timeout=5).stdout.strip()
    calls = lambda: (base / "calls").read_text().split("\n")[:-1] if (base / "calls").exists() else []
    def wait(pred, what):
        for _ in range(80):
            out = ipc("state")
            if out.startswith("{") and pred(json.loads(out)): return json.loads(out)
            time.sleep(0.05)
        log.seek(0); raise AssertionError(what + " | " + ipc("state") + " | " + str(calls()) + "\n" + log.read())
    return proc, ipc, calls, wait, log

def ok(label): print("ok:", label)

proc, ipc, calls, wait, log = run({"kitty": "available", "neovim": "own"})
try:
    s = wait(lambda s: "kitty:following" in s["apps"], "an available app is set up quietly")
    assert calls()[:2] == ["status", "setup kitty"] and s["conflict"] == "neovim", (calls(), s)
    ok("start: status, then quiet setup of an available app; an own theme becomes the conflict")
    ipc("keep", "neovim"); s = wait(lambda s: s["conflict"] == "", "keep clears the conflict")
    assert "setup neovim" not in calls() and s["kept"] == ["neovim"], (calls(), s)
    ok("Keep mine: no setup, remembered")
    ipc("use", "neovim"); wait(lambda s: "neovim:following" in s["apps"], "use sets it up")
    assert calls()[-1] == "use neovim" and wait(lambda s: True, "")["kept"] == []
    ok("Use Pistachio: set up, no longer kept")
    ipc("off"); s = wait(lambda s: not s["enabled"] and all(a.endswith("available") for a in s["apps"]), "off undoes")
    assert sorted(c for c in calls() if c.startswith("undo")) == ["undo kitty", "undo neovim"] and s["conflict"] == ""
    ok("off: every wired app undone, no conflict shown")
    n = len(calls()); ipc("on"); wait(lambda s: s["enabled"] and "kitty:following" in s["apps"], "on again sets up")
    assert calls()[n] == "status", calls()
    ok("on again: status, then setup")
finally:
    proc.terminate(); proc.wait(timeout=5)
log.seek(0); assert "ERROR" not in log.read()

proc, ipc, calls, wait, log = run({"kitty": "available", "neovim": "available"})
try:
    wait(lambda s: s["apps"] == ["kitty:following", "neovim:following"], "both set up")
    ipc("storeOff")
    wait(lambda s: not s["enabled"] and s["apps"] == ["kitty:available", "neovim:available"], "a reset/import turning it off undoes too")
    ok("switch turned off by a page reset or import: apps undone as well")
finally:
    proc.terminate(); proc.wait(timeout=5)

proc, ipc, calls, wait, log = run({"kitty": "available", "neovim": "unsupported"}, enabled=False)
try:
    s = wait(lambda s: len(s["apps"]) == 2, "disabled start still reads status")
    time.sleep(0.5)
    assert calls() == ["status"] and s["conflict"] == "", calls()
    ok("disabled at start: only status, nothing set up")
finally:
    proc.terminate(); proc.wait(timeout=5)
