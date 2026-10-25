import qs
import QtQuick

// 40 px rounded chip that lightens on hover and while `highlighted` (its panel is open).
// Children go in a row; use `foreground` for icon colours.
Rectangle {
    id: root

    default property alias content: row.data
    property int leftPadding: 16
    property int rightPadding: 16
    property alias spacing: row.spacing
    property bool highlighted
    readonly property bool lit: highlighted || mouse.containsMouse
    readonly property color foreground: lit ? Theme.textBright : Theme.text

    signal clicked

    implicitWidth: leftPadding + row.implicitWidth + rightPadding
    implicitHeight: Theme.chipHeight
    radius: Theme.chipRadius
    color: lit ? Theme.overlay2 : Theme.overlay
    Accessible.role: Accessible.Button

    Behavior on color {
        ColorAnimation {
            duration: Theme.hoverDuration
            easing.type: Theme.easing
        }
    }

    Row {
        id: row
        x: root.leftPadding
        anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
