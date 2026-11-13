import qs
import QtQuick

// TUI's "[c] copy": the key bright in brackets, the label quiet; `on` makes the key pistachio.
Item {
    id: root
    property string key
    property string label
    property bool on
    signal clicked
    implicitWidth: text.implicitWidth
    implicitHeight: Theme.tuiLineHeight
    Accessible.role: Accessible.Button
    Accessible.name: label

    Text {
        id: text
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.StyledText
        text: `<b><font color="${root.on ? Theme.pistachio : Theme.textBright}">[${root.key === " " ? "&nbsp;" : root.key}]</font></b>&nbsp;${root.label}`
        color: mouse.containsMouse ? Theme.textBright : root.on ? Theme.text : Theme.subtext
        font.family: Theme.fontTui
        font.pixelSize: Theme.tuiTextSize
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
