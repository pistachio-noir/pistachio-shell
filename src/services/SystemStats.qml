pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// CPU, memory, GPU and disk readings for the launcher's System monitor card. services/stats.sh takes
// a reading (/proc for the CPU and memory, the CPU's hwmon sensor, nvidia-smi for an NVIDIA card, df
// for / and /home); it runs every 1.5 s while something shows the readings (setWatching), and every
// 30 s in the background for the warnings.
Singleton {
    id: root

    property bool watching
    property string cpuName // e.g. "i5-9400F", "Ryzen 7 5800X"
    property real cpu: -1 // 0–1; -1 until two readings give a difference
    property real cpuTemp: -1 // °C; -1 without a sensor
    property real memUsed // GiB
    // the shell itself with its helpers (owner's request, 3 November 2026): CPU 0–1 of the whole
    // machine (-1 until two readings), memory in MiB
    property real shellCpu: -1
    property real shellMem
    property var lastShell: null // [ticks, ms]
    // Hyprland, the same way (owner's request, 12 November 2026); hyprMem 0 while it isn't found
    property real hyprCpu: -1
    property real hyprMem
    property var lastHypr: null
    property int cores: 1
    property real memTotal
    property bool gpuFound
    property string gpuName // e.g. "GeForce GTX 1660"
    property real gpu // 0–1
    property real gpuTemp // °C
    property real vramUsed // GiB
    property real vramTotal
    // / and /home, or only / when /home is on the same filesystem (btrfs subvolumes are): each
    // { mount, size, free } in GiB, and `low` under 10 % free (owner's request, after phase 8)
    property var disks: []
    // their mount points, which change far less often: the launcher's rows are built from these
    property var diskMounts: []
    property var last: null // the previous CPU counters: [busy, total]
    // Warnings (owner's request, after phase 8), as notifications: a disk under 10 % free (again only
    // once it has been back over 12 %), and the CPU or GPU at 85 °C or more for a minute (again only
    // once it has cooled under 75 °C). Checked with every reading.
    property var warned: ({}) // "disk:/", "cpu", "gpu" -> true while warned about
    property var hotSince: ({}) // "cpu", "gpu" -> when it reached 85 °C (ms since epoch)

    function setWatching(on: bool) {
        watching = on;
        if (!on)
            last = null; // a load since minutes ago would mislead
    }

    function parse(text: string) {
        const found = [];
        for (const line of text.trim().split("\n")) {
            const f = line.trim().split(/\s+/);
            if (f[0] === "stat") {
                // user nice system idle iowait irq softirq steal (guest time is already in user)
                const c = f.slice(2, 10).map(Number);
                const total = c.reduce((a, b) => a + b, 0);
                const busy = total - c[3] - c[4];
                if (last && total > last[1])
                    cpu = (busy - last[0]) / (total - last[1]);
                else if (!last && watching)
                    again.restart(); // the first reading only sets the baseline
                last = [busy, total];
            } else if (f[0] === "shell") {
                const ticks = Number(f[1]), now = Date.now();
                if (lastShell && now > lastShell[1])
                    shellCpu = Math.min(1, (ticks - lastShell[0]) / 100 / ((now - lastShell[1]) / 1000) / Math.max(1, Number(f[3])));
                lastShell = [ticks, now];
                shellMem = Number(f[2]) / 1024;
                cores = Math.max(1, Number(f[3]));
            } else if (f[0] === "hypr") {
                const ticks = Number(f[1]), now = Date.now();
                if (lastHypr && now > lastHypr[1])
                    hyprCpu = Math.min(1, (ticks - lastHypr[0]) / 100 / ((now - lastHypr[1]) / 1000) / cores);
                lastHypr = [ticks, now];
                hyprMem = Number(f[2]) / 1024;
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
            } else if (f[0] === "disk" && !found.some(d => d.device === f[1])) {
                const size = Number(f[2]) / 1048576, free = Number(f[3]) / 1048576;
                found.push({ device: f[1], mount: f[4], size: size, free: free, low: free < 0.1 * size });
            }
        }
        disks = found;
        if (found.map(d => d.mount).join(" ") !== diskMounts.join(" "))
            diskMounts = found.map(d => d.mount);
        check();
    }

    function check() {
        const w = Object.assign({}, warned);
        for (const d of disks) {
            const key = "disk:" + d.mount;
            if (d.low && !w[key]) {
                w[key] = true;
                const which = d.mount === "/" ? (disks.length === 1 ? "The disk" : "The system disk") : "Home";
                warn(`${which} is almost full`, `${gigabytes(d.free)} left of ${gigabytes(d.size)} (${Math.round(100 * d.free / d.size)} %)`, "drive-harddisk");
            } else if (w[key] && d.free >= 0.12 * d.size) {
                delete w[key];
            }
        }
        heat(w, "cpu", "CPU", cpuTemp);
        if (gpuFound)
            heat(w, "gpu", "GPU", gpuTemp);
        warned = w;
    }

    function heat(w, key: string, label: string, temp: real) {
        const since = Object.assign({}, hotSince);
        if (temp >= 85) {
            since[key] = since[key] ?? Date.now();
            if (!w[key] && Date.now() - since[key] >= 60000) {
                w[key] = true;
                warn(`${label} running hot`, `${Math.round(temp)} °C for over a minute`, "dialog-warning");
            }
        } else {
            delete since[key];
            if (temp < 75)
                delete w[key];
        }
        hotSince = since;
    }

    function warn(title: string, body: string, icon: string) {
        Quickshell.execDetached(["notify-send", "--app-name=System", `--icon=${icon}`, title, body]);
    }

    // "463 GB", "8.4 GB", "1.8 TB"
    function gigabytes(g: real): string {
        return g >= 1000 ? `${(g / 1024).toFixed(1)} TB` : `${g >= 100 ? Math.round(g) : g.toFixed(1)} GB`;
    }

    // the background reading, for the warnings; while watched, the readings below do
    Timer {
        running: !root.watching
        interval: 30000
        repeat: true
        onTriggered: reader.running = true
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
