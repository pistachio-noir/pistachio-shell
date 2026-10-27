import qs
import qs.panels
import qs.popups
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick

// The floating bar. Only the bottom edge is anchored, so the compositor centres it horizontally.
// It hides while a window on the active workspace overlaps it; pointing at the bottom edge brings it back.
PanelWindow {
    id: root

    // The bar's area on screen (the pill, the tray pill if shown, and the gap under them), grown by a small margin.
    readonly property int trayGap: 12
    readonly property rect zone: Qt.rect((screen.width - width) / 2 - 8, screen.height - height - 8, width + 16 + (tray.visible ? trayGap + tray.width : 0), height + 8)
    readonly property bool overlapped: Compositor.windowBounds.some(r => r.x < zone.x + zone.width && r.x + r.width > zone.x && r.y + r.height > zone.y)
    // the pointer is on the bar or the tray pill, or a tray menu is open
    readonly property bool pointed: hover.hovered || tray.hovered || tray.menuOpen
    // Stays up while pointed (even if a window moves under it), for a moment after, long enough to
    // cross the gap to the tray pill, and while a panel is open.
    readonly property bool shown: !overlapped || pointed || linger.running || quickSettings.open || centre.open

    onPointedChanged: if (!pointed) linger.restart()

    // Tooltips (owner's request; not on a board): what the pointer rests on, as lines and the x to
    // centre on, or null. It shows after half a second; moving on to the next item swaps it at once,
    // across the gaps between them too, and the bar hiding, a panel or a tray menu drops it.
    readonly property var tipTarget: !shown || quickSettings.open || centre.open || tray.menuOpen ? null
        : clock.hovered ? { lines: clock.tooltip, x: centreOf(clock) }
        : status.hovered ? { lines: status.tooltip, x: centreOf(status) }
        : workspaces.hoveredSlot ? { lines: workspaces.tooltip, x: centreOf(workspaces.hoveredSlot) }
        : tray.tipIcon ? { lines: tray.tipLines, x: tray.tipCentre }
        : null

    function centreOf(item: Item): real {
        return (screen.width - width) / 2 + item.mapToItem(null, item.width / 2, 0).x;
    }

    onTipTargetChanged: {
        if (tipTarget) {
            tipClose.stop();
            tip.lines = tipTarget.lines;
            tip.centre = tipTarget.x;
            if (!tip.open)
                tipDelay.restart();
        } else {
            tipDelay.stop();
            tipClose.restart();
        }
    }

    Timer {
        id: tipDelay
        interval: 500
        onTriggered: tip.open = true
    }

    Timer {
        id: tipClose
        interval: 150 // long enough to cross to the next item
        onTriggered: tip.open = false
    }

    BarTooltip {
        id: tip
        lift: Theme.barHeight + Theme.barMargin + 8
    }

    Timer {
        id: linger
        interval: 400
    }

    // quick settings asks for a launcher mode; shell.qml owns the launcher
    signal launcherRequested(string mode)

    // One panel at a time.
    function toggle(panel) {
        const open = !panel.open;
        quickSettings.open = false;
        centre.open = false;
        panel.open = open;
    }

    anchors.bottom: true
    exclusiveZone: 0 // reserve no space, so windows can sit under the bar
    implicitWidth: Theme.barWidth
    implicitHeight: Theme.barHeight + Theme.barMargin // reaches the screen edge, where the reveal strip is
    color: "transparent"

    // Hidden, only a 4 px strip at the screen edge takes the pointer; clicks elsewhere reach the windows below.
    mask: Region {
        y: root.shown ? 0 : root.height - 4
        width: root.width
        height: root.shown ? root.height : 4
    }

    HoverHandler {
        id: hover
    }

    // From the handle left behind while hidden (AutoHide board: 72 x 4, 2 px above the screen edge,
    // in subtext) to the pill and back: 0 is the handle, 1 the bar (owner's request).
    property real grown: shown ? 1 : 0

    Behavior on grown {
        NumberAnimation {
            duration: Theme.growDuration
            easing.type: Theme.easing
        }
    }

    // The pill, grown out of the handle: it widens and rises as the handle's colour gives way to the
    // bar's within the first third.
    Rectangle {
        width: 72 + (parent.width - 72) * root.grown
        height: 4 + (Theme.barHeight - 4) * root.grown
        x: (parent.width - width) / 2
        y: (root.height - 2 - 4) * (1 - root.grown)
        radius: height / 2 // 2 for the handle, Theme.barRadius for the bar
        color: Qt.tint(Theme.bgAlt, Qt.rgba(Theme.subtext.r, Theme.subtext.g, Theme.subtext.b, Math.max(0, 1 - 3 * root.grown)))
        border.width: 1
        border.color: Qt.rgba(Theme.overlay2.r, Theme.overlay2.g, Theme.overlay2.b, root.grown)
    }

    // The bar's content, at its full size: it fades in rising 6 px once the pill is half grown, and
    // goes first when it shrinks.
    Item {
        id: content

        readonly property real shownPart: Math.max(0, 2 * root.grown - 1)

        width: parent.width
        height: Theme.barHeight
        opacity: shownPart
        visible: opacity > 0
        transform: Translate {
            y: 6 * (1 - content.shownPart)
        }

        // Edges sit 9 px in (1 px border + 8 px padding) with 8 px gaps, as on the board.
        Workspaces {
            id: workspaces
            anchors.left: parent.left
            anchors.leftMargin: 9
            anchors.verticalCenter: parent.verticalCenter
        }

        WindowTitle {
            anchors.left: workspaces.right
            anchors.right: clock.left
            anchors.leftMargin: 12 // gap + the title's own 4 px padding
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
        }

        ClockChip {
            id: clock
            anchors.right: status.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            highlighted: centre.open
            onClicked: root.toggle(centre)
        }

        StatusChip {
            id: status
            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            highlighted: quickSettings.open
            onClicked: root.toggle(quickSettings)
        }
    }

    // the tray pill, right of the bar while any app has a tray icon
    TrayPill {
        id: tray
        anchors.bottom: true
        anchors.left: true
        margins.left: (screen.width + root.width) / 2 + root.trayGap
        shown: root.shown
    }

    // Quick settings is right-aligned with the bar, 12 px above it. The notification centre, wider
    // with the calendar beside it, and the toasts are centred over the bar, 16 px above it (as on
    // their boards).
    QuickSettings {
        id: quickSettings
        anchors.bottom: true
        anchors.left: true
        margins.left: (screen.width + root.width) / 2 - width + quickSettings.side
        margins.bottom: root.height + 12 - quickSettings.below
        onOpenChanged: grab.active = open || centre.open
        onPowerRequested: {
            open = false;
            powerMenu.open = true;
        }
        onLauncherRequested: mode => {
            open = false;
            root.launcherRequested(mode);
        }
    }

    PowerMenu {
        id: powerMenu
    }

    NotificationCentre {
        id: centre
        anchors.bottom: true
        margins.bottom: root.height + 16 - centre.below
        onOpenChanged: grab.active = open || quickSettings.open
    }

    // only the bottom edge is anchored, so the compositor centres it, like the bar
    Toasts {
        id: toasts
        visible: Notifs.popups.length > 0 && !centre.open
        anchors.bottom: true
        margins.bottom: root.height + 16 - toasts.below
    }

    // where the pill is while the bar is hidden, else above it like the toasts
    Osd {
        anchors.bottom: true
        lift: root.shown ? root.height + 16 : Theme.barMargin
        suppressed: quickSettings.open
    }

    // A click outside the panels and the bar closes the panels; the bar stays clickable.
    FocusGrab {
        id: grab
        windows: [quickSettings, centre, root]
        onCleared: {
            quickSettings.open = false;
            centre.open = false;
        }
    }

    // For keybinds: qs -c pistachio ipc call quicksettings toggle (or notifications toggle)
    IpcHandler {
        target: "quicksettings"

        function toggle(): void {
            root.toggle(quickSettings);
        }
    }

    IpcHandler {
        target: "notifications"

        function toggle(): void {
            root.toggle(centre);
        }

        function toggleDnd(): void {
            Notifs.setDnd(!Notifs.dnd);
        }
    }
}
