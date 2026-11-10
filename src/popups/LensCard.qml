import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls

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

    Reveal { id: reveal; open: Lens.open }

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
            x: Lens.area.x; y: Lens.area.y
            width: Lens.area.width; height: Lens.area.height
            source: Lens.path ? "file://" + Lens.path : ""
            cache: false
            fillMode: Image.Stretch
        }
        Rectangle {
            x: Lens.area.x; y: Lens.area.y
            width: Lens.area.width; height: Lens.area.height
            color: "transparent"
            radius: 6
            border.width: 1
            border.color: Theme.textBright
        }
        Rectangle {
            x: Lens.area.x
            y: Math.max(4, Lens.area.y - 34)
            width: sizeLabel.implicitWidth + 20
            height: 26; radius: 13
            color: Theme.bgAlt
            border.width: 1; border.color: Theme.overlay2
            Text {
                id: sizeLabel
                anchors.centerIn: parent
                text: `${Lens.answer ? "Snip · " : ""}${Lens.area.width} × ${Lens.area.height}`
                color: Theme.textBright
                font.family: Theme.fontUi
                font.pixelSize: 11
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
            }
        }
        Rectangle {
            visible: Lens.busy
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
        readonly property real inset: answered || failed ? 20 : 12
        readonly property real maxHeight: height - 48

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
            function onOpenChanged() { if (Lens.open) Qt.callLater(() => window.answered ? followup.focusInput() : prompt.focusInput()); }
            function onStateChanged() {
                if (Lens.state === "answer") {
                    if (!Lens.stoppedRequest) followup.text = "";
                    Qt.callLater(() => followup.focusInput());
                }
                else if (Lens.state === "prompt") Qt.callLater(() => prompt.focusInput());
            }
        }

        Item {
            id: card
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
                const above = Lens.area.y - height - 18;
                const top = !window.answered && desired + height > window.height - 24 && above >= 24 ? above : desired;
                return Math.max(24, Math.min(window.height - height - 24, top)) + 12 * (1 - reveal.progress);
            }
            opacity: reveal.progress
            focus: Lens.open
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) { event.accepted = true; Lens.close(); }
            }

            Shadow { anchors.fill: panel; radius: panel.radius; kind: Theme.shadowPanel; frostable: true }
            Rectangle {
                id: panel
                anchors.fill: parent
                radius: Theme.panelRadius
                color: Theme.surface
                border.width: 1; border.color: Theme.overlay2
                Accessible.role: window.failed ? Accessible.AlertMessage : Accessible.Dialog
                Accessible.name: "Pistachio Lens"
            }

            Column {
                id: content
                x: window.inset; y: window.inset
                width: parent.width - 2 * window.inset
                spacing: 14

                Row {
                    visible: window.answered
                    width: parent.width
                    height: visible ? 44 : 0
                    spacing: 10
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36; height: 36; radius: 18
                        color: Theme.overlay2
                        Icon { anchors.centerIn: parent; paths: Icons.sparkles; size: 18; color: Theme.clay }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 46 - 88
                        Text { text: Lens.providerName; color: Theme.textBright; font.family: Theme.fontUi; font.pixelSize: 13; font.weight: Font.Bold }
                        Text {
                            text: Lens.busy ? "Reading…" : `Answered in ${Math.round(Lens.seconds)} s`
                            color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 11; font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                    }
                    GhostButton { icon: Icons.copy; label: "Copy answer"; onClicked: Clipboard.copyText(Lens.answer) }
                    GhostButton { icon: Icons.close; label: "Close Lens"; onClicked: Lens.close() }
                }

                Rectangle {
                    visible: window.answered
                    width: parent.width; height: visible ? 56 : 0
                    radius: Theme.tileRadius; color: Theme.overlay
                    Image {
                        x: 8; y: 8; width: 64; height: 40
                        source: Lens.path ? "file://" + Lens.path : ""
                        fillMode: Image.PreserveAspectCrop
                    }
                    Column {
                        x: 84; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - 14
                        Text {
                            width: parent.width; text: Lens.question; textFormat: Text.PlainText; elide: Text.ElideRight
                            color: Theme.textBright; font.family: Theme.fontUi; font.pixelSize: 13; font.weight: Font.Bold
                        }
                        Text { text: `Region snip · ${Lens.area.width} × ${Lens.area.height}`; color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 11; font.weight: Font.DemiBold }
                    }
                }

                Flickable {
                    id: response
                    visible: window.answered
                    width: parent.width
                    height: visible ? Math.min(body.implicitHeight, Math.max(100, window.maxHeight - 300 - followup.height)) : 0
                    contentWidth: width; contentHeight: body.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    Column {
                        id: body
                        width: response.width
                        spacing: 14
                        LensMarkdown { width: parent.width; markdown: Lens.answer }
                        Flow {
                            width: parent.width; spacing: 8
                            Repeater {
                                model: Lens.actions
                                ActionButton {
                                    required property var modelData
                                    text: modelData.label
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

                Column {
                    visible: window.failed
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
                            onClicked: Lens.ask(modelData.name === "Extract text" ? "Extract all text from this snip, preserving its layout where useful." : modelData.name + " this snip.")
                        }
                    }
                }
                Row {
                    visible: Lens.busy && !window.answered
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
                    Text { text: `${Lens.providerName} is reading…`; color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold }
                    Text { text: `${Math.floor(Lens.seconds)} s`; color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 11; font.features: { "tnum": 1 } }
                }
                Text {
                    visible: !window.answered && !window.failed && !Lens.busy
                    text: "Enter ask     Shift+Enter new line     Esc cancel"
                    color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 11; font.weight: Font.DemiBold
                }
                Text {
                    visible: Lens.notice !== ""
                    width: parent.width; text: Lens.notice; textFormat: Text.PlainText; wrapMode: Text.Wrap
                    color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 11
                }
                Column {
                    visible: window.answered
                    width: parent.width; spacing: 14
                    Rectangle { width: parent.width; height: 1; color: Theme.overlay }
                    LensInput {
                        id: followup
                        width: parent.width
                        placeholder: "Ask a follow-up…"
                        reading: Lens.busy
                        onSubmitted: text => Lens.ask(text)
                        onStopped: Lens.cancel()
                    }
                }
            }
        }
    }
}
