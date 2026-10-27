import qs
import QtQuick

// A notification's action as a pill: the first one pistachio (`primary`), the rest on `base`, which
// lightens on hover. Toasts use it at 40 px on bgAlt, the notification centre's cards at 32 px.
Rectangle {
    id: button

    property string text
    property bool primary
    property color base: Theme.overlay

    signal clicked

    width: label.implicitWidth + 32
    height: 40
    radius: height / 2
    color: primary ? Theme.pistachio : mouse.containsMouse ? Theme.overlay2 : base
    Accessible.role: Accessible.Button
    Accessible.name: text

    Behavior on color {
        ColorAnimation {
            duration: Theme.hoverDuration
            easing.type: Theme.easing
        }
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: button.text
        textFormat: Text.PlainText
        color: button.primary ? Theme.bg : Theme.text
        font.family: Theme.fontUi
        font.pixelSize: 12
        font.weight: button.primary ? Font.ExtraBold : Font.Bold
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
