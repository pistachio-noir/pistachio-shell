pragma Singleton

import Quickshell
import Quickshell.Services.Notifications
import QtQuick

// The notification daemon. Only one program can own org.freedesktop.Notifications: stop any other first.
// History survives restarts: notifications from before come back from Store as plain records
// (`saved: true`, no actions); a live reload keeps the real ones.
Singleton {
    id: root

    // new notifications are kept but not shown as popups, except critical ones
    readonly property bool dnd: Store.saved.dnd
    // the same while a fullscreen window has focus, if the shell setting is on
    readonly property bool quiet: dnd || ShellSettings.quietFullscreen && Compositor.fullscreen
    // Do not disturb's schedule (owner's request, after phase 8): on at dndFrom, off at dndTo, with its
    // own times or night light's. Like night light's, it only acts at those two moments, so switching
    // by hand holds until the next one; when the shell starts or the times change, it is set to match.
    readonly property bool dndScheduled: Store.saved.dndSchedule
    readonly property bool dndFollowsNight: Store.saved.dndFollowsNight
    readonly property int dndFrom: dndFollowsNight ? NightLight.from : Store.saved.dndFrom
    readonly property int dndTo: dndFollowsNight ? NightLight.to : Store.saved.dndTo
    readonly property bool inDndSchedule: dndScheduled && NightLight.within(clock.date, dndFrom, dndTo)
    property bool dndWanted // what the schedule last asked for
    // for the quick settings tile and the launcher: "Until 07:00", "On", "From 22:00", "Off"
    readonly property string dndStatus: dnd && inDndSchedule ? `Until ${NightLight.timeText(dndTo)}`
        : dnd ? "On"
        : dndScheduled ? `From ${NightLight.timeText(dndFrom)}`
        : "Off"
    readonly property string dndScheduleText: dndScheduled ? `${NightLight.timeText(dndFrom)}–${NightLight.timeText(dndTo)}` : "Off"
    // changes whenever the schedule does, night light's times included
    readonly property string dndPlan: Store.ready && dndScheduled ? `${dndFrom} ${dndTo}` : ""
    onDndPlanChanged: followDnd(true)
    // records from before the last restart, newest first
    property var saved: []
    property bool historyLoaded // until then, saving would overwrite the saved history
    readonly property var live: server.trackedNotifications.values.slice().reverse()
    // every notification held, newest first
    readonly property var notifications: live.concat(saved)
    // the ones showing as popups, oldest first
    property var popups: []
    // Opening the centre marks everything seen. seenBefore is the previous mark, for the centre's
    // "new since last time" dots.
    property real seenAt: Date.now()
    property real seenBefore: Date.now()
    property var receivedAt: ({}) // notification id -> ms since epoch
    readonly property bool unread: notifications.some(n => received(n) > seenAt)
    // how many, for the lock screen (owner's request, after phase 8: the count only, no content)
    readonly property int unreadCount: notifications.filter(n => received(n) > seenAt).length

    function isCritical(n): bool {
        return n.urgency === NotificationUrgency.Critical;
    }

    // Per-app rules (owner's request, after phase 8), by app name, set from a card's right click:
    // silenced until a time, or no toasts until undone. The notifications still reach the centre, and
    // critical ones still show. The launcher's System mode lists them to undo.
    readonly property var rules: Store.saved.notificationRules ?? ({})

    function quietFor(app: string): bool {
        const r = rules[app];
        return !!r && (r.noToasts || r.until > Date.now());
    }

    function setRule(app: string, rule) {
        const all = Object.assign({}, rules);
        if (rule)
            all[app] = rule;
        else
            delete all[app];
        Store.saved.notificationRules = all;
    }

    // "No toasts", "Silenced until 11:30"
    function ruleText(app: string): string {
        const r = rules[app];
        return !r ? "" : r.noToasts ? "No toasts" : `Silenced until ${Qt.formatTime(new Date(r.until), "hh:mm")}`;
    }

    // The choices on a card's right click, shaped like its actions ({ text, invoke() }) so they share
    // its button row; `rule` marks them.
    function ruleChoices(app: string): var {
        const r = rules[app];
        return [
            r?.until ? { rule: true, text: "Unsilence", invoke: () => setRule(app, null) } : { rule: true, text: "Silence 1 h", invoke: () => setRule(app, { until: Date.now() + 3600000 }) },
            r?.noToasts ? { rule: true, text: "Toasts again", invoke: () => setRule(app, null) } : { rule: true, text: "No toasts", invoke: () => setRule(app, { noToasts: true }) },
            { rule: true, cancel: true, text: "Cancel", invoke: () => {} }
        ];
    }

    // silences that ran out
    function pruneRules() {
        const now = Date.now();
        if (Object.values(rules).some(r => r.until && r.until <= now))
            Store.saved.notificationRules = Object.fromEntries(Object.entries(rules).filter(([, r]) => !r.until || r.until > now));
    }

    // the shell's own screenshot notification (Screenshots): it shows even while quiet
    function own(n): bool {
        return preview(n) !== "";
    }

    // the screenshot's file, for a preview in the toast and the centre; "" for other notifications
    function preview(n): string {
        return (n.saved ? n.preview : n.hints?.["x-pistachio-screenshot"]) ?? "";
    }

    function received(n): real {
        return n.saved ? n.time : receivedAt[n.id] ?? 0;
    }

    function setDndSchedule(on: bool) {
        Store.saved.dndSchedule = on;
    }

    function setDndFollowsNight(on: bool) {
        Store.saved.dndFollowsNight = on;
    }

    // its own times, used while it doesn't follow night light's
    function setDndTimes(start: int, end: int) {
        Store.saved.dndFrom = (start + 1440) % 1440;
        Store.saved.dndTo = (end + 1440) % 1440;
    }

    // Switch when the schedule's answer changes (or always, when `force`).
    function followDnd(force: bool) {
        if (!dndScheduled || !Store.ready)
            return;
        const w = NightLight.within(clock.date, dndFrom, dndTo);
        if (force || w !== dndWanted)
            setDnd(w);
        dndWanted = w;
    }

    function setDnd(on: bool) {
        Store.saved.dnd = on;
    }

    // a live notification or a saved record
    function dismiss(n) {
        if (n.saved)
            saved = saved.filter(r => r !== n);
        else
            n.dismiss();
    }

    function markSeen() {
        seenBefore = seenAt;
        seenAt = Date.now();
        popups = [];
    }

    function hidePopup(n) {
        popups = popups.filter(p => p !== n);
    }

    function clearAll() {
        saved = [];
        for (const n of server.trackedNotifications.values.slice())
            n.dismiss();
    }

    // one app's notifications, from the notification centre's group header
    function clearApp(app: string) {
        saved = saved.filter(r => (r.appName ?? "") !== app);
        for (const n of server.trackedNotifications.values.slice()) {
            if ((n.appName ?? "") === app)
                n.dismiss();
        }
    }

    function same(record, n): bool {
        return record.summary === n.summary && record.body === n.body && record.appName === n.appName;
    }

    // what's kept of a notification: no actions, and only an image that is a file (others are
    // generated for this run and gone after it)
    function record(n) {
        if (n.saved)
            return n;
        const file = n.image.startsWith("/") || n.image.startsWith("file:");
        return { saved: true, summary: n.summary, body: n.body, appName: n.appName, appIcon: n.appIcon, image: file ? n.image : "", urgency: n.urgency, time: received(n), preview: preview(n) };
    }

    // Once Store has loaded: bring back the saved records, except the ones a live reload kept (those
    // take the saved time instead).
    function loadHistory() {
        const times = Object.assign({}, receivedAt);
        saved = (Store.saved.notifications ?? []).filter(r => {
            const n = live.find(l => same(r, l));
            if (n)
                times[n.id] = r.time;
            return !n;
        }).map(r => Object.assign({}, r, { saved: true }));
        receivedAt = times;
        historyLoaded = true;
        pruneOld();
    }

    // The last 200 are kept across restarts (50 until the launcher could search them), and any older
    // than a week go by themselves, from the centre too (owner's request, after phase 8). One whose
    // time isn't known (kept over a reload without a record) stays.
    readonly property int keepCount: 200
    readonly property real keepFor: 7 * 24 * 3600000

    function pruneOld() {
        const cutoff = Date.now() - keepFor;
        const old = t => t > 0 && t < cutoff;
        if (saved.some(r => old(r.time)))
            saved = saved.filter(r => !old(r.time));
        for (const n of server.trackedNotifications.values.slice()) {
            if (old(receivedAt[n.id] ?? 0))
                n.dismiss();
        }
    }

    // "now", "2 min", "1 h", "3 d" since `ms`; "" when it isn't known
    function age(ms: real, now: date): string {
        if (ms <= 0)
            return "";
        const min = Math.floor((now.getTime() - ms) / 60000);
        return min < 1 ? "now" : min < 60 ? `${min} min` : min < 1440 ? `${Math.floor(min / 60)} h` : `${Math.floor(min / 1440)} d`;
    }

    onNotificationsChanged: if (historyLoaded) Store.saved.notifications = notifications.slice(0, keepCount).map(n => record(n))

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
        onDateChanged: {
            root.followDnd(false);
            root.pruneRules();
            if (root.historyLoaded)
                root.pruneOld();
        }
    }

    Connections {
        target: Store

        function onReadyChanged() {
            if (Store.ready)
                root.loadHistory();
        }
    }

    Component.onCompleted: if (Store.ready) loadHistory()

    // The default action is what clicking the notification does; the rest become buttons.
    function invokeDefault(n) {
        n.actions.find(a => a.identifier === "default")?.invoke();
    }

    // An image source for the notification: its image, else its app icon, else "". An icon name sent
    // as the image (notify-send -i does) arrives as an unchecked "image://icon/…", which draws
    // Quickshell's magenta checkerboard when the theme lacks it, so it only counts if the theme has it.
    function iconSource(n): string {
        const themed = n.image.startsWith("image://icon/") ? Quickshell.iconPath(n.image.slice(13), true) : n.image;
        if (themed)
            return themed;
        if (n.appIcon.startsWith("/") || n.appIcon.includes("://"))
            return n.appIcon;
        return n.appIcon ? Quickshell.iconPath(n.appIcon, true) : "";
    }

    NotificationServer {
        id: server

        actionsSupported: true
        imageSupported: true
        // body markup stays off; it is shown as plain text

        onNotification: n => {
            n.tracked = true;
            n.closed.connect(() => root.hidePopup(n));
            // after a shell reload old notifications come back; they are not new, and keep a saved time
            const kept = n.lastGeneration ? root.saved.find(r => root.same(r, n)) : null;
            if (kept)
                root.saved = root.saved.filter(r => r !== kept);
            root.receivedAt = Object.assign({}, root.receivedAt, { [n.id]: n.lastGeneration ? kept?.time ?? 0 : Date.now() });
            // a toast unless something keeps it quiet: Do not disturb, fullscreen or the app's rule;
            // critical ones and the shell's own always show
            const shows = root.isCritical(n) || root.own(n) || !root.quiet && !root.quietFor(n.appName ?? "");
            if (shows && !n.lastGeneration)
                root.popups = root.popups.filter(p => p !== n).concat([n]);
        }
    }
}
