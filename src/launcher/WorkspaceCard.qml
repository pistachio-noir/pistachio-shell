import qs
import QtQuick
import QtQuick.Shapes

// A workspace card (LauncherWorkspaces board): its number (pistachio with a dot when current), a mini
// map of its real window layout, the apps on it and a window count. Empty ones get a dashed outline.
Rectangle {
    id: root

    required property var card
    property bool chosen
    property size screenSize

    signal clicked

    readonly property bool empty: card.count === 0

    height: content.implicitHeight + 24
    radius: Theme.tileRadius
    color: chosen ? Theme.overlay2 : empty ? "transparent" : Theme.overlay
    Accessible.role: Accessible.Button
    Accessible.name: `Workspace ${card.id}` + (card.active ? ", current" : "") + (empty ? ", empty" : `, ${card.count} window${card.count === 1 ? "" : "s"}`)

    Shape {
        anchors.fill: parent
        visible: root.empty && !root.chosen
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: Theme.overlay2
            strokeWidth: 1
            strokeStyle: ShapePath.DashLine
            dashPattern: [4, 3]
            fillColor: "transparent"

            PathRectangle {
                x: 0.5
                y: 0.5
                width: root.width - 1
                height: root.height - 1
                radius: root.radius
            }
        }
    }

    Column {
        id: content

        x: 12
        y: 12
        width: root.width - 24
        spacing: 10

        Row {
            spacing: 6

            Text {
                text: root.card.id
                color: root.card.active ? Theme.pistachio : Theme.text
                font.family: Theme.fontUi
                font.pixelSize: 14
                font.weight: Font.ExtraBold
            }

            Rectangle {
                visible: root.card.active
                anchors.verticalCenter: parent.verticalCenter
                width: 6
                height: 6
                radius: 3
                color: Theme.pistachio
            }
        }

        // the windows at their real positions, scaled down; the most recently focused one is lighter
        Rectangle {
            width: parent.width
            height: 56
            radius: 8
            color: Theme.bg

            Item {
                x: 4
                y: 4
                width: parent.width - 8
                height: parent.height - 8

                Repeater {
                    model: root.card.windows

                    Rectangle {
                        required property var modelData
                        readonly property rect b: modelData.bounds

                        x: b.x / root.screenSize.width * parent.width
                        y: b.y / root.screenSize.height * parent.height
                        width: b.width / root.screenSize.width * parent.width
                        height: b.height / root.screenSize.height * parent.height
                        radius: 3
                        color: modelData.recent ? Theme.muted : Theme.overlay2
                    }
                }
            }
        }

        Column {
            width: parent.width
            spacing: 1

            Text {
                width: parent.width
                text: root.empty ? "Empty" : root.card.apps.join(" · ")
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Bold
            }

            Text {
                width: parent.width
                text: root.empty ? "No windows" : root.card.urgent ? "Needs attention" : `${root.card.count} window${root.card.count === 1 ? "" : "s"}`
                elide: Text.ElideRight
                color: root.card.urgent ? Theme.terracotta : Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
