import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland // the layer (a Wayland protocol, not a compositor module)
import Quickshell.Widgets // ClippingRectangle, for the cover
import QtQuick

// The ambient clock (services/Ambient.qml; owner's request, 20 November 2026; laid out by Claude, no
// board): over everything on the Overlay layer, but taking no input at all (an empty input region, no
// keyboard), so the first key or movement reaches the desktop and ends the idle. The screen dims to
// nearly the background colour over 1.5 s; in the middle a big clock, the date, what's playing and a
// running Pomodoro or timer. The group drifts a little each minute so nothing stays in one place.
PanelWindow {
    id: root

    readonly property bool tui: Theme.tui
    // the line under the media: the Pomodoro/Focus phase, else the first timer, else the stopwatch
    readonly property string timerLine: {
        if (FocusMode.session)
            return `${FocusMode.phaseName()} · ${FocusMode.clock(FocusMode.left())}${FocusMode.paused ? " · paused" : " left"}`;
        const t = Clocks.timers[0];
        if (t)
            return `${t.label || "Timer"} · ${Clocks.clock(Clocks.left(t))}${t.endsAt ? " left" : " · paused"}`;
        if (Clocks.stopwatch)
            return `Stopwatch · ${Clocks.clock(Clocks.elapsed())}`;
        return "";
    }

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: veil.opacity > 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "pistachio-ambient"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region { width: 0; height: 0 } // clicks and the pointer go to what's below

    // TEMP (owner, 20 November 2026: "remove the preview IPC after I tell you"): `psc ambient preview`
    IpcHandler {
        target: "ambient"
        function preview(): void { Ambient.preview(); }
        function status(): string { return JSON.stringify({ enabled: Ambient.enabled, delay: Ambient.delay, idle: Ambient.idle, desktopEmpty: Ambient.desktopEmpty, shown: Ambient.shown, previewing: Ambient.previewing }); }
    }

    Item {
        id: veil
        objectName: "ambient-veil"
        anchors.fill: parent
        opacity: 0

        // slowly in (as night light dims the wallpaper), at once out: any movement brings the desktop
        // back. Started by hand: a Behavior picks its duration before the binding that names the way
        // has changed, so it faded out as slowly as in.
        NumberAnimation {
            id: fade
            target: veil
            property: "opacity"
            easing.type: Theme.easing
        }
        Connections {
            target: Ambient
            function onShownChanged() {
                fade.stop();
                fade.to = Ambient.shown ? 1 : 0;
                fade.duration = Ambient.shown ? Theme.dimDuration : Theme.motionDuration;
                fade.start();
            }
        }
        Component.onCompleted: opacity = Ambient.shown ? 1 : 0

        Rectangle {
            anchors.fill: parent
            color: Theme.bg
            opacity: 0.94 // nearly black, the wallpaper only just there
        }

        SystemClock {
            id: clock
            enabled: veil.visible
            precision: SystemClock.Minutes
            onDateChanged: {
                // a few pixels somewhere else each minute (as far as 32 px), the same place for the same minute
                const m = date.getHours() * 60 + date.getMinutes();
                group.driftX = ((m * 37) % 65) - 32;
                group.driftY = ((m * 23) % 49) - 24;
            }
        }

        Column {
            id: group
            objectName: "ambient-group"
            property real driftX
            property real driftY
            x: (parent.width - width) / 2 + driftX
            y: (parent.height - height) / 2 + driftY
            spacing: root.tui ? 10 : 8

            // only the drift glides: on x/y the centring itself animated, from the corner while the
            // window's size was still 0 (owner's report, 20 November 2026)
            Behavior on driftX { NumberAnimation { duration: Theme.dimDuration; easing.type: Theme.easing } }
            Behavior on driftY { NumberAnimation { duration: Theme.dimDuration; easing.type: Theme.easing } }

            Text {
                objectName: "ambient-time"
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatTime(clock.date, "hh:mm")
                color: Theme.textBright
                font.family: Theme.fontUi
                font.pixelSize: root.tui ? 140 : 168
                font.weight: Font.ExtraBold
                font.features: { "tnum": 1 }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.tui ? Qt.formatDate(clock.date, "dddd yyyy-MM-dd").toLowerCase() : Qt.formatDate(clock.date, "dddd, d MMMM")
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: root.tui ? 18 : 22
                font.weight: Font.DemiBold
            }

            Item { width: 1; height: 18 }

            // what's playing: a small cover, the title and the artist
            Row {
                objectName: "ambient-media"
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !!Media.player?.trackTitle
                spacing: 12

                ClippingRectangle {
                    width: 40
                    height: 40
                    radius: root.tui ? 0 : 10
                    color: Theme.overlay
                    anchors.verticalCenter: parent.verticalCenter
                    Icon {
                        anchors.centerIn: parent
                        size: 18
                        paths: Icons.music
                        color: Theme.subtext
                        visible: cover.status !== Image.Ready
                    }
                    Image {
                        id: cover
                        anchors.fill: parent
                        source: Media.player?.trackArtUrl ?? ""
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(80, 80)
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 560)
                    elide: Text.ElideRight
                    text: (Media.player?.trackTitle ?? "") + (Media.player?.trackArtist ? ` — ${Media.player.trackArtist}` : "")
                    color: (Media.player?.isPlaying ?? false) ? Theme.text : Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: root.tui ? Theme.tuiTextSize + 2 : 16
                    font.weight: Font.Bold
                }
            }

            Text {
                objectName: "ambient-timer"
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.timerLine !== ""
                text: root.tui ? root.timerLine.toLowerCase() : root.timerLine
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: root.tui ? Theme.tuiTextSize + 2 : 15
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
        }
    }
}
