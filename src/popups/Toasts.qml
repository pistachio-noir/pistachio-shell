import qs
import qs.components
import qs.services
import Quickshell
import QtQuick

// Notification popups (Toasts board), stacked upward with the newest nearest the bar. The bar positions it.
PanelWindow {
    id: root

    // room around the toasts for their shadows (Theme.shadowSmall: 36 px blur, 14 px down); the bar
    // places the window with `below`
    readonly property int side: Theme.shadowSmall.blur
    readonly property int above: Theme.shadowSmall.blur - Theme.shadowSmall.y
    readonly property int below: Theme.shadowSmall.blur + Theme.shadowSmall.y

    exclusiveZone: 0
    implicitWidth: side + 400 + side
    implicitHeight: above + Math.max(1, stack.implicitHeight) + below
    color: "transparent"
    mask: Region {
        item: stack // the shadows' room lets clicks through
    }

    Column {
        id: stack

        x: root.side
        y: root.above
        width: 400
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

        // beneath the card (z -1), so it fades and rises with it
        Shadow {
            z: -1
            kind: Theme.shadowSmall
            anchors.fill: parent
            radius: parent.radius
        }

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
}
