import qs
import QtQuick

// The Classic switch (components/Switch.qml without its TUI form): 48×28 track in a 52×44 hit area.
Item {
    id: root
    property bool checked
    signal toggled

    width: 52
    height: 44
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: checked

    Rectangle {
        anchors.centerIn: parent
        width: 48; height: 28; radius: 14
        color: root.checked ? Theme.pistachio : Theme.overlay2
        Behavior on color { ColorAnimation { duration: Classic.hoverDuration; easing.type: Theme.easing } }
        Rectangle {
            x: root.checked ? parent.width - width - 4 : 4
            y: 4; width: 20; height: 20; radius: 10
            color: root.checked ? Theme.bg : Theme.subtext
            Behavior on x { NumberAnimation { duration: Classic.hoverDuration; easing.type: Easing.OutBack } }
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
