pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The clipboard, through wl-copy (wl-clipboard): text and pictures, and the emoji copied lately from
// the launcher (kept in Store, newest first), which it lists first after a bare ":".
// History (opt-in) is cliphist's: copied text, and pictures too with Keep pictures (its own switch, off;
// owner's call, 28 November 2026: cliphist keeps them on disk, copied screenshots included). A picture
// lists as "[[ binary data 48 KiB png 800x600 ]]" (cliphist's preview); its thumbnail is decoded into
// the runtime folder (memory, gone at logout), the newest 40 only, and thumbnails of entries gone go too.
Singleton {
    id: root
    property var history: [] // { id, text } or { id, text: "Picture 800 × 600", picture, format, size, width, height, thumb }
    readonly property string thumbDir: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/pistachio-clipboard`

    function loadHistory() { if (ShellSettings.clipboardHistory) historyReader.exec({ command: historyReader.command }); }
    function restoreHistory(id) {
        const item = history.find(h => h.id === id);
        if (item?.picture)
            Quickshell.execDetached(["sh", "-c", 'cliphist decode "$1" | wl-copy --type "image/$2"', "sh", id, item.format]);
        else
            Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | cliphist decode | wl-copy', "sh", id]);
    }
    function clearHistory() { clearReader.running = true; }

    // one cliphist list line, or null
    function entry(line: string): var {
        const tab = line.indexOf("\t");
        const id = tab > 0 ? line.slice(0, tab) : "";
        if (!/^\d+$/.test(id))
            return null;
        const text = line.slice(tab + 1);
        const m = /^\[\[ binary data (\S+ \S+) (\w+) (\d+)x(\d+) \]\]$/.exec(text);
        if (!m)
            return { id: id, text: text };
        return { id: id, text: `Picture ${m[3]} × ${m[4]}`, picture: true, format: m[2].toLowerCase(), size: m[1], width: Number(m[3]), height: Number(m[4]), thumb: "" };
    }

    Process { command: ["wl-paste", "--type", "text", "--watch", "cliphist", "store"]; running: ShellSettings.clipboardHistory }
    Process { command: ["wl-paste", "--type", "image", "--watch", "cliphist", "store"]; running: ShellSettings.clipboardHistory && ShellSettings.clipboardPictures }
    Process {
        id: historyReader
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!ShellSettings.clipboardHistory)
                    return;
                root.history = text.split("\n").map(line => root.entry(line)).filter(item => item);
                root.makeThumbs();
            }
        }
    }

    // Decodes the missing thumbnails (as <id>.<format>), drops the ones of entries gone, then shows them.
    function makeThumbs() {
        const files = history.filter(h => h.picture).slice(0, 40).map(h => `${h.id}.${h.format}`);
        thumbMaker.exec({ command: ["sh", "-c", 'dir=$1; shift; [ $# -gt 0 ] || { rm -rf "$dir"; exit 0; }; mkdir -p -m 700 "$dir" || exit 1\n'
            + 'for old in "$dir"/*; do case " $* " in *" ${old##*/} "*) ;; *) rm -f "$old" ;; esac; done\n'
            + 'for f; do [ -s "$dir/$f" ] || { cliphist decode "${f%%.*}" > "$dir/$f.part" && mv "$dir/$f.part" "$dir/$f"; }; done',
            "sh", thumbDir].concat(files) });
    }
    Process {
        id: thumbMaker
        onExited: (code, status) => {
            const made = root.history.filter(h => h.picture).slice(0, 40).map(h => h.id);
            root.history = root.history.map(h => made.includes(h.id) ? Object.assign({}, h, { thumb: `${root.thumbDir}/${h.id}.${h.format}` }) : h);
        }
    }
    Process {
        id: clearReader
        command: ["sh", "-c", 'cliphist wipe && rm -rf "$1"', "sh", root.thumbDir]
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
