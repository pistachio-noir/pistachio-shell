import qs
import QtQuick

// A card over its parent panel, which it dims (quick settings' night light schedule and Bluetooth
// devices). Its children stack in a column. A click beside the card emits `dismissed`.
Item {
    id: root

    property bool open
    property string title // for screen readers
    default property alias content: body.data

    signal dismissed

    anchors.fill: parent
    visible: reveal.shown

    Reveal {
        id: reveal
        open: root.open
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.panelRadius
        color: Theme.bg
        opacity: 0.6 * reveal.progress

        MouseArea {
            anchors.fill: parent
            onClicked: root.dismissed()
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 20
        width: parent.width - 40
        height: body.implicitHeight + 32
        radius: Theme.tileRadius
        color: Theme.bgAlt
        border.width: 1
        border.color: Theme.overlay2
        opacity: reveal.progress
        scale: 0.96 + 0.04 * reveal.progress
        Accessible.role: Accessible.Dialog
        Accessible.name: root.title

        MouseArea {
            anchors.fill: parent // clicks on the card stay on it
        }

        Column {
            id: body
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 4
        }
    }
}
