pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Blue-light filter. The shell runs hyprsunset itself while night light is on; stopping it restores
// normal colours. Warmth changes while it runs go over its IPC (`hyprctl hyprsunset temperature`).
// On/off, warmth and the schedule are kept in Store.
//
// The schedule switches it on at `from` and off at `to` (minutes after midnight; `to` may be the next
// morning). It only acts at those two moments, so switching by hand holds until the next one; when
// the shell starts or the schedule changes, it is set to match.
Singleton {
    id: root

    readonly property bool enabled: Store.saved.nightLight && available
    readonly property int temperature: Store.saved.temperature // kelvin, 2500–6500
    property bool available: false // hyprsunset is installed
    property int pending: -1

    readonly property bool scheduled: Store.saved.nightSchedule
    readonly property int from: Store.saved.nightFrom
    readonly property int to: Store.saved.nightTo
    readonly property bool inSchedule: scheduled && within(clock.date)
    property bool wanted // what the schedule last asked for
    // for the quick settings tile and the launcher: "Until 07:00", "4000 K", "From 20:00", "Off"
    readonly property string status: !available ? "Not installed"
        : enabled && inSchedule ? `Until ${timeText(to)}`
        : enabled ? `${temperature} K`
        : scheduled ? `From ${timeText(from)}`
        : "Off"
    readonly property string scheduleText: scheduled ? `${timeText(from)}–${timeText(to)}` : "Off"

    function setEnabled(on: bool) {
        Store.saved.nightLight = on && available;
    }

    function setTemperature(k: int) {
        Store.saved.temperature = k;
        if (!enabled)
            return; // used when it next starts
        pending = k;
        if (!ipc.running)
            flush();
    }

    function setSchedule(on: bool, start: int, end: int) {
        Store.saved.nightSchedule = on;
        Store.saved.nightFrom = (start + 1440) % 1440;
        Store.saved.nightTo = (end + 1440) % 1440;
        follow(true);
    }

    function within(d): bool {
        const m = d.getHours() * 60 + d.getMinutes();
        return from <= to ? m >= from && m < to : m >= from || m < to;
    }

    // "07:00"
    function timeText(m: int): string {
        return `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
    }

    // Switch when the schedule's answer changes (or always, when `force`).
    function follow(force: bool) {
        if (!scheduled || !Store.ready || !available)
            return;
        const w = within(clock.date);
        if (force || w !== wanted)
            setEnabled(w);
        wanted = w;
    }

    function flush() {
        if (pending < 0)
            return;
        ipc.command = ["hyprctl", "hyprsunset", "temperature", String(pending)];
        pending = -1;
        ipc.running = true;
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
        onDateChanged: root.follow(false)
    }

    // match the schedule once the saved settings are in and hyprsunset is known to exist
    readonly property bool started: Store.ready && available
    onStartedChanged: if (started) follow(true)

    Process {
        running: true
        command: ["sh", "-c", "command -v hyprsunset"]
        onExited: code => root.available = code === 0
    }

    Process {
        running: root.enabled
        command: ["hyprsunset", "--temperature", String(root.temperature)]
        // also covers it dying on its own, e.g. when another hyprsunset already runs
        onExited: Store.saved.nightLight = false
    }

    Process {
        id: ipc
        onExited: root.flush()
    }
}
