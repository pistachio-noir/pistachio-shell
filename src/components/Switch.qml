import qs
import QtQuick

// On/off switch from the notification centre board: 48×28 track in a 52×44 hit area.
// Off is overlay2 with a subtext knob on the left; on is pistachio with a bg knob on the right.
Item {
    id: root

    property bool checked

    signal toggled

    width: 52
    height: 44
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: checked

    Rectangle {
        visible: !Theme.tui
        anchors.centerIn: parent
        width: 48
        height: 28
        radius: 14
        color: root.checked ? Theme.pistachio : Theme.overlay2

        Behavior on color {
            ColorAnimation {
                duration: Theme.hoverDuration
                easing.type: Theme.easing
            }
        }

        Rectangle {
            x: root.checked ? parent.width - width - 4 : 4
            y: 4
            width: 20
            height: 20
            radius: 10
            color: root.checked ? Theme.bg : Theme.subtext

            Behavior on x {
                NumberAnimation {
                    duration: Theme.hoverDuration
                    easing.type: Theme.easing
                }
            }
        }
    }

    Text {
        objectName: "switch-state"
        visible: Theme.tui
        anchors.centerIn: parent
        text: root.checked ? "[x]" : "[ ]"
        color: root.checked ? Theme.pistachio : Theme.subtext
        font.family: Theme.fontTui
        font.pixelSize: Theme.tuiTextSize
        font.weight: Font.Bold
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
