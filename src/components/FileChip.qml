import qs
import QtQuick

// A file waiting to go, or offered by a device: its tinted icon and name on a 28 px chip (LocalSend boards).
Rectangle {
    id: chip

    required property var item
    property real maxWidth: 140

    width: Math.min(maxWidth, label.implicitWidth + 38)
    height: 28
    radius: 14
    color: Theme.overlay2

    Icon {
        id: glyph
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        size: 14
        paths: LocalSendLook.fileIcon(chip.item)
        color: LocalSendLook.fileTint(chip.item)
    }

    Text {
        id: label
        anchors.left: glyph.right
        anchors.leftMargin: 6
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: chip.item.name
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Theme.text
        font.family: Theme.fontUi
        font.pixelSize: 12
        font.weight: Font.DemiBold
    }
}
