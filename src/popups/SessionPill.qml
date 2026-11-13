import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland // the layer's name (a Wayland protocol, not a compositor module)
import QtQuick

// A Pomodoro's time while Zen mode hides the bar (FocusMode, owner's request, 11 November 2026; laid
// out by Claude, no board): a small flat pill where the bar would be, like the bar's own session
// pill. A click pauses or resumes; ⏭ skips to the next phase, ✕ ends the Pomodoro (Zen stays).
PanelWindow {
    id: root

    readonly property bool wanted: FocusMode.zen && FocusMode.session !== null

    visible: reveal.shown
    anchors.bottom: true
    margins.bottom: Theme.barMargin
    exclusiveZone: 0
    implicitWidth: pill.width
    implicitHeight: Theme.chipHeight + 8
    color: "transparent"
    WlrLayershell.namespace: "pistachio-bar" // frosted like the bar
    WlrLayershell.layer: WlrLayer.Top

    Reveal {
        id: reveal
        open: root.wanted
    }

    Rectangle {
        id: pill

        width: row.implicitWidth + 12 + 8
        height: Theme.chipHeight + 8
        radius: Theme.tui ? 0 : height / 2
        color: Theme.glass(Theme.bgAlt)
        border.width: 1
        border.color: Theme.overlay2
        opacity: reveal.progress
        transform: Translate {
            y: 6 * (1 - reveal.progress)
        }
        Accessible.role: Accessible.Grouping
        Accessible.name: `${FocusMode.phaseName()} ${FocusMode.clock(FocusMode.left())}`

        Row {
            id: row
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                size: 16
                paths: FocusMode.working ? Icons.lightbulb : Icons.moon
                color: FocusMode.paused ? Theme.subtext : FocusMode.working ? Theme.pistachio : Theme.teal
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: FocusMode.clock(FocusMode.left())
                color: FocusMode.paused ? Theme.subtext : Theme.textBright
                font.family: Theme.fontUi
                font.pixelSize: Theme.tui ? Theme.tuiTextSize : 13
                font.weight: Font.ExtraBold
                font.features: { "tnum": 1 }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: FocusMode.pause()
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: FocusMode.phaseName() + (FocusMode.paused ? " · paused" : "")
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: Theme.tui ? Theme.tuiTextSize : 11
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }

            PillButton {
                paths: Icons.skipForward
                label: FocusMode.working ? "Skip to the break" : "Skip to work"
                onClicked: FocusMode.skip()
            }

            PillButton {
                paths: Icons.close
                label: "End the Pomodoro"
                onClicked: FocusMode.endSession()
            }
        }
    }

    component PillButton: Rectangle {
        id: button

        required property list<string> paths
        required property string label

        signal clicked

        anchors.verticalCenter: parent?.verticalCenter
        width: 28
        height: 28
        radius: Theme.tui ? 0 : 14
        color: mouse.containsMouse ? Theme.overlay2 : Theme.overlay
        Accessible.role: Accessible.Button
        Accessible.name: label

        Behavior on color {
            ColorAnimation {
                duration: Theme.hoverDuration
                easing.type: Theme.easing
            }
        }

        Icon {
            anchors.centerIn: parent
            size: 14
            paths: button.paths
            color: mouse.containsMouse ? Theme.textBright : Theme.subtext
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
