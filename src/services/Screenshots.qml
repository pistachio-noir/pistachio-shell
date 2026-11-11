pragma Singleton

import qs
import Quickshell
import Quickshell.Io
import QtQuick

// Screenshots (owner's request, after phase 8): where they go, and the notification that follows one.
// popups/ScreenshotPicker.qml takes the picture itself, cut from a still of the screen. The
// notification comes from the shell's own notify-send, which waits for its actions: a click copies
// the image (Clipboard), Open shows it (xdg-open), Delete moves it to the trash (gio). Its hint marks it
// as the shell's, so it shows even in Do not disturb (Notifs.own) with a preview of the picture.
// Text from the screen (owner's pick, 30 October 2026): the picker's Text choice saves the area to the
// runtime folder (memory, gone at logout), tesseract reads it (Polish and English), the text is copied,
// and a notification shows the area and the start of the text; a click copies it again.
Singleton {
    id: root

    // ~/Pictures/Screenshots, or the Pictures folder xdg-user-dir names
    property string folder: `${Quickshell.env("HOME")}/Pictures/Screenshots`

    // Screenshot_2026-10-27_22-55-03.png in the folder
    function nextPath(): string {
        return ShellSettings.screenshotOutput === "copy"
            ? `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/pistachio-copy-${Date.now()}.png`
            : `${folder}/Screenshot_${Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss-zzz")}.png`;
    }

    // before a picture is taken, so the folder is there when it's saved
    function prepare() {
        if (ShellSettings.screenshotOutput !== "copy")
            Quickshell.execDetached(["mkdir", "-p", folder]);
    }

    // A soft camera click as a picture is taken (owner's pick, 31 October 2026), with the notification
    // sound's switch; the notification after it then plays no chime of its own (Notifs.showPopup)
    function shutter() {
        if (ShellSettings.notificationSound)
            Quickshell.execDetached(["pw-play", Quickshell.shellPath("sounds/shutter.wav")]);
    }

    function saved(path: string, output: string) {
        const choice = output || ShellSettings.screenshotOutput;
        if (choice === "copy" || choice === "both")
            Clipboard.copyImage(path);
        if (choice === "copy")
            copiedNotifier.createObject(root, { path: path });
        else
            notifier.createObject(root, { path: path });
    }

    Component {
        id: copiedNotifier
        Process {
            required property string path
            running: true
            command: ["setpriv", "--pdeathsig", "TERM", "notify-send", "--app-name=Screenshot",
                `--hint=string:x-pistachio-screenshot:${path}`, "--action=default=Copy", "Screenshot copied", "Temporary image · not saved to Pictures"]
            stdout: SplitParser { onRead: data => { if (data === "default") Clipboard.copyImage(path); } }
            // Runtime-only image is also available for the notification preview and copy action.
            // wl-copy reads asynchronously, so leave it until logout rather than racing its stdin.
            onExited: destroy()
        }
    }

    function nextTextPath(): string {
        return `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/pistachio-text-${Date.now()}.png`;
    }

    function nextLensPath(): string {
        return `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/pistachio-lens-${Date.now()}.png`;
    }

    function readText(path: string) {
        reader.createObject(root, { path: path });
    }

    // Owner's picks, 8 November 2026: the tools for the picker's Colour and Record and the
    // notification's Edit, each offered only while installed
    property bool hasPicker
    property bool hasRecorder
    property bool hasEditor

    Process {
        running: true
        command: ["sh", "-c", "for t in hyprpicker gpu-screen-recorder satty; do command -v $t >/dev/null && echo $t; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.hasPicker = text.includes("hyprpicker");
                root.hasRecorder = text.includes("gpu-screen-recorder");
                root.hasEditor = text.includes("satty");
            }
        }
    }

    // Colour: hyprpicker freezes the screen for a click and copies the colour's hex; a notification
    // shows it with a swatch (a 64 px PNG written in the runtime folder)
    function pickColour() {
        Quickshell.execDetached(["sh", "-c", 'c=$(hyprpicker -a -f hex) && [ -n "$c" ] || exit 0; p="${XDG_RUNTIME_DIR:-/tmp}/pistachio-colour.png"; python3 -I "$1" "$c" "$p"; notify-send --app-name=Colour -i "$p" "$c" "Copied to the clipboard"', "sh", Quickshell.shellPath("services/swatch.py")]);
    }

    // Record: gpu-screen-recorder, the whole screen or an area, with the sound playing, to ~/Videos;
    // the bar shows a dot and the time while it runs, and a click there stops it (SIGINT, which saves)
    property string videos: `${Quickshell.env("HOME")}/Videos`
    readonly property bool recording: recorder.running
    property real recordingSince
    property string recordingPath
    property rect recordingArea: Qt.rect(0, 0, 0, 0)
    property bool recordingWhole: true
    property string recordingMonitor
    property bool paused
    property real pausedAt
    property real pausedTotal
    property int countdown
    property bool pendingRecording
    property rect pendingArea
    property bool pendingWhole
    property string pendingMonitor
    readonly property bool countingDown: pendingRecording

    function elapsedMs(now: real): real {
        return Math.max(0, (paused ? pausedAt : now) - recordingSince - pausedTotal);
    }

    function queueRecord(r: rect, whole: bool, monitor: string) {
        if (recording || pendingRecording) return;
        pendingArea = r; pendingWhole = whole; pendingMonitor = monitor;
        countdown = ShellSettings.recordingCountdown;
        pendingRecording = true;
        if (countdown > 0) countdownTick.start();
        else startAfterCountdown.start();
    }

    function cancelCountdown() {
        countdownTick.stop(); startAfterCountdown.stop();
        pendingRecording = false; countdown = 0;
    }

    Timer {
        id: countdownTick; interval: 1000; repeat: true
        onTriggered: {
            root.countdown--;
            if (root.countdown <= 0) { stop(); startAfterCountdown.start(); }
        }
    }
    Timer {
        id: startAfterCountdown; interval: Theme.motionDuration + 80
        onTriggered: {
            root.pendingRecording = false;
            root.record(root.pendingArea, root.pendingWhole, root.pendingMonitor);
        }
    }

    function togglePause() {
        if (!recording) return;
        recorder.signal(12); // SIGUSR2, documented pause/unpause (not SIGSTOP).
        if (paused) pausedTotal += Date.now() - pausedAt;
        else pausedAt = Date.now();
        paused = !paused;
    }

    function record(r: rect, whole: bool, monitor: string) {
        if (recorder.running)
            return;
        const x = Math.round(r.x), y = Math.round(r.y), w = Math.round(r.width) & ~1, h = Math.round(r.height) & ~1; // even sizes, for the encoder
        if (!whole && (w < 2 || h < 2))
            return;
        recordingArea = Qt.rect(x, y, w, h);
        recordingWhole = whole;
        recordingMonitor = monitor;
        recordingPath = `${videos}/Recording_${Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss")}.mp4`;
        recorder.command = ["sh", "-c", 'mkdir -p "$1" && shift && exec "$@"', "sh", videos, "setpriv", "--pdeathsig", "INT", "gpu-screen-recorder",
            "-w", whole ? monitor : "region"].concat(whole ? [] : ["-region", `${w}x${h}+${x}+${y}`], ["-f", "60", "-o", recordingPath]);
        const audio = ShellSettings.recordingAudio;
        if (audio !== "off") {
            const source = audio === "both" ? "default_output|default_input" : audio === "mic" ? "default_input" : "default_output";
            // Default input follows the Sound page's PipeWire selection; never pick another mic.
            recorder.command = recorder.command.concat(["-a", source]);
        }
        paused = false; pausedAt = 0; pausedTotal = 0;
        recordingSince = Date.now();
        recorder.running = true;
    }

    function stopRecording() {
        if (!recording) return;
        recorder.signal(2); // SIGINT: it finishes the file
    }

    Process {
        id: recorder
        stderr: SplitParser {
            onRead: data => {
                if (/error|fail/i.test(data)) // it reports its frame rate every few seconds otherwise
                    console.warn("recording:", data);
            }
        }
        onExited: code => {
            root.paused = false;
            if (code === 0)
                recordedNotifier.createObject(root, { path: root.recordingPath });
            else
                Quickshell.execDetached(["notify-send", "--app-name=Recording", "Recording failed", `gpu-screen-recorder stopped with code ${code}; psc log has its words.`]);
        }
    }

    Component {
        id: recordedNotifier

        Process {
            required property string path

            running: true
            command: ["setpriv", "--pdeathsig", "TERM", "notify-send", "--app-name=Recording", "--action=default=Open", "--action=folder=Show in folder"].concat(root.hasTrimmer ? ["--action=trim=Trim"] : [], [
                "Recording saved", path.split("/").pop()])
            stdout: SplitParser {
                onRead: data => {
                    if (data === "default")
                        Quickshell.execDetached(["xdg-open", path]);
                    else if (data === "folder")
                        Quickshell.execDetached(["xdg-open", path.slice(0, path.lastIndexOf("/"))]);
                    else if (data === "trim")
                        root.openTrim(path);
                }
            }
            onExited: destroy()
        }
    }

    property bool hasTrimmer
    property bool trimOpen
    property string trimPath
    property real trimDuration
    property string trimError
    readonly property bool trimBusy: trimmer.running
    property string trimSavedPath
    function openTrim(path: string) {
        if (probe.running || trimmer.running) return;
        trimPath = path; trimDuration = 0; trimError = ""; trimSavedPath = ""; trimOpen = true;
        probe.command = ["setpriv", "--pdeathsig", "TERM", "python3", "-I", Quickshell.shellPath("services/capture.py"), "probe", path];
        probe.running = true;
    }
    function saveTrim(start: real, end: real) {
        if (trimmer.running || trimDuration <= 0) return;
        if (!Number.isFinite(start) || !Number.isFinite(end) || start < 0 || end <= start || end > trimDuration) {
            trimError = "Choose a start before the end, within the recording"; return;
        }
        trimError = "";
        trimmer.command = ["setpriv", "--pdeathsig", "TERM", "python3", "-I", Quickshell.shellPath("services/capture.py"), "trim", trimPath, String(start), String(end)];
        trimmer.running = true;
    }
    function closeTrim() {
        if (trimmer.running) trimmer.signal(15);
        if (probe.running) probe.signal(15);
        trimOpen = false;
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null"]
        onExited: code => root.hasTrimmer = code === 0
    }
    Process {
        id: probe
        stdout: StdioCollector { id: probed }
        onExited: code => {
            if (!root.trimOpen) return;
            try {
                const reply = JSON.parse(probed.text);
                root.trimDuration = reply.duration || 0;
                root.trimError = reply.error || "";
            } catch(e) { root.trimError = "Could not read recording duration"; }
        }
    }
    Process {
        id: trimmer
        stdout: StdioCollector { id: trimmed }
        onExited: code => {
            if (!root.trimOpen) return;
            try {
                const reply = JSON.parse(trimmed.text);
                root.trimError = reply.error || "";
                root.trimSavedPath = reply.path || "";
                if (reply.path) recordedNotifier.createObject(root, { path: reply.path });
            } catch(e) { root.trimError = "Trim stopped before saving"; }
        }
    }

    Process {
        running: true
        command: ["xdg-user-dir", "VIDEOS"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim();
                if (v && v !== Quickshell.env("HOME"))
                    root.videos = v;
            }
        }
    }

    Process {
        running: true
        command: ["xdg-user-dir", "PICTURES"]
        stdout: StdioCollector {
            onStreamFinished: {
                const pictures = text.trim();
                if (pictures && pictures !== Quickshell.env("HOME"))
                    root.folder = `${pictures}/Screenshots`;
            }
        }
    }

    // tesseract on the area; no more than two blank lines in a row, and a missing tesseract says so
    Component {
        id: reader

        Process {
            required property string path

            running: true
            command: ["sh", "-c", 'command -v tesseract >/dev/null || exit 127; tesseract "$1" - -l pol+eng 2>/dev/null', "sh", path]
            stdout: StdioCollector {
                id: read
            }
            onExited: code => {
                const text = read.text.replace(/\f/g, "").replace(/[ \t]+$/gm, "").replace(/\n{3,}/g, "\n\n").trim();
                if (text)
                    Clipboard.copyText(text);
                textNotifier.createObject(root, { path: path, text: text, problem: code === 127 ? "tesseract isn't installed" : code !== 0 ? `tesseract failed (exit ${code})` : "" });
                destroy();
            }
        }
    }

    Component {
        id: textNotifier

        Process {
            required property string path
            required property string text
            required property string problem

            running: true
            command: ["setpriv", "--pdeathsig", "TERM", "notify-send", "--app-name=Screenshot",
                `--hint=string:x-pistachio-screenshot:${path}`].concat(text ? ["--action=default=Copy"] : [],
                [problem ? "Couldn't read the text" : text ? "Text copied" : "No text found",
                problem || (text ? (text.length > 140 ? `${text.slice(0, 140)}…` : text) : "Try a larger area, or text with more contrast")])
            stdout: SplitParser {
                onRead: data => {
                    if (data === "default")
                        Clipboard.copyText(text);
                }
            }
            onExited: destroy()
        }
    }

    // one per screenshot, while its notification lasts; setpriv stops it with the shell
    Component {
        id: notifier

        Process {
            required property string path

            running: true
            command: ["setpriv", "--pdeathsig", "TERM", "notify-send", "--app-name=Screenshot",
                `--hint=string:x-pistachio-screenshot:${path}`,
                "--action=default=Copy", "--action=open=Open"].concat(root.hasEditor ? ["--action=edit=Edit"] : [], ["--action=delete=Delete",
                "Screenshot saved", `${path.split("/").pop()}\nClick to copy it`])
            stdout: SplitParser {
                onRead: data => {
                    if (data === "default")
                        Clipboard.copyImage(path);
                    else if (data === "open")
                        Quickshell.execDetached(["xdg-open", path]);
                    else if (data === "edit") // satty: arrows, boxes, blur; its save writes over the file
                        Quickshell.execDetached(["satty", "--filename", path, "--output-filename", path]);
                    else if (data === "delete")
                        Quickshell.execDetached(["gio", "trash", path]);
                }
            }
            onExited: destroy()
        }
    }
}
