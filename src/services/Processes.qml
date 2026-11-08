pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// `kill <name>` in the launcher (owner's pick, 8 November 2026): your own running programs, the
// busiest first, read with ps each time the search changes; ending one sends SIGTERM (or SIGKILL).
Singleton {
    id: root

    property var list: [] // { pid, cpu (%), memory (MB), name, command }

    function load() {
        reader.exec({ command: reader.command }); // stops a reading still going, unlike running off and on
    }

    function end(p, force: bool) {
        Quickshell.execDetached(["kill", force ? "-KILL" : "-TERM", String(p.pid)]);
        list = list.filter(x => x.pid !== p.pid);
    }

    Process {
        id: reader
        command: ["sh", "-c", 'ps -u "$(id -u)" -o pid=,pcpu=,rss=,comm=,args= --sort=-pcpu']
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    const m = /^\s*(\d+)\s+([\d.]+)\s+(\d+)\s+(\S+)\s+(.*)$/.exec(line);
                    if (m && m[4] !== "ps" && m[4] !== "sh")
                        out.push({ pid: parseInt(m[1]), cpu: parseFloat(m[2]), memory: parseInt(m[3]) / 1024, name: m[4], command: m[5] });
                }
                root.list = out;
            }
        }
    }
}
