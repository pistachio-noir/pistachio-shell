import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland // layer-shell layer for this window (a Wayland protocol, not a compositor module)
import QtQuick

// Volume, brightness, output device, microphone and screen sharing OSD (Osd board; the last three
// aren't on it). Volume shows on any PipeWire change, whoever made it, and so does a new default output,
// e.g. headphones connecting; brightness only through IPC, because the monitor reports nothing. The
// microphone and screen sharing ones name the apps that start recording or sharing, and say when all
// have stopped (owner's request: privacy cues, so they show even in Do not disturb, fullscreen or with
// quick settings open). The bar positions it.
PanelWindow {
    id: root

    property string kind: "volume" // or "brightness", "output", "mic" or "screen"
    property bool suppressed // set by the bar while quick settings (which has the same sliders) is open
    property int lift // the pill's distance from the screen's bottom edge; the bar sets it
    // room around the pill for its shadow; below, at most what's left down to the screen edge
    readonly property int side: Theme.shadowSmall.blur
    readonly property int above: Theme.shadowSmall.blur - Theme.shadowSmall.y
    readonly property int below: Math.min(lift, Theme.shadowSmall.blur + Theme.shadowSmall.y)
    property bool settling: true // after startup and output switches, when volume "changes" on its own
    readonly property bool output: kind === "output"
    readonly property bool cue: kind === "mic" || kind === "screen" // a privacy cue
    readonly property bool muted: (kind === "volume" || output) && Audio.muted
    readonly property real value: kind === "brightness" ? Brightness.value : Audio.volume
    // The bar and number ease to a new value; they start at it while hidden and on a switch between
    // volume and brightness, rather than sweep from the other one.
    property real level: value
    property bool snap
    // the default output's node name, to tell a real switch from the moment between two devices
    property string outputNode
    property string outputName
    Component.onCompleted: outputNode = Audio.sink?.name ?? ""
    // the apps recording as last announced; null until the first look after startup, which isn't news
    property bool cueOn // false: the apps in cueNames have stopped
    property string cueNames
    readonly property string cueTitle: kind === "screen" ? (cueOn ? "Sharing your screen" : "Screen sharing stopped")
        : !cueOn ? "Microphone not in use" : Audio.micMuted ? "Microphone in use, muted" : "Microphone in use"

    function show(k: string) {
        snap = k !== kind;
        kind = k;
        snap = false;
        hide.restart();
    }

    Behavior on level {
        enabled: reveal.shown && !root.snap
        NumberAnimation {
            duration: Theme.motionDuration
            easing.type: Theme.easing
        }
    }

    visible: reveal.shown
    exclusiveZone: 0
    margins.bottom: lift - below
    implicitWidth: side + 320 + side
    implicitHeight: above + 56 + below
    color: "transparent"
    mask: Region {} // clicks go through
    WlrLayershell.layer: WlrLayer.Overlay // above fullscreen windows

    Reveal {
        id: reveal
        open: hide.running && (!root.suppressed || root.cue)
    }

    Timer {
        id: hide
        interval: root.output || root.cue ? 2500 : 1500 // a name takes longer to read than a bar
    }

    Timer {
        id: settle
        running: true
        interval: 1000
        onTriggered: root.settling = false
    }

    // a device switch reports the new volume before the new device, so look a tick later
    function volumeMoved() {
        if (!settling)
            show("volume");
    }

    // outputNode is "" until the first output after startup, which isn't a switch
    function outputMoved() {
        const node = Audio.sink?.name ?? "";
        if (!node || node === outputNode)
            return;
        const first = outputNode === "";
        outputNode = node;
        outputName = Audio.deviceName(Audio.sink);
        if (!first)
            show("output");
    }

    function showCue(k: string, on: bool, names: string) {
        cueOn = on;
        cueNames = names;
        show(k);
    }

    // A new app shows the cue again; one stopping while others go on doesn't.
    PrivacyWatch {
        apps: Audio.recorders.map(n => Audio.appName(n))
        onStarted: names => root.showCue("mic", true, names)
        onStopped: names => root.showCue("mic", false, names)
    }

    PrivacyWatch {
        apps: ScreenShare.apps
        onStarted: names => root.showCue("screen", true, names)
        onStopped: names => root.showCue("screen", false, names)
    }

    Connections {
        target: Audio

        function onVolumeChanged() {
            Qt.callLater(root.volumeMoved);
        }
        function onMutedChanged() {
            Qt.callLater(root.volumeMoved);
        }
        function onSinkChanged() {
            root.settling = true;
            settle.restart();
            Qt.callLater(root.outputMoved);
        }
    }

    // For the brightness keys: qs -c pistachio ipc call brightness up (or down)
    IpcHandler {
        target: "brightness"

        function up(): void {
            root.step(0.05);
        }
        function down(): void {
            root.step(-0.05);
        }
    }

    function step(d: real) {
        if (!Brightness.available)
            return;
        Brightness.set(Brightness.value + d);
        show("brightness");
    }

    Rectangle {
        id: pill

        x: root.side
        width: 320
        height: 56
        radius: height / 2
        color: Theme.bgAlt
        border.width: 1
        border.color: Theme.overlay2
        // fades in rising 12 px, and back
        opacity: reveal.progress
        y: root.above + 12 * (1 - reveal.progress)
        Accessible.role: Accessible.StatusBar

        // beneath the pill (z -1), so it fades and rises with it
        Shadow {
            z: -1
            kind: Theme.shadowSmall
            anchors.fill: parent
            radius: parent.radius
        }
        Accessible.name: root.cue ? `${root.cueTitle}, ${root.cueNames}`
            : root.output ? `Output ${root.outputName}`
            : root.muted ? "Volume muted" : `${root.kind === "volume" ? "Volume" : "Brightness"} ${label.text} percent`

        Icon {
            id: icon
            x: 22
            anchors.verticalCenter: parent.verticalCenter
            size: 20
            paths: root.kind === "brightness" ? Icons.sun
                : root.output ? (Audio.isHeadphones(Audio.sink) ? Icons.headphones : Icons.speaker)
                : root.kind === "mic" ? (root.cueOn && Audio.micMuted ? Icons.micOff : Icons.mic)
                : root.kind === "screen" ? Icons.screenShare
                : root.muted ? Icons.volumeMuted : Icons.volume
            // as the bar shows them: clay while in use, subtext when muted or let go
            color: root.cue ? (root.cueOn && !(root.kind === "mic" && Audio.micMuted) ? Theme.clay : Theme.subtext)
                : root.muted ? Theme.subtext : Theme.textBright
        }

        // the new output's name in place of the bar
        Text {
            visible: root.output
            anchors.left: icon.right
            anchors.leftMargin: 14
            anchors.right: label.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: root.outputName
            elide: Text.ElideRight
            color: Theme.textBright
            font.family: Theme.fontUi
            font.pixelSize: 14
            font.weight: Font.Bold
        }

        // a privacy cue's news in place of the bar: what happened, and to which apps
        Column {
            visible: root.cue
            anchors.left: icon.right
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: root.cueTitle
                elide: Text.ElideRight
                color: Theme.textBright
                font.family: Theme.fontUi
                font.pixelSize: 14
                font.weight: Font.Bold
            }

            Text {
                width: parent.width
                text: root.cueNames
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: 12
                font.weight: Font.Medium
            }
        }

        Rectangle {
            visible: !root.output && !root.cue
            anchors.left: icon.right
            anchors.leftMargin: 14
            anchors.right: label.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            height: 8
            radius: 4
            color: Theme.overlay

            Rectangle {
                width: parent.width * Math.min(1, root.level)
                height: parent.height
                radius: 4
                color: root.muted ? Theme.overlay2 : Theme.pistachio
            }
        }

        Text {
            id: label
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            width: root.muted ? 50 : 30
            // a new output's volume reads 0 until PipeWire has bound it
            visible: !root.cue && (!root.output || (Audio.sink?.ready ?? false))
            horizontalAlignment: Text.AlignRight
            text: root.muted ? "Muted" : Math.round(root.level * 100)
            color: root.muted ? Theme.subtext : Theme.textBright
            font.family: Theme.fontUi
            font.pixelSize: 13
            font.weight: Font.ExtraBold
            font.features: { "tnum": 1 }
        }
    }
}
