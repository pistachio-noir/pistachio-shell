import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland // the layer's name, level and keyboard (a Wayland protocol, not a compositor module)
import QtQuick

// An alarm ringing, or a timer done (owner's request, 9 November 2026; laid out by Claude under the
// Pistachio Noir rules, no board): a card in the middle of the screen over a dim, with the time large,
// the label, and Snooze (10 min) and Stop, Stop chosen; a soft chime every 2 s until it's answered (at
// most 3 min). It shows through Do not disturb and over fullscreen windows. Enter stops, S snoozes.
PanelWindow {
    id: root

    readonly property var ring: Clocks.ringing
    readonly property bool alarm: ring?.kind === "alarm"

    visible: reveal.shown
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "pistachio-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.ring ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // the last ring, kept while the card fades out
    property var shown: null
    onRingChanged: if (ring) shown = ring

    Reveal {
        id: reveal
        open: root.ring !== null
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        opacity: 0.55 * reveal.progress
    }

    Timer {
        id: chime
        running: root.ring !== null
        interval: 2000
        repeat: true
        triggeredOnStart: true
        property int count
        onRunningChanged: count = 0
        onTriggered: {
            if (++count > 90) {
                Clocks.stopRinging();
                return;
            }
            Quickshell.execDetached(["pw-play", Quickshell.shellPath("sounds/notification.wav")]);
        }
    }

    Item {
        id: card

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.3) + 12 * (1 - reveal.progress)
        width: 360
        height: column.implicitHeight + 56
        opacity: reveal.progress
        focus: root.ring !== null
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Escape)
                Clocks.stopRinging();
            else if (event.key === Qt.Key_S)
                Clocks.snooze();
        }

        Shadow {
            kind: Theme.shadowModal
            anchors.fill: panel
            radius: panel.radius
        }

        Rectangle {
            id: panel
            anchors.fill: parent
            radius: Theme.panelRadius
            color: Theme.bgAlt
            border.width: 1
            border.color: Theme.overlay2
            Accessible.role: Accessible.AlertMessage
            Accessible.name: `${root.alarm ? "Alarm" : "Timer done"}: ${root.shown?.label ?? ""}`
        }

        Column {
            id: column
            x: 28
            y: 28
            width: parent.width - 56
            spacing: 16

            // a gold bell (or hourglass) that sways a little while it rings
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 56
                height: 56
                radius: 28
                color: Theme.overlay

                Icon {
                    id: bell
                    anchors.centerIn: parent
                    size: 26
                    paths: root.shown?.kind === "timer" ? Icons.clock : Icons.bell
                    color: Theme.gold

                    SequentialAnimation on rotation {
                        running: root.ring !== null
                        loops: Animation.Infinite
                        NumberAnimation { to: 14; duration: 120; easing.type: Theme.easing }
                        NumberAnimation { to: -14; duration: 240; easing.type: Theme.easing }
                        NumberAnimation { to: 0; duration: 120; easing.type: Theme.easing }
                        PauseAnimation { duration: 900 }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 2

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.shown?.kind === "timer" ? "TIMER DONE" : "ALARM"
                    color: Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 0.66
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.shown?.time ?? ""
                    color: Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: 56
                    font.weight: Font.ExtraBold
                    font.features: { "tnum": 1 }
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: root.shown?.label ?? ""
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10

                ActionButton {
                    width: 140
                    height: 44
                    text: "Snooze 10 min"
                    onClicked: Clocks.snooze()
                }

                ActionButton {
                    width: 140
                    height: 44
                    primary: true
                    text: "Stop"
                    onClicked: Clocks.stopRinging()
                }
            }
        }
    }
}
