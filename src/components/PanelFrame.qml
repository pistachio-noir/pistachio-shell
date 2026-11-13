import qs
import QtQuick

// Title tabs sit across the neutral border; the caller leaves ten pixels above the frame.
Rectangle {
    id: root
    property string title
    property string detail
    property bool active: true
    color: Theme.tui ? Theme.tuiSurface : Theme.bgAlt
    radius: Theme.tui ? 0 : Theme.panelRadius
    border.width: 1
    border.color: Theme.tuiBorder
    Rectangle {
        visible: Theme.tui && root.title !== ""
        x: 8; y: -10
        width: Math.max(0, Math.min(titleText.implicitWidth + 16, root.width - 16 - (root.detail ? Math.min(detailText.implicitWidth + 16, root.width * 0.4) + 8 : 0))); height: Theme.tuiLineHeight
        color: root.active ? Theme.pistachio : root.color
        Text { id: titleText; anchors.centerIn: parent; width: parent.width - 16; elide: Text.ElideRight; textFormat: Text.PlainText; text: root.title; color: root.active ? Theme.bg : Theme.subtext; font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize; font.weight: Font.Bold }
    }
    Rectangle {
        visible: Theme.tui && root.detail !== ""
        anchors.right: parent.right; anchors.rightMargin: 8
        y: -10; width: Math.min(detailText.implicitWidth + 16, root.width * 0.4); height: Theme.tuiLineHeight
        color: root.color
        Text { id: detailText; anchors.centerIn: parent; width: parent.width - 16; elide: Text.ElideRight; textFormat: Text.PlainText; text: root.detail; color: Theme.subtext; font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize }
    }
}
