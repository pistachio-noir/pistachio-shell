import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland // ScreencopyView, the active window's picture (a Wayland protocol, not a compositor module)
import QtQuick
import QtQuick.Controls

// The quick chat in TUI (boards design/TUI/launcher-and-shell/QuickChat{Replying,Context,History}.html):
// a 600 px frame under the top strip, its tab naming who answers (a click picks Claude, ChatGPT or Ask
// both) and "quick chat" or "recent" beside it. Rows of "you" / "claude" with the answer, code in
// frames; the context card and an include line; a "> " input with a block cursor; the keys underneath.
// QuickChat.qml stays the controller (keys, sending with the window's picture, a click beside it), so
// this file only draws. Start (the four suggestions) and the error box have no TUI board: drawn by
// Claude in the boards' language.
PanelFrame {
    id: frame

    required property var controller
    property real progress: 1
    readonly property alias windowView: windowView
    readonly property bool history: Chat.view === "history"
    readonly property bool start: !history && !Chat.messages.length && !Chat.writing && Chat.state !== "error" && !Chat.includeShown && !Chat.hasContext
    readonly property int maxBody: Math.max(200, (parent?.height ?? 800) - Theme.tuiBarHeight - 340)
    readonly property color voice: Chat.both ? Theme.lavender : Chat.provider === "codex" ? Theme.teal : Theme.clay

    function focusInput() {
        if (history)
            searchField.forceActiveFocus();
        else
            field.forceActiveFocus();
    }
    function voiceOf(p: string): color {
        return p === "codex" ? Theme.teal : p === "both" ? Theme.lavender : Theme.clay;
    }
    // Ctrl+H history, Ctrl+N a new chat; the rest goes to the controller (Esc, Recent's arrows)
    function key(event) {
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_H) {
            event.accepted = true;
            Chat.showHistory();
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_N) {
            event.accepted = true;
            Chat.newChat();
        } else
            controller.key(event);
    }

    x: Math.round(((parent?.width ?? 0) - width) / 2)
    y: Theme.tuiBarHeight + 30 + 8 * (1 - progress)
    opacity: progress
    width: 600
    height: body.implicitHeight + 32
    title: Chat.both ? "claude + chatgpt" : Chat.providerName.toLowerCase()
    detail: history ? "recent" : "quick chat"
    color: Theme.tuiSurface
    Accessible.role: Accessible.Dialog
    Accessible.name: "Quick chat"

    // clicks inside don't close it
    MouseArea {
        anchors.fill: parent
        onClicked: frame.controller.menuOpen = false
    }

    // the tab picks who answers
    MouseArea {
        x: 8
        y: -10
        width: Math.min(240, frame.title.length * 8 + 16)
        height: Theme.tuiLineHeight
        cursorShape: Qt.PointingHandCursor
        Accessible.role: Accessible.Button
        Accessible.name: "Choose who answers"
        onClicked: frame.controller.menuOpen = !frame.controller.menuOpen
    }

    Column {
        id: body

        x: 16
        y: 20
        width: parent.width - 32
        spacing: 0

        // ---- Recent -----------------------------------------------------------------------------
        Item {
            visible: frame.history
            width: parent.width
            height: Theme.tuiLineHeight

            Text {
                id: slash
                text: "/ "
                color: Theme.subtext
                font.family: Theme.fontTui
                font.pixelSize: Theme.tuiTextSize
            }

            TextInput {
                id: searchField
                anchors.left: slash.right
                anchors.right: parent.right
                height: parent.height
                verticalAlignment: TextInput.AlignVCenter
                text: frame.controller.search
                onTextEdited: {
                    frame.controller.search = text;
                    frame.controller.current = 0;
                }
                color: Theme.textBright
                selectionColor: Theme.overlay2
                font.family: Theme.fontTui
                font.pixelSize: Theme.tuiTextSize
                Accessible.role: Accessible.EditableText
                Accessible.name: "Search recent chats"
                Keys.onPressed: event => frame.key(event)
                cursorDelegate: Rectangle {
                    width: 8
                    height: Theme.tuiLineHeight - 2
                    color: Theme.pistachio
                    visible: searchField.activeFocus
                }

                Text {
                    visible: searchField.text === ""
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "search recent chats"
                    color: Theme.subtext
                    font.family: Theme.fontTui
                    font.pixelSize: Theme.tuiTextSize
                }
            }
        }

        Rule { visible: frame.history }

        Text {
            visible: frame.history && !frame.controller.found.length
            width: parent.width
            topPadding: 6
            bottomPadding: 6
            text: Chat.chats.length ? "no chats match" : "no chats yet. ask something first."
            color: Theme.subtext
            font.family: Theme.fontTui
            font.pixelSize: Theme.tuiTextSize
        }

        Flickable {
            id: recent
            visible: frame.history && frame.controller.found.length > 0
            x: -12 // room for the chip to span the frame
            width: parent.width + 24
            height: Math.min(contentHeight, frame.maxBody)
            contentHeight: recentColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: recentColumn
                x: 12
                width: parent.width - 24

                Repeater {
                    model: ScriptModel {
                        values: frame.controller.found
                        objectProp: "id"
                    }

                    Column {
                        id: chatRow

                        required property var modelData
                        required property int index
                        readonly property string day: frame.controller.dayOf(modelData.time).toLowerCase()
                        readonly property bool firstOfDay: index === 0 || frame.controller.dayOf(frame.controller.found[index - 1].time).toLowerCase() !== day
                        readonly property bool selected: frame.controller.current === index

                        width: recentColumn.width
                        onSelectedChanged: if (selected) recent.contentY = Math.max(0, Math.min(y, recent.contentHeight - recent.height, Math.max(recent.contentY, y + height - recent.height)))

                        Text {
                            visible: chatRow.firstOfDay
                            height: 28
                            verticalAlignment: Text.AlignBottom
                            bottomPadding: 4
                            text: chatRow.day
                            color: Theme.subtext
                            font.family: Theme.fontTui
                            font.pixelSize: Theme.tuiTextSize
                        }

                        // the chip spans the frame, as on the board
                        Rectangle {
                            x: -12
                            width: parent.width + 24
                            height: Theme.tuiLauncherRowHeight
                            color: chatRow.selected ? Theme.pistachio : rowMouse.containsMouse ? Theme.tuiHover : "transparent"
                            Accessible.role: Accessible.ListItem
                            Accessible.name: chatRow.modelData.title
                            Accessible.selected: chatRow.selected

                            Text {
                                x: 12
                                width: parent.width - when.width - 40
                                anchors.verticalCenter: parent.verticalCenter
                                text: chatRow.modelData.title
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: chatRow.selected ? Theme.bg : Theme.text
                                font.family: Theme.fontTui
                                font.pixelSize: Theme.tuiTextSize
                                font.weight: Font.Bold
                            }

                            Text {
                                id: when
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: Qt.formatTime(new Date(chatRow.modelData.time), "hh:mm")
                                color: chatRow.selected ? Theme.bg : Theme.subtext
                                font.family: Theme.fontTui
                                font.pixelSize: Theme.tuiTextSize
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

        // ---- Start: what you can ask (no board) ---------------------------------------------------
        Column {
            visible: frame.start
            width: parent.width
            bottomPadding: 6

            Text {
                text: "what do you need?"
                color: Theme.textBright
                font.family: Theme.fontTui
                font.pixelSize: Theme.tuiTextSize
                font.weight: Font.ExtraBold
            }
            Text {
                width: parent.width
                bottomPadding: 8
                wrapMode: Text.Wrap
                text: `short questions, quick answers. long chats open in ${Chat.provider === "codex" ? "chatgpt" : "claude desktop"}.`
                color: Theme.subtext
                font.family: Theme.fontTui
                font.pixelSize: Theme.tuiTextSize
            }

            Repeater {
                model: [["error", "explain this error"], ["clipboard", "summarise my clipboard"], ["translate", "translate to english"], ["oneliner", "write a shell one-liner"]]

                Rectangle {
                    id: suggestion
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: Theme.tuiLauncherRowHeight
                    color: suggestionMouse.containsMouse ? Theme.tuiHover : "transparent"
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData[1]

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: `[${suggestion.index + 1}]`
                        color: Theme.subtext
                        font.family: Theme.fontTui
                        font.pixelSize: Theme.tuiTextSize
                        font.weight: Font.Bold
                    }
                    Text {
                        x: 40
                        anchors.verticalCenter: parent.verticalCenter
                        text: suggestion.modelData[1]
                        color: Theme.text
                        font.family: Theme.fontTui
                        font.pixelSize: Theme.tuiTextSize
                    }
                    MouseArea {
                        id: suggestionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Chat.suggest(suggestion.modelData[0])
                    }
                }
            }
        }

        // ---- the conversation ------------------------------------------------------------------
        Flickable {
            id: talk
            visible: !frame.history && (Chat.messages.length > 0 || Chat.writing || Chat.state === "error")
            width: parent.width
            height: Math.min(contentHeight, frame.maxBody)
            contentHeight: said.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

            Column {
                id: said
                width: parent.width
                spacing: 8

                Repeater {
                    model: ScriptModel {
                        values: Chat.messages
                    }

                    Item {
                        id: line

                        required property var modelData
                        required property int index
                        readonly property bool mine: modelData.role === "user"
                        readonly property bool lastAnswer: !mine && index === Chat.messages.length - 1 && !Chat.writing

                        width: said.width
                        height: content.implicitHeight

                        Text {
                            width: 72
                            text: line.mine ? "you" : (line.modelData.both ? "both" : Chat.nameOf(line.modelData.provider).toLowerCase())
                            color: line.mine ? Theme.subtext : frame.voiceOf(line.modelData.both ? "both" : line.modelData.provider)
                            font.family: Theme.fontTui
                            font.pixelSize: Theme.tuiTextSize
                            font.weight: line.mine ? Font.Normal : Font.Bold
                        }

                        Column {
                            id: content
                            x: 72
                            width: parent.width - 72
                            spacing: 4

                            Text {
                                visible: line.mine
                                width: parent.width
                                text: line.modelData.text
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                color: Theme.textBright
                                font.family: Theme.fontTui
                                font.pixelSize: Theme.tuiTextSize
                                font.weight: Font.Bold
                            }
                            Text {
                                visible: line.mine && (line.modelData.context ?? "") !== ""
                                width: parent.width
                                text: "with " + (line.modelData.context ?? "").toLowerCase()
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: Theme.subtext
                                font.family: Theme.fontTui
                                font.pixelSize: Theme.tuiTextSize
                            }
                            ChatMarkdown {
                                visible: !line.mine
                                width: parent.width
                                markdown: line.mine ? "" : line.modelData.text
                            }
                            Text {
                                visible: line.modelData.stopped === true
                                text: "stopped"
                                color: Theme.subtext
                                font.family: Theme.fontTui
                                font.pixelSize: Theme.tuiTextSize
                            }
                            // [c] copy  [r] retry  [o] open in desktop (Lens's answer board)
                            Row {
                                visible: line.lastAnswer
                                topPadding: 4
                                spacing: 24

                                Bracket { key: "c"; label: "copy"; onClicked: Chat.copy(line.modelData.text) }
                                Bracket { key: "r"; label: "retry"; onClicked: Chat.retry() }
                                Bracket { key: "o"; label: Chat.provider === "codex" ? "open in chatgpt" : "open in desktop"; onClicked: Chat.openExternally() }
                            }
                        }
                    }
                }

                // the answer as it's written
                Item {
                    visible: Chat.writing
                    width: said.width
                    height: writing.implicitHeight

                    Text {
                        visible: Chat.partial !== ""
                        width: 72
                        text: Chat.both ? "both" : Chat.providerName.toLowerCase()
                        color: frame.voice
                        font.family: Theme.fontTui
                        font.pixelSize: Theme.tuiTextSize
                        font.weight: Font.Bold
                    }

                    Column {
                        id: writing
                        x: 72
                        width: parent.width - 72
                        spacing: 4

                        ChatMarkdown {
                            visible: Chat.partial !== ""
                            width: parent.width
                            markdown: Chat.partial
                            writing: true
                        }

                        // ● ○ ○ writing          2 s
                        Item {
                            width: parent.width
                            height: Theme.tuiLineHeight

                            Text {
                                textFormat: Text.StyledText
                                text: {
                                    const lit = Math.floor(Chat.seconds * 3) % 3;
                                    const dots = [0, 1, 2].map(i => `<font color="${i === lit ? Theme.pistachio : Theme.overlay2}">${i === lit ? "●" : "○"}</font>`).join(" ");
                                    return dots + "  " + (Chat.both && !Chat.combining ? "asking both" : Chat.combining ? "combining" : "writing");
                                }
                                color: Theme.subtext
                                font.family: Theme.fontTui
                                font.pixelSize: Theme.tuiTextSize
                            }
                            Text {
                                anchors.right: parent.right
                                text: `${Math.floor(Chat.seconds)} s`
                                color: Theme.subtext
                                font.family: Theme.fontTui
                                font.pixelSize: Theme.tuiTextSize
                                font.features: { "tnum": 1 }
                            }
                        }
                    }
                }

                // couldn't reach (Lens's error board)
                Rectangle {
                    visible: Chat.state === "error"
                    width: said.width
                    height: errorColumn.implicitHeight + 24
                    color: Theme.bgAlt
                    border.width: 1
                    border.color: Theme.tuiBorder

                    Column {
                        id: errorColumn
                        x: 14
                        y: 12
                        width: parent.width - 28
                        spacing: 2

                        Text {
                            text: "[!] " + (Chat.error?.unavailable ? `couldn’t reach ${Chat.providerName.toLowerCase()}` : `${Chat.providerName.toLowerCase()} couldn’t answer`)
                            color: Theme.terracotta
                            font.family: Theme.fontTui
                            font.pixelSize: Theme.tuiTextSize
                            font.weight: Font.Bold
                        }
                        Text {
                            width: parent.width
                            bottomPadding: 10
                            wrapMode: Text.Wrap
                            text: Chat.error?.unavailable ? "check your connection. your question is saved." : (Chat.error?.message ?? "")
                            textFormat: Text.PlainText
                            color: Theme.subtext
                            font.family: Theme.fontTui
                            font.pixelSize: Theme.tuiTextSize
                        }
                        Row {
                            spacing: 8
                            ActionButton { height: 44; primary: true; text: "Try again"; onClicked: Chat.retry() }
                            ActionButton { height: 44; base: Theme.overlay; text: "Edit question"; onClicked: Chat.editQuestion() }
                        }
                    }
                }
            }
        }

        Item {
            visible: talk.visible && (Chat.includeShown || Chat.hasContext)
            width: 1
            height: 12
        }

        // ---- with context ----------------------------------------------------------------------
        Column {
            visible: !frame.history && (Chat.includeShown || Chat.hasContext)
            width: parent.width
            spacing: 10

            Row {
                visible: !Chat.messages.length
                spacing: 16
                Text {
                    text: "with context"
                    color: Theme.textBright
                    font.family: Theme.fontTui
                    font.pixelSize: Theme.tuiTextSize
                    font.weight: Font.Bold
                }
                Text {
                    text: `${Chat.both ? "both" : Chat.providerName.toLowerCase()} will see what is attached`
                    color: Theme.subtext
                    font.family: Theme.fontTui
                    font.pixelSize: Theme.tuiTextSize
                }
            }

            // the selected text
            Card {
                visible: Chat.selection !== null
                tag: "[text]"
                heading: (Chat.selection?.label ?? "").toLowerCase()
                note: Chat.selection ? `${Chat.selection.lines} ${Chat.selection.lines === 1 ? "line" : "lines"} · ${Chat.selection.first}` : ""
                onRemoved: Chat.selection = null
            }

            // the active window, with its live picture
            Card {
                id: windowCard
                visible: Chat.withWindow && Chat.windowSource !== null
                tag: "[win]"
                heading: `a picture of ${(Chat.windowApp || "the active window").toLowerCase()}`
                note: "taken as you send"
                thumbWidth: 72
                onRemoved: Chat.withWindow = false

                ScreencopyView {
                    id: windowView
                    parent: windowCard.thumb
                    anchors.fill: parent
                    captureSource: Chat.withWindow && Chat.open && Theme.tui ? Chat.windowSource : null
                    live: false // a still, as Classic's
                }
            }

            // include  [x] active window  [ ] clipboard  [ ] snip a region
            Flow {
                width: parent.width
                spacing: 18

                Text {
                    text: "include"
                    color: Theme.subtext
                    font.family: Theme.fontTui
                    font.pixelSize: Theme.tuiTextSize
                }
                Bracket { visible: Chat.windowSource !== null; key: Chat.withWindow ? "x" : " "; on: Chat.withWindow; label: "active window"; onClicked: Chat.withWindow = !Chat.withWindow }
                Bracket { key: Chat.withClipboard ? "x" : " "; on: Chat.withClipboard; label: "clipboard"; onClicked: Chat.withClipboard = !Chat.withClipboard }
                Bracket { key: " "; label: "snip a region"; onClicked: Chat.snip() }
            }
        }

        // ---- the input -------------------------------------------------------------------------
        Rule { visible: !frame.history }

        Item {
            visible: !frame.history
            width: parent.width
            height: Math.max(Theme.tuiLineHeight, Math.min(field.implicitHeight, 6 * Theme.tuiLineHeight))

            Text {
                id: prompt
                text: ">"
                color: Theme.pistachio
                font.family: Theme.fontTui
                font.pixelSize: Theme.tuiTextSize
                font.weight: Font.Bold
            }

            Flickable {
                id: fieldScroll
                x: 16
                width: parent.width - x - (stop.visible ? stop.width + 12 : 0)
                height: parent.height
                contentHeight: field.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                TextArea {
                    id: field
                    width: fieldScroll.width
                    padding: 0
                    text: Chat.draft
                    onTextChanged: if (Chat.draft !== text) Chat.draft = text
                    onCursorRectangleChanged: {
                        const top = cursorRectangle.y, bottom = top + cursorRectangle.height;
                        if (fieldScroll.contentY > top)
                            fieldScroll.contentY = top;
                        else if (fieldScroll.contentY + fieldScroll.height < bottom)
                            fieldScroll.contentY = bottom - fieldScroll.height;
                    }
                    wrapMode: TextEdit.Wrap
                    color: Theme.textBright
                    selectionColor: Theme.overlay2
                    selectedTextColor: Theme.textBright
                    font.family: Theme.fontTui
                    font.pixelSize: Theme.tuiTextSize
                    font.weight: Font.Bold
                    background: null
                    Accessible.name: "Question"
                    cursorDelegate: Rectangle {
                        width: 8
                        height: Theme.tuiLineHeight - 2
                        color: Theme.pistachio
                        visible: field.activeFocus
                    }
                    // after the block cursor, as the boards draw it
                    Text {
                        visible: field.text === "" && field.preeditText === ""
                        x: 12
                        text: Chat.messages.length ? "ask a follow-up" : Chat.both ? "ask both anything" : `ask ${Chat.providerName.toLowerCase()} anything`
                        color: Theme.subtext
                        font.family: Theme.fontTui
                        font.pixelSize: Theme.tuiTextSize
                    }
                    Keys.onPressed: event => {
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                            event.accepted = true;
                            if (!Chat.writing)
                                frame.controller.submit(text); // while writing: "Enter send when done"
                        } else
                            frame.key(event);
                    }
                }
            }

            Bracket {
                id: stop
                visible: Chat.writing
                anchors.right: parent.right
                key: "s"
                label: "stop"
                onClicked: Chat.stop()
            }
        }

        // ---- the keys --------------------------------------------------------------------------
        Flow {
            width: parent.width
            topPadding: 12
            spacing: 16

            Repeater {
                model: frame.history ? [["↑↓", "move"], ["Enter", "open"], ["Esc", "back"]]
                    : Chat.writing ? [["Esc", "stop"], ["Enter", "send when done"]]
                    : [["Enter", "send"], ["Shift+Enter", "new line"], ["Ctrl+H", "history"], ["Esc", "close"]]

                Row {
                    required property var modelData
                    spacing: 8

                    Text {
                        text: modelData[0]
                        color: Theme.textBright
                        font.family: Theme.fontTui
                        font.pixelSize: Theme.tuiTextSize
                        font.weight: Font.Bold
                    }
                    Text {
                        text: modelData[1]
                        color: Theme.subtext
                        font.family: Theme.fontTui
                        font.pixelSize: Theme.tuiTextSize
                    }
                }
            }
        }
    }

    // who answers: under the tab
    PanelFrame {
        visible: frame.controller.menuOpen
        x: 8
        y: 14
        z: 2
        width: 340
        height: menuColumn.implicitHeight + 16
        color: Theme.tuiSurface

        Column {
            id: menuColumn
            x: 8
            y: 8
            width: parent.width - 16

            Repeater {
                model: [
                    { choice: "claude", title: "claude", detail: Chat.modelOf("claude") },
                    { choice: "codex", title: "chatgpt", detail: Chat.modelOf("codex") },
                    { choice: "both", title: "ask both", detail: `then ${Chat.nameOf(Chat.preferred).toLowerCase()} combines` }
                ]

                Rectangle {
                    id: pick
                    required property var modelData
                    readonly property bool chosen: modelData.choice === "both" ? Chat.both : !Chat.both && Chat.provider === modelData.choice
                    width: menuColumn.width
                    height: Theme.tuiLauncherRowHeight
                    color: pickMouse.containsMouse ? Theme.tuiHover : "transparent"
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: modelData.title
                    Accessible.checked: chosen

                    Text {
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: pick.chosen ? "[x]" : "[ ]"
                        color: pick.chosen ? Theme.pistachio : Theme.subtext
                        font.family: Theme.fontTui
                        font.pixelSize: Theme.tuiTextSize
                        font.weight: Font.Bold
                    }
                    Text {
                        x: 48
                        anchors.verticalCenter: parent.verticalCenter
                        text: pick.modelData.title
                        color: Theme.text
                        font.family: Theme.fontTui
                        font.pixelSize: Theme.tuiTextSize
                        font.weight: Font.Bold
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width - 160)
                        elide: Text.ElideRight
                        text: pick.modelData.detail
                        color: Theme.subtext
                        font.family: Theme.fontTui
                        font.pixelSize: Theme.tuiTextSize
                    }
                    MouseArea {
                        id: pickMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Chat.choice = pick.modelData.choice === Chat.preferred ? "" : pick.modelData.choice;
                            frame.controller.menuOpen = false;
                            frame.focusInput();
                        }
                    }
                }
            }
        }
    }

    // a full-width rule in a line's height
    component Rule: Item {
        width: body.width
        height: Theme.tuiLineHeight

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 1
            color: Theme.tuiBorder
        }
    }

    // "[c] copy": the key bright, the label quiet; on, the key pistachio
    component Bracket: Item {
        id: bracket
        property string key
        property string label
        property bool on
        signal clicked
        implicitWidth: bracketText.implicitWidth
        implicitHeight: Theme.tuiLineHeight
        Accessible.role: Accessible.Button
        Accessible.name: label

        Text {
            id: bracketText
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.StyledText
            text: `<b><font color="${bracket.on ? Theme.pistachio : Theme.textBright}">[${bracket.key === " " ? "&nbsp;" : bracket.key}]</font></b>&nbsp;${bracket.label}`
            color: bracketMouse.containsMouse ? Theme.textBright : bracket.on ? Theme.text : Theme.subtext
            font.family: Theme.fontTui
            font.pixelSize: Theme.tuiTextSize
        }
        MouseArea {
            id: bracketMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: bracket.clicked()
        }
    }

    // the context card: "[term] selected text from kitty", a note under it, x to remove
    component Card: Rectangle {
        id: card
        property string tag
        property string heading
        property string note
        property int thumbWidth: 0
        readonly property alias thumb: thumbBox
        signal removed
        width: body.width
        height: 56
        color: Theme.bgAlt
        border.width: 1
        border.color: Theme.tuiBorder

        Rectangle {
            id: thumbBox
            visible: card.thumbWidth > 0
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            width: card.thumbWidth
            height: 40
            color: Theme.bg
            clip: true
        }
        Column {
            x: card.thumbWidth > 0 ? card.thumbWidth + 24 : 12
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - 40

            Text {
                width: parent.width
                textFormat: Text.StyledText
                elide: Text.ElideRight
                text: `<font color="${Theme.teal}">${card.tag}</font> ${card.heading.replace(/&/g, "&amp;").replace(/</g, "&lt;")}`
                color: Theme.textBright
                font.family: Theme.fontTui
                font.pixelSize: Theme.tuiTextSize
                font.weight: Font.Bold
            }
            Text {
                width: parent.width
                leftPadding: 16
                elide: Text.ElideRight
                text: card.note
                textFormat: Text.PlainText
                color: Theme.subtext
                font.family: Theme.fontTui
                font.pixelSize: Theme.tuiTextSize
            }
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: "x"
            color: removeMouse.containsMouse ? Theme.textBright : Theme.subtext
            font.family: Theme.fontTui
            font.pixelSize: Theme.tuiTextSize
            MouseArea {
                id: removeMouse
                anchors.fill: parent
                anchors.margins: -8
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: card.removed()
            }
        }
    }
}
