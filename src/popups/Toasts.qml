import qs
import qs.components
import qs.services
import Quickshell
import QtQuick

// Notification popups (Toasts board), stacked upward with the newest nearest the bar. The bar positions it.
PanelWindow {
    id: root

    exclusiveZone: 0
    implicitWidth: 400
    implicitHeight: Math.max(1, stack.implicitHeight)
    color: "transparent"

    Column {
        id: stack

        width: parent.width
        spacing: 12

        Repeater {
            // keeps existing toasts (and their timers) when one is added or removed
            model: ScriptModel {
                values: Notifs.popups
            }

            Toast {}
        }
    }

    component Toast: Rectangle {
        id: toast

        required property var modelData
        readonly property var n: modelData
        readonly property bool critical: Notifs.isCritical(n)
        readonly property var buttons: n.actions.filter(a => a.identifier !== "default")
        property var after // what to do once faded out

        // fade out sinking 12 px, then `then`
        function leave(then) {
            if (leaving.running)
                return;
            after = then;
            leaving.start();
        }

        width: parent.width
        height: Math.max(icon.height, content.implicitHeight) + 32
        radius: 24
        color: Theme.bgAlt
        border.width: 1
        border.color: Theme.overlay2
        opacity: 0
        transform: Translate {
            id: rise
            y: 12
        }
        Accessible.role: critical ? Accessible.AlertMessage : Accessible.StatusBar
        Accessible.name: n.summary + ". " + n.body

        // fade in and rise 12 px
        Component.onCompleted: arrive.start()

        ParallelAnimation {
            id: arrive

            NumberAnimation {
                target: toast
                property: "opacity"
                to: 1
                duration: Theme.motionDuration
                easing.type: Theme.easing
            }
            NumberAnimation {
                target: rise
                property: "y"
                to: 0
                duration: Theme.motionDuration
                easing.type: Theme.easing
            }
        }

        ParallelAnimation {
            id: leaving

            NumberAnimation {
                target: toast
                property: "opacity"
                to: 0
                duration: Theme.motionDuration
                easing.type: Theme.easing
            }
            NumberAnimation {
                target: rise
                property: "y"
                to: 12
                duration: Theme.motionDuration
                easing.type: Theme.easing
            }
            onFinished: toast.after()
        }

        // Critical ones stay until dismissed. expireTimeout arrives in milliseconds (the 0.3.2 docs say
        // seconds; checked with notify-send -t); 0 or less means "server default".
        Timer {
            running: !toast.critical
            interval: toast.n.expireTimeout > 0 ? toast.n.expireTimeout : 5000
            onTriggered: toast.leave(() => Notifs.hidePopup(toast.n))
        }

        // Clicking the toast runs its default action and hides it; it stays in the centre.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                Notifs.invokeDefault(toast.n);
                Notifs.hidePopup(toast.n);
            }
        }

        NotificationIcon {
            id: icon
            x: 16
            y: 16
            notification: toast.n
            critical: toast.critical
        }

        Column {
            id: content

            anchors.left: icon.right
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: 16
            y: 16
            spacing: 10

            Column {
                width: parent.width
                spacing: 2

                Item {
                    width: parent.width
                    height: title.height

                    Text {
                        id: title
                        anchors.left: parent.left
                        anchors.right: when.left
                        anchors.rightMargin: 8
                        text: toast.n.summary
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.textBright
                        font.family: Theme.fontUi
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }

                    Text {
                        id: when
                        anchors.right: parent.right
                        anchors.baseline: title.baseline
                        text: toast.critical ? "Critical" : "now"
                        color: toast.critical ? Theme.terracotta : Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: toast.n.body
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    color: Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    lineHeight: 17
                    lineHeightMode: Text.FixedHeight
                }
            }

            // The app's actions, the first one pistachio, then Dismiss.
            Row {
                visible: toast.buttons.length > 0
                spacing: 8

                Repeater {
                    model: toast.buttons

                    ActionButton {
                        required property var modelData
                        required property int index
                        text: modelData.text
                        primary: index === 0
                        onClicked: modelData.invoke()
                    }
                }

                ActionButton {
                    text: "Dismiss"
                    onClicked: toast.leave(() => toast.n.dismiss())
                }
            }
        }
    }

    component ActionButton: Rectangle {
        id: button

        property string text
        property bool primary

        signal clicked

        width: label.implicitWidth + 32
        height: 40
        radius: 20
        color: primary ? Theme.pistachio : mouse.containsMouse ? Theme.overlay2 : Theme.overlay
        Accessible.role: Accessible.Button
        Accessible.name: text

        Text {
            id: label
            anchors.centerIn: parent
            text: button.text
            textFormat: Text.PlainText
            color: button.primary ? Theme.bg : Theme.text
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: button.primary ? Font.ExtraBold : Font.Bold
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }
}
