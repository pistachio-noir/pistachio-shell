"""Run the actual settings window with QtTest input and system-service stand-ins."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
MOCKS = {
    "Qalc": "property bool found:false",
    "Ambient": "property bool enabled:false;property int delay:3;property bool previewing:false;function setEnabled(v){enabled=v;}function setDelay(m){delay=m;}function preview(){previewing=true;}",
    "DesktopWidgets": "property bool enabled:false;property bool arranging:false;function setEnabled(v){enabled=v;}function arrange(){enabled=true;arranging=true;}function done(){arranging=false;}",
    "Events": 'property bool available:false; property var calendars:[]',
    "Clocks": 'property bool clocksInstalled:false;property var ringing:null;',
    "FocusMode": 'signal phaseFinished(string message);property bool zen:false;property bool focusing:false;property bool pomodoring:false;property var allowed:[];function setOption(k,v){Store.saved[k]=v;}function setAllowed(a,v){}function startZen(v){}function stopZen(){}function toggleFocus(){}function togglePomodoro(){}',

    "Compositor": 'property var windows: []; property int activeWorkspace: 1; function placeSettingsWindow(w,x,y) {}',
    "Session": 'property bool locked',
    "FirstRun": 'property bool opened; function open() { opened = true; }',
    "About": 'property string branch:"tui";property string mood:"cooking";property string moodLong:"Experimental build";property string kind:"cooking";property bool stable:false;property string repo: ""; property string commit: "test"; property string date: "2026-11-10"; property string subject: "Test build"; property int changed: 0; property string quickshell: "0.3.2"; property string hyprland: "0.57.1"; property string qt: "6"; function load() {}',
    "Weather": 'property string city: "Before"; property string placeName: city; property var pending; function lookup(s,then) { pending=then; } function setCity(s) {city=s;}',
    "Cider": 'property bool installed: true; property bool usable: false; property string token: ""; property var pending; function check(s,then) {pending=then;} function setToken(s) {token=s;}',
    "LocalSend": 'property bool available:true; property bool wanted:false; property string summary:"Off"; property string name:"Test computer"; property string folderShown:"~/Downloads"; property bool acceptKnown:false; signal openRequested; function setReceive(v){wanted=v;} function setName(v){name=v;} function pickFolder(){} function setAcceptKnown(v){acceptKnown=v;}',
    "Bluetooth": '''property bool enabled:true; property bool ready:true; property bool agent:true; property bool scanning:false;
        property bool detailsWatching; function audioDetail(d){return "aac · 48000 Hz";} property string summary:"On"; property var paired:[]; property var nearby:[]; property var request:null;
        property string requestName:"Test keyboard"; property var answerGiven:null; signal asked;
        function setEnabled(v){enabled=v;} function setScanning(v){scanning=v;}
        function name(d){return d.name;} function status(d){return "Not connected";}
        function toggleConnection(d){} function pair(d){} function forget(d){}
        function serviceName(u){return "audio";} function answer(ok,value){answerGiven={ok:ok,value:value};request=null;}
        function ask(kind){request={kind:kind,id:1,code:"123456",entered:2,uuid:"0000110d"};asked();}''',
    "SystemStats": '''property bool watching:false; property real cpu:0.12;property real cpuTemp:48;property string cpuName:"Test CPU";
        property real memUsed:12;property real memTotal:32;property bool gpuFound:true;property real gpu:0.05;
        property real gpuTemp:45;property real vramUsed:1;property real shellCpu:0.002;property real shellMem:100;
        property var diskMounts:["/"];property real hyprCpu:0.01;property real hyprMem:100;property var disks:[{mount:"/",size:512,free:150}];function gigabytes(v){return Math.round(v)+" GB";}function setWatching(v){watching=v;}''',
    "Network": 'property bool watching; property string interfaceName:"eth0"; property var details:({ipv4:["192.0.2.4/24"],ipv6:[],gateways:["192.0.2.1"],dns:["192.0.2.53"]}); function copyDetail(key){Clipboard.copyText(details[key].join("\\n"));} property bool connected:true;property bool hasLink:true;property int speed:1000;',
    "Clipboard": 'property string copied; function copyText(value){copied=value;}',
    "Brightness": 'property bool available:true;property real value:0.7;function set(v){value=v;}',
    "NightLight": '''property bool available:true;property bool enabled:false;property int temperature:4000;
        property bool scheduled:false;property int from:1200;property int to:420;
        function setEnabled(v){enabled=v;}function setTemperature(v){temperature=v;}
        function setSchedule(on,a,b){scheduled=on;from=a;to=b;}
        function timeText(v){return String(Math.floor(v/60)).padStart(2,"0")+":"+String(v%60).padStart(2,"0");}''',
    "AppTheming": 'property bool enabled:true;property var apps:[{id:"kitty",name:"Kitty",state:"following",detail:""},{id:"neovim",name:"Neovim",state:"own",detail:""}];property var conflict:null;property var kept:[];property string used;function setEnabled(v){enabled=v;}function keep(id){kept=kept.concat([id]);conflict=null;}function use(id){used=id;conflict=null;}',
    "Notifs": '''property bool dnd:false;property bool dndScheduled:false;property bool dndFollowsNight:false;
        property int dndFrom:1320;property int dndTo:420;property var notifications:[];property var rules:({"Test app":{noToasts:true}});
        function setDnd(v){dnd=v;}function setDndSchedule(v){dndScheduled=v;}function setDndFollowsNight(v){dndFollowsNight=v;}
        function setDndTimes(a,b){dndFrom=a;dndTo=b;}function ruleText(a){return "No toasts";}
        function setRule(a,v){rules={};}''',
    "Apps": 'property var list:[];property var terminalChoices:["kitty","foot"];property string terminal:"kitty";function terminalName(s){return s;}function setTerminal(s){terminal=s;}',
    "Wallpapers": 'property string current:"";property string folder:"/tmp/wallpapers";function openFolder(){}',
    "Desktop": 'property bool enabled:true;function setEnabled(v){enabled=v;}',
    "Drives": 'property var mounted:[]; property var result:null;property var pending:null;property bool busy;function eject(d){} function canReturn(pid){return false;}function returnToApp(pid){}',
    "Audio": '''property var sinks:[{id:1,name:"Speakers"},{id:2,name:"Headphones"},{id:3,name:"Unplugged"}];
        property var sources:[{id:4,name:"Mic"}];property var sink:sinks[0];property var source:sources[0];
        property real volume:0.6;property real micVolume:0.4;property bool muted:false;property bool micMuted:false;
        property var streams:[];function deviceName(n){return n.name;}function isUnplugged(n){return n.id===3;}
        function setSink(n){sink=n;}function setSource(n){source=n;}
        function setVolume(v){volume=v;muted=false;}function setMicVolume(v){micVolume=v;micMuted=false;}
        function toggleMute(){muted=!muted;}function toggleMicMute(){micMuted=!micMuted;}
        function appName(n){return n.name;}function setStreamVolume(n,v){}function toggleStreamMute(n){}''',
}

with tempfile.TemporaryDirectory(prefix="pistachio-settings-test-") as directory:
    base = Path(directory)
    (base / "services").mkdir()
    (base / "panels").mkdir()
    shutil.copy(ROOT / "src/panels/DesktopCat.qml", base / "panels/DesktopCat.qml")
    for folder in ("settings", "components"):
        shutil.copytree(ROOT / "src" / folder, base / folder)
    shutil.copy(ROOT / "src/Theme.qml", base / "Theme.qml")
    for name in ("SettingsHub", "Store", "ShellSettings", "SettingsReset", "SystemHealth", "MicCheck", "Preferences", "GameMode"):
        shutil.copy(ROOT / f"src/services/{name}.qml", base / f"services/{name}.qml")
    for name, body in MOCKS.items():
        (base / f"services/{name}.qml").write_text("pragma Singleton\nimport Quickshell\nimport QtQuick\nSingleton {\n" + body + "\n}\n")
    for helper in ():  # system-tools.py and mic-check.py are psc since 19 November 2026 (the fixture's bin/ stands in for pw-record/pw-play)
        shutil.copy(ROOT / "src/services" / helper, base / "services" / helper)
    media = (ROOT / "src/services/Media.qml").read_text().replace("import Quickshell.Services.Mpris", "").replace("readonly property var players: Mpris.players.values", "property var players: []")
    (base / "services/Media.qml").write_text(media)
    (base / "bin").mkdir()
    (base / "bin/pw-record").write_text("#!/usr/bin/env python3\nimport sys,time\nwhile True:\n sys.stdout.buffer.write(b'\\x00\\x40'*1600);sys.stdout.buffer.flush();time.sleep(0.03)\n")
    (base / "bin/pw-record").chmod(0o755)
    (base / "bin/pw-play").write_text("#!/bin/sh\nsleep 0.3\n")
    (base / "bin/pw-play").chmod(0o755)
    # Deterministically race a real adapter write with a newer preference edit.
    store_fixture=base / "services/Store.qml"
    store_fixture.write_text(store_fixture.read_text().replace('    FileView {','    function fixtureWriteNow(): void { file.writeAdapter(); }\n    FileView {'))
    shutil.copy(ROOT / "tests/settings-ui.qml", base / "shell.qml")

    # the copied services run the installed `$HOME/.local/bin/psc`: test this build instead (PSC= another one)
    psc_build = os.environ.get("PSC") or str(ROOT / "rust/target/release/psc")
    rewritten = 0
    for qml in base.rglob("*.qml"):
        text = qml.read_text()
        if 'Quickshell.env("HOME") + "/.local/bin/psc"' in text:
            qml.write_text(text.replace('Quickshell.env("HOME") + "/.local/bin/psc"', json.dumps(psc_build)))
            rewritten += 1
    assert rewritten, "no service runs psc any more: update this fixture"
    (base / "runtime").mkdir(mode=0o700)
    env = dict(os.environ, PATH=str(base / "bin")+":"+os.environ["PATH"], QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=str(base / "runtime"),
               XDG_STATE_HOME=str(base / "state"), XDG_CACHE_HOME=str(base / "cache"),
               # the real ShellSettings publishes Colours through the installed psc into $XDG_CONFIG_HOME:
               # keep it (and Preferences' settings.toml) in the fixture, never the owner's (19 November 2026)
               XDG_CONFIG_HOME=str(base / "config"))
    real_config = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    guarded = [real_config / p for p in ("pistachio/shared-theme", "kitty/pistachio-shared.conf", "kitty/kitty.conf", "nvim/init.lua",
                                         "pistachio/pistachio-shell/settings.toml")]
    def snapshot():
        return {str(p): (p.read_bytes(), p.stat().st_mtime_ns) if p.exists() else None for p in guarded}
    before = snapshot()
    native = os.environ.get("PISTACHIO_SETTINGS_NATIVE") == "1"
    if native:
        env["QT_QPA_PLATFORM"] = "wayland"
        display = os.environ.get("WAYLAND_DISPLAY", "wayland-1")
        env["WAYLAND_DISPLAY"] = display if display.startswith("/") else os.environ["XDG_RUNTIME_DIR"] + "/" + display
    else:
        for key in ("WAYLAND_DISPLAY", "DISPLAY"):
            env.pop(key, None)
    with (base / "log").open("w+") as log:
        proc = subprocess.Popen(["qs", "-p", directory], env=env, stdout=log, stderr=log)
        try:
            result = None
            placed = False
            for _ in range(70):
                if native and not placed:
                    clients = json.loads(subprocess.check_output(["hyprctl", "--instance", "0", "-j", "clients"]))
                    window = next((w for w in clients if w["pid"] == proc.pid), None)
                    if window:
                        selector = "address:" + window["address"]
                        if not window["floating"]:
                            subprocess.run(["hyprctl", "--instance", "0", "dispatch", f'hl.dsp.window.float({{action="set",window="{selector}"}})'], capture_output=True, check=True)
                        subprocess.run(["hyprctl", "--instance", "0", "dispatch", f'hl.dsp.window.resize({{window="{selector}",x=1040,y=760,relative=false}})'], capture_output=True, check=True)
                        placed = True
                if native and not placed:
                    time.sleep(.1)
                    continue
                probe = subprocess.run(["qs", "-p", directory, "ipc", "call", "settingsTest", "ready"], env=env, capture_output=True, text=True)
                if probe.stdout.strip() == "true":
                    result = subprocess.run(["qs", "-p", directory, "ipc", "call", "settingsTest", "run"], env=env, capture_output=True, text=True, timeout=60 if native else 35)
                    break
                time.sleep(0.1)
            log.flush()
            output = (base / "log").read_text()
            assert result and result.stdout.strip().startswith("all passed"), (result.stdout if result else "No IPC target") + "\n" + output
            assert "WARN scene:" not in output and "ERROR" not in output, output
            print("settings QML: " + result.stdout.strip())
            assert snapshot() == before, "the Settings fixture changed the owner's real config files"
            timing=subprocess.check_output(["qs","-p",directory,"ipc","call","settingsTest","writeTime"],env=env,text=True).strip()
            print("settings state save: 200 fixture notifications, "+timing+" ms")
            proc.terminate()
            proc.wait(timeout=5)
            proc = subprocess.Popen(["qs", "-p", directory], env=env, stdout=log, stderr=log)
            saved = None
            for _ in range(70):
                probe = subprocess.run(["qs", "-p", directory, "ipc", "call", "settingsTest", "codingState"], env=env, capture_output=True, text=True)
                if probe.returncode == 0 and probe.stdout.lstrip().startswith("{"):
                    saved = json.loads(probe.stdout)
                    if saved["ready"]: break
                time.sleep(0.1)
            assert saved and saved["ready"] and saved["style"] == "tui" and not saved["suggest"] and saved["claude"] == "opus" and saved["codexEffort"] == "medium" and saved["normalClaude"] == "opus", saved
            print("settings QML: coding toggle/presets persist across restart; normal settings stay independent")
        finally:
            proc.terminate()
            proc.wait(timeout=5)
