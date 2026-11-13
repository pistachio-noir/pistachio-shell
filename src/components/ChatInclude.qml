import qs
import QtQuick

// One of the quick chat's Include choices (QuickChatContext board): a pill with a glyph; on, it's a
// step lighter with a check after its name.
Rectangle {
    id: root

    property string text
    property var glyph: []
    property bool on
    signal clicked

    width: row.implicitWidth + 28
    height: 36
    radius: 18
    color: on ? Theme.overlay2 : mouse.containsMouse ? Theme.overlay2 : Theme.overlay
    Accessible.role: Accessible.CheckBox
    Accessible.name: text
    Accessible.checked: on

    Behavior on color {
        ColorAnimation {
            duration: Theme.hoverDuration
            easing.type: Theme.easing
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            size: 15
            paths: root.glyph
            color: root.on ? Theme.textBright : Theme.subtext
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.on ? Theme.textBright : Theme.text
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Font.Bold
        }

        Icon {
            visible: root.on
            anchors.verticalCenter: parent.verticalCenter
            size: 14
            paths: Icons.check
            color: Theme.pistachio
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
