"""The real DevTools service (Experimental → Dev features) with a stand-in LauncherTools and a stand-in
notify-send: the commands it hands to Background jobs, the repo found through a linked config folder,
the toast at the end of tests and the rebuild (and none for Shell errors, a cancelled run or someone
else's job), and a click on the toast opening Background jobs. Runs nothing from the repo; no owner state."""
import json, os, pathlib, shutil, subprocess, tempfile, time
ROOT = pathlib.Path(__file__).resolve().parents[1]
LAUNCHER_TOOLS = """pragma Singleton
import Quickshell
import QtQuick
Singleton { property var jobs: []; property var ran: []; property int shown: 0
    function run(command) { ran = ran.concat([command]); }
    function showJobs() { shown++; } }
"""
SHELL = '''import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
ShellRoot {
    IpcHandler {
        target: "devTest"
        function command(kind: string): string { return DevTools.command(kind); }
        function run(kind: string): void { DevTools.run(kind); }
        function jobs(json: string): void { LauncherTools.jobs = JSON.parse(json).list; } // qs ipc unwraps a bare JSON array argument
        function state(): string { return JSON.stringify({ ran: LauncherTools.ran, shown: LauncherTools.shown, watching: Object.keys(DevTools.watching).length }); }
    }
}
'''
with tempfile.TemporaryDirectory(prefix="pistachio-dev-") as d:
    tmp = pathlib.Path(d)
    # the config lives in repo/src and is reached through a link, like ~/.config/quickshell/pistachio
    base = tmp / "repo/src"; (base / "services").mkdir(parents=True); (tmp / "runtime").mkdir(mode=0o700)
    (tmp / "link").symlink_to(base)
    shutil.copy(ROOT / "src/services/DevTools.qml", base / "services/DevTools.qml")
    (base / "services/LauncherTools.qml").write_text(LAUNCHER_TOOLS)
    (base / "shell.qml").write_text(SHELL)
    bin_ = tmp / "bin"; bin_.mkdir()
    toasts = tmp / "toasts"
    (bin_ / "notify-send").write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$DEV_TOASTS"\n[ -n "$DEV_CLICK" ] && echo default\nexit 0\n')
    (bin_ / "notify-send").chmod(0o755)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=str(tmp / "runtime"), XDG_STATE_HOME=str(tmp / "state"),
               XDG_CACHE_HOME=str(tmp / "cache"), PATH=f"{bin_}:{os.environ['PATH']}", DEV_TOASTS=str(toasts), DEV_CLICK="1")
    env.pop("WAYLAND_DISPLAY", None)
    log = (tmp / "log").open("w+")
    config = str(tmp / "link")
    proc = subprocess.Popen(["qs", "-p", config], env=env, stdout=log, stderr=log)
    def ipc(*args):
        return subprocess.run(["qs", "-p", config, "ipc", "call", "devTest", *args], env=env, capture_output=True, text=True, timeout=5).stdout.strip()
    state = lambda: json.loads(ipc("state"))
    read_toasts = lambda: toasts.read_text().splitlines() if toasts.exists() else []
    def check(cond, what):
        if not cond:
            log.seek(0); raise AssertionError(what + "\n" + log.read())
        print("ok:", what)
    def settle(predicate):
        for _ in range(60):
            if predicate(): return True
            time.sleep(0.05)
        return predicate()
    try:
        for _ in range(100):
            if ipc("state").startswith("{"): break
            time.sleep(0.05)
        tests = ipc("command", "tests")
        check(tests.endswith("&& sh tests/run.sh") and ipc("command", "native").endswith("sh tests/run.sh --native"), "tests and native run tests/run.sh")
        where = subprocess.run(["sh", "-c", tests.replace("sh tests/run.sh", "pwd")], capture_output=True, text=True).stdout.strip()
        check(where == str((tmp / "repo").resolve()), f"the repo is the folder above src/, through the link ({where})")
        check(ipc("command", "errors") == '"$HOME/.local/bin/psc" log --errors', "Shell errors is psc log --errors")
        rebuild = ipc("command", "rebuild")
        check("cargo build --release -p psc" in rebuild and rebuild.index("rm -f") < rebuild.index("install -m 755"), "Rebuild psc builds, removes the old file, then installs")
        check(ipc("command", "nonsense") == "", "unknown kinds give no command")

        ipc("run", "tests")
        check(state() == {"ran": [tests], "shown": 1, "watching": 1}, "Dev tests starts one job and opens Background jobs")
        now = int(time.time() * 1000)
        ipc("jobs", json.dumps({"list": [{"id": "a", "command": tests, "started": now, "state": "running", "code": None}]}))
        time.sleep(0.2)
        check(read_toasts() == [], "no toast while it runs")
        ipc("jobs", json.dumps({"list": [{"id": "a", "command": tests, "started": now, "state": "failed", "code": 3}]}))
        check(settle(lambda: len(read_toasts()) == 1), "a toast when it ends")
        check("Dev tests: 3 suites failed" in read_toasts()[0] and "--action=default=Open" in read_toasts()[0], "failed suites counted from the exit status")
        check(settle(lambda: state()["shown"] == 2) and state()["watching"] == 0, "clicking the toast opens Background jobs; the run is no longer watched")
        ipc("jobs", json.dumps({"list": [{"id": "a", "command": tests, "started": now, "state": "failed", "code": 3}]}))
        time.sleep(0.2)
        check(len(read_toasts()) == 1, "an ended job gives one toast only")

        ipc("run", "tests")
        later = int(time.time() * 1000)
        ipc("jobs", json.dumps({"list": [{"id": "a", "command": tests, "started": now - 60000, "state": "finished", "code": 0},
                                {"id": "b", "command": tests, "started": later, "state": "finished", "code": 0}]}))
        check(settle(lambda: len(read_toasts()) == 2) and "Dev tests passed" in read_toasts()[1], "passed; an old run of the same command isn't mistaken for it")

        ipc("run", "rebuild")
        ipc("jobs", json.dumps({"list": [{"id": "c", "command": rebuild, "started": int(time.time() * 1000), "state": "cancelled", "code": None}]}))
        time.sleep(0.3)
        check(len(read_toasts()) == 2 and state()["watching"] == 0, "a cancelled run gives no toast")
        ipc("run", "rebuild")
        ipc("jobs", json.dumps({"list": [{"id": "d", "command": rebuild, "started": int(time.time() * 1000), "state": "finished", "code": 0}]}))
        check(settle(lambda: len(read_toasts()) == 3) and "psc rebuilt" in read_toasts()[2], "rebuild gets its own toast")

        ipc("run", "errors")
        ipc("jobs", json.dumps({"list": [{"id": "e", "command": ipc("command", "errors"), "started": int(time.time() * 1000), "state": "finished", "code": 0}]}))
        time.sleep(0.3)
        check(len(read_toasts()) == 3 and state()["watching"] == 0, "Shell errors opens the job without a toast")
        ipc("jobs", json.dumps({"list": [{"id": "f", "command": "make", "started": int(time.time() * 1000), "state": "failed", "code": 2}]}))
        time.sleep(0.3)
        check(len(read_toasts()) == 3, "someone else's job gives no toast")
        log.seek(0)
        errors = [l for l in log.read().splitlines() if "ERROR" in l or "ReferenceError" in l or "TypeError" in l]
        check(not errors, "no QML errors: " + "; ".join(errors))
    finally:
        proc.terminate()
        try: proc.wait(timeout=5)
        except subprocess.TimeoutExpired: proc.kill()
print("PASS dev features: commands, repo through the link, toasts and their click")
