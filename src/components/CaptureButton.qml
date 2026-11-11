import qs
import QtQuick

Rectangle {
    id: root
    property string text
    property bool selected
    signal clicked
    implicitWidth: label.implicitWidth + 28
    implicitHeight: 40
    radius: 20
    color: selected ? Theme.pistachio : mouse.containsMouse ? Theme.overlay2 : Theme.overlay
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.checkable: true
    Accessible.checked: selected
    opacity: enabled ? 1 : 0.5
    Behavior on color { ColorAnimation { duration: Theme.hoverDuration; easing.type: Theme.easing } }
    Text {
        id: label; anchors.centerIn: parent; text: root.text
        color: root.selected ? Theme.bg : Theme.text
        font.family: Theme.fontUi; font.pixelSize: 12; font.weight: Font.Bold
    }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked() }
}
