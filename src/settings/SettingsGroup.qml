import qs
import QtQuick

Column {
    id: root
    property string title
    property var rows: []
    property bool sideBySide: title === "At a glance"
    // a little life (owner's request, 12 November 2026): on a page change the groups rise in, one after
    // another (SettingsContent bumps `arrival`); rows light up softly under the pointer
    property int order
    property int arrival
    onArrivalChanged: rise.restart()
    transform: Translate { id: lift }
    SequentialAnimation {
        id: rise
        PropertyAction { target: root; property: "opacity"; value: 0 }
        PropertyAction { target: lift; property: "y"; value: 12 }
        PauseAnimation { duration: Math.min(root.order, 6) * 45 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 1; duration: Theme.motionDuration + 60; easing.type: Theme.easing }
            NumberAnimation { target: lift; property: "y"; to: 0; duration: Theme.motionDuration + 60; easing.type: Theme.easing }
        }
    }
    objectName: title === "App rules" ? "setting-rules" : title === "Storage" ? "setting-storage" : ""
    spacing: 8
    SettingsText { visible: root.title !== ""; text: root.title; secondary: true; font.pixelSize: 11; font.weight: Font.Bold; x: 2 }
    Rectangle {
        width: parent.width; height: stack.height
        radius: Theme.tileRadius; color: root.sideBySide ? "transparent" : Theme.overlay
        Grid {
            id: stack
            width: parent.width
            columns: root.sideBySide ? 2 : 1
            columnSpacing: root.sideBySide ? 14 : 0
            Repeater {
                model: root.rows
                Rectangle {
                    required property var modelData
                    required property int index
                    width: (stack.width - stack.columnSpacing * (stack.columns - 1)) / stack.columns
                    height: row.implicitHeight
                    radius: Theme.tileRadius
                    color: root.sideBySide ? (rowHover.hovered ? Theme.overlay2 : Theme.overlay) : rowHover.hovered ? Qt.rgba(Theme.overlay2.r, Theme.overlay2.g, Theme.overlay2.b, 0.45) : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.hoverDuration; easing.type: Theme.easing } }
                    HoverHandler { id: rowHover }
                    SettingsRow { id: row; width: parent.width; height: implicitHeight; spec: modelData; divided: index > 0 && !root.sideBySide }
                }
            }
        }
    }
}
