import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Window

// Boards 02–06: frozen snip, a prompt below it, then an answer beside it. Outside clicks never close.
PanelWindow {
    id: backdrop
    visible: reveal.shown
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Reveal { id: reveal; open: Lens.open && !Lens.pickingFile }

    Item {
        anchors.fill: parent
        opacity: reveal.progress
        Image {
            anchors.fill: parent
            source: Lens.still?.url ?? ""
            fillMode: Image.Stretch
        }
        Rectangle { anchors.fill: parent; color: Theme.bg; opacity: 0.64 }
        Image {
            visible: Lens.images.some(image => image.id === 1)
            x: Lens.area.x; y: Lens.area.y
            width: Lens.area.width; height: Lens.area.height
            source: Lens.path ? "file://" + Lens.path : ""
            cache: false
            fillMode: Image.Stretch
        }
        Rectangle {
            visible: Lens.images.some(image => image.id === 1)
            x: Lens.area.x; y: Lens.area.y
            width: Lens.area.width; height: Lens.area.height
            color: "transparent"
            radius: Theme.tui ? 0 : 6
            border.width: 1
            border.color: Theme.textBright
        }
        Rectangle {
            visible: Lens.images.some(image => image.id === 1)
            x: Lens.area.x
            y: Math.max(4, Lens.area.y - (Theme.tui ? 28 : 34))
            width: sizeLabel.implicitWidth + (Theme.tui ? 16 : 20)
            height: Theme.tui ? Theme.tuiLineHeight : 26; radius: Theme.tui ? 0 : 13
            color: Theme.bgAlt
            border.width: 1; border.color: Theme.overlay2
            Text {
                id: sizeLabel
                anchors.centerIn: parent
                text: `${Lens.answer && !Theme.tui ? "Snip · " : ""}${Lens.area.width} × ${Lens.area.height}`
                color: Theme.textBright
                font.family: Theme.fontUi
                font.pixelSize: Theme.tui ? Theme.tuiTextSize : 11
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
            }
        }
        Rectangle {
            visible: Lens.busy && Lens.images.some(image => image.id === 1)
            x: Lens.area.x; width: Lens.area.width; height: 2
            color: Theme.pistachio
            y: Lens.area.y + (Lens.area.height - 2) * scan.progress
            NumberAnimation on opacity { from: 0.4; to: 1; duration: 900; loops: Animation.Infinite; running: Lens.busy }
            QtObject { id: scan; property real progress }
            SequentialAnimation {
                running: Lens.busy; loops: Animation.Infinite
                NumberAnimation { target: scan; property: "progress"; from: 0; to: 1; duration: 1600; easing.type: Theme.easing }
                NumberAnimation { target: scan; property: "progress"; from: 1; to: 0; duration: 1600; easing.type: Theme.easing }
            }
        }
    }

    PanelWindow {
        id: window
        readonly property bool answered: Lens.answer !== "" && Lens.state !== "prompt" && Lens.state !== "error"
        readonly property bool failed: Lens.state === "error"
        readonly property real inset: Theme.tui ? 16 : answered || failed ? 20 : 12
        readonly property real maxHeight: height - 48

        // Reserve actual visible controls and their Column gaps, including wrapped actions.
        function fixedContentHeight(): real {
            let total=0, count=0;
            for (const item of content.children) {
                if (item===response || !item.visible || item.height<=0) continue;
                total+=item.height; count++;
            }
            return total+count*content.spacing;
        }
        screen: backdrop.screen
        // Map after the frozen backdrop, so its full-screen image cannot cover the card.
        visible: reveal.shown && backdrop.backingWindowVisible
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region { item: card; radius: Theme.panelRadius }
        WlrLayershell.namespace: "pistachio-panel"
        WlrLayershell.layer: WlrLayer.Overlay
        // Keep the keyboard through fade-out, as with the switcher (CLAUDE.md).
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Connections {
            target: Lens
            function onOpenChanged() { if (Lens.open) Qt.callLater(() => card.focusInput()); }
            function onUpgradePromptChanged() { if (!Lens.upgradePrompt) Qt.callLater(() => card.focusInput()); }
            function onPickingFileChanged() { if (!Lens.pickingFile && Lens.open) Qt.callLater(() => card.focusInput()); }
            function onStateChanged() {
                if (Lens.state === "answer") {
                    if (!Lens.stoppedRequest) followup.text = "";
                    Qt.callLater(() => card.focusInput());
                }
                else if (Lens.state === "prompt") Qt.callLater(() => card.focusInput());
            }
        }

        Item {
            id: card
            objectName: "lens-card"
            function focusInput() {
                // A restored layer must own native focus before enabling Wayland text input.
                if (Lens.open && !Lens.upgradePrompt && Window.active)
                    window.answered ? followup.focusInput() : prompt.focusInput();
            }
            Window.onActiveChanged: if (Window.active) Qt.callLater(() => card.focusInput())
            width: Math.min(window.answered ? Theme.lensAnswerWidth : Theme.lensPromptWidth, window.width - 32)
            height: content.implicitHeight + window.inset * 2
            x: {
                if (!window.answered) return Math.max(16, Math.min(window.width - width - 16, Lens.area.x + (Lens.area.width - width) / 2));
                const right = Lens.area.x + Lens.area.width + 28;
                const left = Lens.area.x - width - 28;
                return right + width <= window.width - 24 ? right : left >= 24 ? left : window.width - width - 24;
            }
            y: {
                const desired = window.answered ? Lens.area.y - 124 : Lens.area.y + Lens.area.height + 18;
                const above = Lens.area.y - height - (Theme.tui ? 28 : 18);
                const top = !window.answered && desired + height > window.height - 24 && above >= 24 ? above : desired;
                // TUI: below the top strip, with room for the frame's tab
                const least = Theme.tui ? Theme.tuiBarHeight + 24 : 24;
                return Math.max(least, Math.min(window.height - height - 24, top)) + (Theme.tui ? 8 : 12) * (1 - reveal.progress);
            }
            opacity: reveal.progress
            focus: Lens.open
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) { event.accepted = true; if (Lens.upgradePrompt) Lens.respondCodingUpgrade(false); else Lens.close(); }
            }

            Shadow { anchors.fill: panel; radius: panel.radius; kind: Theme.shadowPanel; frostable: true }
            // TUI (Lens boards): "ask" with the snip's size, then the provider's name with "lens"
            PanelFrame {
                id: panel
                anchors.fill: parent
                title: Theme.tui ? (window.answered ? (Lens.combined ? "claude + chatgpt" : Lens.providerName.toLowerCase()) : "ask") : ""
                detail: Theme.tui ? (window.answered ? "lens" : `snip ${Lens.area.width} × ${Lens.area.height}`) : ""
                radius: Theme.panelRadius
                color: Theme.surface
                border.width: 1; border.color: Theme.overlay2
                Accessible.role: window.failed ? Accessible.AlertMessage : Accessible.Dialog
                Accessible.name: "Pistachio Lens"
            }

            Column {
                id: content
                enabled: !Lens.upgradePrompt
                x: window.inset; y: window.inset + (Theme.tui ? 4 : 0)
                width: parent.width - 2 * window.inset
                spacing: Theme.tui ? 10 : 14

                // TUI: "you" and "snip" rows in place of the header and the question tile
                Column {
                    visible: Theme.tui && window.answered
                    width: parent.width
                    Repeater {
                        model: [["you", Lens.question, true], ["snip", `${Lens.images.length} image${Lens.images.length === 1 ? "" : "s"}${Lens.attachment ? " · " + Lens.attachment : ""} · ${Lens.busy ? Lens.readingLabel.toLowerCase() : "answered in " + Math.round(Lens.seconds) + " s · " + Lens.modelLabel + (Lens.effort ? " · " + Lens.effort : "")}`, false]]
                        Item {
                            required property var modelData
                            width: parent.width; height: Math.max(Theme.tuiLineHeight, rowText.implicitHeight)
                            Text { text: modelData[0]; color: Theme.subtext; font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize }
                            Text {
                                id: rowText
                                x: 64; width: parent.width - 64
                                text: modelData[1]; textFormat: Text.PlainText; wrapMode: Text.Wrap; maximumLineCount: modelData[2] ? 4 : 2; elide: Text.ElideRight
                                color: modelData[2] ? Theme.textBright : Theme.subtext; font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize; font.weight: modelData[2] ? Font.Bold : Font.Normal
                            }
                        }
                    }
                }

                Item {
                    objectName: "lens-answer-header"
                    visible: window.answered && !Theme.tui
                    width: parent.width
                    height: visible ? 44 : 0
                    Rectangle {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        width: 36; height: 36; radius: 18
                        color: Theme.overlay2
                        Icon { anchors.centerIn: parent; paths: Icons.sparkles; size: 18; color: Theme.clay }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left; anchors.leftMargin: 46
                        anchors.right: parent.right; anchors.rightMargin: 106
                        Text { width: parent.width; elide: Text.ElideRight; text: Lens.combined ? "Claude + ChatGPT" : Lens.providerName; color: Theme.textBright; font.family: Theme.fontUi; font.pixelSize: 13; font.weight: Font.Bold }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: Lens.busy ? Lens.readingLabel : `Answered in ${Math.round(Lens.seconds)} s · ${Lens.modelLabel}${Lens.effort ? " · " + Lens.effort : ""}`
                            color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 11; font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                    }
                    GhostButton { anchors.right: parent.right; anchors.rightMargin: 52; objectName: "lens-copy"; icon: Icons.copy; label: "Copy answer"; onClicked: Clipboard.copyText(Lens.answer) }
                    GhostButton { anchors.right: parent.right; objectName: "lens-close"; icon: Icons.close; label: "Close Lens"; onClicked: Lens.close() }
                }

                Rectangle {
                    visible: window.answered && !Theme.tui
                    width: parent.width; height: visible ? 56 : 0
                    radius: Theme.tileRadius; color: Theme.overlay
                    Image {
                        x: 8; y: 8; width: 64; height: 40
                        source: Lens.images.length ? "file://" + Lens.images[0].path : ""
                        fillMode: Image.PreserveAspectCrop
                    }
                    Column {
                        x: 84; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - 14
                        Text {
                            width: parent.width; text: Lens.question; textFormat: Text.PlainText; elide: Text.ElideRight
                            color: Theme.textBright; font.family: Theme.fontUi; font.pixelSize: 13; font.weight: Font.Bold
                        }
                        Text { text: `${Lens.images.length} image${Lens.images.length === 1 ? "" : "s"}`; color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 11; font.weight: Font.DemiBold }
                    }
                }

                Flickable {
                    id: response
                    visible: window.answered
                    width: parent.width
                    height: visible ? Math.min(body.implicitHeight, Math.max(0, window.maxHeight - 2 * window.inset - window.fixedContentHeight())) : 0
                    contentWidth: width; contentHeight: body.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    Column {
                        id: body
                        width: response.width
                        spacing: 14
                        // TUI: the provider's name beside the answer, as the board's rows
                        Item {
                            width: parent.width; height: answerText.implicitHeight
                            Text {
                                visible: Theme.tui
                                text: Lens.combined ? "both" : Lens.providerName.toLowerCase()
                                color: Lens.combined ? Theme.lavender : Lens.provider === "codex" ? Theme.teal : Theme.clay
                                font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize; font.weight: Font.Bold
                            }
                            LensMarkdown { id: answerText; x: Theme.tui ? 64 : 0; width: parent.width - x; markdown: Lens.answer }
                        }
                        // [c] copy  [r] retry
                        Row {
                            visible: Theme.tui && !Lens.busy
                            x: 64; spacing: 24
                            TuiBracket { key: "c"; label: "copy"; onClicked: Clipboard.copyText(Lens.answer) }
                            TuiBracket { key: "r"; label: "retry"; onClicked: Lens.retry() }
                        }
                        Rectangle {
                            visible: Lens.diff !== ""
                            width: parent.width
                            height: visible ? proposal.implicitHeight + 24 : 0
                            radius: Theme.tileRadius
                            color: Theme.tui ? Theme.bgAlt : Theme.overlay
                            border.width: Theme.tui ? 1 : 0; border.color: Theme.tuiBorder
                            Column {
                                id: proposal
                                x: 12; y: 12; width: parent.width - 24; spacing: 12
                                Text {
                                    width: parent.width
                                    text: "Proposed changes · " + Lens.attachment
                                    textFormat: Text.PlainText; elide: Text.ElideMiddle
                                    color: Theme.textBright; font.family: Theme.fontUi; font.pixelSize: 12; font.weight: Font.Bold
                                }
                                TextEdit {
                                    width: parent.width
                                    text: Lens.diff; textFormat: TextEdit.PlainText
                                    readOnly: true; selectByMouse: true; wrapMode: TextEdit.WrapAnywhere
                                    color: Theme.text; selectionColor: Theme.overlay2; selectedTextColor: Theme.textBright
                                    font.family: Theme.fontMono; font.pixelSize: 12
                                }
                                Row {
                                    spacing: 8
                                    ActionButton { text: "Apply changes"; primary: true; height: 44; enabled: !Lens.busy; onClicked: Lens.review(true) }
                                    ActionButton { text: "Discard"; height: 44; enabled: !Lens.busy; onClicked: Lens.review(false) }
                                }
                            }
                        }
                        Flow {
                            objectName: "lens-answer-actions"
                            width: parent.width; spacing: 8
                            Repeater {
                                model: Lens.actions
                                ActionButton {
                                    required property var modelData
                                    text: modelData.label
                                    maximumWidth: parent.width
                                    height: 44
                                    icon: modelData.kind === "search" ? Icons.search : Icons.languages
                                    primary: false
                                    enabled: !Lens.busy
                                    onClicked: if (modelData.kind === "search") Lens.search(modelData.query); else Lens.ask(modelData.prompt)
                                }
                            }
                        }
                    }
                }

                // TUI error (LensError board): the question, then a framed box
                Text {
                    visible: Theme.tui && window.failed
                    width: parent.width
                    text: "> " + Lens.question; textFormat: Text.PlainText; wrapMode: Text.Wrap
                    color: Theme.textBright; font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize; font.weight: Font.Bold
                }
                Rectangle {
                    visible: Theme.tui && window.failed
                    width: parent.width; height: visible ? tuiError.implicitHeight + 28 : 0
                    color: Theme.bgAlt
                    border.width: 1; border.color: Theme.tuiBorder
                    Accessible.role: Accessible.AlertMessage
                    Accessible.name: `Couldn't reach ${Lens.providerName}`
                    Column {
                        id: tuiError
                        x: 14; y: 14; width: parent.width - 28; spacing: 2
                        Text { text: `[!] couldn’t reach ${Lens.providerName.toLowerCase()}`; color: Theme.terracotta; font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize; font.weight: Font.Bold }
                        Text {
                            width: parent.width; bottomPadding: 10
                            text: (Lens.problem ? Lens.problem.toLowerCase() + " " : "") + "your snip and question are saved."; textFormat: Text.PlainText
                            wrapMode: Text.Wrap; maximumLineCount: 8; elide: Text.ElideRight
                            color: Theme.subtext; font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize
                        }
                        Row {
                            spacing: 8
                            ActionButton { text: "Try again"; primary: true; height: 44; onClicked: Lens.retry() }
                            ActionButton { text: "Edit question"; base: Theme.overlay; height: 44; onClicked: Lens.edit() }
                        }
                    }
                }
                Column {
                    visible: window.failed && !Theme.tui
                    width: parent.width
                    spacing: 14
                    Row {
                        width: parent.width; spacing: 14
                        Rectangle {
                            width: 40; height: 40; radius: 20; color: Theme.overlay2
                            Icon { anchors.centerIn: parent; paths: Icons.sparkles; color: Theme.terracotta; size: 20 }
                        }
                        Column {
                            width: parent.width - 54; spacing: 4
                            Text { text: `Couldn't reach ${Lens.providerName}`; color: Theme.terracotta; font.family: Theme.fontUi; font.pixelSize: 14; font.weight: Font.ExtraBold }
                            Text {
                                width: parent.width; text: Lens.problem + "\nYour snip and question are still here."; textFormat: Text.PlainText
                                wrapMode: Text.Wrap; maximumLineCount: 8; elide: Text.ElideRight
                                color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 12; font.weight: Font.Medium
                            }
                        }
                    }
                    Row {
                        spacing: 8
                        ActionButton { text: "Try again"; primary: true; onClicked: Lens.retry() }
                        ActionButton { text: "Edit question"; onClicked: Lens.edit() }
                        ActionButton { text: "Close"; onClicked: Lens.close() }
                    }
                }

                LensImages {
                    id: imageAttachments
                    width: parent.width
                }

                Column {
                    id: attachmentChips
                    visible: !Lens.busy
                    width: parent.width; spacing: 8
                    Flow {
                        objectName: "lens-attachment-tools"
                        width: parent.width; spacing: 8
                        ActionButton {
                            text: "Add snip"; icon: Icons.crop; height: 44
                            enabled: Lens.ready && Lens.images.length < 3
                            opacity: enabled ? 1 : 0.65
                            onClicked: Lens.requestSnip()
                        }
                        ActionButton {
                            text: "Add image"; icon: Icons.image; height: 44
                            enabled: Lens.ready && Lens.images.length < 3
                            opacity: enabled ? 1 : 0.65
                            onClicked: Lens.attachImage()
                        }
                        ActionButton {
                            text: Lens.attachment ? "Change file" : "Attach file"
                            icon: Icons.fileCode; height: 44; enabled: Lens.ready
                            onClicked: Lens.attachFile()
                        }
                        ActionButton {
                            visible: !window.answered && !window.failed
                            objectName: "lensAskBothPrompt"
                            text: "Ask both"; icon: Icons.sparkles; height: 44
                            enabled: Lens.ready && !!prompt.text.trim()
                            onClicked: Lens.askBoth(prompt.text.trim())
                        }
                    }
                    ActionButton {
                        visible: Lens.attachment !== ""
                        width: parent.width
                        text: "Remove " + (Lens.attachment.length > 24 ? Lens.attachment.slice(0, 21) + "…" : Lens.attachment)
                        icon: Icons.close; height: 44
                        onClicked: Lens.detachFile()
                    }
                    Flow {
                        objectName: "lens-agent-tools"
                        visible: window.answered || window.failed
                        width: parent.width; spacing: 8
                        ActionButton {
                            visible: Lens.question !== ""
                            text: Lens.provider === "claude" ? "Ask ChatGPT instead" : "Ask Claude instead"
                            icon: Icons.sparkles; height: 44; enabled: Lens.ready
                            onClicked: Lens.askOther()
                        }
                        ActionButton {
                            visible: !window.failed
                            objectName: "lensAskBoth"
                            text: "Ask both"; icon: Icons.sparkles; height: 44
                            enabled: Lens.ready && !!(followup.text.trim() || Lens.question)
                            onClicked: Lens.askBoth(followup.text.trim() || Lens.question)
                        }
                    }
                }

                LensInput {
                    id: prompt
                    visible: !window.answered && !window.failed
                    width: parent.width
                    initial: true
                    reading: Lens.busy
                    text: Lens.question
                    placeholder: "Ask about this…"
                    onSubmitted: text => Lens.ask(text)
                    onStopped: Lens.cancel()
                }
                Flow {
                    visible: !window.answered && !window.failed && !Lens.busy
                    width: parent.width; spacing: 8
                    Repeater {
                        model: [
                            { name: "Explain", icon: Icons.lightbulb }, { name: "Fix it", icon: Icons.wrench },
                            { name: "Translate", icon: Icons.languages }, { name: "Summarise", icon: Icons.summarise },
                            { name: "Extract text", icon: Icons.textScan }
                        ]
                        ActionButton {
                            required property var modelData
                            text: modelData.name
                            icon: modelData.icon
                            horizontalPadding: 12
                            height: 44
                            onClicked: Lens.askTask(modelData.name === "Extract text" ? "Extract all text from this snip, preserving its layout where useful."
                                : modelData.name === "Fix it" && Lens.attachment ? "Fix the attached file using this snip, and explain what changed and why."
                                : modelData.name + " this snip.", modelData.name === "Translate" ? "translation" : modelData.name === "Summarise" ? "summary" : modelData.name === "Extract text" ? "extraction" : "auto")
                        }
                    }
                }
                // TUI: ● ○ ○ reading your snip          2 s
                Item {
                    visible: Theme.tui && Lens.busy && !window.answered
                    width: parent.width; height: visible ? Theme.tuiLineHeight : 0
                    Text {
                        textFormat: Text.StyledText
                        text: {
                            const lit = Math.floor(Lens.seconds * 2) % 3;
                            return [0, 1, 2].map(i => `<font color="${i === lit ? Theme.pistachio : Theme.overlay2}">${i === lit ? "●" : "○"}</font>`).join(" ")
                                + "  " + (Lens.synthesising ? "combining both answers" : "reading your snip");
                        }
                        color: Theme.subtext; font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize
                    }
                    Text { anchors.right: parent.right; text: `${Math.floor(Lens.seconds)} s`; color: Theme.subtext; font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize; font.features: { "tnum": 1 } }
                }
                Row {
                    visible: Lens.busy && !window.answered && !Theme.tui
                    width: parent.width; height: visible ? 18 : 0
                    spacing: 10
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        Repeater {
                            model: 3
                            Rectangle {
                                required property int index
                                width: 6; height: 6; radius: 3
                                color: Math.floor(Lens.seconds * 2) % 3 === index ? Theme.pistachio : Theme.muted
                            }
                        }
                    }
                    Text { text: Lens.readingLabel; color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold }
                    Text { text: `${Math.floor(Lens.seconds)} s`; color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 11; font.features: { "tnum": 1 } }
                }
                // TUI's keys: bright key, quiet label
                Flow {
                    visible: Theme.tui && !window.failed && !window.answered && !Lens.busy
                    width: parent.width; spacing: 16
                    Repeater {
                        model: [["Enter", "ask"], ["Shift+Enter", "new line"], ["Esc", "cancel"]]
                        Row {
                            required property var modelData
                            spacing: 8
                            Text { text: modelData[0]; color: Theme.textBright; font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize; font.weight: Font.Bold }
                            Text { text: modelData[1]; color: Theme.subtext; font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize }
                        }
                    }
                }
                Text {
                    visible: !window.answered && !window.failed && !Lens.busy && !Theme.tui
                    text: "Enter ask     Shift+Enter new line     Esc cancel"
                    color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 11; font.weight: Font.DemiBold
                }
                Text {
                    id: statusNotice
                    visible: Lens.notice !== ""
                    width: parent.width; text: Lens.notice; textFormat: Text.PlainText; wrapMode: Text.Wrap
                    color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 11
                }
                Column {
                    id: answerFooter
                    visible: window.answered
                    width: parent.width; spacing: 14
                    Rectangle { width: parent.width; height: 1; color: Theme.tui ? Theme.tuiBorder : Theme.overlay }
                    LensInput {
                        id: followup
                        width: parent.width
                        placeholder: "Ask a follow-up…"
                        reading: Lens.busy
                        onSubmitted: text => Lens.ask(text)
                        onStopped: Lens.cancel()
                    }
                    Row {
                        visible: Theme.tui
                        spacing: 16
                        Repeater {
                            model: [["Enter", "send"], ["Esc", "close"]]
                            Row {
                                required property var modelData
                                spacing: 8
                                Text { text: modelData[0]; color: Theme.textBright; font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize; font.weight: Font.Bold }
                                Text { text: modelData[1]; color: Theme.subtext; font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize }
                            }
                        }
                    }
                }
            }
            LensUpgrade { anchors.fill: parent }
        }
    }
}
