import qs
import qs.components
import QtQuick

Rectangle {
    id: root
    property string title
    property string description
    property string button
    property list<string> glyph: Icons.search
    signal activated
    height: content.height + 48
    radius: Theme.tileRadius
    color: Theme.overlay
    Column {
        id: content
        x: 24; y: 24; width: parent.width - 48; spacing: 8
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 48; height: 48; radius: 24; color: Theme.overlay2
            Icon { anchors.centerIn: parent; size: 22; paths: root.glyph; color: Theme.subtext }
        }
        SettingsText { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.title; font.pixelSize: 14 }
        SettingsText { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.description; secondary: true }
        SettingsButton { anchors.horizontalCenter: parent.horizontalCenter; visible: root.button !== ""; text: root.button; onClicked: root.activated() }
    }
}
