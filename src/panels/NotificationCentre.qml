import qs
import qs.components
import qs.services
import Quickshell
import QtQuick

// Notification centre (NotificationCentre board): history, clear all, do-not-disturb switch.
// The bar positions it and closes it on an outside click.
PanelWindow {
    id: root

    // "now", "2 min", "1 h", "3 d"; "" for notifications carried over from before a shell reload
    function age(ms: real): string {
        if (ms <= 0)
            return "";
        const min = Math.floor((clock.date.getTime() - ms) / 60000);
        return min < 1 ? "now" : min < 60 ? `${min} min` : min < 1440 ? `${Math.floor(min / 60)} h` : `${Math.floor(min / 1440)} d`;
    }

    property bool open

    visible: reveal.shown
    focusable: true // for Escape
    exclusiveZone: 0
    implicitWidth: 400
    implicitHeight: panel.height
    color: "transparent"

    onOpenChanged: if (open) Notifs.markSeen()

    Reveal {
        id: reveal
        open: root.open
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Rectangle {
        id: panel

        width: parent.width
        height: content.implicitHeight + 40
        radius: Theme.panelRadius
        color: Theme.bgAlt
        border.width: 1
        border.color: Theme.overlay2
        // fades and grows slightly from the clock chip, and back
        opacity: reveal.progress
        scale: 0.96 + 0.04 * reveal.progress
        transformOrigin: Item.BottomRight
        focus: true
        Keys.onEscapePressed: root.open = false

        Column {
            id: content

            x: 20
            y: 20
            width: parent.width - 40
            spacing: 14

            Item {
                width: parent.width
                height: 44

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Notifications"
                    color: Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: 17
                    font.weight: Font.ExtraBold
                }

                Rectangle {
                    anchors.right: parent.right
                    width: clearLabel.implicitWidth + 28
                    height: 44
                    radius: 22
                    color: clearMouse.containsMouse ? Theme.overlay : "transparent"
                    visible: Notifs.notifications.length > 0
                    Accessible.role: Accessible.Button
                    Accessible.name: "Clear all"

                    Text {
                        id: clearLabel
                        anchors.centerIn: parent
                        text: "Clear all"
                        color: Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Notifs.clearAll()
                    }
                }
            }

            Text {
                visible: Notifs.notifications.length === 0
                text: "No notifications"
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Bold
            }

            ListView {
                width: parent.width
                height: Math.min(contentHeight, root.screen.height * 0.6)
                visible: count > 0
                spacing: 10
                clip: true
                interactive: contentHeight > height
                model: ScriptModel {
                    values: Notifs.notifications
                }
                delegate: Entry {}
            }

            Item {
                width: parent.width
                height: 14 + 44

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.overlay
                }

                Icon {
                    id: dndIcon
                    y: 14 + (44 - height) / 2
                    paths: Icons.bellOff
                    color: Theme.subtext
                }

                Text {
                    anchors.left: dndIcon.right
                    anchors.leftMargin: 12
                    anchors.verticalCenter: dndIcon.verticalCenter
                    text: "Do not disturb"
                    color: Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }

                Switch {
                    anchors.right: parent.right
                    y: 14
                    checked: Notifs.dnd
                    Accessible.name: "Do not disturb"
                    onToggled: Notifs.setDnd(!Notifs.dnd)
                }
            }
        }
    }

    // One notification: icon, title with a dot if new since the centre was last opened, age, body, dismiss.
    component Entry: Rectangle {
        id: entry

        required property var modelData
        readonly property var n: modelData
        readonly property bool fresh: Notifs.received(n) > Notifs.seenBefore

        width: ListView.view.width
        height: Math.max(36, text.implicitHeight + 1) + 28
        radius: Theme.tileRadius
        color: Theme.overlay
        Accessible.role: Accessible.ListItem
        Accessible.name: n.summary + ". " + n.body

        // clicking runs the notification's default action, if it has one
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Notifs.invokeDefault(entry.n)
        }

        NotificationIcon {
            id: icon
            x: 14
            y: 14
            size: 36
            color: Theme.overlay2
            notification: entry.n
            critical: Notifs.isCritical(entry.n)
        }

        Column {
            id: text

            anchors.left: icon.right
            anchors.leftMargin: 12
            anchors.right: dismiss.left
            anchors.rightMargin: 12
            y: 15
            spacing: 2

            Item {
                width: parent.width
                height: title.height

                Rectangle {
                    id: dot
                    anchors.verticalCenter: title.verticalCenter
                    visible: entry.fresh
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.pistachio
                }

                Text {
                    id: title
                    x: entry.fresh ? 14 : 0
                    width: when.x - x - 8
                    text: entry.n.summary
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }

                Text {
                    id: when
                    anchors.right: parent.right
                    anchors.verticalCenter: title.verticalCenter
                    text: root.age(Notifs.received(entry.n))
                    color: Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: entry.n.body
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: 12
                font.weight: Font.Medium
                lineHeight: 17
                lineHeightMode: Text.FixedHeight
            }
        }

        Item {
            id: dismiss
            x: entry.width - 50
            y: 6
            width: 44
            height: 44
            Accessible.role: Accessible.Button
            Accessible.name: "Dismiss notification"

            Icon {
                anchors.centerIn: parent
                size: 14
                paths: Icons.close
                color: dismissMouse.containsMouse ? Theme.textBright : Theme.subtext
            }

            MouseArea {
                id: dismissMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Notifs.dismiss(entry.n)
            }
        }
    }
}
