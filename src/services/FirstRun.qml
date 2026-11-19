pragma Singleton

import Quickshell
import Quickshell.Io
import qs
import QtQuick

// First-run setup (owner's call, 19 November 2026; boards design/FirstRun/, window
// setup/FirstRunWindow.qml). It opens by itself once: on the shell's very first start, when there
// was no saved state yet. A shell that already had state but no "setup done" mark (set up before
// this existed) is marked done quietly and never sees it. Done or Skip marks it for good;
// `psc setup` (IPC `setup open`) opens it again any time.
//
// The check runs `psc doctor --json` (the README's Requirements, one list) and asks D-Bus who owns
// the notification name. It only shows; it never installs or stops anything. Missing tools show
// their package name; another notification daemon shows the command that stops it.
Singleton {
    id: root

    property bool opened
    property bool loaded // the window exists: from open until its fade-out ends (shell.qml loads it lazily)
    readonly property bool done: Store.saved.setupDone
    property bool decided
    signal present

    // the check: rows for the view ({ title, detail, status, package?, command? }), revealed one by one
    property string checkState: "idle" // checking, clear or attention
    property var checks: []
    property int checkTotal: 0
    property string checkNote
    property var found: ({}) // doctor id -> installed
    property var pending: [] // rows still to reveal

    readonly property string psc: Quickshell.env("HOME") + "/.local/bin/psc"
    readonly property var window: Compositor.windows.find(w => w.title === "Pistachio Setup" && w.pid === Quickshell.processId) ?? null
    property string placedAddress
    onWindowChanged: {
        if (opened && window && window.bounds.width > 0 && window.address !== placedAddress) {
            placedAddress = window.address;
            Compositor.placeSettingsWindow(window, Theme.setupWidth, Theme.setupHeight);
        }
        if (!window) placedAddress = "";
    }

    Connections { target: Store; function onReadyChanged() { root.decide(); } }
    Component.onCompleted: decide()

    function decide() {
        if (decided || !Store.ready) return;
        decided = true;
        if (Store.saved.setupDone) return;
        if (Store.fresh) open();
        else Store.saved.setupDone = true; // set up before first-run setup existed
    }

    function open() {
        if (Session.locked) return;
        unload.stop();
        loaded = true;
        opened = true;
        present();
    }

    // shell: back to the desktop; settings: Settings opens; skip: the same as shell, said differently
    function finish(destination: string) {
        Store.saved.setupDone = true;
        opened = false;
        unload.restart();
        Preferences.cancel();
        if (destination === "settings") SettingsHub.openPage("appearance", "");
    }

    Timer { id: unload; interval: Theme.motionDuration + 200; onTriggered: root.loaded = false }

    function check() {
        if (doctor.running || bus.running) return;
        checkState = "checking";
        checks = [];
        pending = [];
        checkNote = "";
        doctor.running = true;
        bus.running = true;
        giveUp.restart();
    }
    // a helper that never starts sends no exit: settle with what there is
    Timer {
        id: giveUp
        interval: 15000
        onTriggered: {
            doctor.running = false;
            bus.running = false;
            root.settle();
        }
    }

    function readDoctor(text: string): var {
        try {
            const rows = JSON.parse(text);
            return Array.isArray(rows) ? rows : null;
        } catch (e) {
            return null;
        }
    }
    function readOwner(text: string): var {
        const pid = /^PID=(\d+)$/m.exec(text), comm = /^Comm=(.+)$/m.exec(text);
        return pid ? { pid: parseInt(pid[1]), comm: comm ? comm[1].trim() : "" } : {};
    }

    // both answers in (their collectors hold the text): build the rows, then show them one by one
    function settle() {
        if (doctor.running || bus.running || checkState !== "checking" || pending.length || reveal.running) return;
        const doctorRows = readDoctor(doctorOut.text);
        if (doctorRows === null) {
            checkTotal = 1;
            checks = [{ title: "psc doctor didn't answer", detail: "The check needs psc in ~/.local/bin. Run ./install.sh, then check again.", status: "warning", package: "./install.sh" }];
            checkState = "attention";
            return;
        }
        const map = {};
        const rows = doctorRows.map(r => {
            map[r.id] = r.found;
            return r.found ? { title: r.title, detail: r.kind === "required" ? "Required" : r.package, status: "pass" }
                : { title: r.title, detail: "Without it: " + r.without + ".", status: r.kind === "required" ? "warning" : "optional", package: r.package };
        });
        found = map;
        const owner = readOwner(busOut.text);
        if (owner.pid && owner.pid !== Quickshell.processId) {
            const name = owner.comm || "Another program";
            rows.unshift({ title: name + " is running", detail: "Only one program can show notifications. Stop it, take it out of your autostart, then restart the shell (psc restart).",
                status: "conflict", command: owner.comm ? "pkill -x " + owner.comm : "" });
        } else {
            rows.unshift({ title: "Notification service", detail: owner.pid ? "The shell shows them" : "Nobody owns it yet", status: owner.pid ? "pass" : "warning" });
        }
        checkTotal = rows.length;
        pending = rows;
        reveal.restart();
    }

    function finishReveal() {
        const missing = checks.filter(r => r.status === "optional");
        const attention = checks.some(r => r.status === "warning" || r.status === "conflict");
        checkNote = missing.length ? `${missing.length} optional ${missing.length === 1 ? "tool" : "tools"} not installed: ${missing.map(r => r.package).join(", ")}` : "";
        checkState = attention ? "attention" : "clear";
    }

    Timer {
        id: reveal
        interval: 28
        repeat: true
        onTriggered: {
            if (!root.pending.length) {
                stop();
                root.finishReveal();
                return;
            }
            root.checks = root.checks.concat([root.pending[0]]);
            root.pending = root.pending.slice(1);
        }
    }

    Process {
        id: doctor
        command: [root.psc, "doctor", "--json"]
        stdout: StdioCollector { id: doctorOut }
        onExited: Qt.callLater(root.settle)
    }
    Process {
        id: bus
        command: ["busctl", "--user", "status", "org.freedesktop.Notifications"]
        stdout: StdioCollector { id: busOut }
        onExited: Qt.callLater(root.settle)
    }

    // Restore my settings: Preferences reads and reviews a Settings export; Apply writes it
    property string chosenFile
    function chooseRestoreFile() {
        if (!chooser.running) chooser.running = true;
    }
    Process {
        id: chooser
        command: ["env", "zenity", "--file-selection", "--title=Restore Pistachio settings", "--file-filter=Settings export | *.toml"]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (path) {
                    root.chosenFile = path;
                    Preferences.review(path);
                }
            }
        }
    }

    function playSound() {
        Quickshell.execDetached(["pw-play", Quickshell.shellPath("sounds/notification.wav")]);
    }

    IpcHandler {
        target: "setup"
        function open(): void { root.open(); }
        function close(): void { if (root.opened) root.finish("skip"); }
        function status(): string { return JSON.stringify({ open: root.opened, done: root.done, check: root.checkState }); }
    }
}
