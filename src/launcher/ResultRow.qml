import qs
import qs.components
import QtQuick
import "fuzzy.js" as Fuzzy

// A launcher result (Launcher boards): icon, title with the matched letters in pistachio, subtitle,
// an optional workspace badge, and while selected an action label and room for the pistachio ↵ chip,
// which the launcher draws on its gliding selection so the two move together. Disabled (`enabled`
// false), it is greyed out and takes no clicks, e.g. an input with nothing plugged in.
Rectangle {
    id: root

    property string title
    property var indices: []
    property string subtitle
    property string icon // image source; "" shows `glyph`
    property string emoji // shown in place of the icon, e.g. for the emoji picker
    property list<string> glyph: Icons.window
    property color glyphColor: Theme.subtext
    property string badge
    property bool badgeActive
    property string action // shown before the ↵ chip, e.g. "Switch"
    property bool actionAlways // also show the action (in subtext) when not selected
    property bool selected
    property bool compact
    property int indent // px, for rows under another (an app's actions)

    signal clicked
    signal menuRequested(point at) // a right click, where (in the window)

    height: compact ? 56 : 60
    radius: Theme.tileRadius
    color: "transparent" // selected: the launcher's gliding chip is under it
    Accessible.role: Accessible.ListItem
    Accessible.name: title + (subtitle ? ", " + subtitle : "")
    Accessible.selected: selected

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => mouse.button === Qt.RightButton ? root.menuRequested(mapToItem(null, mouse.x, mouse.y)) : root.clicked()
    }

    Rectangle {
        id: disc

        x: 14 + root.indent
        anchors.verticalCenter: parent.verticalCenter
        width: root.compact ? 34 : 38
        height: width
        radius: width / 2
        color: Theme.overlay

        Text {
            anchors.centerIn: parent
            visible: root.emoji !== ""
            text: root.emoji
            font.family: Theme.fontEmoji
            font.pixelSize: root.compact ? 18 : 20
        }

        Image {
            id: image
            anchors.centerIn: parent
            width: 22
            height: 22
            sourceSize: Qt.size(44, 44)
            source: root.icon
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            visible: status === Image.Ready
        }

        Icon {
            anchors.centerIn: parent
            visible: !image.visible && root.emoji === ""
            paths: root.glyph
            color: root.enabled ? root.glyphColor : Theme.muted
        }
    }

    Column {
        anchors.left: disc.right
        anchors.leftMargin: 14
        anchors.right: trailing.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            width: parent.width
            textFormat: Text.StyledText // for the highlight; fuzzy.highlight() escapes the title
            text: Fuzzy.highlight(root.title, root.indices, Theme.pistachio)
            elide: Text.ElideRight
            color: !root.enabled ? Theme.subtext : root.selected ? Theme.textBright : Theme.text
            font.family: Theme.fontUi
            font.pixelSize: root.compact ? 14 : 15
            font.weight: Font.Bold
            lineHeight: root.compact ? 19 : 20
            lineHeightMode: Text.FixedHeight

            TipHover {}
        }

        Text {
            width: parent.width
            visible: text !== ""
            text: root.subtitle
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Font.Medium
            lineHeight: 16
            lineHeightMode: Text.FixedHeight

            TipHover {}
        }
    }

    Row {
        id: trailing

        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Rectangle {
            visible: root.badge !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(30, badgeText.implicitWidth + 18)
            height: 24
            radius: 12
            color: Theme.overlay

            Text {
                id: badgeText
                anchors.centerIn: parent
                text: root.badge
                color: root.badgeActive ? Theme.pistachio : Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: 12
                font.weight: Font.ExtraBold
            }
        }

        Text {
            visible: (root.selected || root.actionAlways) && root.action !== ""
            anchors.verticalCenter: parent.verticalCenter
            opacity: visible ? 1 : 0 // fades in as the selection arrives
            text: root.action
            color: root.selected ? Theme.textBright : Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Font.Bold

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.motionDuration
                    easing.type: Theme.easing
                }
            }
        }

        // where the launcher's ↵ chip lands (28 x 26, as Launcher.qml draws it)
        Item {
            visible: root.selected
            width: 28
            height: 26
        }
    }
}
