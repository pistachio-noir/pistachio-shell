"""First-run setup's backend: FirstRun (when it opens, the check, finishing), the controller that wires
the real view to the services, and Restore my settings through Preferences, against stand-in services,
a stand-in psc (doctor, prefs, theme) and a stand-in busctl. Offscreen; private HOME and XDG paths."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
MOCKS = {
    "Compositor": 'property var windows: []; property var placed: null; function placeSettingsWindow(w,x,y) { placed=[x,y]; }',
    "Session": 'property bool locked',
    "SettingsHub": 'property string opened: ""; function openPage(p, c) { opened = p; }',
    "LauncherTools": 'property var actions: []',
    "GameMode": 'property bool active',
    "Clipboard": 'property string copied; function copyText(v) { copied = v; }',
    "Screenshots": 'property string folder: Quickshell.env("HOME") + "/Pictures/Screenshots"',
    "Weather": 'property string city: "Warsaw"; property string placeName: city; function lookup(s, then) { if (s === "Nowhere") then(null, "No place called Nowhere."); else then({ name: s }, ""); } function setCity(s) { city = s; }',
    "LocalSend": 'property bool available: true; property bool wanted; property string name: "workstation"; function setReceive(v) { wanted = v; }',
    "Bluetooth": 'property bool present: true; property bool enabled: true; property var paired: []; function setEnabled(v) { enabled = v; } function name(d) { return d.name; } function status(d) { return ""; }',
    "Network": 'property bool connected: true; property bool hasLink: true; property int speed: 1000',
    "Brightness": 'property bool available: true; property real value: 0.7; function set(v) { value = v; }',
    "NightLight": 'property bool available: true; property bool enabled; property int temperature: 4000; function setEnabled(v) { enabled = v; } function setTemperature(v) { temperature = v; }',
    "Apps": 'property var terminalChoices: ["kitty", "foot"]; property string terminal: "kitty"; function terminalName(s) { return s; } function setTerminal(s) { terminal = s; }',
    "Wallpapers": 'property string current: ""; property string folder: Quickshell.env("HOME") + "/Pictures/Wallpapers"; property var images: [{ path: "/w/a.png", name: "a" }]; function set(p) { current = p; }',
    "Desktop": 'property bool enabled: true; function setEnabled(v) { enabled = v; }',
    "Audio": '''property var sinks: [{ id: 1, name: "Speakers" }, { id: 2, name: "Headphones" }]; property var sources: [{ id: 4, name: "Mic" }];
        property var sink: sinks[0]; property var source: sources[0]; property real volume: 0.6; property real micVolume: 0.4;
        function deviceName(n) { return n.name; } function isUnplugged(n) { return false; } function setSink(n) { sink = n; } function setSource(n) { source = n; }
        function setVolume(v) { volume = v; } function setMicVolume(v) { micVolume = v; }''',
}

DOCTOR = [
    {"id": "hyprctl", "title": "Hyprland", "kind": "required", "found": True, "package": "hyprland", "without": "nothing works"},
    {"id": "wl-copy", "title": "Wayland clipboard", "kind": "required", "found": True, "package": "wl-clipboard", "without": "copying"},
    {"id": "ddcutil", "title": "Monitor brightness", "kind": "optional", "found": False, "package": "ddcutil", "without": "the brightness slider is hidden"},
    {"id": "claude", "title": "Claude Code CLI", "kind": "optional", "found": False, "package": "claude-code", "without": "Lens"},
    {"id": "codex", "title": "Codex CLI", "kind": "optional", "found": False, "package": "openai-codex", "without": "Lens"},
]

PSC = r'''#!/usr/bin/env python3
import json, os, sys
log = os.environ["FIXTURE_LOG"]
with open(log, "a") as f: f.write(json.dumps(sys.argv[1:]) + "\n")
if sys.argv[1:3] == ["doctor", "--json"]:
    print(open(os.environ["FIXTURE_DOCTOR"]).read()); sys.exit(0)
if sys.argv[1:3] == ["prefs", "read"]:
    path = sys.argv[3]
    if not os.path.exists(path): print(json.dumps({"ok": False, "error": "no settings file yet: export first"})); sys.exit(0)
    print(json.dumps({"ok": True, "values": json.load(open(path)), "skipped": [{"key": "x.y", "reason": "unknown"}]})); sys.exit(0)
sys.exit(0)
'''
BUSCTL = '#!/bin/sh\nif [ "$FIXTURE_OWNER" = self ]; then echo "PID=$PPID"; echo "Comm=qs"; elif [ -n "$FIXTURE_OWNER" ]; then echo "PID=1"; echo "Comm=$FIXTURE_OWNER"; else exit 1; fi\n'

SHELL = r'''import qs
import qs.services
import qs.setup
import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    readonly property var background: [FirstRun]
    FloatingWindow {
        implicitWidth: 880; implicitHeight: 600; color: "transparent"
        FirstRunWizard { id: view; anchors.fill: parent; open: FirstRun.opened; reducedMotion: true }
        SetupController { id: controller; wizard: view }
    }
    IpcHandler {
        target: "fixture"
        function state(): string {
            return JSON.stringify({ ready: Store.ready, fresh: Store.fresh, opened: FirstRun.opened, done: Store.saved.setupDone,
                check: FirstRun.checkState, checks: FirstRun.checks, total: FirstRun.checkTotal, note: FirstRun.checkNote,
                lensAvailable: view.available.lensProvider, viewChecks: view.checks.length, settings: SettingsHub.opened,
                restore: view.restore, colours: ShellSettings.colourScheme, shadows: ShellSettings.shadows, frosted: ShellSettings.frosted,
                glassy: ShellSettings.glassy, sink: Audio.sink.id, volume: Audio.volume, lens: [ShellSettings.lensProvider, Store.saved.lensCodexModel],
                terminal: Apps.terminal, city: Weather.city, weather: view.details.weather, copied: Clipboard.copied, values: view.values });
        }
        function check(): void { view.checkRequested(); }
        function value(key: string, json: string): void { view.valueRequested(key, JSON.parse(json)); }
        function act(name: string, payload: string): void { view.actionRequested(name, payload); }
        function finish(destination: string): void { view.finished(destination); }
        function open(): void { FirstRun.open(); }
    }
}
'''


def run(case, state=None, owner="self", doctor=DOCTOR, export=None):
    with tempfile.TemporaryDirectory(prefix="pistachio-first-run-backend-") as folder:
        base = Path(folder)
        (base / "services").mkdir()
        shutil.copytree(ROOT / "src/setup", base / "setup")
        shutil.copytree(ROOT / "src/settings", base / "settings")
        shutil.copytree(ROOT / "src/components", base / "components")
        shutil.copy(ROOT / "src/Theme.qml", base / "Theme.qml")
        for name in ("Store", "ShellSettings", "Preferences", "FirstRun"):
            shutil.copy(ROOT / f"src/services/{name}.qml", base / f"services/{name}.qml")
        for name, body in MOCKS.items():
            (base / f"services/{name}.qml").write_text("pragma Singleton\nimport Quickshell\nimport QtQuick\nSingleton {\n" + body + "\n}\n")
        (base / "shell.qml").write_text(SHELL)
        bin_dir = base / "bin"
        bin_dir.mkdir()
        (bin_dir / "psc").write_text(PSC)
        (bin_dir / "busctl").write_text(BUSCTL)
        for tool in ("psc", "busctl"):
            (bin_dir / tool).chmod(0o755)
        rewritten = 0
        for qml in base.rglob("*.qml"):
            text = qml.read_text()
            if 'Quickshell.env("HOME") + "/.local/bin/psc"' in text:
                qml.write_text(text.replace('Quickshell.env("HOME") + "/.local/bin/psc"', json.dumps(str(bin_dir / "psc"))))
                rewritten += 1
        assert rewritten >= 3, f"FirstRun, Preferences and ShellSettings must run psc: rewrote {rewritten}"
        home = base / "home"
        for name in ("home", "runtime", "state", "cache", "config"):
            (base / name).mkdir(mode=0o700)
        (base / "doctor.json").write_text(json.dumps(doctor))
        if export is not None:
            target = base / "config/pistachio/pistachio-shell/settings.toml"
            target.parent.mkdir(parents=True)
            target.write_text(json.dumps(export))
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", HOME=str(home), XDG_RUNTIME_DIR=str(base / "runtime"),
                   XDG_STATE_HOME=str(base / "state"), XDG_CACHE_HOME=str(base / "cache"), XDG_CONFIG_HOME=str(base / "config"),
                   PATH=str(bin_dir) + ":" + os.environ["PATH"], FIXTURE_LOG=str(base / "psc.log"),
                   FIXTURE_DOCTOR=str(base / "doctor.json"), FIXTURE_OWNER=owner)
        for name in ("DISPLAY", "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "DBUS_SESSION_BUS_ADDRESS"):
            env.pop(name, None)
        log = (base / "log").open("w+")
        shell = subprocess.Popen(["qs", "-p", folder], env=env, stdout=log, stderr=log)

        def call(*args):
            return subprocess.run(["qs", "-p", folder, "ipc", "call", "fixture", *args], env=env, capture_output=True, text=True, timeout=15).stdout.strip()

        def get():
            text = call("state")
            return json.loads(text) if text.startswith("{") else None

        def wait(predicate, what, seconds=8):
            for _ in range(int(seconds / 0.05)):
                s = get()
                if s and predicate(s):
                    return s
                time.sleep(0.05)
            log.seek(0)
            raise AssertionError(f"{case}: timed out waiting for {what}: {get()}\n{log.read()}")

        def state_file():
            files = list((base / "state").rglob("state.json"))
            return json.loads(files[0].read_text()) if files else None

        try:
            first = wait(lambda s: s["ready"], "Store")
            if state is not None:
                # the first start made the state folder: seed it and start again
                call("finish", "shell") if first["opened"] else None
                time.sleep(0.5)
                files = list((base / "state").rglob("state.json"))
                assert files, f"{case}: no state file to seed"
                shell.terminate(); shell.wait(timeout=5)
                files[0].write_text(json.dumps(state))
                shell = subprocess.Popen(["qs", "-p", folder], env=env, stdout=log, stderr=log)
                first = wait(lambda s: s["ready"], "Store after seeding")
            return case(first, call, get, wait, state_file, base)
        finally:
            shell.terminate()
            shell.wait(timeout=5)
            log.seek(0)
            output = log.read()
            assert "ERROR" not in output and "WARN scene" not in output, output
            log.close()


def fresh_start(first, call, get, wait, state_file, base):
    assert first["fresh"] and first["opened"] and not first["done"], first
    call("check")
    s = wait(lambda s: s["check"] in ("clear", "attention"), "the check")
    titles = [c["title"] for c in s["checks"]]
    assert s["check"] == "clear" and s["total"] == len(DOCTOR) + 1, s
    assert titles[0] == "Notification service" and s["checks"][0]["status"] == "pass", s["checks"][0]
    missing = next(c for c in s["checks"] if c["title"] == "Monitor brightness")
    assert missing["status"] == "optional" and missing["package"] == "ddcutil" and "command" not in missing, "package names only: " + str(missing)
    assert "ddcutil" in s["note"] and "claude-code" in s["note"], s["note"]
    assert s["lensAvailable"] is False, "no Claude Code and no Codex: Lens has nothing to pick"
    # every choice goes through the services' setters
    for key, value in (("colourScheme", "noir"), ("shadows", False), ("frostStyle", "glassy"), ("outputDevice", 2), ("outputLevel", 0.25),
                       ("lensProvider", "codex"), ("lensModel", "gpt-6.1-sol"), ("terminal", "foot"), ("weatherLocation", "Gdańsk")):
        call("value", key, json.dumps(value))
    s = wait(lambda s: s["city"] == "Gdańsk", "the routed values")
    assert s["colours"] == "noir" and not s["shadows"] and s["frosted"] and s["glassy"], s
    assert s["sink"] == 2 and abs(s["volume"] - 0.25) < 1e-6 and s["lens"] == ["codex", "gpt-6.1-sol"] and s["terminal"] == "foot", s
    assert s["values"]["frostStyle"] == "glassy" and s["values"]["colourScheme"] == "noir", "the view reads back what the services hold"
    call("value", "weatherLocation", json.dumps("Nowhere"))
    s = wait(lambda s: "No place called Nowhere" in s["weather"], "the weather error")
    assert s["city"] == "Gdańsk", "a failed lookup keeps the city"
    call("act", "copyCommand", "ddcutil")
    assert wait(lambda s: s["copied"] == "ddcutil", "copy")["copied"] == "ddcutil"
    call("finish", "settings")
    s = wait(lambda s: not s["opened"], "finish")
    assert s["done"] and s["settings"] == "appearance", s
    time.sleep(0.6)
    saved = state_file()
    assert saved and saved.get("setupDone") is True and saved.get("colourScheme") == "noir", saved
    calls = [json.loads(l) for l in (base / "psc.log").read_text().splitlines()]
    assert ["doctor", "--json"] in calls and ["theme", "noir"] in calls, calls
    return "fresh start opens; check, routing, finish"


def conflict(first, call, get, wait, state_file, base):
    call("check")
    s = wait(lambda s: s["check"] in ("clear", "attention"), "the check")
    assert s["check"] == "attention", s
    row = s["checks"][0]
    assert row["status"] == "conflict" and row["title"] == "mako is running" and row["command"] == "pkill -x mako", row
    call("check")
    s = wait(lambda s: s["check"] == "attention" and s["viewChecks"] == len(DOCTOR) + 1, "a second check")
    assert len(s["checks"]) == len(DOCTOR) + 1, "check again starts the rows over"
    return "another notification daemon is a conflict with its command"


def required_missing(first, call, get, wait, state_file, base):
    call("check")
    s = wait(lambda s: s["check"] in ("clear", "attention"), "the check")
    row = next(c for c in s["checks"] if c["title"] == "Wayland clipboard")
    assert s["check"] == "attention" and row["status"] == "warning" and row["package"] == "wl-clipboard", s
    return "a missing required tool needs attention"


def set_up_before(first, call, get, wait, state_file, base):
    assert not first["fresh"] and not first["opened"], first
    s = wait(lambda s: s["done"], "the quiet mark")
    time.sleep(0.6)
    assert state_file().get("setupDone") is True and state_file().get("shadows") is False, "marked, and the old state kept"
    call("open")
    assert wait(lambda s: s["opened"], "psc setup")["opened"]
    call("finish", "skip")
    s = wait(lambda s: not s["opened"], "skip")
    assert s["done"] and s["settings"] == "", s
    return "existing state is marked done quietly; setup opens on request"


def done_before(first, call, get, wait, state_file, base):
    time.sleep(0.3)
    s = get()
    assert not s["opened"] and s["done"], s
    return "done stays closed"


def restore(first, call, get, wait, state_file, base):
    call("act", "restoreReview", "")
    s = wait(lambda s: s["restore"]["state"] == "reviewing", "the review")
    titles = [c["title"] for c in s["restore"]["changes"]]
    assert titles == ["Colours"] and s["restore"]["skipped"] == 1 and s["restore"]["path"].endswith("settings.toml"), s["restore"]
    assert s["colours"] == "pistachio", "nothing applies before Apply"
    call("act", "restoreApply", "")
    s = wait(lambda s: s["colours"] == "noir", "apply")
    assert s["restore"]["state"] == "idle", s["restore"]
    return "restore reviews, then applies"


def restore_missing(first, call, get, wait, state_file, base):
    call("act", "restoreReview", "")
    s = wait(lambda s: s["restore"]["state"] == "missing", "the missing file")
    assert "Choose the settings.toml" in s["restore"]["message"], s["restore"]
    return "restore says when there's no export"


results = [
    run(fresh_start),
    run(conflict, owner="mako"),
    run(required_missing, doctor=[dict(DOCTOR[1], found=False)] + DOCTOR[2:]),
    run(set_up_before, state={"shadows": False}),
    run(done_before, state={"setupDone": True}),
    run(restore, state={"setupDone": True}, export={"colourScheme": "noir", "shadows": True}),
    run(restore_missing, state={"setupDone": True}),
]
print("PASS " + "; ".join(results))
