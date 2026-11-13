import qs
import qs.components
import QtQuick
import QtQuick.Controls.Basic as Basic

Basic.Button {
    id: root
    property bool active
    property bool selected
    property bool quiet
    property bool danger
    property bool card
    property bool animateSelection
    property list<string> glyph: []
    implicitHeight: 44
    implicitWidth: Math.max(44, Theme.tui ? naturalLabel.implicitWidth + leftPadding + rightPadding : contentItem.implicitWidth + 48)
    padding: Theme.tui ? Theme.tuiButtonPadding : 18
    leftPadding: padding
    rightPadding: padding
    topPadding: 0
    bottomPadding: 0
    font.family: Theme.fontUi
    font.pixelSize: Theme.tui ? Theme.tuiTextSize : 12
    font.weight: Theme.tui ? Font.DemiBold : Font.Bold
    hoverEnabled: true
    background: Rectangle {
        y: Theme.tui && !root.animateSelection ? (root.height-Theme.tuiButtonHeight)/2 : 0
        height: Theme.tui && !root.animateSelection ? Theme.tuiButtonHeight : root.height
        radius: Theme.tui ? 0 : (root.card ? Theme.tileRadius : height / 2)
        scale: !Theme.tui && root.animateSelection && !root.active ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: Theme.motionDuration; easing.type: Theme.easing } }
        color: Theme.tui ? (root.active ? Theme.pistachio : root.hovered || root.visualFocus || root.selected ? Theme.tuiHover : root.quiet ? "transparent" : Theme.overlay) : root.card ? root.hovered || root.visualFocus ? Theme.overlay2 : Theme.overlay : root.active ? Theme.pistachio : root.selected ? Theme.overlay2 : root.hovered || root.visualFocus ? Theme.overlay : root.quiet ? "transparent" : Theme.overlay2
        border.width: root.visualFocus ? 1 : 0
        border.color: Theme.subtext
        Behavior on color { ColorAnimation { duration: Theme.hoverDuration; easing.type: Theme.easing } }
    }
    Text { id: naturalLabel; visible: false; text: root.text; font: root.font }
    contentItem: Text {
        text: root.glyph.length ? "" : root.text
        font: root.font
        color: !root.enabled ? Theme.subtext : root.active ? Theme.bg : root.danger ? Theme.terracotta : root.quiet ? Theme.subtext : Theme.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    Icon {
        visible: root.glyph.length > 0
        anchors.centerIn: parent
        paths: root.glyph
        size: 18
        color: root.active ? Theme.bg : root.danger ? Theme.terracotta : Theme.subtext
    }
    opacity: enabled ? 1 : 0.65
}
