pragma Singleton

import qs
import Quickshell
import Quickshell.Wayland // IdleMonitor (Wayland's idle-notify protocol, not a compositor module)
import QtQuick

// The ambient clock (owner's request, 20 November 2026, feature 18; Experimental, off by default; laid
// out by Claude, no board): after a few idle minutes on a workspace with no windows, a big quiet clock,
// what's playing and a running timer fade in over the dimmed wallpaper (popups/AmbientClock.qml). Any
// key or pointer movement ends the idle and it fades out; it never takes input and isn't a lock
// (hypridle's lock at 10 min is untouched). Apps that inhibit idle (a playing video) keep it away.
Singleton {
    id: root

    readonly property bool enabled: Store.saved.ambientClock === true
    function setEnabled(value: bool) { Store.saved.ambientClock = value; }
    readonly property int delay: [2, 3, 5].includes(Store.saved.ambientDelay) ? Store.saved.ambientDelay : 3 // minutes
    function setDelay(minutes: int) { if ([2, 3, 5].includes(minutes)) Store.saved.ambientDelay = minutes; }

    // idle for `delay` minutes (a binding a test may replace)
    property bool idle: monitor.isIdle
    IdleMonitor {
        id: monitor
        enabled: root.enabled
        timeout: root.delay * 60
        respectInhibitors: true
    }

    // the active workspace has no windows at all (floating ones count too) and nothing is fullscreen
    readonly property bool desktopEmpty: !!((Compositor.workspaces ?? []).some(w => w.active) && !Compositor.fullscreen && !(Compositor.windows ?? []).some(w => w.workspace === Compositor.activeWorkspace && !w.hidden && !w.minimized))

    // Settings' Preview (and, TEMP until the owner says, 20 November 2026: `psc ambient preview` in
    // popups/AmbientClock.qml) shows it for previewLength ms, whatever the idle state
    property bool previewing
    property int previewLength: 10000
    function preview() { previewing = true; previewTimer.restart(); }
    Timer { id: previewTimer; interval: root.previewLength; onTriggered: root.previewing = false }

    readonly property bool shown: previewing || enabled && idle && desktopEmpty
}
