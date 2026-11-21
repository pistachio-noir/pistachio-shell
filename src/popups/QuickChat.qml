import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland // the layer's keyboard and name, and the window's picture (Wayland protocols, not a compositor module)
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls

// The quick chat (owner's boards pistachio-shell-design/QuickChat*.html, 13 November 2026): a 560 px panel centred
// 16 px above the bar, growing upwards with the conversation. Start (four suggestions), with context
// (the selected text as a card, Include: the active window's picture, the clipboard; Snip a region goes on to Lens),
// replying (the answer as it's written, Esc stops), answer (code blocks with Copy, a callout; Copy,
// Retry and Open in the provider's app), couldn't reach (Try again, Edit question) and recent chats
// (search, Today / Yesterday / earlier, ↑↓ Enter Esc). Esc closes it, and so does a click beside it
// (owner's call, 13 November 2026): its layer covers the screen while it's open, as the launcher's does,
// since with the keyboard held exclusively Hyprland's focus grab doesn't clear; that click only closes it.
PanelWindow {
    id: root

    readonly property int panelWidth: 560
    readonly property int pad: 20
    readonly property int maxBody: Math.max(200, screen.height - Theme.barHeight - Theme.barMargin - 16 - 260)
    property int current // the selected chat in Recent
    property bool menuOpen // the header's provider menu
    property string search

    readonly property var found: {
        const q = root.search.trim().toLowerCase();
        return Chat.chats.filter(c => !q || c.title.toLowerCase().includes(q));
    }
    // Today / Yesterday / the day's date, for Recent's headings
    function dayOf(iso: string): string {
        const d = new Date(iso), now = new Date();
        const days = Math.round((new Date(now.getFullYear(), now.getMonth(), now.getDate()) - new Date(d.getFullYear(), d.getMonth(), d.getDate())) / 86400000);
        return days === 0 ? "Today" : days === 1 ? "Yesterday" : Qt.formatDate(d, "d MMMM");
    }

    function focusInput() {
        if (Theme.tui)
            tuiChat.focusInput();
        else if (Chat.view === "history")
            searchField.forceActiveFocus();
        else
            input.focusField();
    }

    // the question, after a picture of the window if it's included (taken from its live view)
    function submit(text: string) {
        if (!text.trim() || Chat.writing)
            return;
        const windowView = Theme.tui ? tuiChat.windowView : classicWindowView;
        if (Chat.withWindow && windowView.hasContent && !Chat.windowPicture) {
            const path = `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/pistachio-chat-window-${Date.now()}.png`;
            const grabbed = windowView.grabToImage(result => {
                if (result.saveToFile(path))
                    Chat.windowPicture = path;
                Chat.send(text);
            }, windowView.sourceSize);
            if (grabbed)
                return;
        }
        Chat.send(text);
    }

    function key(event) {
        if (event.key === Qt.Key_Escape) {
            event.accepted = true;
            if (root.menuOpen)
                root.menuOpen = false;
            else if (Chat.writing)
                Chat.stop();
            else if (Chat.view === "history")
                Chat.showHistory(); // back
            else
                Chat.close();
        } else if (Chat.view === "history") {
            if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                event.accepted = true;
                current = Math.max(0, Math.min(found.length - 1, current + (event.key === Qt.Key_Down ? 1 : -1)));
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                event.accepted = true;
                if (found[current])
                    Chat.openChat(found[current].id);
            }
        }
    }

    Connections {
        target: Chat
        function onFocusInput() {
            Qt.callLater(root.focusInput);
        }
        function onViewChanged() {
            root.current = 0;
            root.search = "";
            viewFade.restart();
            Qt.callLater(root.focusInput);
        }
        function onChatIdChanged() {
            if (!Chat.chatId)
                viewFade.restart(); // a new chat
        }
    }

    Reveal {
        id: reveal
        open: Chat.open
        onOpenChanged: if (!open) root.menuOpen = false
    }

    visible: reveal.shown
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "pistachio-panel" // frosted panels: Hyprland blurs the shell's layers by name
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Chat.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // the whole screen while it's open (a click beside the panel closes it); nothing while it fades out
    mask: Region {
        width: Chat.open ? root.width : 0
        height: Chat.open ? root.height : 0
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: mouse => {
            if (root.menuOpen)
                root.menuOpen = false;
            else if (!(Theme.tui ? tuiChat : panel).contains(mapToItem(Theme.tui ? tuiChat : panel, mouse.x, mouse.y)))
                Chat.close();
        }
    }

    // TUI: the boards' frame under the top strip; this file stays its controller
    TuiQuickChat {
        id: tuiChat
        visible: Theme.tui
        controller: root
        progress: reveal.progress
    }

    Shadow {
        id: shadow
        visible: !Theme.tui
        frostable: true
        kind: Theme.shadowPanel
        anchors.fill: panel
        radius: panel.radius
        opacity: panel.opacity
    }

    // Motion (owner's request, 13 November 2026, "more life"): the panel rises and grows a little as
    // it opens; its height eases as content comes and goes (it unrolls upwards, the content kept at its
    // bottom and clipped to its round corners); views cross-fade; suggestions and Recent's rows arrive
    // one after another; a question slides in from the right, an answer rises in; the sparkle turns
    // while an answer is written. One curve and the Theme's durations, as everywhere.
    ClippingRectangle {
        id: panel
        visible: !Theme.tui

        // centred over the bar, 16 px above it (the boards), growing upwards
        x: Math.round((root.width - width) / 2)
        y: root.height - Theme.barHeight - Theme.barMargin - 16 - height + 10 * (1 - reveal.progress)
        width: root.panelWidth
        height: column.implicitHeight + root.pad * 2
        scale: 0.96 + 0.04 * reveal.progress
        transformOrigin: Item.Bottom
        contentInsideBorder: true
        radius: Theme.panelRadius

        Behavior on height {
            enabled: reveal.shown && reveal.progress === 1
            NumberAnimation {
                duration: Theme.motionDuration
                easing.type: Theme.easing
            }
        }
        color: Theme.surface
        border.width: 1
        border.color: Theme.overlay2
        opacity: reveal.progress
        focus: true
        Keys.onPressed: event => root.key(event)

        // the provider menu, under the header's name
        Rectangle {
            visible: root.menuOpen
            z: 2
            x: root.pad - panel.border.width
            y: column.y + 46
            width: 230
            height: menuColumn.implicitHeight + 12
            radius: Theme.chipRadius
            color: Theme.overlay
            border.width: 1
            border.color: Theme.overlay2

            Column {
                id: menuColumn
                x: 6
                y: 6
                width: parent.width - 12

                Repeater {
                    model: [
                        { choice: "claude", title: "Claude", detail: Chat.modelOf("claude"), glyph: Icons.sparkles, tint: Theme.clay },
                        { choice: "codex", title: "ChatGPT", detail: Chat.modelOf("codex"), glyph: Icons.message, tint: Theme.teal },
                        { choice: "both", title: "Ask both", detail: `Each answers, then ${Chat.nameOf(Chat.preferred)} combines`, glyph: Icons.layers, tint: Theme.lavender }
                    ]

                    Rectangle {
                        id: entry
                        required property var modelData
                        readonly property bool chosen: modelData.choice === "both" ? Chat.both : !Chat.both && Chat.provider === modelData.choice
                        width: menuColumn.width
                        height: 48
                        radius: 14
                        color: entryMouse.containsMouse ? Theme.overlay2 : "transparent"

                        Icon {
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            size: 16
                            paths: entry.modelData.glyph
                            color: entry.modelData.tint
                        }

                        Column {
                            x: 40
                            width: parent.width - 70
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                text: entry.modelData.title
                                color: Theme.textBright
                                font.family: Theme.fontUi
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                            Text {
                                width: parent.width
                                text: entry.modelData.detail
                                elide: Text.ElideRight
                                color: Theme.subtext
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                        }

                        Icon {
                            visible: entry.chosen
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            size: 15
                            paths: Icons.check
                            color: Theme.pistachio
                        }

                        MouseArea {
                            id: entryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Chat.choice = entry.modelData.choice === Chat.preferred ? "" : entry.modelData.choice;
                                root.menuOpen = false;
                                root.focusInput();
                            }
                        }
                    }
                }
            }
        }

        Column {
            id: column

            x: root.pad - panel.border.width
            // at the panel's bottom: while its height eases, the top is what's still unrolling
            y: panel.height - root.pad - implicitHeight - panel.border.width
            width: panel.width - root.pad * 2
            spacing: 16

            NumberAnimation {
                id: viewFade
                target: column
                property: "opacity"
                from: 0.55
                to: 1
                duration: Theme.motionDuration
                easing.type: Theme.easing
            }

            // ---- the header: who answers, and New / Recent / Open in its app / Close -------------
            Item {
                width: parent.width
                height: 40

                Rectangle {
                    width: 36
                    height: 36
                    radius: 18
                    anchors.verticalCenter: parent.verticalCenter
                    color: who.containsMouse || root.menuOpen ? Theme.overlay2 : Theme.overlay

                    Icon {
                        id: avatarGlyph
                        anchors.centerIn: parent
                        size: 18
                        paths: Chat.both ? Icons.layers : Chat.provider === "codex" ? Icons.message : Icons.sparkles

                        // turning while an answer is written, then easing back upright
                        RotationAnimation on rotation {
                            running: Chat.writing && Chat.open
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 2400
                            onRunningChanged: if (!running) upright.restart()
                        }
                        NumberAnimation {
                            id: upright
                            target: avatarGlyph
                            property: "rotation"
                            to: avatarGlyph.rotation > 180 ? 360 : 0
                            duration: Theme.motionDuration
                            easing.type: Theme.easing
                            onFinished: avatarGlyph.rotation = 0
                        }
                        color: Chat.both ? Theme.lavender : Chat.provider === "codex" ? Theme.teal : Theme.clay
                    }
                }

                // who answers: a click opens the menu (Claude, ChatGPT, Ask both) for this chat
                MouseArea {
                    id: who
                    width: 46 + whoText.width + 22
                    height: parent.height
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.menuOpen = !root.menuOpen
                }

                Column {
                    id: whoText
                    x: 46
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Row {
                        spacing: 4

                        Text {
                            text: Chat.providerName
                            color: Theme.textBright
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            size: 13
                            paths: Icons.chevronDown
                            color: Theme.subtext
                        }
                    }

                    Text {
                        text: "Quick chat" + (Chat.view === "history" ? " · recent" : Chat.hasContext && !Chat.messages.length ? " · with context" : "")
                        color: Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    ChatButton {
                        glyph: Icons.plus
                        tip: "New chat"
                        onClicked: Chat.newChat()
                    }
                    ChatButton {
                        glyph: Icons.clock
                        tip: "Recent chats"
                        active: Chat.view === "history"
                        onClicked: Chat.showHistory()
                    }
                    ChatButton {
                        glyph: Icons.externalLink
                        tip: Chat.provider === "codex" ? "Open in ChatGPT" : "Open in Claude Desktop"
                        onClicked: Chat.openExternally()
                    }
                    ChatButton {
                        glyph: Icons.close
                        tip: "Close"
                        onClicked: Chat.close()
                    }
                }
            }

            // ---- Recent chats ---------------------------------------------------------------------
            Rectangle {
                visible: Chat.view === "history"
                width: parent.width
                height: 48
                radius: 24
                color: Theme.bg
                border.width: 1
                border.color: Theme.overlay2

                Icon {
                    x: 18
                    anchors.verticalCenter: parent.verticalCenter
                    size: 18
                    paths: Icons.search
                    color: Theme.subtext
                }

                TextField {
                    id: searchField
                    x: 46
                    width: parent.width - 62
                    anchors.verticalCenter: parent.verticalCenter
                    padding: 0
                    background: null
                    placeholderText: "Search recent chats"
                    placeholderTextColor: Theme.subtext
                    color: Theme.textBright
                    selectionColor: Theme.overlay2
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    text: root.search
                    onTextEdited: {
                        root.search = text;
                        root.current = 0;
                    }
                    Keys.onPressed: event => root.key(event)
                }
            }

            Flickable {
                id: historyList
                visible: Chat.view === "history"
                width: parent.width
                height: Math.min(contentHeight, root.maxBody)
                contentWidth: width
                contentHeight: historyColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: historyColumn
                    width: parent.width
                    spacing: 8

                    Text {
                        visible: !root.found.length
                        width: parent.width
                        topPadding: 8
                        bottomPadding: 8
                        text: Chat.chats.length ? "No chats match." : "No chats yet. Ask something first."
                        color: Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                    }

                    Repeater {
                        model: ScriptModel {
                            values: root.found
                            objectProp: "id"
                        }

                        Column {
                            id: chatRow
                            required property var modelData
                            required property int index
                            property real appear: 0
                            opacity: appear
                            transform: Translate {
                                y: (1 - chatRow.appear) * 8
                            }
                            SequentialAnimation on appear {
                                PauseAnimation {
                                    duration: Math.min(chatRow.index, 8) * 30
                                }
                                NumberAnimation {
                                    to: 1
                                    duration: Theme.motionDuration + 60
                                    easing.type: Theme.easing
                                }
                            }
                            readonly property string day: root.dayOf(modelData.time)
                            readonly property bool firstOfDay: index === 0 || root.dayOf(root.found[index - 1].time) !== day
                            readonly property bool selected: index === root.current
                            width: historyColumn.width
                            spacing: 8

                            Text {
                                visible: chatRow.firstOfDay
                                topPadding: chatRow.index > 0 ? 6 : 0
                                x: 4
                                text: chatRow.day.toUpperCase()
                                color: Theme.subtext
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                font.letterSpacing: 0.6
                            }

                            Rectangle {
                                width: parent.width
                                height: 54
                                radius: Theme.chipRadius
                                color: chatRow.selected ? Theme.pistachio : rowMouse.containsMouse ? Theme.overlay2 : Theme.overlay

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.hoverDuration
                                        easing.type: Theme.easing
                                    }
                                }

                                Text {
                                    x: 16
                                    width: parent.width - 90
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: chatRow.modelData.title
                                    elide: Text.ElideRight
                                    color: chatRow.selected ? Theme.bg : Theme.textBright
                                    font.family: Theme.fontUi
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Qt.formatTime(new Date(chatRow.modelData.time), "HH:mm")
                                    color: chatRow.selected ? Theme.bg : Theme.subtext
                                    font.family: Theme.fontUi
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    font.features: { "tnum": 1 }
                                }

                                MouseArea {
                                    id: rowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Chat.openChat(chatRow.modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            // ---- Start: the suggestions -----------------------------------------------------------
            Column {
                visible: Chat.view === "chat" && !Chat.messages.length && !Chat.writing && !Chat.includeShown && !Chat.hasContext
                width: parent.width
                spacing: 6

                Text {
                    text: "What do you need?"
                    color: Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: 17
                    font.weight: Font.ExtraBold
                }

                Text {
                    bottomPadding: 10
                    text: `Short questions, quick answers. Long chats open in ${Chat.provider === "codex" ? "ChatGPT" : "Claude Desktop"}.`
                    color: Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }

                Grid {
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 10

                    Repeater {
                        model: [
                            { kind: "error", title: "Explain this error", glyph: Icons.lightbulb, tint: Theme.gold },
                            { kind: "clipboard", title: "Summarise my clipboard", glyph: Icons.summarise, tint: Theme.sageBlue },
                            { kind: "translate", title: "Translate to English", glyph: Icons.languages, tint: Theme.teal },
                            { kind: "oneliner", title: "Write a shell one-liner", glyph: Icons.terminal, tint: Theme.lavender }
                        ]

                        Rectangle {
                            id: suggestion
                            required property var modelData
                            required property int index
                            property real appear: Chat.open ? 1 : 0
                            Behavior on appear {
                                SequentialAnimation {
                                    PauseAnimation {
                                        duration: Chat.open ? 60 + suggestion.index * 35 : 0
                                    }
                                    NumberAnimation {
                                        duration: Theme.motionDuration + 60
                                        easing.type: Theme.easing
                                    }
                                }
                            }
                            opacity: appear
                            transform: Translate {
                                y: (1 - suggestion.appear) * 10
                            }
                            scale: suggestionMouse.containsMouse ? 1.02 : 1
                            Behavior on scale {
                                NumberAnimation {
                                    duration: Theme.hoverDuration
                                    easing.type: Theme.easing
                                }
                            }
                            width: (column.width - 10) / 2
                            height: 56
                            radius: Theme.chipRadius
                            color: suggestionMouse.containsMouse ? Theme.overlay2 : Theme.overlay
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.title

                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.hoverDuration
                                    easing.type: Theme.easing
                                }
                            }

                            Rectangle {
                                x: 10
                                width: 36
                                height: 36
                                radius: 18
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.overlay2

                                Icon {
                                    anchors.centerIn: parent
                                    size: 17
                                    paths: suggestion.modelData.glyph
                                    color: suggestion.modelData.tint
                                }
                            }

                            Text {
                                x: 56
                                width: parent.width - 66
                                anchors.verticalCenter: parent.verticalCenter
                                text: suggestion.modelData.title
                                elide: Text.ElideRight
                                color: Theme.textBright
                                font.family: Theme.fontUi
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }

                            MouseArea {
                                id: suggestionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Chat.suggest(suggestion.modelData.kind)
                            }
                        }
                    }
                }
            }

            // ---- the conversation -----------------------------------------------------------------
            Flickable {
                id: conversation
                visible: Chat.view === "chat" && (Chat.messages.length > 0 || Chat.writing)
                width: parent.width
                height: Math.min(contentHeight, root.maxBody)
                contentWidth: width
                contentHeight: talk.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                // the newest at the bottom stays in view as it grows
                onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

                Column {
                    id: talk
                    width: parent.width
                    spacing: 14

                    Repeater {
                        // a message added keeps the others as they are (a plain list remade them all)
                        model: ScriptModel {
                            values: Chat.messages
                        }

                        Item {
                            id: said
                            required property var modelData
                            required property int index
                            // arriving: a question from the right, an answer from below; an answer that
                            // was just written out on screen is already there
                            property real appear: 0
                            opacity: appear
                            transform: Translate {
                                x: said.mine ? (1 - said.appear) * 18 : 0
                                y: said.mine ? 0 : (1 - said.appear) * 10
                            }
                            NumberAnimation on appear {
                                id: arrive
                                running: false
                                to: 1
                                duration: Theme.motionDuration + 60
                                easing.type: Theme.easing
                            }
                            Component.onCompleted: {
                                if (!said.mine && Chat.streamed && index === Chat.messages.length - 1)
                                    appear = 1;
                                else
                                    arrive.start();
                            }
                            readonly property bool mine: modelData.role === "user"
                            readonly property bool lastAnswer: !mine && index === Chat.messages.length - 1 && !Chat.writing
                            width: talk.width
                            height: mine ? bubble.height : answerColumn.implicitHeight

                            // a question: a pill on the right
                            Rectangle {
                                id: bubble
                                visible: said.mine
                                anchors.right: parent.right
                                width: Math.min(parent.width * 0.85, question.implicitWidth + 32)
                                height: question.implicitHeight + (contextLine.visible ? contextLine.implicitHeight + 4 : 0) + 22
                                radius: Theme.chipRadius
                                color: Theme.overlay

                                Text {
                                    id: question
                                    x: 16
                                    y: 11
                                    width: parent.width - 32
                                    text: said.modelData.text
                                    wrapMode: Text.Wrap
                                    color: Theme.textBright
                                    font.family: Theme.fontUi
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    id: contextLine
                                    visible: said.mine && (said.modelData.context ?? "") !== ""
                                    x: 16
                                    anchors.top: question.bottom
                                    anchors.topMargin: 4
                                    width: parent.width - 32
                                    text: `With ${(said.modelData.context ?? "").charAt(0).toLowerCase()}${(said.modelData.context ?? "").slice(1)}`
                                    elide: Text.ElideRight
                                    color: Theme.subtext
                                    font.family: Theme.fontUi
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }
                            }

                            // an answer, and under the latest its Copy / Retry / Open
                            Column {
                                id: answerColumn
                                visible: !said.mine
                                width: parent.width
                                spacing: 10

                                ChatMarkdown {
                                    width: parent.width
                                    markdown: said.mine ? "" : said.modelData.text
                                }

                                Text {
                                    visible: said.modelData.stopped === true
                                    text: "Stopped"
                                    color: Theme.subtext
                                    font.family: Theme.fontUi
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }

                                Row {
                                    visible: said.lastAnswer
                                    spacing: 6

                                    ChatButton {
                                        size: 36
                                        glyph: copiedAnswer.running ? Icons.check : Icons.copy
                                        tip: "Copy the answer"
                                        onClicked: {
                                            Chat.copy(said.modelData.text);
                                            copiedAnswer.restart();
                                        }
                                    }
                                    ChatButton {
                                        size: 36
                                        glyph: Icons.refresh
                                        tip: "Ask again"
                                        onClicked: Chat.retry()
                                    }
                                    ChatButton {
                                        size: 36
                                        glyph: Icons.externalLink
                                        tip: Chat.provider === "codex" ? "Continue in ChatGPT" : "Continue in Claude Desktop"
                                        onClicked: Chat.openExternally()
                                    }
                                }

                                Timer {
                                    id: copiedAnswer
                                    interval: 1500
                                }
                            }
                        }
                    }

                    // the answer as it's written (Claude), and the "Writing · 2 s" line under it
                    Column {
                        visible: Chat.writing
                        width: parent.width
                        spacing: 12

                        ChatMarkdown {
                            visible: Chat.partial !== ""
                            width: parent.width
                            markdown: Chat.partial
                            writing: true
                        }

                        Item {
                            width: parent.width
                            height: 18

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Repeater {
                                    model: 3

                                    Rectangle {
                                        required property int index
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 6
                                        height: 6
                                        radius: 3
                                        color: Theme.pistachio
                                        opacity: 0.3 + 0.7 * Math.max(0, Math.sin((Chat.seconds * 4 - index * 0.8)))
                                    }
                                }

                                Text {
                                    leftPadding: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Chat.both && !Chat.combining ? "Asking both" : Chat.combining ? "Combining" : "Writing"
                                    color: Theme.subtext
                                    font.family: Theme.fontUi
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: `${Math.floor(Chat.seconds)} s`
                                color: Theme.subtext
                                font.family: Theme.fontUi
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                font.features: { "tnum": 1 }
                            }
                        }
                    }

                    // couldn't answer: Try again, Edit question
                    Rectangle {
                        id: errorCard
                        visible: Chat.state === "error"
                        onVisibleChanged: if (visible) errorRise.restart()
                        transform: Translate {
                            id: errorLift
                        }
                        ParallelAnimation {
                            id: errorRise
                            NumberAnimation { target: errorCard; property: "opacity"; from: 0; to: 1; duration: Theme.motionDuration + 60; easing.type: Theme.easing }
                            NumberAnimation { target: errorLift; property: "y"; from: 10; to: 0; duration: Theme.motionDuration + 60; easing.type: Theme.easing }
                        }
                        width: parent.width
                        height: errorColumn.implicitHeight + 32
                        radius: Theme.chipRadius
                        color: Theme.overlay

                        Rectangle {
                            x: 16
                            y: 16
                            width: 36
                            height: 36
                            radius: 18
                            color: Theme.overlay2

                            Icon {
                                anchors.centerIn: parent
                                size: 17
                                paths: Chat.error?.unavailable ? Icons.wifiOff : Icons.triangleAlert
                                color: Theme.terracotta
                            }
                        }

                        Column {
                            id: errorColumn
                            x: 64
                            y: 16
                            width: parent.width - 80
                            spacing: 4

                            Text {
                                text: Chat.error?.unavailable ? `Couldn’t reach ${Chat.providerName}` : `${Chat.providerName} couldn’t answer`
                                color: Theme.textBright
                                font.family: Theme.fontUi
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }

                            Text {
                                width: parent.width
                                text: Chat.error?.unavailable ? "Check your connection. Your question is saved." : (Chat.error?.message ?? "")
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                color: Theme.subtext
                                font.family: Theme.fontUi
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }

                            Row {
                                topPadding: 10
                                x: -48
                                spacing: 8

                                ActionButton {
                                    text: "Try again"
                                    icon: Icons.refresh
                                    primary: true
                                    onClicked: Chat.retry()
                                }
                                ActionButton {
                                    text: "Edit question"
                                    base: Theme.overlay2
                                    onClicked: Chat.editQuestion()
                                }
                            }
                        }
                    }
                }
            }

            // ---- what goes with the next question -------------------------------------------------
            Column {
                visible: Chat.view === "chat" && (Chat.includeShown || Chat.hasContext)
                width: parent.width
                spacing: 12

                // the selected text, as on the context board
                Rectangle {
                    visible: Chat.selection !== null
                    width: parent.width
                    height: 60
                    radius: Theme.chipRadius
                    color: Theme.overlay

                    Rectangle {
                        x: 10
                        width: 52
                        height: 40
                        radius: 10
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.bg

                        Column {
                            anchors.centerIn: parent
                            spacing: 4
                            Rectangle { width: 30; height: 3; radius: 1.5; color: Theme.terracotta }
                            Rectangle { width: 24; height: 3; radius: 1.5; color: Theme.subtext }
                            Rectangle { width: 32; height: 3; radius: 1.5; color: Theme.sageBlue }
                            Rectangle { width: 20; height: 3; radius: 1.5; color: Theme.subtext }
                        }
                    }

                    Column {
                        x: 74
                        width: parent.width - 74 - 52
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: Chat.selection?.label ?? ""
                            elide: Text.ElideRight
                            color: Theme.textBright
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }

                        Text {
                            width: parent.width
                            text: Chat.selection ? `${Chat.selection.lines} ${Chat.selection.lines === 1 ? "line" : "lines"} · ${Chat.selection.first}` : ""
                            elide: Text.ElideRight
                            color: Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }

                    ChatButton {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        size: 36
                        glyph: Icons.close
                        tip: "Remove the selected text"
                        onClicked: Chat.selection = null
                    }
                }

                // the active window's picture, live while it's included
                Rectangle {
                    visible: Chat.withWindow && Chat.windowSource !== null
                    width: parent.width
                    height: 60
                    radius: Theme.chipRadius
                    color: Theme.overlay

                    Rectangle {
                        x: 10
                        width: 52
                        height: 40
                        radius: 10
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.bg
                        clip: true

                        ScreencopyView {
                            id: classicWindowView
                            anchors.fill: parent
                            captureSource: Chat.withWindow && Chat.open && !Theme.tui ? Chat.windowSource : null
                            live: false
                        }
                    }

                    Text {
                        x: 74
                        width: parent.width - 74 - 52
                        anchors.verticalCenter: parent.verticalCenter
                        text: `A picture of ${Chat.windowApp || "the active window"}`
                        elide: Text.ElideRight
                        color: Theme.textBright
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }

                    ChatButton {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        size: 36
                        glyph: Icons.close
                        tip: "Leave the window out"
                        onClicked: Chat.withWindow = false
                    }
                }

                Row {
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        rightPadding: 4
                        text: "Include"
                        color: Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    ChatInclude {
                        visible: Chat.windowSource !== null
                        text: "Active window"
                        glyph: Icons.monitor
                        on: Chat.withWindow
                        onClicked: Chat.withWindow = !Chat.withWindow
                    }
                    ChatInclude {
                        text: "Clipboard"
                        glyph: Icons.clipboard
                        on: Chat.withClipboard
                        onClicked: Chat.withClipboard = !Chat.withClipboard
                    }
                    // on to Lens (owner's call): the chat closes and Lens's area selection starts
                    ChatInclude {
                        text: "Snip a region"
                        glyph: Icons.scanSearch
                        on: false
                        onClicked: Chat.snip()
                    }
                }
            }

            // ---- the input -------------------------------------------------------------------------
            Rectangle {
                id: input

                visible: Chat.view === "chat"
                width: parent.width
                height: Math.min(136, Math.max(52, field.contentHeight + 22))
                radius: 26
                color: Theme.bg
                border.width: 1
                border.color: Theme.overlay2

                function focusField() {
                    field.forceActiveFocus();
                    field.cursorPosition = field.length;
                }

                ChatButton {
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    size: 40
                    glyph: Icons.paperclip
                    tip: "Include something"
                    active: Chat.includeShown
                    onClicked: {
                        Chat.includeShown = !Chat.includeShown;
                        input.focusField();
                    }
                }

                Flickable {
                    id: fieldScroll
                    x: 54
                    y: 11
                    width: parent.width - x - 56
                    height: parent.height - 22
                    contentWidth: width
                    contentHeight: Math.max(height, field.height)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    function ensureCursor() {
                        const top = field.y + field.cursorRectangle.y;
                        const bottom = top + field.cursorRectangle.height;
                        if (contentY > top)
                            contentY = top;
                        else if (contentY + height < bottom)
                            contentY = bottom - height;
                        contentY = Math.max(0, Math.min(contentY, contentHeight - height));
                    }

                    TextArea {
                        id: field
                        width: fieldScroll.width
                        height: contentHeight
                        y: Math.max(0, (fieldScroll.height - height) / 2) // short text centred, as Lens's (CLAUDE.md)
                        padding: 0
                        text: Chat.draft
                        onTextChanged: if (Chat.draft !== text) Chat.draft = text
                        onCursorRectangleChanged: fieldScroll.ensureCursor()
                        placeholderText: Chat.messages.length ? "Ask a follow-up…" : Chat.both ? "Ask both anything…" : `Ask ${Chat.providerName} anything…`
                        placeholderTextColor: Theme.subtext
                        wrapMode: TextEdit.Wrap
                        color: Theme.textBright
                        selectionColor: Theme.overlay2
                        selectedTextColor: Theme.textBright
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        background: null
                        cursorDelegate: Rectangle {
                            width: 2
                            height: field.font.pixelSize + 6
                            radius: 1
                            color: Theme.pistachio
                            visible: field.activeFocus
                        }
                        Keys.onPressed: event => {
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                event.accepted = true;
                                if (!Chat.writing)
                                    root.submit(text); // while writing: "Enter send when done"
                            } else {
                                root.key(event);
                            }
                        }
                    }
                }

                Rectangle {
                    readonly property bool ready: !Chat.writing && Chat.draft.trim() !== ""
                    width: 44
                    height: 44
                    radius: 22
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    color: ready ? Theme.pistachio : sendMouse.containsMouse ? Theme.overlay2 : Theme.overlay
                    Accessible.role: Accessible.Button
                    Accessible.name: Chat.writing ? "Stop" : "Send"

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.hoverDuration
                            easing.type: Theme.easing
                        }
                    }

                    Icon {
                        anchors.centerIn: parent
                        paths: Chat.writing ? Icons.stop : Icons.arrowUp
                        size: Chat.writing ? 14 : 20
                        color: parent.ready ? Theme.bg : Theme.text
                        transform: Translate {
                            id: arrowLift
                        }
                    }

                    // the arrow lifts once as a question goes
                    SequentialAnimation {
                        id: sent
                        NumberAnimation { target: arrowLift; property: "y"; to: -7; duration: 90; easing.type: Theme.easing }
                        NumberAnimation { target: arrowLift; property: "y"; to: 0; duration: Theme.motionDuration; easing.type: Theme.easing }
                    }
                    Connections {
                        target: Chat
                        function onStateChanged() {
                            if (Chat.writing)
                                sent.restart();
                        }
                    }

                    MouseArea {
                        id: sendMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Chat.writing ? Chat.stop() : root.submit(field.text)
                    }
                }
            }

            // ---- the keys --------------------------------------------------------------------------
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14

                Repeater {
                    model: Chat.view === "history" ? [["↑ ↓", "move"], ["Enter", "open"], ["Esc", "back"]]
                        : Chat.writing ? [["Esc", "stop"], ["Enter", "send when done"]]
                        : [["Enter", "send"], ["Shift+Enter", "new line"], ["Esc", "close"]]

                    Row {
                        required property var modelData
                        spacing: 4

                        Text {
                            text: modelData[0]
                            color: Theme.text
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            font.weight: Font.Bold
                        }
                        Text {
                            text: modelData[1]
                            color: Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }
                }
            }
        }
    }
}
