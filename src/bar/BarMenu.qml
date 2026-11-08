import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland // the layer's name, level and keyboard (a Wayland protocol, not a compositor module)
import QtQuick

// The bar's right-click menu (owner's request, 9 November 2026): for the workspace on screen, tabbed
// (i3-style) on or off, and naming it. Over the whole screen while open, so a click beside it (or
// Esc) closes it, as with the power menu.
PanelWindow {
    id: root

    property bool open
    property real at // the click's x on the screen
    property int lift // the bar's top, from the screen's bottom edge

    signal renameRequested(int workspace)

    readonly property int ws: Compositor.activeWorkspace
    readonly property var entries: [
        { text: Compositor.isTabbed(ws) ? "Tabs off: tile again" : "Tabbed, i3-style", glyph: Icons.layers, run: () => Compositor.setTabbed(ws, !Compositor.isTabbed(ws)) },
        { text: Compositor.nameOf(ws) ? `Rename “${Compositor.nameOf(ws)}”…` : `Name workspace ${ws}…`, glyph: Icons.pencil, run: () => root.renameRequested(ws) }
    ].concat(Compositor.nameOf(ws) ? [{ text: "Clear its name", glyph: Icons.close, run: () => Compositor.setName(ws, "") }] : [])

    visible: open
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "pistachio-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: root.open = false
    }

    Item {
        id: card

        x: Math.max(8, Math.min(root.at - width / 2, root.width - width - 8))
        y: root.height - root.lift - height - 8
        width: 240
        height: column.implicitHeight + 12
        focus: root.open
        Keys.onEscapePressed: root.open = false

        Shadow {
            kind: Theme.shadowSmall
            anchors.fill: panel
            radius: panel.radius
        }

        Rectangle {
            id: panel
            anchors.fill: parent
            radius: Theme.tileRadius
            color: Theme.bgAlt
            border.width: 1
            border.color: Theme.overlay2
            Accessible.role: Accessible.PopupMenu
        }

        Column {
            id: column
            x: 6
            y: 6
            width: parent.width - 12

            Text {
                x: 10
                height: 28
                verticalAlignment: Text.AlignVCenter
                text: `WORKSPACE ${root.ws}`
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 0.66
            }

            Repeater {
                model: root.entries

                Rectangle {
                    id: entry

                    required property var modelData

                    width: column.width
                    height: 36
                    radius: 14
                    color: entryMouse.containsMouse ? Theme.overlay : "transparent"
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: modelData.text

                    Icon {
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        size: 16
                        paths: entry.modelData.glyph
                        color: Theme.subtext
                    }

                    Text {
                        x: 40
                        width: parent.width - 52
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData.text
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: entryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const run = entry.modelData.run;
                            root.open = false;
                            run();
                        }
                    }
                }
            }
        }
    }
}
