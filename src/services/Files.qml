pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Files and folders in the home folder, for the launcher's "/" search (owner's request, after phase
// 8). `psc files` (rust/psc/src/files.rs) lists the folder as it starts and answers each query; matching ~20,000 names
// in QML took ~90 ms a keystroke, too slow to type over. It runs only while the launcher shows the
// search (setActive), so each new search sees the folder as it is now.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    property bool active
    property bool ready // listed: `count` entries
    property int count
    property string query // the last query asked
    // the answer to it, best first: { path (from home), name, folder }; the previous answer until it comes
    property var results: []

    function setActive(on: bool) {
        active = on;
        if (!on) {
            ready = false;
            query = "";
            results = [];
        }
    }

    function search(q: string) {
        query = q;
        if (q === "")
            results = [];
        else
            helper.write(JSON.stringify({ query: q }) + "\n"); // read once the listing is done
    }

    function heard(line: string) {
        const m = JSON.parse(line);
        if (m.event === "ready") {
            count = m.count;
            ready = true;
            if (query) // asked as it started, perhaps before it could read
                search(query);
        } else if (m.query === query) { // older answers are already out of date
            results = m.results.map(r => ({ path: r[1], name: r[1].slice(r[1].lastIndexOf("/") + 1), folder: r[0] === "d" }));
        }
    }

    // "~/Documents/Notes" for "Documents/Notes/a.md", "~" for a file in the home folder itself
    function place(entry): string {
        const at = entry.path.lastIndexOf("/");
        return at < 0 ? "~" : "~/" + entry.path.slice(0, at);
    }

    // in its app, or a folder in the file manager
    function open(entry) {
        Quickshell.execDetached(["xdg-open", home + "/" + entry.path]);
    }

    // Pistachio FM, when installed: given a file, it opens its folder with the file selected (owner's
    // call, 28 November 2026: "Show in Files"). Quickshell drops the entry's %U from `command`.
    readonly property var filesApp: Apps.list.find(a => a.id === "pistachio-fm") ?? null

    // the folder it is in, in the file manager: a file in Pistachio FM, selected there; otherwise (a
    // folder, or no FM) the folder by xdg-open (FileManager1's ShowItems would pick the file there, but
    // on this machine it starts Nautilus)
    function reveal(entry) {
        if (filesApp && !entry.folder) {
            Quickshell.execDetached({ command: Array.from(filesApp.command).concat([home + "/" + entry.path]), workingDirectory: home });
            return;
        }
        const at = entry.path.lastIndexOf("/");
        Quickshell.execDetached(["xdg-open", at < 0 ? home : home + "/" + entry.path.slice(0, at)]);
    }

    Process {
        id: helper
        running: root.active
        command: [Quickshell.env("HOME") + "/.local/bin/psc", "files"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => root.heard(data)
        }
        stderr: SplitParser {
            onRead: data => console.warn("files:", data)
        }
    }
}
