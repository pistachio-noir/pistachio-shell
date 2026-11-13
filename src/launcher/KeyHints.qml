import qs
import QtQuick

Item {
    id: root
    property var hints: []
    property var clickableKeys: ({})
    signal activated(string key)
    objectName: "launcher-key-hints"
    implicitHeight: Theme.tui?Math.max(40,hintsFlow.implicitHeight+20):Math.max(46,hintsFlow.implicitHeight+24)
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
        x: Theme.tui?12:26; y: Theme.tui?10:12
        width: Math.max(0,parent.width-(Theme.tui?24:52))
        spacing: 12

        Repeater {
            model: root.hints

            Row {
                id: hint
                required property var modelData
                readonly property bool clickable: root.clickableKeys[modelData[0]] !== undefined
                spacing: 8

                Rectangle {
                    width: Theme.tui?keyText.implicitWidth:Math.max(22,keyText.implicitWidth+12)
                    height: Theme.tui?20:22
                    radius: Theme.tui?0:7
                    color: Theme.tui?"transparent":hintHover.hovered?Theme.overlay2:Theme.overlay

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
                        font.pixelSize: Theme.tui?Theme.tuiTextSize:12
                        font.weight: Font.ExtraBold
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData[1]
                    color: hintHover.hovered ? Theme.text : Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.tui?Theme.tuiTextSize:12
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
