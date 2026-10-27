import qs
import qs.components
import qs.services
import Quickshell
import QtQuick

// Notification centre with the calendar beside it (calendar-notifications board): history, clear all,
// do-not-disturb switch. Two panels 16 px apart, both as tall as the calendar, so the list scrolls in
// what's left; ← → (or h l) change the calendar's month, Home goes back to today. The bar positions it
// and closes it on an outside click.
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
    // Notifications grouped by app (owner's request, after phase 8): the app with the newest one
    // first, newest first within each. `groups.by` maps an app to its notifications, `ordered` is the
    // list in that order; `openGroups` holds the groups shown in full. They stay as they were left
    // until the shell restarts (owner's request), but a group that empties forgets it was open.
    readonly property var groups: {
        const by = {}, order = [];
        for (const n of Notifs.notifications) {
            const k = n.appName ?? "";
            if (!(k in by)) {
                by[k] = [];
                order.push(k);
            }
            by[k].push(n);
        }
        return { by: by, order: order };
    }
    readonly property var ordered: groups.order.reduce((all, k) => all.concat(groups.by[k]), []) // flatMap isn't there
    property var openGroups: ({})

    function toggleGroup(app: string) {
        openGroups = Object.assign({}, openGroups, { [app]: !openGroups[app] });
    }

    onGroupsChanged: {
        const kept = {};
        for (const k in openGroups) {
            if (openGroups[k] && k in groups.by)
                kept[k] = true;
        }
        if (Object.keys(kept).length !== Object.keys(openGroups).length)
            openGroups = kept;
    }
    // room below the panels for their shadows; the bar places the window with it
    readonly property int below: panelShadow.below

    visible: reveal.shown
    focusable: true // for Escape
    exclusiveZone: 0
    implicitWidth: panelShadow.side + panels.width + panelShadow.side
    implicitHeight: panelShadow.above + panels.height + below
    color: "transparent"
    mask: Region {
        item: panels // the shadows' room lets clicks through
    }

    onOpenChanged: {
        if (!open)
            return;
        Notifs.markSeen();
        calendar.showToday(false); // every opening starts at this month, without a slide
    }

    Reveal {
        id: reveal
        open: root.open
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Item {
        id: panels

        x: panelShadow.side
        y: panelShadow.above
        width: calendar.width + 16 + panel.width
        height: calendar.implicitHeight // owner's call: a long list stretched the calendar into empty space
        // fades and grows slightly from the bar, and back
        opacity: reveal.progress
        scale: 0.96 + 0.04 * reveal.progress
        transformOrigin: Item.Bottom
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape)
                root.open = false;
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_H)
                calendar.step(-1, false);
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_L)
                calendar.step(1, false);
            else if (event.key === Qt.Key_Home)
                calendar.showToday(true);
            else
                return;
            event.accepted = true;
        }

        Shadow {
            kind: Theme.shadowPanel
            anchors.fill: calendar
            radius: calendar.radius
        }

        Shadow {
            id: panelShadow
            kind: Theme.shadowPanel
            anchors.fill: panel
            radius: panel.radius
        }

        Calendar {
            id: calendar
            height: parent.height
        }

        Rectangle {
            id: panel

            x: calendar.width + 16
            width: 360
            height: parent.height
            radius: Theme.panelRadius
            color: Theme.bgAlt
            border.width: 1
            border.color: Theme.overlay2

            Item {
                x: 20
                y: 20
                width: parent.width - 40
                height: 44

                Text {
                    x: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Notifications"
                    color: Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: 17
                    font.weight: Font.ExtraBold
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: -8
                    width: clearLabel.implicitWidth + 28
                    height: 44
                    radius: 22
                    color: clearMouse.containsMouse ? Theme.overlay : "transparent"
                    opacity: Notifs.notifications.length > 0 && !(list.clearing && list.clearingApp === null) ? 1 : 0
                    visible: opacity > 0
                    Accessible.role: Accessible.Button
                    Accessible.name: "Clear all"

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.motionDuration
                            easing.type: Theme.easing
                        }
                    }

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
                        onClicked: list.clearAll()
                    }
                }
            }

            // nothing to show: centred in the list's space (owner's request; not on the board); fades in
            // rising 8 px as the last card goes
            Column {
                id: empty

                anchors.centerIn: list
                opacity: list.count === 0 ? 1 : 0
                visible: opacity > 0
                transform: Translate {
                    y: 8 * (1 - empty.opacity)
                }
                Accessible.role: Accessible.StaticText
                Accessible.name: "No notifications"

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.motionDuration
                        easing.type: Theme.easing
                    }
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 56
                    height: 56
                    radius: 28
                    color: Theme.overlay

                    Icon {
                        anchors.centerIn: parent
                        size: 24
                        paths: Icons.inbox
                        color: Theme.sageBlue
                    }
                }

                Item {
                    width: 1
                    height: 14
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Inbox zero"
                    color: Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: 15
                    font.weight: Font.ExtraBold
                }

                Item {
                    width: 1
                    height: 4
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Nothing new here. Enjoy the quiet."
                    color: Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
            }

            ListView {
                id: list
                x: 20
                y: 20 + 44 + 14
                width: parent.width - 40
                height: footer.y - 14 - y
                visible: count > 0
                spacing: 0 // each card keeps 10 px under it, which a folded one gives up
                clip: true
                interactive: contentHeight > height
                // older notifications below what's on screen; worked out from the numbers, because with
                // atYEnd the button once stayed hidden after a reload
                readonly property bool more: count > 0 && contentY + height < originY + contentHeight - 1
                property bool clearing // Clear all or a group's ✕: the cards on screen are leaving
                property var clearingApp: null // the app whose group is going, null for all

                // the cards on screen slide out one after another from the top, then the list empties
                function clearAll() {
                    clear(null);
                }

                // the same for one app's group, from its header
                function clear(app) {
                    if (clearing)
                        return;
                    clearingApp = app;
                    clearing = true;
                    cleared.restart();
                }

                model: ScriptModel {
                    values: root.ordered
                }
                delegate: Entry {}

                // a new card fades in and grows into place; the others slide to make room or close a gap
                add: Transition {
                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Theme.motionDuration
                        easing.type: Theme.easing
                    }
                    NumberAnimation {
                        property: "scale"
                        from: 0.96
                        to: 1
                        duration: Theme.motionDuration
                        easing.type: Theme.easing
                    }
                }
                displaced: Transition {
                    NumberAnimation {
                        property: "y"
                        duration: Theme.motionDuration
                        easing.type: Theme.easing
                    }
                }

                // empties the list once the last card on screen has left (they start up to 120 ms apart)
                Timer {
                    id: cleared
                    interval: 120 + Theme.motionDuration
                    onTriggered: {
                        const app = list.clearingApp;
                        list.clearing = false;
                        if (app === null)
                            Notifs.clearAll();
                        else
                            Notifs.clearApp(app);
                    }
                }
            }

            // The wheel glides: a notch moves where the list is heading by 100 px and it eases there,
            // instead of jumping. A touchpad's pixel steps go to the list as they come.
            MouseArea {
                anchors.fill: list
                acceptedButtons: Qt.NoButton
                onWheel: wheel => {
                    if (wheel.pixelDelta.y !== 0 || wheel.angleDelta.y === 0 || !list.interactive) {
                        glide.stop();
                        wheel.accepted = false;
                        return;
                    }
                    toEnd.stop();
                    list.cancelFlick();
                    const from = glide.running ? glide.to : list.contentY;
                    const end = list.originY + list.contentHeight - list.height;
                    glide.to = Math.max(list.originY, Math.min(end, from - wheel.angleDelta.y / 120 * 100));
                    glide.restart();
                }

                NumberAnimation {
                    id: glide
                    target: list
                    property: "contentY"
                    duration: Theme.motionDuration
                    easing.type: Theme.easing
                    onFinished: list.returnToBounds() // in case the height estimate was off
                }
            }

            // the list fades out at the bottom while there's more below it
            Rectangle {
                x: list.x
                anchors.bottom: list.bottom
                width: list.width
                height: Math.round(list.height * 0.18)
                opacity: list.more ? 1 : 0
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0)
                    }
                    GradientStop {
                        position: 1
                        color: Theme.bgAlt
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.hoverDuration
                        easing.type: Theme.easing
                    }
                }
            }

            // with the fade, a way down to the oldest (owner's request; not on the board)
            Rectangle {
                anchors.horizontalCenter: list.horizontalCenter
                anchors.bottom: list.bottom
                width: 32
                height: 32
                radius: 16
                color: Theme.overlay2
                opacity: list.more ? 1 : 0
                visible: opacity > 0
                Accessible.role: Accessible.Button
                Accessible.name: "Scroll to the oldest notification"

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.hoverDuration
                        easing.type: Theme.easing
                    }
                }

                Icon {
                    anchors.centerIn: parent
                    size: 16
                    paths: Icons.chevronDown
                    color: toEndMouse.containsMouse ? Theme.textBright : Theme.text
                }

                MouseArea {
                    id: toEndMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        glide.stop();
                        toEnd.to = list.contentHeight - list.height + list.originY;
                        toEnd.restart();
                    }
                }

                // a slide to where the end should be, then a snap in case the list's estimate of its
                // height (from the cards made so far) was off
                NumberAnimation {
                    id: toEnd
                    target: list
                    property: "contentY"
                    duration: Theme.motionDuration
                    easing.type: Theme.easing
                    onFinished: list.positionViewAtEnd()
                }
            }

            Item {
                id: footer
                x: 20
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 20
                width: parent.width - 40
                height: 14 + 44

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.overlay
                }

                Icon {
                    id: dndIcon
                    x: 4
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
                    anchors.rightMargin: -4
                    y: 14
                    checked: Notifs.dnd
                    Accessible.name: "Do not disturb"
                    onToggled: Notifs.setDnd(!Notifs.dnd)
                }
            }
        }
    }

    // One notification: icon, title with a dot if new since the centre was last opened, age, body, dismiss.
    // In a group of two or more (one app's), the newest card carries the group's header (app, count,
    // Show all, ✕) and, while the group is folded, the edges of the cards behind it; the others fold
    // to nothing until it opens. Each card keeps 10 px under it.
    component Entry: Item {
        id: entry

        required property var modelData
        // a live notification is destroyed once dismissed, which nulls modelData before the card goes
        // (it has faded out by then): a blank record keeps the bindings from reading null
        readonly property var n: modelData ?? ({ saved: true, summary: "", body: "", appIcon: "", image: "", urgency: 0, time: 0 })
        readonly property bool fresh: Notifs.received(n) > Notifs.seenBefore
        readonly property string group: n.appName ?? ""
        readonly property var members: root.groups.by[group] ?? []
        readonly property bool lead: members.length > 1 && members[0] === modelData // carries the header
        readonly property bool groupOpen: root.openGroups[group] ?? false
        readonly property bool folded: members.length > 1 && !lead && !groupOpen
        readonly property bool clearing: (ListView.view?.clearing ?? false) && (ListView.view.clearingApp === null || ListView.view.clearingApp === group)
        // The app's actions (Open, Reply…), shown only while the pointer is on the card (owner's
        // request): the card grows to make room as they fade in. Records from before a restart have
        // none, and the default action is the click on the card.
        readonly property var buttons: n.saved ? [] : n.actions.filter(a => a.identifier !== "default")
        readonly property bool expanded: hover.hovered && buttons.length > 0 && !leaving.running
        property real reveal: expanded ? 1 : 0
        readonly property int body: Math.max(36, text.implicitHeight + 1) // the icon or the text, whichever is taller
        // eased 0–1: the header, the edges of a folded group, and the card itself (0 while folded away)
        property real headerShown: lead ? 1 : 0
        property real stackShown: lead && !groupOpen ? 1 : 0
        property real shown: folded ? 0 : 1

        // Swiped away: slides out to the right as it fades, after `delay` ms, then runs `then` (unless
        // Clear all is emptying the list); the cards below close the gap (the list's displaced
        // transition). It moves by a Translate: the list resets x when it lays the cards out.
        function leave(delay: int, then) {
            if (leaving.running)
                return;
            pause.duration = delay;
            after = then;
            leaving.start();
        }
        property var after

        // An action dismisses the notification unless it's resident: the card swipes away first.
        function act(action) {
            if (n.resident)
                action.invoke();
            else
                leave(0, () => action.invoke());
        }

        width: ListView.view.width
        height: Math.round(shown * (36 * headerShown + card.height + (members.length > 2 ? 12 : 6) * stackShown + 10))
        visible: shown > 0
        clip: true // a folded card, and one growing as its group opens

        // Clear all: the top card first, the one at the bottom of the list 120 ms later
        onClearingChanged: {
            const view = ListView.view;
            if (clearing && view)
                leave(Math.max(0, Math.min(1, (y - view.contentY) / view.height)) * 120, null);
        }

        // opening at the bottom of the list, it scrolls the buttons into view
        onExpandedChanged: {
            const view = ListView.view;
            const bottom = y + card.y + body + 28 + actions.height + 10;
            if (expanded && view && bottom > view.contentY + view.height) {
                bringIn.to = bottom - view.height;
                bringIn.restart();
            }
        }

        Behavior on reveal {
            NumberAnimation {
                duration: Theme.motionDuration
                easing.type: Theme.easing
            }
        }
        Behavior on headerShown {
            NumberAnimation {
                duration: Theme.motionDuration
                easing.type: Theme.easing
            }
        }
        Behavior on stackShown {
            NumberAnimation {
                duration: Theme.motionDuration
                easing.type: Theme.easing
            }
        }
        Behavior on shown {
            NumberAnimation {
                duration: Theme.motionDuration
                easing.type: Theme.easing
            }
        }

        NumberAnimation {
            id: bringIn
            target: entry.ListView.view
            property: "contentY"
            duration: Theme.motionDuration
            easing.type: Theme.easing
        }

        SequentialAnimation {
            id: leaving

            PauseAnimation {
                id: pause
            }
            ParallelAnimation {
                NumberAnimation {
                    target: swipe
                    property: "x"
                    to: entry.width
                    duration: Theme.motionDuration
                    easing.type: Theme.easing
                }
                NumberAnimation {
                    target: card
                    property: "opacity"
                    to: 0
                    duration: Theme.motionDuration
                    easing.type: Theme.easing
                }
            }
            ScriptAction {
                script: if (!entry.clearing && entry.after) entry.after()
            }
        }

        // The group's header, laid out like the launcher's section headers; it goes with the group.
        // A click anywhere on it, not only on Show all, folds or opens the group (owner's request).
        Item {
            width: entry.width
            height: 36
            opacity: entry.headerShown * (entry.clearing ? 0 : 1)
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.motionDuration
                    easing.type: Theme.easing
                }
            }

            MouseArea {
                id: headerMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleGroup(entry.group)
            }

            Text {
                x: 4
                anchors.verticalCenter: parent.verticalCenter
                text: `${(entry.group || "Other apps").toUpperCase()} · ${entry.members.length}`
                textFormat: Text.PlainText
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 0.9
                font.features: { "tnum": 1 }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: -6
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: toggleLabel.implicitWidth + 24
                    height: 32
                    radius: 16
                    // lights up with the whole header, which does the same
                    color: toggleMouse.containsMouse || headerMouse.containsMouse ? Theme.overlay : "transparent"
                    Accessible.role: Accessible.Button
                    Accessible.name: toggleLabel.text + " " + entry.group

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.hoverDuration
                            easing.type: Theme.easing
                        }
                    }

                    Text {
                        id: toggleLabel
                        anchors.centerIn: parent
                        text: entry.groupOpen ? "Show less" : "Show all"
                        color: toggleMouse.containsMouse || headerMouse.containsMouse ? Theme.textBright : Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: toggleMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleGroup(entry.group)
                    }
                }

                Item {
                    width: 32
                    height: 32
                    Accessible.role: Accessible.Button
                    Accessible.name: `Clear ${entry.group || "these"} notifications`

                    Icon {
                        anchors.centerIn: parent
                        size: 14
                        paths: Icons.close
                        color: clearGroupMouse.containsMouse ? Theme.textBright : Theme.subtext
                    }

                    MouseArea {
                        id: clearGroupMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: entry.ListView.view.clear(entry.group)
                    }
                }
            }
        }

        // a folded group: the next cards' edges peek out under this one, 6 px each; a click opens it
        Repeater {
            model: Math.max(0, Math.min(2, entry.members.length - 1)) // none once the card has gone

            Rectangle {
                required property int index

                z: -1 - index
                x: 10 * (index + 1)
                y: card.y + card.height - height + 6 * (index + 1) * entry.stackShown
                width: entry.width - 20 * (index + 1)
                height: 2 * Theme.tileRadius
                radius: Theme.tileRadius
                color: Theme.overlay
                opacity: (index === 0 ? 0.7 : 0.4) * entry.stackShown * card.opacity
                visible: entry.lead && opacity > 0

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleGroup(entry.group)
                }
            }
        }

        Rectangle {
            id: card

            y: 36 * entry.headerShown
            width: entry.width
            height: entry.body + 28 + Math.round(entry.reveal * (actions.height + 10))
            radius: Theme.tileRadius
            color: Theme.overlay
            transform: Translate {
                id: swipe
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: entry.n.summary + ". " + entry.n.body

            HoverHandler {
                id: hover
            }

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

            // the app's actions, under the text: the first one pistachio, as on the toasts
            Row {
                id: actions

                anchors.left: text.left
                y: 14 + entry.body + 10
                spacing: 8
                opacity: entry.reveal
                visible: opacity > 0

                Repeater {
                    model: entry.buttons

                    ActionButton {
                        required property var modelData
                        required property int index

                        height: 32
                        base: Theme.bgAlt // on the card's overlay, as the launcher's question choices
                        text: modelData.text
                        primary: index === 0
                        onClicked: entry.act(modelData)
                    }
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
                    onClicked: entry.leave(0, () => Notifs.dismiss(entry.n))
                }
            }
        }
    }
}
