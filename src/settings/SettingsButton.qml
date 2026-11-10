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
    implicitWidth: Math.max(44, contentItem.implicitWidth + 48)
    padding: 18
    topPadding: 0
    bottomPadding: 0
    font.family: Theme.fontUi
    font.pixelSize: 12
    font.weight: Font.Bold
    hoverEnabled: true
    background: Rectangle {
        radius: root.card ? Theme.tileRadius : height / 2
        scale: root.animateSelection && !root.active ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: Theme.motionDuration; easing.type: Theme.easing } }
        color: root.card ? root.hovered || root.visualFocus ? Theme.overlay2 : Theme.overlay : root.active ? Theme.pistachio : root.selected ? Theme.overlay2 : root.hovered || root.visualFocus ? Theme.overlay : root.quiet ? "transparent" : Theme.overlay2
        border.width: root.visualFocus ? 1 : 0
        border.color: Theme.subtext
        Behavior on color { ColorAnimation { duration: Theme.hoverDuration; easing.type: Theme.easing } }
    }
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
