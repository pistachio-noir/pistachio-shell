pragma Singleton

import qs
import Quickshell
import Quickshell.Io
import QtQuick

// LocalSend (owner's request, 2 November 2026; boards pistachio-shell-design/*localsend*.html): the shell is a LocalSend
// device itself, through pistachio-localsend (built from rust/localsend), which speaks the protocol. All of it exists only while
// the LocalSend app is installed (owner's call); the app itself mustn't run meanwhile, as both need the
// port. Receiving is off until switched on, and remembered.
Singleton {
    id: root

    readonly property var app: Apps.list.find(a => a.id === "localsend" || a.id === "org.localsend.localsend_app") ?? null
    readonly property bool available: app !== null

    property bool ready
    property string hostName
    readonly property string name: Store.saved.localsendName || hostName
    readonly property string folder: Store.saved.localsendFolder || `${Quickshell.env("HOME")}/Downloads`
    readonly property string folderShown: folder.replace(Quickshell.env("HOME"), "~")
    readonly property bool acceptKnown: Store.saved.localsendAcceptKnown
    readonly property var known: Store.saved.localsendKnown ?? []
    readonly property bool wanted: Store.saved.localsendReceive // the switch
    property bool receiving // the helper's server is up
    property bool busy // another program has the port (the LocalSend app, most likely)

    property var devices: []
    property bool scanning
    property var items: [] // ready to send: { path, name, size, count, dir, mime } or { text, name, size }
    readonly property real itemsSize: items.reduce((sum, i) => sum + i.size, 0)
    property bool nothingToPaste // a moment after Paste found nothing
    property var send: null // the transfer out: the helper's last "send" event
    readonly property bool sendRunning: send !== null && (send.state === "waiting" || send.state === "sending")

    property var request: null // a device asks to send: { session, from, files, total }
    property var incoming: null // the transfer in: { session, from, done, total, speed, file, index, count }
    property var message: null // a text from a device: { from, text }
    property string note // a short line for the toast, e.g. "iPhone cancelled"
    property var noteFrom: null
    readonly property bool toastShown: request !== null || incoming !== null || message !== null || note !== ""

    readonly property string summary: busy ? "Can't receive · port in use" : send && sendRunning ? (send.state === "waiting" ? `Waiting for ${send.device.alias}` : `Sending to ${send.device.alias} · ${percent(send)} %`) : incoming ? `Receiving from ${incoming.from.alias} · ${percent(incoming)} %` : receiving ? `Receiving as ${name}${devices.length ? ` · ${devices.length} nearby` : ""}` : "Off"

    signal openRequested // the desktop's "Send with LocalSend" and `psc localsend add`: the page, in quick settings

    function percent(t): int {
        return t.total > 0 ? Math.floor(100 * t.done / t.total) : 0;
    }

    function command(m) {
        if (ready)
            helper.write(JSON.stringify(m) + "\n");
    }

    function configure() {
        command({ cmd: "config", alias: name, folder: folder, acceptKnown: acceptKnown, known: known });
    }

    function setReceive(on: bool) {
        Store.saved.localsendReceive = on;
        command({ cmd: "receive", on: on });
    }

    function scan() {
        command({ cmd: "scan", legacy: true });
    }

    function add(paths) {
        if (paths.length)
            command({ cmd: "inspect", paths: paths });
    }

    function addText(text: string) {
        items = items.filter(i => !i.text).concat([{ text: text, name: text.split("\n")[0].slice(0, 40), size: text.length }]);
    }

    function clear() {
        items = [];
    }

    function pickFiles(folders: bool) {
        picker.folders = folders;
        picker.running = true;
    }

    function paste() {
        command({ cmd: "paste" });
    }

    function sendTo(device) {
        if (!items.length || sendRunning)
            return;
        const text = items.find(i => i.text)?.text ?? "";
        command({ cmd: "send", device: device.fingerprint, paths: items.filter(i => !i.text).map(i => i.path), text: text });
    }

    function cancelSend() {
        command({ cmd: "cancelSend" });
    }

    // Done, Back or Try again on the sending page
    function closeSend(again: bool) {
        const to = send?.device;
        const sent = send?.state === "done";
        send = null;
        if (sent)
            items = [];
        else if (again && to)
            sendTo(to);
    }

    function accept() {
        if (!request)
            return;
        const fp = request.from.fingerprint;
        if (fp && !known.includes(fp))
            Store.saved.localsendKnown = known.concat([fp]);
        command({ cmd: "answer", session: request.session, accept: true });
    }

    function decline() {
        if (!request)
            return;
        command({ cmd: "answer", session: request.session, accept: false });
        request = null;
    }

    function cancelReceive() {
        command({ cmd: "cancelReceive" });
    }

    function copyMessage() {
        if (message)
            Clipboard.copyText(message.text);
        message = null;
    }

    function setName(text: string) {
        Store.saved.localsendName = text.trim() === hostName ? "" : text.trim();
    }

    function setFolder(path: string) {
        Store.saved.localsendFolder = path;
    }

    function setAcceptKnown(on: bool) {
        Store.saved.localsendAcceptKnown = on;
    }

    function forgetKnown() {
        Store.saved.localsendKnown = [];
    }

    // a device's kind for its icon and label: phone, tablet, computer, browser or server
    function kind(d): string {
        if (d.type === "mobile")
            return /ipad|tab/i.test(d.model) ? "tablet" : "phone";
        return d.type === "web" ? "browser" : d.type === "headless" || d.type === "server" ? "server" : "computer";
    }

    function kindLabel(d): string {
        const k = kind(d);
        return k === "computer" ? (d.model || "Computer") : k[0].toUpperCase() + k.slice(1);
    }

    function size(bytes: real): string {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let i = 0;
        while (bytes >= 1000 && i < units.length - 1) {
            bytes /= 1000;
            i++;
        }
        return `${i === 0 || bytes >= 100 ? Math.round(bytes) : bytes.toFixed(1)} ${units[i]}`;
    }

    // "24 MB/s · 3 s left"
    function pace(t): string {
        if (!t.speed)
            return "";
        const left = Math.max(0, Math.round((t.total - t.done) / t.speed));
        return `${size(t.speed)}/s · ${left >= 60 ? `${Math.round(left / 60)} min` : `${left} s`} left`;
    }

    function done(m) {
        const count = m.paths.length;
        const title = `${count} file${count === 1 ? "" : "s"} from ${m.from.alias}`;
        Quickshell.execDetached(["sh", "-c", 'a=$(notify-send -a LocalSend -i "$1" -A open="Open folder" "$2" "$3"); [ "$a" = open ] && xdg-open "$4"', "sh", root.app?.icon ?? "", title, `Saved to ${root.folderShown}`, root.folder]);
    }

    function heard(line: string) {
        let m;
        try {
            m = JSON.parse(line);
        } catch (e) {
            console.warn("localsend:", line);
            return;
        }
        switch (m.event) {
        case "ready":
            ready = true;
            hostName = m.host;
            configure();
            if (Store.ready && wanted)
                command({ cmd: "receive", on: true });
            break;
        case "receive":
            receiving = m.on;
            busy = m.busy;
            break;
        case "clear":
            devices = [];
            break;
        case "scan":
            scanning = m.running;
            break;
        case "device":
            devices = devices.filter(d => d.fingerprint !== m.fingerprint).concat([m]).sort((a, b) => a.alias.localeCompare(b.alias));
            break;
        case "items":
            items = items.filter(i => i.text || !m.items.some(n => n.path === i.path)).concat(m.items);
            break;
        case "paste":
            if (m.paths)
                add(m.paths);
            else if (m.text)
                addText(m.text);
            else {
                nothingToPaste = true;
                pasteNote.restart();
            }
            break;
        case "send":
            send = m;
            break;
        case "request":
            if (Session.locked) { // nobody can answer behind the lock screen
                command({ cmd: "answer", session: m.session, accept: false });
                break;
            }
            note = "";
            if (m.auto)
                incoming = { session: m.session, from: m.from, done: 0, total: m.total, speed: 0, file: "", index: 1, count: m.files.length };
            else {
                request = m;
                if (!Notifs.dnd)
                    Notifs.chime();
            }
            break;
        case "requestGone":
            if (request?.session === m.session) {
                tell(`${request.from.alias} cancelled`);
                request = null;
            }
            break;
        case "message":
            message = m;
            if (!Notifs.dnd)
                Notifs.chime();
            break;
        case "receiving":
            incoming = Object.assign({ from: incoming?.from ?? request?.from }, m);
            request = null;
            break;
        case "received":
            incoming = null;
            done(m);
            break;
        case "receiveFailed":
            request = null;
            incoming = null;
            tell(m.reason === "cancelled" ? `${m.from.alias} cancelled` : m.reason === "stopped" ? "Stopped" : `${m.from.alias} went away`);
            break;
        }
    }

    function tell(text: string) {
        note = text;
        noteTimer.restart();
    }

    Timer {
        id: noteTimer
        interval: 4000
        onTriggered: root.note = ""
    }

    Timer {
        id: pasteNote
        interval: 2000
        onTriggered: root.nothingToPaste = false
    }

    // the settings change: tell the helper
    onNameChanged: configure()
    onFolderChanged: configure()
    onAcceptKnownChanged: configure()
    onKnownChanged: configure()

    Connections {
        target: Store
        function onReadyChanged() {
            if (Store.ready && root.wanted)
                root.command({ cmd: "receive", on: true });
        }
    }

    Process {
        id: helper
        running: root.available
        command: [Quickshell.env("HOME") + "/.local/bin/pistachio-localsend"] // it ends itself when the shell dies
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => root.heard(data)
        }
        stderr: SplitParser {
            onRead: data => console.warn("localsend:", data)
        }
        onExited: code => {
            root.ready = false;
            root.receiving = false;
            root.devices = [];
            root.request = null;
            root.incoming = null;
            root.send = null;
        }
    }

    // Add files / Add folder: GTK's file chooser, through zenity
    Process {
        id: picker
        property bool folders
        command: ["zenity", "--file-selection", "--multiple", "--separator=\n", `--title=${folders ? "Folders" : "Files"} to send`].concat(folders ? ["--directory"] : [])
        stdout: StdioCollector {
            onStreamFinished: root.add(text.split("\n").filter(p => p !== ""))
        }
        // the chooser took the keyboard, which closed quick settings as a click outside would: open
        // the page again, with what was picked, so Send is one click away (owner's report, 13 November)
        onExited: root.openRequested()
    }

    // the settings card's Change: a folder for what arrives
    Process {
        id: folderPicker
        command: ["zenity", "--file-selection", "--directory", "--title=Save LocalSend files to", `--filename=${root.folder}/`]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (path)
                    root.setFolder(path);
            }
        }
    }

    function pickFolder() {
        folderPicker.running = true;
    }

    // For the file manager or a keybind: psc localsend add /path/to/file (one path a call), psc localsend open
    IpcHandler {
        target: "localsend"
        enabled: root.available

        function add(path: string): void {
            root.add([path]);
            root.openRequested();
        }

        function open(): void {
            root.openRequested();
        }
    }
}
