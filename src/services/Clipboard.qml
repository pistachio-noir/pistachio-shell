pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The clipboard, through wl-copy (wl-clipboard): text and pictures, and the emoji copied lately from
// the launcher (kept in Store, newest first), which it lists first after a bare ":".
Singleton {
    id: root
    property var history: []

    function loadHistory() { if (ShellSettings.clipboardHistory) historyReader.exec({ command: historyReader.command }); }
    function restoreHistory(id) {
        Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | cliphist decode | wl-copy', "sh", id]);
    }
    function clearHistory() { clearReader.running = true; }

    Process { command: ["wl-paste", "--type", "text", "--watch", "cliphist", "store"]; running: ShellSettings.clipboardHistory }
    Process {
        id: historyReader
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: if (ShellSettings.clipboardHistory) root.history = text.split("\n").map(line => {
                const tab = line.indexOf("\t");
                return tab > 0 ? { id: line.slice(0, tab), text: line.slice(tab + 1) } : null;
            }).filter(item => item && /^\d+$/.test(item.id));
        }
    }
    Process {
        id: clearReader
        command: ["cliphist", "wipe"]
        onExited: (code, status) => { if (code === 0) root.loadHistory(); }
    }
    readonly property var recentEmoji: Store.saved.recentEmoji ?? []

    function copyText(text: string) {
        Quickshell.execDetached(["wl-copy", "--", text]);
    }

    function copyImage(path: string) {
        Quickshell.execDetached(["sh", "-c", "wl-copy --type image/png < \"$1\"", "sh", path]);
    }

    function copyEmoji(emoji: string) {
        copyText(emoji);
        Store.saved.recentEmoji = [emoji].concat(recentEmoji.filter(e => e !== emoji)).slice(0, 16);
    }
}
