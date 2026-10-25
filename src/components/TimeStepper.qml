import qs
import QtQuick

// A label and a time of day with − and + buttons, in 15-minute steps (the mouse wheel steps too).
Item {
    id: root

    required property string label
    required property int minutes // after midnight
    readonly property string time: `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`

    signal stepped(int minutes)

    function step(by: int) {
        stepped((minutes + by + 1440) % 1440);
    }

    width: parent.width
    height: 44
    Accessible.role: Accessible.SpinBox
    Accessible.name: `${label} ${time}`

    WheelHandler {
        onWheel: event => root.step(event.angleDelta.y > 0 ? 15 : -15)
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: Theme.text
        font.family: Theme.fontUi
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        IconButton {
            icon: Icons.minus
            Accessible.name: `${root.label} 15 minutes earlier`
            onClicked: root.step(-15)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 52
            horizontalAlignment: Text.AlignHCenter
            text: root.time
            color: Theme.textBright
            font.family: Theme.fontUi
            font.pixelSize: 15
            font.weight: Font.Bold
            font.features: { "tnum": 1 }
        }

        IconButton {
            icon: Icons.plus
            Accessible.name: `${root.label} 15 minutes later`
            onClicked: root.step(15)
        }
    }
}
