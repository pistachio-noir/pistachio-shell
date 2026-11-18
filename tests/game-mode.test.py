"""The real GameMode service with stand-in Compositor and ShellSettings: when game mode turns on and
off, its 2 s off-delay, the switch, and the extra window-class parser. No Hyprland, no owner state."""
import json, os, pathlib, shutil, subprocess, tempfile, time
ROOT = pathlib.Path(__file__).resolve().parents[1]
MOCKS = {
    "Compositor": "property var focusedWindow: null; property var calls: []; function gameLayout(on) { calls = calls.concat([on]); }",
    "ShellSettings": "property bool gameMode: true; property var gameClasses: []",
}
SHELL = '''import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
ShellRoot {
    IpcHandler {
        target: "gameTest"
        function focus(appId: string, fullscreen: bool): void { Compositor.focusedWindow = appId ? { appId: appId, fullscreen: fullscreen } : null; }
        function setSwitch(on: bool): void { ShellSettings.gameMode = on; }
        function setClasses(json: string): void { ShellSettings.gameClasses = JSON.parse(json); }
        function state(): string { return JSON.stringify({ active: GameMode.active, calls: Compositor.calls }); }
        function parse(text: string): string { return JSON.stringify(GameMode.parseClasses(text)); }
    }
}
'''
with tempfile.TemporaryDirectory(prefix="pistachio-game-") as d:
    base = pathlib.Path(d); (base / "services").mkdir(); (base / "runtime").mkdir(mode=0o700)
    shutil.copy(ROOT / "src/services/GameMode.qml", base / "services/GameMode.qml")
    for name, body in MOCKS.items():
        (base / f"services/{name}.qml").write_text("pragma Singleton\nimport Quickshell\nimport QtQuick\nSingleton { " + body + " }\n")
    (base / "shell.qml").write_text(SHELL)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=str(base / "runtime"),
               XDG_STATE_HOME=str(base / "state"), XDG_CACHE_HOME=str(base / "cache"))
    env.pop("WAYLAND_DISPLAY", None)
    log = (base / "log").open("w+")
    proc = subprocess.Popen(["qs", "-p", d], env=env, stdout=log, stderr=log)
    def ipc(*args):
        return subprocess.run(["qs", "-p", d, "ipc", "call", "gameTest", *args], env=env, capture_output=True, text=True, timeout=5).stdout.strip()
    state = lambda: json.loads(ipc("state"))
    def check(cond, what):
        if not cond:
            log.seek(0); raise AssertionError(what + "\n" + log.read())
        print("ok:", what)
    try:
        for _ in range(80):
            if ipc("state").startswith("{"): break
            time.sleep(0.05)
        ipc("focus", "steam_app_570", "true"); time.sleep(0.1)
        check(state() == {"active": True, "calls": [True]}, "a fullscreen Steam game turns game mode on")
        ipc("focus", "firefox", "true"); time.sleep(1.0); ipc("focus", "steam_app_570", "true"); time.sleep(0.1)
        check(state() == {"active": True, "calls": [True]}, "a 1 s alt-tab does not turn it off")
        ipc("focus", "firefox", "true"); time.sleep(2.5)
        check(state() == {"active": False, "calls": [True, False]}, "off 2 s after the game leaves the front")
        ipc("focus", "firefox", "true"); time.sleep(0.1)
        check(not state()["active"], "a fullscreen non-game window is not a game")
        ipc("focus", "steam_app_570", "false"); time.sleep(0.1)
        check(not state()["active"], "a game that is not fullscreen does not count")
        ipc("setClasses", '["minecraft"]'); ipc("focus", "Minecraft", "true"); time.sleep(0.1)
        check(state()["active"], "an extra class matches case-insensitively")
        ipc("setSwitch", "false"); time.sleep(0.1)
        check(not state()["active"], "turning the switch off ends game mode at once")
        ipc("setSwitch", "true"); ipc("focus", "org.vinegarhq.Sober", "true"); time.sleep(0.1)
        check(state()["active"], "Sober counts as a game")
        ipc("focus", "firefox", "true"); time.sleep(0.3); ipc("setSwitch", "false"); time.sleep(0.1)
        check(not state()["active"], "switching off during the 2 s delay ends game mode at once")
        ipc("setSwitch", "true")
        p = lambda t: json.loads(ipc("parse", t))
        check(p(" Minecraft , foo.bar ,minecraft") == {"list": ["minecraft", "foo.bar"], "error": ""}, "classes are trimmed, lowercased and deduplicated")
        check(p("") == {"list": [], "error": ""}, "an empty list clears")
        check(p("bad class!")["error"] != "", "a class with spaces or symbols is refused")
        check(p(",".join(f"c{i}" for i in range(21)))["error"] != "", "more than 20 classes are refused")
        check(p("a" * 101)["error"] != "", "a class over 100 characters is refused")
    finally:
        proc.terminate(); proc.wait(timeout=5)
    log.seek(0); out = log.read()
    assert "ERROR" not in out, out
