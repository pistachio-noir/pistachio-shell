import qs
import QtQuick

// A round 44 px icon button without a background until hovered: the LocalSend page's header and its
// files card (boards localsend-send and localsend-sending).
Rectangle {
    id: button

    required property list<string> icon
    property color tint: Theme.subtext
    property real iconSize: 18
    property string label // for screen readers

    signal clicked

    width: 44
    height: 44
    radius: Theme.tui ? 0 : (22)
    color: mouse.containsMouse ? Theme.overlay2 : "transparent"
    Accessible.role: Accessible.Button
    Accessible.name: label

    Behavior on color {
        ColorAnimation {
            duration: Theme.hoverDuration
            easing.type: Theme.easing
        }
    }

    Icon {
        anchors.centerIn: parent
        size: button.iconSize
        paths: button.icon
        color: mouse.containsMouse ? Theme.textBright : button.tint
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
