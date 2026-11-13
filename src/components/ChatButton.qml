import qs
import QtQuick

// A round icon button of the quick chat (its header, the answer's actions, a code block's Copy):
// transparent until hovered; `active` (the open Recent view) keeps the hover colour.
Rectangle {
    id: root

    property var glyph: []
    property string tip
    property int size: 40
    property bool active
    signal clicked

    width: size
    height: size
    radius: size / 2
    color: mouse.containsMouse || active ? Theme.overlay2 : "transparent"
    Accessible.role: Accessible.Button
    Accessible.name: tip

    Behavior on color {
        ColorAnimation {
            duration: Theme.hoverDuration
            easing.type: Theme.easing
        }
    }

    Icon {
        anchors.centerIn: parent
        size: root.size >= 40 ? 18 : 16
        paths: root.glyph
        color: mouse.containsMouse || root.active ? Theme.textBright : Theme.subtext
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
