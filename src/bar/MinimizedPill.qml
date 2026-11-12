import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland // the layer's name, which a Hyprland blur rule matches (a Wayland protocol, not a compositor module)
import QtQuick

// The minimised windows (owner's request, 12 November 2026; laid out like the tray pill, no board):
// a pill beside the bar, right of the tray pill, while any window is minimised (`window minimize`).
// Each shows its app's icon; a click brings it back onto the workspace on screen. The bar positions
// it and hides and reveals it along with itself. In Zen mode, which hides the bar, it stays (owner's
// request, 12 November 2026), compact like Zen's session pill and beside it.
PanelWindow {
    id: root

    property bool shown: true // the bar's state
    property bool instant // the bar's: a change of `shown` jumps instead of easing
    property bool compact // Zen mode: the session pill's size and look, at the bottom of the screen
    readonly property bool hovered: hover.hovered
    // the icon under the pointer, for the bar's tooltip: the window's title and app, centred on it
    property Item tipIcon: null
    readonly property var tipLines: tipIcon ? [[tipIcon.modelData.title || Apps.nameFor(tipIcon.modelData.appId)], ["Minimised · click to bring back"]] : []
    readonly property real tipCentre: tipIcon ? margins.left + tipIcon.mapToItem(null, tipIcon.width / 2, 0).x : 0

    visible: Compositor.minimized.length > 0
    exclusiveZone: 0
    implicitWidth: pill.width
    implicitHeight: Theme.barHeight + Theme.barMargin // like the bar, so it slides off the same way
    color: "transparent"
    WlrLayershell.namespace: "pistachio-bar" // frosted panels: Hyprland blurs the shell's layers by name

    // takes no clicks while hidden; the bar's edge strip brings it back
    mask: Region {
        y: pill.y
        width: root.shown ? root.width : 0
        height: root.shown ? pill.height : 0
    }

    HoverHandler {
        id: hover
    }

    // 0 hidden, 1 shown, on the bar's curve, as the tray pill
    property real grown: shown ? 1 : 0

    Behavior on grown {
        enabled: !root.instant

        NumberAnimation {
            duration: Theme.growDuration
            easing.type: Theme.easing
        }
    }

    Rectangle {
        id: pill

        readonly property real shownPart: Math.max(0, 2 * root.grown - 1)

        width: icons.implicitWidth + (root.compact ? 10 : 18) // 1 px border + 8 px padding each side, as in the bar (4 compact)
        height: root.compact ? Theme.chipHeight + 8 : Theme.barHeight
        y: Theme.barHeight - height // bottoms line up: the bar's, or Zen's session pill's
        opacity: shownPart
        scale: 0.8 + 0.2 * shownPart
        transformOrigin: Item.Left // the edge nearest the bar
        radius: root.compact ? height / 2 : Theme.barRadius
        color: root.compact ? Theme.glass(Theme.bgAlt) : Theme.surface
        border.width: 1
        border.color: Theme.overlay2

        Row {
            id: icons

            anchors.centerIn: parent
            spacing: 4

            Repeater {
                // keeps the icons when one is added or removed
                model: ScriptModel {
                    values: Compositor.minimized
                    objectProp: "address"
                }

                WindowIcon {}
            }
        }
    }

    component WindowIcon: Rectangle {
        id: icon

        required property var modelData
        readonly property string iconSource: Apps.iconFor(modelData.appId)

        width: Theme.chipHeight
        height: Theme.chipHeight
        radius: Theme.chipRadius
        color: mouse.containsMouse ? Theme.overlay2 : "transparent"
        Accessible.role: Accessible.Button
        Accessible.name: `Bring back ${modelData.title || Apps.nameFor(modelData.appId)}`

        Behavior on color {
            ColorAnimation {
                duration: Theme.hoverDuration
                easing.type: Theme.easing
            }
        }

        Image {
            id: picture
            anchors.centerIn: parent
            width: 20
            height: 20
            sourceSize: Qt.size(40, 40)
            source: icon.iconSource
            fillMode: Image.PreserveAspectFit
            asynchronous: true // every app icon in the shell loads so (see CLAUDE.md: a mix aborts)
        }

        // an app without an icon in the theme
        Icon {
            visible: picture.status !== Image.Ready
            anchors.centerIn: parent
            size: 18
            paths: Icons.window
            color: Theme.subtext
        }

        MouseArea {
            id: mouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: {
                if (containsMouse)
                    root.tipIcon = icon;
                else if (root.tipIcon === icon)
                    root.tipIcon = null;
            }
            onClicked: {
                if (root.tipIcon === icon)
                    root.tipIcon = null;
                Compositor.restore(icon.modelData.address);
            }
        }
    }
}
