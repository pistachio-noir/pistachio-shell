import qs
import QtQuick
import QtQuick.Layouts

// A card of title/detail pairs on the All set page; `mono` sets the details in JetBrains Mono.
Rectangle {
    id: recap
    required property string heading
    required property var items
    property bool mono
    property string footnote
    visible: items.length > 0
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.preferredWidth: 0
    implicitHeight: entries.implicitHeight + 24
    color: Theme.overlay; radius: Classic.tileRadius

    ColumnLayout {
        id: entries
        anchors.fill: parent; anchors.margins: 12
        spacing: 4
        SetupText { Layout.bottomMargin: 3; text: recap.heading; font.weight: Font.ExtraBold }
        Repeater {
            model: recap.items
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.minimumHeight: 26
                spacing: 8
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    SetupText { Layout.fillWidth: true; text: modelData.title; textFormat: Text.PlainText; font.pixelSize: 11; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                    SetupText {
                        Layout.fillWidth: true
                        visible: !!modelData.note
                        text: modelData.note || ""; textFormat: Text.PlainText
                        secondary: true; font.pixelSize: 10; elide: Text.ElideRight; wrapMode: Text.NoWrap
                    }
                }
                SetupText {
                    Layout.maximumWidth: recap.width * 0.62
                    horizontalAlignment: Text.AlignRight
                    text: modelData.detail || ""; textFormat: Text.PlainText; secondary: !recap.mono
                    font.family: recap.mono ? Classic.fontMono : Classic.fontUi
                    font.pixelSize: 11; elide: Text.ElideLeft; wrapMode: Text.NoWrap
                }
            }
        }
        SetupText {
            Layout.fillWidth: true
            Layout.topMargin: 4
            visible: recap.footnote !== ""
            text: recap.footnote; textFormat: Text.PlainText
            secondary: true; font.pixelSize: 10
            font.family: Classic.fontMono
            wrapMode: Text.WrapAnywhere
        }
        Item { Layout.fillHeight: true }
    }
}
