import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland // the layer's name, which a Hyprland blur rule matches (a Wayland protocol, not a compositor module)
import QtQuick

// Notification popups (Toasts board), stacked upward with the newest nearest the bar. The bar positions it.
PanelWindow {
    id: root

    // room around the toasts for their shadows (Theme.shadowSmall: 36 px blur, 14 px down); the bar
    // places the window with `below`
    readonly property int side: Theme.shadowSmall.blur
    readonly property int above: Theme.shadowSmall.blur - Theme.shadowSmall.y
    readonly property int below: Theme.shadowSmall.blur + Theme.shadowSmall.y
    readonly property bool phoneShown: phoneReveal.shown
    property bool suppressNotifications

    exclusiveZone: 0
    implicitWidth: side + 400 + side
    implicitHeight: above + Math.max(1, stack.implicitHeight) + below
    color: "transparent"
    WlrLayershell.namespace: "pistachio-panel" // frosted panels: Hyprland blurs the shell's layers by name
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

            Toast { visible: !root.suppressNotifications }
        }

        // The phone invitation shares the notification stack and its placement.
        PanelFrame {
            id: phoneToast
            objectName: "phone-toast"
            visible: phoneReveal.shown
            width: parent.width
            height: Math.max(Theme.tui ? 0 : phoneIcon.height, phoneContent.implicitHeight) + (Theme.tui ? 36 : 32)
            radius: Theme.tui ? 0 : 24
            color: Theme.surface
            border.color: Theme.overlay2
            title: Theme.tui ? "focus timer" : ""
            detail: Theme.tui ? "now" : ""
            active: false
            opacity: phoneReveal.progress
            transform: Translate { y: Theme.tui ? 0 : 12 * (1 - phoneReveal.progress) }
            Accessible.role: Accessible.StatusBar
            Accessible.name: "Focus timer is running"
            property real remaining: 1
            NumberAnimation { target: phoneToast; property: "remaining"; from: 1; to: 0; duration: FocusMode.phoneToastDuration; running: FocusMode.phoneToast }
            Rectangle { x: 20; anchors.bottom: parent.bottom; anchors.bottomMargin: 6; width: (parent.width - 40) * phoneToast.remaining; height: Theme.tui ? 2 : 3; radius: Theme.tui ? 0 : 1.5; color: Theme.overlay2 }
            Reveal { id: phoneReveal; open: FocusMode.phoneToast && FocusMode.session !== null && !Showoff.active }
            Shadow { frostable: true; z: -1; kind: Theme.shadowSmall; anchors.fill: parent; radius: parent.radius }
            Rectangle {
                id: phoneIcon
                visible: !Theme.tui
                x: 16; y: 16; width: 40; height: 40; radius: 20
                color: Theme.overlay
                Icon { anchors.centerIn: parent; size: 20; paths: Icons.smartphone; color: Theme.subtext }
            }
            Column {
                id: phoneContent
                anchors.left: Theme.tui ? parent.left : phoneIcon.right
                anchors.leftMargin: Theme.tui ? 16 : 14
                anchors.right: parent.right; anchors.rightMargin: 16
                y: Theme.tui ? 20 : 16
                spacing: 10
                Item {
                    width: parent.width; height: phoneTitle.implicitHeight
                    Text { id: phoneTitle; anchors.left: parent.left; anchors.right: phoneWhen.left; anchors.rightMargin: 8; text: "Focus timer is running"; elide: Text.ElideRight; color: Theme.textBright; font.family: Theme.fontUi; font.pixelSize: Theme.tui ? Theme.tuiTextSize : 14; font.weight: Font.Bold }
                    Text { id: phoneWhen; visible: !Theme.tui; anchors.right: parent.right; anchors.baseline: phoneTitle.baseline; text: "now"; color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 11; font.weight: Font.DemiBold }
                }
                Row {
                    spacing: 8
                    ActionButton { text: "View on phone"; primary: true; onClicked: FocusMode.showPhone() }
                    ActionButton { text: "Dismiss"; onClicked: FocusMode.phoneToast = false }
                }
            }
        }

        // LocalSend's request, transfer or message, nearest the bar (not a notification: it waits for an answer)
        LocalSendToast {}
    }

    // TUI: a frame whose title tab names the app and whose detail says "now", "critical" or "5 new";
    // no round icon, square countdown (drawn by Claude in the TUI notification centre's language)
    component Toast: PanelFrame {
        id: toast

        title: Theme.tui ? (n.appName || "notification").toLowerCase() : ""
        detail: Theme.tui ? (critical ? "critical" : count > 1 ? `${count} new` : "now") : ""
        active: false

        required property var modelData
        readonly property var n: modelData
        readonly property bool critical: Notifs.isCritical(n)
        // the app's actions, or after a right click its rule choices (Notifs.ruleChoices)
        property bool ruling
        readonly property var buttons: ruling ? Notifs.ruleChoices(n.appName ?? "") : n.actions.filter(a => a.identifier !== "default")
        property var after // what to do once faded out
        // its time, and how much of it is left (expireTimeout arrives in milliseconds, though the 0.3.2
        // docs say seconds; checked with notify-send -t; 0 or less means "server default")
        readonly property real lifetime: n.expireTimeout > 0 ? n.expireTimeout : 5000
        property real remaining: 1
        // how many of the app's notifications it stands for, when a flood folded them (Notifs)
        readonly property int count: Notifs.popupCounts[n.id] ?? 1

        // a rule choice applies and the toast goes (Cancel brings back its actions and countdown)
        function choose(action) {
            action.invoke();
            if (!action.rule)
                return;
            ruling = false;
            if (action.cancel)
                resume();
            else
                leave(() => Notifs.hidePopup(n));
        }

        // the countdown again, never with less than 1.5 s left
        function resume() {
            if (critical)
                return;
            countdown.duration = Math.max(1500, remaining * lifetime);
            countdown.start();
        }

        // fade out sinking 12 px, then `then`
        function leave(then) {
            if (leaving.running)
                return;
            after = then;
            leaving.start();
        }

        width: parent.width
        height: Math.max(Theme.tui ? 0 : icon.height, content.implicitHeight) + (Theme.tui ? 36 : 32)
        radius: Theme.tui ? 0 : 24
        color: Theme.surface
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
            frostable: true
            z: -1
            kind: Theme.shadowSmall
            anchors.fill: parent
            radius: parent.radius
        }

        // fade in and rise 12 px, and start the countdown
        Component.onCompleted: {
            arrive.start();
            if (!critical)
                countdown.start();
        }

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

        // The countdown (owner's request, after phase 8): it runs down the bar along the bottom and
        // stops while the pointer is over the toast; it then never has less than 1.5 s left, so the
        // toast doesn't vanish as the pointer leaves. Critical ones stay until dismissed.
        NumberAnimation {
            id: countdown
            target: toast
            property: "remaining"
            to: 0
            duration: toast.lifetime
            onFinished: toast.leave(() => Notifs.hidePopup(toast.n))
        }

        HoverHandler {
            onHoveredChanged: {
                if (hovered)
                    countdown.stop();
                else if (!toast.ruling)
                    toast.resume();
            }
        }

        Rectangle {
            visible: !toast.critical
            x: 20
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            width: (parent.width - 40) * toast.remaining
            height: Theme.tui ? 2 : 3
            radius: Theme.tui ? 0 : 1.5
            color: Theme.overlay2
        }

        // Clicking the toast runs its default action and hides it; it stays in the centre. A right
        // click shows the app's rule choices and holds the countdown.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    toast.ruling = true;
                    countdown.stop();
                } else {
                    Notifs.invokeDefault(toast.n);
                    Notifs.hidePopup(toast.n);
                }
            }
        }

        NotificationIcon {
            id: icon
            visible: !Theme.tui
            x: 16
            y: 16
            notification: toast.n
            critical: toast.critical
        }

        Column {
            id: content

            anchors.left: Theme.tui ? parent.left : icon.right
            anchors.leftMargin: Theme.tui ? 16 : 14
            anchors.right: parent.right
            anchors.rightMargin: 16
            y: Theme.tui ? 20 : 16
            spacing: 10

            Column {
                width: parent.width
                spacing: 2

                // a folded flood: "VESKTOP · 5 NEW" over the newest, as the centre's group headers
                Text {
                    width: parent.width
                    visible: toast.count > 1 && !Theme.tui // the title tab says it
                    bottomPadding: 2
                    text: `${(toast.n.appName || "Notifications").toUpperCase()} · ${toast.count} NEW`
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 0.9
                    font.features: { "tnum": 1 }
                }

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
                        font.pixelSize: Theme.tui ? Theme.tuiTextSize : 14
                        font.weight: Font.Bold
                    }

                    Text {
                        id: when
                        visible: !Theme.tui // the title tab says it
                        width: Theme.tui ? 0 : implicitWidth
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
                    font.pixelSize: Theme.tui ? Theme.tuiTextSize : 12
                    font.weight: Font.Medium
                    lineHeight: 17
                    lineHeightMode: Text.FixedHeight
                }
            }

            // a screenshot's picture (the shell's own notification)
            NotificationPreview {
                width: parent.width
                notification: toast.n
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
                        onClicked: toast.choose(modelData)
                    }
                }

                ActionButton {
                    visible: !toast.ruling // Cancel stands in for it
                    text: "Dismiss"
                    onClicked: toast.leave(() => toast.n.dismiss())
                }
            }
        }
    }
}
