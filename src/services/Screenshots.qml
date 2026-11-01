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
                "--action=default=Copy", "--action=open=Open", "--action=delete=Delete",
                "Screenshot saved", `${path.split("/").pop()}\nClick to copy it`]
            stdout: SplitParser {
                onRead: data => {
                    if (data === "default")
                        Clipboard.copyImage(path);
                    else if (data === "open")
                        Quickshell.execDetached(["xdg-open", path]);
                    else if (data === "delete")
                        Quickshell.execDetached(["gio", "trash", path]);
                }
            }
            onExited: destroy()
        }
    }
}
