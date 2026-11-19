pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Timers, a stopwatch and alarms (owner's request, 9 November 2026). Alarms are GNOME Clocks' own (its
// settings, through `psc clocks`), so both lists are the same; the shell rings them itself, as
// Clocks rings only while it runs, and Clocks' own alarm notifications are hidden (Notifs) so nothing
// rings twice. Timers and the stopwatch run in the shell (Clocks doesn't share its running ones) and
// end with a restart. A ringing alarm or finished timer is `ringing`, for popups/AlarmPopup.qml.
Singleton {
    id: root

    readonly property bool clocksInstalled: Apps.list.some(a => a.id === "org.gnome.clocks")
    // its alarms rung by the shell; off in Settings → Integrations, and Clocks rings them itself again
    readonly property bool enabled: ShellSettings.integration("clocks")
    onEnabledChanged: run(["list"])
    property var alarms: [] // { id, name, hour, minute, days, active }
    property var timers: [] // { id, label, duration (ms), endsAt (ms, while running), left (ms, while paused) }
    property var stopwatch: null // { since (ms, while running), elapsed (ms before it), laps: [ms] }
    property var ringing: null // { kind: "alarm" | "timer", label, time, id }
    property real now: Date.now()

    function left(t): real {
        return t.endsAt ? Math.max(0, t.endsAt - now) : t.left;
    }

    function elapsed(): real {
        return stopwatch ? stopwatch.elapsed + (stopwatch.since ? now - stopwatch.since : 0) : 0;
    }

    // "25:00", "1:02:03"
    function clock(ms: real): string {
        const s = Math.ceil(ms / 1000), two = n => String(n).padStart(2, "0");
        return s >= 3600 ? `${Math.floor(s / 3600)}:${two(Math.floor(s % 3600 / 60))}:${two(s % 60)}` : `${Math.floor(s / 60)}:${two(s % 60)}`;
    }

    // "25m", "1h 30m", "90s", "1:30" (minutes:seconds), "10" (minutes): ms, or 0
    function parseDuration(text: string): real {
        text = text.trim().toLowerCase();
        let m = /^(\d+):(\d{1,2})$/.exec(text);
        if (m)
            return (parseInt(m[1]) * 60 + parseInt(m[2])) * 1000;
        if (/^\d+(\.\d+)?$/.test(text))
            return parseFloat(text) * 60000;
        let total = 0, found = false;
        const re = /(\d+(?:\.\d+)?)\s*(h|hours?|m|min|mins|minutes?|s|sec|secs|seconds?)\b/g;
        while ((m = re.exec(text)) !== null) {
            found = true;
            total += parseFloat(m[1]) * (m[2].startsWith("h") ? 3600000 : m[2].startsWith("m") ? 60000 : 1000);
        }
        // all of it must be a length: "1m tea" isn't one (the caller then tries "1m", and "tea" is the label)
        return found && text.replace(re, "").trim() === "" ? total : 0;
    }

    function startTimer(duration: real, label: string) {
        timers = timers.concat([{ id: String(Date.now()), label: label, duration: duration, endsAt: Date.now() + duration, left: duration }]);
    }

    function pauseTimer(id: string) {
        timers = timers.map(t => t.id !== id ? t : t.endsAt ? Object.assign({}, t, { left: left(t), endsAt: 0 }) : Object.assign({}, t, { endsAt: Date.now() + t.left }));
    }

    function stopTimer(id: string) {
        timers = timers.filter(t => t.id !== id);
    }

    function startStopwatch() {
        stopwatch = { since: Date.now(), elapsed: 0, laps: [] };
    }

    function pauseStopwatch() {
        if (!stopwatch)
            return;
        stopwatch = stopwatch.since ? { since: 0, elapsed: elapsed(), laps: stopwatch.laps } : { since: Date.now(), elapsed: stopwatch.elapsed, laps: stopwatch.laps };
    }

    function lap() {
        if (stopwatch)
            stopwatch = Object.assign({}, stopwatch, { laps: stopwatch.laps.concat([elapsed()]) });
    }

    function stopStopwatch() {
        stopwatch = null;
    }

    function addAlarm(hour: int, minute: int, name: string) {
        run(["add", String(hour), String(minute)].concat(name ? [name] : []));
    }

    function setAlarm(id: string, active: bool) {
        run(["set", id, active ? "active" : "inactive"]);
    }

    function removeAlarm(id: string) {
        run(["remove", id]);
    }

    function openClocks() {
        Quickshell.execDetached(["gnome-clocks"]);
    }

    // the popup's buttons
    function stopRinging() {
        const r = ringing;
        if (!r)
            return;
        if (r.kind !== "alarm") {
            ringing = null;
            return;
        }
        tellClocks("stop", r);
    }

    function snooze() {
        const r = ringing;
        if (!r)
            return;
        if (r.kind !== "alarm") {
            ringing = null;
            snoozed = snoozed.concat([{ at: Date.now() + 10 * 60000, ring: r }]);
            return;
        }
        tellClocks("snooze", r);
    }

    // GNOME Clocks rings its own bell for its alarms: Stop and Snooze go to it too (its stop-alarm and
    // snooze-alarm actions), and the popup closes once it has answered, or failed to (a hung Clocks
    // must not leave the popup up for good).
    function tellClocks(action: string, r) {
        if (stopper.running)
            return;
        stopper.action = action;
        stopper.ring = r;
        stopper.exec({ command: [Quickshell.env("HOME") + "/.local/bin/psc", "clocks", action, r.id] });
    }

    property var snoozed: [] // { at, ring }
    property string lastMinute // so an alarm rings once in its minute

    function run(args) {
        helper.exec({ command: [Quickshell.env("HOME") + "/.local/bin/psc", "clocks"].concat(args) });
    }

    Process {
        id: helper
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.alarms = root.enabled ? JSON.parse(text) : [];
                } catch (e) {
                    console.warn("clocks:", text);
                }
            }
        }
    }

    Process {
        id: stopper
        property string action
        property var ring: null
        onExited: code => {
            const r = ring;
            ring = null;
            if (code !== 0)
                console.warn("clocks: GNOME Clocks did not take", action, "for alarm", r?.id);
            if (root.ringing?.id === r?.id)
                root.ringing = null;
            if (action === "snooze" && r)
                root.snoozed = root.snoozed.concat([{ at: Date.now() + 10 * 60000, ring: r }]);
            root.run(["list"]);
        }
    }

    Component.onCompleted: run(["list"])

    // For keybinds: qs -c pistachio ipc call clocks timer "25m tea", clocks stopwatch (start or stop)
    IpcHandler {
        target: "clocks"

        function timer(text: string): void {
            const words = text.trim().split(/\s+/);
            for (let n = words.length; n > 0; n--) {
                const ms = root.parseDuration(words.slice(0, n).join(" "));
                if (ms > 0) {
                    root.startTimer(ms, words.slice(n).join(" "));
                    return;
                }
            }
        }

        // stops a ringing alarm or finished timer
        function stop(): void {
            root.stopRinging();
        }

        function stopwatch(): void {
            if (root.stopwatch)
                root.stopStopwatch();
            else
                root.startStopwatch();
        }
    }

    // Clocks' alarms change in Clocks too: read them again now and then
    Timer {
        running: true
        interval: 60000
        repeat: true
        onTriggered: root.run(["list"])
    }

    // the second hand: timers count, the stopwatch counts, alarms are checked at each new minute
    Timer {
        running: true
        interval: root.timers.length > 0 || (root.stopwatch?.since ?? 0) ? 250 : 5000
        repeat: true
        onTriggered: {
            root.now = Date.now();
            for (const t of root.timers)
                if (t.endsAt && t.endsAt <= root.now) {
                    root.stopTimer(t.id);
                    root.ringing = { kind: "timer", label: t.label || "Timer", time: root.clock(t.duration), id: t.id };
                }
            const due = root.snoozed.filter(s => s.at <= root.now);
            if (due.length) {
                root.snoozed = root.snoozed.filter(s => s.at > root.now);
                root.ringing = due[0].ring;
            }
            const d = new Date(root.now), minute = `${d.getHours()}:${d.getMinutes()}`;
            if (minute === root.lastMinute)
                return;
            root.lastMinute = minute;
            const iso = d.getDay() === 0 ? 7 : d.getDay();
            for (const a of root.alarms)
                if (a.active && a.hour === d.getHours() && a.minute === d.getMinutes() && (a.days.length === 0 || a.days.includes(iso)))
                    root.ringing = { kind: "alarm", label: a.name || "Alarm", time: `${a.hour}:${String(a.minute).padStart(2, "0")}`, id: a.id, once: a.days.length === 0 };
        }
    }
}
