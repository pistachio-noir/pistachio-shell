import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland
import QtQuick

// Countdown is removed, including its fade, before the first encoded frame.
PanelWindow {
    id: root
    readonly property bool countdownOpen: Screenshots.countingDown && Screenshots.countdown > 0
    readonly property bool open: countdownOpen || Screenshots.trimOpen
    property bool showingCountdown
    onCountdownOpenChanged: if (countdownOpen) showingCountdown = true
    onOpenChanged: if (Screenshots.trimOpen) showingCountdown = false
    visible: reveal.shown
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region { item: card; radius: Theme.panelRadius }
    WlrLayershell.namespace: "pistachio-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    Reveal { id: reveal; open: root.open }

    Connections {
        target: Screenshots
        function onTrimDurationChanged() { start.text = "0"; end.text = String(Math.floor(Screenshots.trimDuration * 100) / 100); }
    }
    Rectangle {
        id: card
        objectName: "recording-tools-card"
        anchors.centerIn: parent
        width: root.showingCountdown ? 240 : 480
        height: root.showingCountdown ? 200 : content.implicitHeight + 48
        radius: Theme.panelRadius; color: Theme.surface
        border.width: 1; border.color: Theme.overlay2
        opacity: reveal.progress
        Shadow { anchors.fill: parent; z: -1; radius: parent.radius; kind: Theme.shadowPanel }
        Column {
            anchors.centerIn: parent; spacing: 10; visible: root.showingCountdown
            Text {
                objectName: "recording-countdown"
                anchors.horizontalCenter: parent.horizontalCenter
                text: Screenshots.countdown
                color: Theme.textBright; font.family: Theme.fontUi; font.pixelSize: 64; font.weight: Font.ExtraBold
                font.features: { "tnum": 1 }
            }
            Text { text: "Recording starts · Esc cancel"; color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 12 }
        }
        Column {
            id: content; x: 24; y: 24; width: parent.width - 48; spacing: 16
            visible: !root.showingCountdown
            Text { text: "Trim recording"; color: Theme.textBright; font.family: Theme.fontUi; font.pixelSize: 20; font.weight: Font.ExtraBold }
            Text {
                width: parent.width; text: Screenshots.trimPath.split("/").pop(); elide: Text.ElideMiddle; textFormat: Text.PlainText
                color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: Theme.tui ? Theme.tuiTextSize : 12
            }
            Text {
                text: Screenshots.trimDuration > 0 ? "Duration " + Screenshots.trimDuration.toFixed(2) + " s · original stays unchanged" : "Reading duration…"
                color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: Theme.tui ? Theme.tuiTextSize : 12
            }
            Row {
                spacing: 12
                Column {
                    spacing: 8
                    Text { text: "Start · seconds"; color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 12 }
                    Rectangle {
                        width: 180; height: 44; radius: Theme.tui ? 0 : 20; color: Theme.overlay
                        TextInput {
                            id: start; objectName: "recording-trim-start"
                            x: 14; width: parent.width - 28; anchors.verticalCenter: parent.verticalCenter
                            text: "0"; color: Theme.textBright; selectionColor: Theme.pistachio; selectedTextColor: Theme.bg
                            font.family: Theme.fontMono; font.pixelSize: Theme.tui ? Theme.tuiTextSize : 13; selectByMouse: true
                            enabled: !Screenshots.trimBusy; inputMethodHints: Qt.ImhFormattedNumbersOnly
                            Keys.onEscapePressed: Screenshots.closeTrim()
                        }
                    }
                }
                Column {
                    spacing: 8
                    Text { text: "End · seconds"; color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 12 }
                    Rectangle {
                        width: 180; height: 44; radius: Theme.tui ? 0 : 20; color: Theme.overlay
                        TextInput {
                            id: end; objectName: "recording-trim-end"
                            x: 14; width: parent.width - 28; anchors.verticalCenter: parent.verticalCenter
                            color: Theme.textBright; selectionColor: Theme.pistachio; selectedTextColor: Theme.bg
                            font.family: Theme.fontMono; font.pixelSize: Theme.tui ? Theme.tuiTextSize : 13; selectByMouse: true
                            enabled: !Screenshots.trimBusy; inputMethodHints: Qt.ImhFormattedNumbersOnly
                            Keys.onEscapePressed: Screenshots.closeTrim()
                        }
                    }
                }
            }
            Text {
                width: parent.width; visible: text !== ""; wrapMode: Text.Wrap
                text: Screenshots.trimError || (Screenshots.trimSavedPath ? "Saved " + Screenshots.trimSavedPath.split("/").pop() : "")
                textFormat: Text.PlainText; color: Screenshots.trimError ? Theme.terracotta : Theme.text
                font.family: Theme.fontUi; font.pixelSize: Theme.tui ? Theme.tuiTextSize : 12
            }
            Row {
                spacing: 8
                CaptureButton {
                    objectName: "recording-trim-save"
                    text: Screenshots.trimBusy ? "Saving…" : "Save new file"
                    enabled: !Screenshots.trimBusy && Screenshots.trimDuration > 0
                    onClicked: Screenshots.saveTrim(Number(start.text), Number(end.text))
                }
                CaptureButton { text: Screenshots.trimBusy ? "Cancel" : "Close"; onClicked: Screenshots.closeTrim() }
            }
        }
    }
    Item {
        anchors.fill: parent; focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                Screenshots.cancelCountdown(); Screenshots.closeTrim(); event.accepted = true;
            }
        }
    }
}
