import qs
import QtQuick

// Round 36 px media button; the main one (play/pause) is pistachio. Dimmed while the player
// doesn't offer it.
Rectangle {
    id: button

    required property list<string> icon
    required property string label
    property bool primary

    signal clicked

    width: 36
    height: 36
    radius: 18
    color: primary ? Theme.pistachio : mouse.containsMouse && enabled ? Theme.overlay2 : "transparent"
    opacity: primary && !enabled ? 0.5 : 1
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
        paths: button.icon
        color: button.primary ? Theme.bg : button.enabled ? Theme.text : Theme.muted
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: button.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
