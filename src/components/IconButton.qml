import qs
import QtQuick

// Round 44 px button with a 20 px icon.
Rectangle {
    id: root

    required property list<string> icon

    signal clicked

    width: 44
    height: 44
    radius: 22
    color: mouse.containsMouse ? Theme.overlay2 : Theme.overlay
    Accessible.role: Accessible.Button

    Behavior on color {
        ColorAnimation {
            duration: Theme.hoverDuration
            easing.type: Theme.easing
        }
    }

    Icon {
        anchors.centerIn: parent
        size: 20
        paths: root.icon
        color: mouse.containsMouse ? Theme.textBright : Theme.text
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
