import qs
import qs.services
import QtQuick

// Round icon for a notification: its image or app icon, else a bell (terracotta when critical); the
// shell's own screenshot notification gets the screenshot menu's Region glyph.
Rectangle {
    id: root

    required property var notification
    property bool critical
    property int size: 40

    width: size
    height: size
    radius: size / 2
    color: Theme.overlay

    Image {
        id: image
        anchors.centerIn: parent
        width: root.size / 2
        height: width
        sourceSize: Qt.size(width * 2, height * 2)
        source: Notifs.iconSource(root.notification)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        visible: status === Image.Ready
    }

    Icon {
        anchors.centerIn: parent
        visible: !image.visible
        size: root.size / 2
        paths: Notifs.own(root.notification) ? Icons.region : Icons.bell
        color: root.critical ? Theme.terracotta : Theme.subtext
    }
}
