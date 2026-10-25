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

    Rectangle {
        width: parent.width
        height: Theme.barHeight
        // hides by sliding down its own height plus the margin while fading
        y: root.shown ? 0 : root.height
        opacity: root.shown ? 1 : 0
        radius: Theme.barRadius
        color: Theme.bgAlt
        border.width: 1
        border.color: Theme.overlay2

        Behavior on y {
            NumberAnimation {
                duration: Theme.motionDuration
                easing.type: Theme.easing
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.motionDuration
                easing.type: Theme.easing
            }
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

    // Panels are right-aligned with the bar, above it (12 px for quick settings, 16 px for the
    // notification centre, as on their boards). Toasts are centred over the bar, 16 px above it.
    QuickSettings {
        id: quickSettings
        anchors.bottom: true
        anchors.left: true
        margins.left: (screen.width + root.width) / 2 - width
        margins.bottom: root.height + 12
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
        anchors.left: true
        margins.left: (screen.width + root.width) / 2 - width
        margins.bottom: root.height + 16
        onOpenChanged: grab.active = open || quickSettings.open
    }

    // only the bottom edge is anchored, so the compositor centres it, like the bar
    Toasts {
        visible: Notifs.popups.length > 0 && !centre.open
        anchors.bottom: true
        margins.bottom: root.height + 16
    }

    // where the pill is while the bar is hidden, else above it like the toasts
    Osd {
        anchors.bottom: true
        margins.bottom: root.shown ? root.height + 16 : Theme.barMargin
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

    // The handle left behind while hidden (AutoHide board).
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        width: 72
        height: 4
        radius: 2
        color: Theme.subtext
        opacity: root.shown ? 0 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.motionDuration
                easing.type: Theme.easing
            }
        }
    }
}
