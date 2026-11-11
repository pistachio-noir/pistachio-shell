import qs
import qs.components
import QtQuick

// A label pill of the Overview boards: a workspace's name and count (small, 28 px), or a window's
// app and title (32 px, with the app's icon in a round well). Pistachio with dark text when active.
Rectangle {
    id: root

    property string text
    property string detail // after the text, a little fainter: "3 windows"
    property bool active
    property bool small
    property string icon // an app icon's source, or ""
    property list<string> glyph // drawn when there's no icon
    property color glyphColor: Theme.subtext
    property real maxWidth: 1e6

    implicitHeight: small ? 28 : 32
    implicitWidth: Math.min(maxWidth, row.implicitWidth + (well.visible ? 8 + 14 : 28))
    radius: height / 2
    color: active ? Theme.pistachio : Theme.overlay

    Behavior on color {
        ColorAnimation {
            duration: Theme.hoverDuration
            easing.type: Theme.easing
        }
    }

    Row {
        id: row
        x: well.visible ? 8 : 14
        width: Math.min(implicitWidth, root.width - x - 14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Rectangle {
            id: well
            visible: !root.small
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 20
            radius: 10
            color: root.active ? Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.14) : Theme.overlay2

            Image {
                visible: root.icon !== ""
                anchors.centerIn: parent
                width: 14
                height: 14
                sourceSize: Qt.size(28, 28)
                source: root.icon
                asynchronous: true
            }

            Icon {
                visible: root.icon === ""
                anchors.centerIn: parent
                size: 12
                paths: root.glyph
                color: root.active ? Theme.bg : root.glyphColor
            }
        }

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.maxWidth - (well.visible ? 8 + 20 + 8 + 14 : 28) - (more.visible ? more.implicitWidth + 8 : 0))
            text: root.text
            elide: Text.ElideRight
            textFormat: Text.PlainText
            color: root.active ? Theme.bg : Theme.text
            font.family: Theme.fontUi
            font.pixelSize: root.small ? 12 : 13
            font.weight: root.active ? Font.ExtraBold : Font.Bold
        }

        Text {
            id: more
            visible: root.detail !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.detail
            opacity: 0.75
            color: root.active ? Theme.bg : Theme.text
            font.family: Theme.fontUi
            font.pixelSize: root.small ? 12 : 13
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }
    }
}
