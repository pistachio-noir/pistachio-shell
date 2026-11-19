import qs
import qs.components
import QtQuick
import QtQuick.Controls.Basic as Basic

// SettingsButton in the Classic look only (Classic.qml): a pill, pistachio while active.
Basic.Button {
    id: root
    property bool active
    property bool quiet
    property list<string> glyph: []
    implicitHeight: 44
    implicitWidth: Math.max(44, contentItem.implicitWidth + 48)
    padding: 18
    leftPadding: padding
    rightPadding: padding
    topPadding: 0
    bottomPadding: 0
    font.family: Classic.fontUi
    font.pixelSize: 12
    font.weight: Font.Bold
    hoverEnabled: true
    background: Rectangle {
        radius: height / 2
        color: root.active ? Theme.pistachio : root.hovered || root.visualFocus ? Theme.overlay : root.quiet ? "transparent" : Theme.overlay2
        border.width: root.visualFocus ? 1 : 0
        border.color: Theme.subtext
        scale: root.pressed ? 0.97 : 1
        Behavior on color { ColorAnimation { duration: Classic.hoverDuration; easing.type: Theme.easing } }
        Behavior on scale { NumberAnimation { duration: Classic.hoverDuration; easing.type: Theme.easing } }
    }
    contentItem: Text {
        text: root.glyph.length ? "" : root.text
        font: root.font
        color: !root.enabled ? Theme.subtext : root.active ? Theme.bg : root.quiet ? Theme.subtext : Theme.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    Icon {
        visible: root.glyph.length > 0
        anchors.centerIn: parent
        paths: root.glyph
        size: 18
        color: root.active ? Theme.bg : Theme.subtext
    }
    opacity: enabled ? 1 : 0.65
}
