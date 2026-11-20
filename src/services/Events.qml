pragma Singleton

import qs
import Quickshell
import Quickshell.Io
import QtQuick

// GNOME Calendar's events for the month calendar (owner's request, 11 November 2026): every calendar
// in Evolution Data Server, read-only, by `psc events` (rust/psc/src/events.rs; Python's events.py until 20 November 2026). Read when the month calendar shows a
// month, again as the notification centre opens, and each minute while it is on screen. Off with Settings → Integrations.
Singleton {
    id: root

    // GNOME Calendar installed and the helper able to read (EDS's libraries present)
    readonly property var app: Apps.list.find(a => a.id === "org.gnome.Calendar") ?? null
    property bool readable: true
    readonly property bool available: app !== null && readable
    readonly property bool enabled: available && ShellSettings.calendarEvents
    property var calendars: [] // { uid, name, color }
    property var events: [] // { calendar, title, location, start, end, allDay }
    property var byDay: ({}) // "yyyy-MM-dd" -> events on that day, all-day first
    property string range // the "from to" last asked for
    property string pending

    // the events of the weeks around a month: the grid shows parts of the months either side
    function load(year: int, month: int) {
        if (!enabled)
            return;
        const from = new Date(year, month, 1 - 7);
        const to = new Date(year, month + 1, 1 + 14);
        pending = `${Qt.formatDate(from, "yyyy-MM-dd")} ${Qt.formatDate(to, "yyyy-MM-dd")}`;
        if (!reader.running)
            start();
    }

    function refresh() {
        if (enabled && range && !reader.running) {
            pending = range;
            start();
        }
    }

    function start() {
        range = pending;
        pending = "";
        reader.command = [Quickshell.env("HOME") + "/.local/bin/psc", "events"].concat(range.split(" "));
        reader.running = true;
    }

    function key(d: date): string {
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    function on(d: date): var {
        return byDay[key(d)] ?? [];
    }

    // a calendar's colour, as the nearest of the palette's accents (pistachio stays for active state)
    function colourFor(uid: string): color {
        const cal = calendars.find(c => c.uid === uid);
        const accents = [Theme.sageBlue, Theme.teal, Theme.lavender, Theme.clay, Theme.gold, Theme.terracotta];
        if (Theme.noir) // Noir keeps its one colour for errors
            return Theme.subtext;
        if (!cal || !cal.color)
            return Theme.sageBlue;
        const c = Qt.color(cal.color);
        if (c.hsvSaturation < 0.15)
            return Theme.subtext;
        let best = accents[0], gap = 2;
        for (const a of accents) {
            const d = Math.abs(a.hsvHue - c.hsvHue);
            const g = Math.min(d, 1 - d);
            if (g < gap) {
                gap = g;
                best = a;
            }
        }
        return best;
    }

    function calendarName(uid: string): string {
        return calendars.find(c => c.uid === uid)?.name ?? "";
    }

    function open() {
        if (app)
            app.execute();
    }

    onEnabledChanged: if (!enabled) {
        events = [];
        byDay = {};
    }

    Timer {
        // a reading taken while the calendar is open
        interval: 60000
        repeat: true
        running: root.enabled && root.watching
        onTriggered: root.refresh()
    }

    property bool watching // the month calendar is on screen

    Process {
        id: reader
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.calendars = d.calendars ?? [];
                    root.events = d.events ?? [];
                    const days = {};
                    for (const e of root.events) {
                        // an event shows on every day it touches; its end is exclusive
                        const first = new Date(e.start);
                        const last = new Date(Math.max(e.start, e.end - 1));
                        for (let day = new Date(first.getFullYear(), first.getMonth(), first.getDate()); day <= last; day.setDate(day.getDate() + 1)) {
                            const k = root.key(day);
                            (days[k] = days[k] ?? []).push(e);
                        }
                    }
                    for (const k in days)
                        days[k].sort((a, b) => (b.allDay - a.allDay) || a.start - b.start);
                    root.byDay = days;
                } catch (e) {
                    if (text.trim())
                        console.warn("events:", text.slice(0, 200));
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (/events: unavailable|unrecognized subcommand/.test(text)) root.readable = false // EDS missing, or a psc from before the port
        }
        onExited: if (root.pending) root.start()
    }
}
