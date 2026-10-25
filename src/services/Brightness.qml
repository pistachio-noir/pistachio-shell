pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Monitor brightness over DDC/CI with ddcutil: a desktop monitor has no /sys/class/backlight.
Singleton {
    id: root

    property real value: 0 // 0–1
    property bool available: false // false until the monitor answers
    property int max: 100
    property int pending: -1

    // Re-read the monitor, e.g. after its own buttons changed it.
    function refresh() {
        reader.running = true;
    }

    function set(v: real) {
        value = Math.max(0, Math.min(1, v));
        pending = Math.round(value * max);
        if (!writer.running)
            flush();
    }

    function flush() {
        if (pending < 0)
            return;
        writer.command = ["ddcutil", "setvcp", "10", String(pending), "--noverify"];
        pending = -1;
        writer.running = true;
    }

    // `ddcutil getvcp 10 --brief` prints "VCP 10 C <current> <max>"
    Process {
        id: reader
        running: true
        command: ["ddcutil", "getvcp", "10", "--brief"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(" ");
                root.available = f.length === 5 && f[0] === "VCP" && Number(f[4]) > 0;
                if (root.available) {
                    root.max = Number(f[4]);
                    root.value = Number(f[3]) / root.max;
                }
            }
        }
    }

    // Each ddcutil call takes ~0.2 s, so run one at a time; a slider drag sends only its latest value.
    Process {
        id: writer
        onExited: root.flush()
    }
}
