pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// `kill <name>` in the launcher (owner's pick, 8 November 2026): your own running programs, the
// busiest first, read with ps each time the search changes; ending one sends SIGTERM (or SIGKILL).
Singleton {
    id: root

    property var list: [] // { pid, cpu (%), memory (MB), name, command }; the shell and its helpers left out
    // the same, one per program name, busiest first: what `kill` ends all of at once, like killall
    // (owner's request, 12 November 2026): { name, pids, cpu, memory, command }
    readonly property var groups: {
        const by = {}, out = [];
        for (const p of list) {
            let g = by[p.name];
            if (!g) {
                g = by[p.name] = { name: p.name, pids: [], cpu: 0, memory: 0, command: p.command };
                out.push(g);
            }
            g.pids.push(p.pid);
            g.cpu += p.cpu;
            g.memory += p.memory;
        }
        return out.sort((a, b) => b.cpu - a.cpu);
    }

    function load() {
        reader.exec({ command: reader.command }); // stops a reading still going, unlike running off and on
    }

    function end(p, force: bool) {
        Quickshell.execDetached(["kill", force ? "-KILL" : "-TERM", String(p.pid)]);
        list = list.filter(x => x.pid !== p.pid);
    }

    // every process of a group, by its process ids rather than `killall <name>`, so the shell and its
    // own helpers (a python3 agent, say) never go with them
    function endAll(g, force: bool) {
        Quickshell.execDetached(["kill", force ? "-KILL" : "-TERM"].concat(g.pids.map(String)));
        list = list.filter(x => !g.pids.includes(x.pid));
    }

    Process {
        id: reader
        command: ["sh", "-c", 'ps -u "$(id -u)" -o pid=,ppid=,pcpu=,rss=,comm=,args= --sort=-pcpu']
        stdout: StdioCollector {
            onStreamFinished: {
                const all = [];
                for (const line of text.split("\n")) {
                    const m = /^\s*(\d+)\s+(\d+)\s+([\d.]+)\s+(\d+)\s+(\S+)\s+(.*)$/.exec(line);
                    if (m && m[5] !== "ps" && m[5] !== "sh")
                        all.push({ pid: parseInt(m[1]), ppid: parseInt(m[2]), cpu: parseFloat(m[3]), memory: parseInt(m[4]) / 1024, name: m[5], command: m[6] });
                }
                // the shell and everything it started (its helpers, and theirs)
                const own = new Set([Quickshell.processId]);
                for (let grew = true; grew;) {
                    grew = false;
                    for (const p of all)
                        if (!own.has(p.pid) && own.has(p.ppid)) {
                            own.add(p.pid);
                            grew = true;
                        }
                }
                root.list = all.filter(p => !own.has(p.pid));
            }
        }
    }
}
