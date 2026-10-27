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

    function isCritical(n): bool {
        return n.urgency === NotificationUrgency.Critical;
    }

    function received(n): real {
        return n.saved ? n.time : receivedAt[n.id] ?? 0;
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
        return { saved: true, summary: n.summary, body: n.body, appName: n.appName, appIcon: n.appIcon, image: file ? n.image : "", urgency: n.urgency, time: received(n) };
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
    }

    onNotificationsChanged: if (historyLoaded) Store.saved.notifications = notifications.slice(0, 50).map(n => record(n))

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
            if ((!root.quiet || root.isCritical(n)) && !n.lastGeneration)
                root.popups = root.popups.filter(p => p !== n).concat([n]);
        }
    }
}
