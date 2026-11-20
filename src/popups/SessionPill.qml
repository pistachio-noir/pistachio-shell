import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland // the layer's name (a Wayland protocol, not a compositor module)
import QtQuick

// A Pomodoro's time while Zen mode hides the bar (FocusMode, owner's request, 11 November 2026; laid
// out by Claude, no board): a small flat pill where the bar would be, like the bar's own session
// pill. A click pauses or resumes; ⏭ skips to the next phase, ✕ ends the Pomodoro (Zen stays).
// Hide (owner's request, 20 November 2026; no board) tucks it into the Classic bar's handle: pointing
// at the bottom edge brings it out while the pointer stays, a click on the handle (or Keep shown)
// brings it back. Per session, not saved: it shows again for the next one.
PanelWindow {
    id: root

    readonly property bool wanted: FocusMode.zen && FocusMode.session !== null
    property bool hidden
    readonly property bool pointed: hover.hovered || linger.running
    readonly property bool shown: !hidden || pointed
    readonly property real pillHeight: Theme.chipHeight + 8

    onWantedChanged: if (!wanted) hidden = false
    Connections {
        target: hover
        function onHoveredChanged() { if (!hover.hovered) linger.restart(); }
    }

    visible: reveal.shown
    anchors.bottom: true
    exclusiveZone: 0
    implicitWidth: pill.fullWidth
    implicitHeight: pillHeight + Theme.barMargin // reaches the screen edge, where the reveal strip is
    color: "transparent"
    WlrLayershell.namespace: "pistachio-bar" // frosted like the bar
    WlrLayershell.layer: WlrLayer.Top

    // hidden, only a 4 px strip at the screen edge takes the pointer; clicks elsewhere reach the windows
    mask: Region {
        y: root.shown ? 0 : root.height - 4
        width: root.width
        height: root.shown ? root.height : 4
    }

    Reveal {
        id: reveal
        open: root.wanted
    }

    HoverHandler {
        id: hover
    }

    Timer {
        id: linger
        interval: 400 // as the bar: a moment to come back before it tucks away
    }

    // 0 is the handle (72 x 4, 2 px above the screen edge, in subtext, as the bar's), 1 the pill
    property real grown: shown ? 1 : 0

    Behavior on grown {
        NumberAnimation {
            duration: Theme.tui ? Theme.motionDuration : Theme.growDuration
            easing.type: Theme.easing
        }
    }

    // the handle's strip: a click brings the pill back for good
    MouseArea {
        anchors.bottom: parent.bottom
        width: parent.width
        height: root.shown ? Theme.barMargin : 4
        cursorShape: root.hidden ? Qt.PointingHandCursor : Qt.ArrowCursor
        enabled: root.hidden
        onClicked: root.hidden = false
    }

    Rectangle {
        id: pill

        readonly property real fullWidth: row.implicitWidth + 12 + 8
        readonly property real shownPart: Math.max(0, 2 * root.grown - 1)

        width: 72 + (fullWidth - 72) * root.grown
        height: 4 + (root.pillHeight - 4) * root.grown
        x: (root.width - width) / 2
        y: (root.height - 2 - 4) * (1 - root.grown)
        radius: Theme.tui ? 0 : height / 2
        color: Theme.glass(Qt.tint(Theme.bgAlt, Qt.rgba(Theme.subtext.r, Theme.subtext.g, Theme.subtext.b, Math.max(0, 1 - 3 * root.grown))))
        border.width: 1
        border.color: Qt.rgba(Theme.overlay2.r, Theme.overlay2.g, Theme.overlay2.b, root.grown)
        opacity: reveal.progress
        transform: Translate {
            y: 6 * (1 - reveal.progress)
        }
        Accessible.role: Accessible.Grouping
        Accessible.name: `${FocusMode.phaseName()} ${FocusMode.clock(FocusMode.left())}`

        Row {
            id: row
            x: 12
            y: (root.pillHeight - height) / 2
            spacing: 8
            opacity: pill.shownPart
            visible: opacity > 0

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
                visible: ShellSettings.phonePreview
                paths: Icons.smartphone
                label: "View on phone"
                onClicked: FocusMode.showPhone()
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

            PillButton {
                paths: root.hidden ? Icons.chevronUp : Icons.chevronDown
                label: root.hidden ? "Keep shown" : "Hide"
                onClicked: root.hidden = !root.hidden
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
