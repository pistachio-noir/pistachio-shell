import qs
import QtQuick

Column {
    id: root
    property string title
    property var rows: []
    property bool sideBySide: title === "At a glance"
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
                    color: root.sideBySide ? Theme.overlay : "transparent"
                    SettingsRow { id: row; width: parent.width; height: implicitHeight; spec: modelData; divided: index > 0 && !root.sideBySide }
                }
            }
        }
    }
}
