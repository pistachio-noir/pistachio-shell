import qs
import qs.components
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property string title
    property string detail
    property list<string> glyph: []
    property Component control
    property color surface: Theme.overlay

    implicitHeight: Math.max(56, content.implicitHeight + 12)
    radius: Classic.tileRadius
    color: surface

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 12

        Rectangle {
            visible: root.glyph.length > 0
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: 16
            color: Theme.overlay2
            Icon { anchors.centerIn: parent; paths: root.glyph; size: 16; color: Theme.subtext }
        }

        ColumnLayout {
            spacing: 2
            Layout.fillWidth: true
            SetupText { Layout.fillWidth: true; text: root.title; textFormat: Text.PlainText }
            SetupText {
                Layout.fillWidth: true
                visible: text !== ""
                secondary: true
                text: root.detail
                textFormat: Text.PlainText
            }
        }

        Loader {
            visible: root.control !== null
            Layout.alignment: Qt.AlignVCenter
            sourceComponent: root.control
        }
    }
}
