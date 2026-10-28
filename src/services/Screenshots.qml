pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Screenshots (owner's request, after phase 8): where they go, and the notification that follows one.
// popups/ScreenshotPicker.qml takes the picture itself, cut from a still of the screen. The
// notification comes from the shell's own notify-send, which waits for its actions: a click copies
// the image (Clipboard), Open shows it (xdg-open), Delete moves it to the trash (gio). Its hint marks it
// as the shell's, so it shows even in Do not disturb (Notifs.own) with a preview of the picture.
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

    function saved(path: string) {
        notifier.createObject(root, { path: path });
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
