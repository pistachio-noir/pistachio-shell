pragma Singleton

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
        return `${folder}/Screenshot_${Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss")}.png`;
    }

    // before a picture is taken, so the folder is there when it's saved
    function prepare() {
        Quickshell.execDetached(["mkdir", "-p", folder]);
    }

    // A soft camera click as a picture is taken (owner's pick, 31 October 2026), with the notification
    // sound's switch; the notification after it then plays no chime of its own (Notifs.showPopup)
    function shutter() {
        if (ShellSettings.notificationSound)
            Quickshell.execDetached(["pw-play", Quickshell.shellPath("sounds/shutter.wav")]);
    }

    function saved(path: string) {
        notifier.createObject(root, { path: path });
    }

    function nextTextPath(): string {
        return `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/pistachio-text-${Date.now()}.png`;
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

    function record(r: rect, whole: bool, monitor: string) {
        if (recorder.running)
            return;
        const x = Math.round(r.x), y = Math.round(r.y), w = Math.round(r.width) & ~1, h = Math.round(r.height) & ~1; // even sizes, for the encoder
        recordingPath = `${videos}/Recording_${Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss")}.mp4`;
        recorder.command = ["sh", "-c", 'mkdir -p "$1" && shift && exec "$@"', "sh", videos, "setpriv", "--pdeathsig", "INT", "gpu-screen-recorder",
            "-w", whole ? monitor : "region"].concat(whole ? [] : ["-region", `${w}x${h}+${x}+${y}`], ["-f", "60", "-a", "default_output", "-o", recordingPath]);
        recordingSince = Date.now();
        recorder.running = true;
    }

    function stopRecording() {
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
            command: ["setpriv", "--pdeathsig", "TERM", "notify-send", "--app-name=Recording", "--action=default=Open", "--action=folder=Show in folder",
                "Recording saved", path.split("/").pop()]
            stdout: SplitParser {
                onRead: data => {
                    if (data === "default")
                        Quickshell.execDetached(["xdg-open", path]);
                    else if (data === "folder")
                        Quickshell.execDetached(["xdg-open", path.slice(0, path.lastIndexOf("/"))]);
                }
            }
            onExited: destroy()
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
