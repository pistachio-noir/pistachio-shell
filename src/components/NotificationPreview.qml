import qs
import qs.services
import Quickshell.Widgets // ClippingRectangle, for the rounded picture
import QtQuick

// A screenshot under its notification's text (the shell's own, from Screenshots): the whole picture,
// fitted into a rounded 16:9 box. Nothing for other notifications, or once the file is gone.
Item {
    id: root

    required property var notification
    property int gap // room above it, for a column with tight spacing
    readonly property string path: Notifs.preview(notification)

    visible: path !== "" && image.status !== Image.Error
    height: gap + box.height

    ClippingRectangle {
        id: box

        y: root.gap
        width: parent.width
        height: Math.round(width * 9 / 16)
        radius: 12
        color: Theme.bg

        Image {
            id: image
            anchors.fill: parent
            source: root.path ? `file://${root.path}` : ""
            sourceSize.width: 720
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
    }
}
