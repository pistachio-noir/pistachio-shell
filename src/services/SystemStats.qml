pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// CPU, memory and GPU load for the launcher's System monitor card. services/stats.sh takes a reading
// (/proc for the CPU and memory, the CPU's hwmon sensor, nvidia-smi for an NVIDIA card); it runs
// every 1.5 s, and only while something shows the readings (setWatching).
Singleton {
    id: root

    property bool watching
    property string cpuName // e.g. "i5-9400F", "Ryzen 7 5800X"
    property real cpu: -1 // 0–1; -1 until two readings give a difference
    property real cpuTemp: -1 // °C; -1 without a sensor
    property real memUsed // GiB
    property real memTotal
    property bool gpuFound
    property string gpuName // e.g. "GeForce GTX 1660"
    property real gpu // 0–1
    property real gpuTemp // °C
    property real vramUsed // GiB
    property real vramTotal
    property var last: null // the previous CPU counters: [busy, total]

    function setWatching(on: bool) {
        watching = on;
        if (!on)
            last = null; // a load since minutes ago would mislead
    }

    function parse(text: string) {
        for (const line of text.trim().split("\n")) {
            const f = line.trim().split(/\s+/);
            if (f[0] === "stat") {
                // user nice system idle iowait irq softirq steal (guest time is already in user)
                const c = f.slice(2, 10).map(Number);
                const total = c.reduce((a, b) => a + b, 0);
                const busy = total - c[3] - c[4];
                if (last && total > last[1])
                    cpu = (busy - last[0]) / (total - last[1]);
                else if (!last)
                    again.restart(); // the first reading only sets the baseline
                last = [busy, total];
            } else if (f[0] === "mem") {
                memTotal = Number(f[1]) / 1048576;
                memUsed = (Number(f[1]) - Number(f[2])) / 1048576;
            } else if (f[0] === "model") {
                cpuName = line.slice(6).replace(/\((R|TM)\)/g, "").replace(/ CPU| Processor|\s*@.*$|\s+\d+-Core/g, "").replace(/\s+/g, " ").trim().replace(/^(Intel|AMD) (Core )?/, "");
            } else if (f[0] === "temp") {
                cpuTemp = Number(f[1]) / 1000;
            } else if (f[0] === "gpu") {
                const g = line.slice(4).split(",").map(x => x.trim());
                gpuName = g[0].replace(/^NVIDIA /, "");
                gpu = Number(g[1]) / 100;
                gpuTemp = Number(g[2]);
                vramUsed = Number(g[3]) / 1024;
                vramTotal = Number(g[4]) / 1024;
                gpuFound = true;
            }
        }
    }

    Timer {
        running: root.watching
        interval: 1500
        repeat: true
        triggeredOnStart: true
        onTriggered: reader.running = true
    }

    // a second reading soon after the first, so the CPU's load shows without a long wait
    Timer {
        id: again
        interval: 400
        onTriggered: reader.running = true
    }

    Process {
        id: reader
        command: ["sh", Quickshell.shellPath("services/stats.sh")]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }
}
