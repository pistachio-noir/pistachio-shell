import qs
import qs.services
import QtQuick

// The existing Lens card keeps its layout; numbered thumbnails identify image order to both agents.
Column {
    id: root
    spacing: 8

    Text {
        text: "Images · " + Lens.images.length + " / 3"
        color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 11
    }
    Row {
        id: thumbnails
        spacing: 8
        height: Lens.images.length ? 76 : 0
        Repeater {
            model: Lens.images
            Rectangle {
                required property var modelData
                required property int index
                width: Math.min(132, (root.width - 16) / 3)
                height: 76
                radius: Theme.tileRadius
                color: Theme.overlay
                Image {
                    anchors.fill: parent; anchors.margins: 6
                    source: "file://" + modelData.path
                    fillMode: Image.PreserveAspectFit
                    cache: false
                }
                Rectangle {
                    x: 4; y: 4; width: 22; height: 22; radius: 11
                    color: Theme.bgAlt
                    Text {
                        objectName: "lensImageNumber_" + (index + 1)
                        anchors.centerIn: parent
                        text: index + 1
                        color: Theme.textBright; font.family: Theme.fontMono; font.pixelSize: 11
                    }
                }
                Item {
                    anchors.right: parent.right; y: 0
                    width: 44; height: 44
                    visible: !Lens.busy
                    Accessible.role: Accessible.Button
                    Accessible.name: "Remove image " + (index + 1)
                    Rectangle {
                        anchors.centerIn: parent; width: 26; height: 26; radius: 13; color: Theme.bgAlt
                        Icon { anchors.centerIn: parent; paths: Icons.close; size: 14; color: Theme.text }
                    }
                    MouseArea {
                        objectName: "lensRemoveImage_" + (index + 1)
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: Lens.removeImage(modelData.id)
                    }
                }
            }
        }
    }
}
