import qs
import qs.components
import Quickshell
import Quickshell.Wayland // the layer's name, which a Hyprland blur rule matches (a Wayland protocol, not a compositor module)
import QtQuick

// An app's tray menu in Pistachio colours: the app's own entries (QsMenuOpener), drawn by the shell
// instead of Qt's platform menu. Submenus open in place with a Back row. The tray pill positions it
// above the icon and closes it on an outside click; Esc closes it too.
PanelWindow {
    id: root

    property bool open
    property var item: null // the tray item whose menu this is; kept while fading out
    property var stack: [] // the submenus opened so far, innermost last

    function show(trayItem) {
        item = trayItem;
        stack = [];
        open = true;
    }

    visible: reveal.shown
    focusable: true // for Esc
    exclusiveZone: 0
    implicitWidth: 260
    implicitHeight: panel.height
    color: "transparent"
    WlrLayershell.namespace: "pistachio-panel" // frosted panels: Hyprland blurs the shell's layers by name

    Reveal {
        id: reveal
        open: root.open
    }

    QsMenuOpener {
        id: opener
        menu: root.stack.length ? root.stack[root.stack.length - 1] : root.item?.menu ?? null
    }

    // Every level stays open while shown (an opener holds each one): once the parent menu has no
    // opener, the app drops the entries of the submenu opened from it.
    QsMenuOpener {
        menu: root.item?.menu ?? null
    }

    Variants {
        model: root.stack

        QsMenuOpener {
            required property var modelData
            menu: modelData
        }
    }

    Rectangle {
        id: panel

        width: parent.width
        height: entries.implicitHeight + 12
        radius: Theme.tileRadius
        color: Theme.surface
        border.width: 1
        border.color: Theme.overlay2
        // fades and grows slightly from the tray, and back
        opacity: reveal.progress
        scale: 0.96 + 0.04 * reveal.progress
        transformOrigin: Item.Bottom
        focus: true
        Keys.onEscapePressed: root.open = false
        Accessible.role: Accessible.PopupMenu

        Column {
            id: entries

            x: 6
            y: 6
            width: parent.width - 12

            // back to the parent menu, inside a submenu
            Entry {
                visible: root.stack.length > 0
                text: "Back"
                glyph: Icons.chevronLeft
                onClicked: root.stack = root.stack.slice(0, -1)
            }

            Repeater {
                model: opener.children

                Item {
                    id: slot

                    required property var modelData

                    width: parent.width
                    height: modelData.isSeparator ? 13 : 36

                    Rectangle {
                        visible: slot.modelData.isSeparator
                        anchors.centerIn: parent
                        width: parent.width - 16
                        height: 1
                        color: Theme.overlay2
                    }

                    Entry {
                        visible: !slot.modelData.isSeparator
                        entry: slot.modelData
                        text: slot.modelData.text
                        icon: slot.modelData.icon
                        onClicked: {
                            if (slot.modelData.hasChildren) {
                                root.stack = root.stack.concat([slot.modelData]);
                            } else {
                                slot.modelData.triggered();
                                root.open = false;
                            }
                        }
                    }
                }
            }
        }
    }

    // One row: an optional icon, the text, and a check box, radio dot or submenu arrow.
    component Entry: Rectangle {
        id: row

        property var entry: null // the menu entry, if this row is one
        property alias text: label.text
        property string icon
        property list<string> glyph // a shell icon instead of the app's, e.g. for Back
        readonly property int button: entry?.buttonType ?? QsMenuButtonType.None
        readonly property bool checked: entry?.checkState === Qt.Checked

        signal clicked

        enabled: entry?.enabled ?? true // also turns the mouse area off
        width: parent.width
        height: 36
        radius: 14
        color: mouse.containsMouse ? Theme.overlay2 : "transparent"
        Accessible.role: button === QsMenuButtonType.CheckBox ? Accessible.CheckBox : button === QsMenuButtonType.RadioButton ? Accessible.RadioButton : Accessible.MenuItem
        Accessible.name: label.text
        Accessible.checked: checked

        Behavior on color {
            ColorAnimation {
                duration: Theme.hoverDuration
                easing.type: Theme.easing
            }
        }

        Image {
            id: appIcon
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            sourceSize: Qt.size(32, 32)
            source: row.icon
            fillMode: Image.PreserveAspectFit
            visible: row.icon !== "" && status === Image.Ready
        }

        Icon {
            id: glyphIcon
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            size: 16
            visible: row.glyph.length > 0
            paths: row.glyph
            color: Theme.subtext
        }

        Text {
            id: label
            anchors.left: parent.left
            anchors.leftMargin: appIcon.visible || glyphIcon.visible ? 38 : 12
            anchors.right: trailing.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: row.enabled ? Theme.text : Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }

        Item {
            id: trailing

            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16

            // check box or radio dot: pistachio when on
            Rectangle {
                visible: row.button !== QsMenuButtonType.None
                anchors.fill: parent
                radius: row.button === QsMenuButtonType.RadioButton ? 8 : 5
                color: row.checked ? Theme.pistachio : "transparent"
                border.width: row.checked ? 0 : 1.5
                border.color: Theme.subtext

                Icon {
                    anchors.centerIn: parent
                    visible: row.checked && row.button === QsMenuButtonType.CheckBox
                    size: 12
                    paths: Icons.check
                    color: Theme.bg
                }
            }

            Icon {
                anchors.centerIn: parent
                visible: row.entry?.hasChildren ?? false
                size: 16
                paths: Icons.chevronRight
                color: Theme.subtext
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.clicked()
        }
    }
}
