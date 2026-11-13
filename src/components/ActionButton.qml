import qs
import QtQuick

// A notification's action as a pill: the first one pistachio (`primary`), the rest on `base`, which
// lightens on hover. Toasts use it at 40 px on bgAlt, the notification centre's cards at 32 px.
Rectangle {
    id: button

    property string text
    property list<string> icon: []
    property int horizontalPadding: 16
    property real maximumWidth: Infinity
    property bool primary
    property color base: Theme.overlay
    property color tint: primary ? Theme.bg : Theme.text // the label's colour (TUI's terracotta Cancel)

    signal clicked

    width: Math.min(maximumWidth, label.implicitWidth + horizontalPadding * 2 + (icon.length ? 22 : 0))
    height: 40
    radius: Theme.tui ? 0 : (height / 2)
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
        anchors.horizontalCenterOffset: button.icon.length ? 11 : 0
        width: Math.max(0, button.width - button.horizontalPadding * 2 - (button.icon.length ? 22 : 0))
        elide: Text.ElideRight
        text: button.text
        textFormat: Text.PlainText
        color: button.tint
        font.family: Theme.fontUi
        font.pixelSize: 12
        font.weight: button.primary ? Font.ExtraBold : Font.Bold
    }

    Icon {
        visible: button.icon.length > 0
        x: button.horizontalPadding - 4
        anchors.verticalCenter: parent.verticalCenter
        paths: button.icon
        size: 15
        color: button.primary ? Theme.bg : Theme.subtext
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
