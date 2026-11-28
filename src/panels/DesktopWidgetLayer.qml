import qs
import qs.services
import Quickshell
import QtQuick

// The desktop widgets on the wallpaper (services/DesktopWidgets.qml), on the icons' grid, under the
// icons (which go around them). They fade in and out with the cat's rule (an empty desktop, not Zen);
// the pointer and keyboard pass through to the desktop. Arranged in popups/WidgetStudio.qml.
Item {
    id: root

    readonly property bool shown: DesktopWidgets.shown
    // the CPU/RAM block opens the system monitor (Apps.openMonitor): Classic's desktop asks
    // monitorAt() on a click, TUI's input region takes statsWidget in
    property Item statsWidget: null
    function monitorAt(x: real, y: real): bool {
        const w = statsWidget;
        return shown && w !== null && Apps.monitorApp !== null && w.contains(w.mapFromItem(root, x, y));
    }

    opacity: shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.motionDuration
            easing.type: Theme.easing
        }
    }

    Repeater {
        model: ScriptModel {
            values: DesktopWidgets.layout
            objectProp: "kind"
        }

        DesktopWidget {
            id: block
            required property var modelData
            // kept by kind; its place read fresh from the layout (a kept delegate's modelData may lag)
            readonly property var at: DesktopWidgets.layout.find(w => w.kind === kind) ?? modelData
            kind: modelData.kind
            live: root.shown
            opensMonitor: true
            x: DesktopWidgets.xOf(at.col) + 6
            y: DesktopWidgets.yOf(at.row) + 6
            width: DesktopWidgets.sizes[kind][0] * DesktopWidgets.cellWidth - 12
            height: DesktopWidgets.sizes[kind][1] * DesktopWidgets.cellHeight - 12

            Component.onCompleted: if (kind === "stats") root.statsWidget = block
            Component.onDestruction: if (root.statsWidget === block) root.statsWidget = null

            Behavior on x { NumberAnimation { duration: Theme.motionDuration; easing.type: Theme.easing } }
            Behavior on y { NumberAnimation { duration: Theme.motionDuration; easing.type: Theme.easing } }
        }
    }
}
