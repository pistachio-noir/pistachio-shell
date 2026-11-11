import qs
import QtQuick

Item {
    id: root
    property var hints: []
    property var clickableKeys: ({})
    signal activated(string key)
    objectName: "launcher-key-hints"
    implicitHeight: Math.max(46, hintsFlow.implicitHeight + 24)
    width: parent.width
    height: implicitHeight

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.overlay
    }

    Flow {
        id: hintsFlow
        objectName: "key-hints-flow"
        x: 26; y: 12
        width: Math.max(0,parent.width-52)
        spacing: 12

        Repeater {
            model: root.hints

            Row {
                id: hint
                required property var modelData
                readonly property bool clickable: root.clickableKeys[modelData[0]] !== undefined
                spacing: 8

                Rectangle {
                    width: Math.max(22, keyText.implicitWidth + 12)
                    height: 22
                    radius: 7
                    color: hintHover.hovered ? Theme.overlay2 : Theme.overlay

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.hoverDuration
                            easing.type: Theme.easing
                        }
                    }

                    Text {
                        id: keyText
                        anchors.centerIn: parent
                        text: modelData[0]
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.ExtraBold
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData[1]
                    color: hintHover.hovered ? Theme.text : Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                // a click does what the key does (owner's request, 5 November 2026); handlers,
                // as a MouseArea would be laid out in the row
                HoverHandler {
                    id: hintHover
                    enabled: hint.clickable
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    enabled: hint.clickable
                    onTapped: root.activated(hint.modelData[0])
                }
            }
        }
    }
}
