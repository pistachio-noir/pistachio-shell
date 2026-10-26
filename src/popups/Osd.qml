import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland // layer-shell layer for this window (a Wayland protocol, not a compositor module)
import QtQuick

// Volume, brightness and output device OSD (Osd board; the output one isn't on it). Volume shows on
// any PipeWire change, whoever made it, and so does a new default output, e.g. headphones connecting;
// brightness only through IPC, because the monitor reports nothing. The bar positions it.
PanelWindow {
    id: root

    property string kind: "volume" // or "brightness", or "output"
    property bool suppressed // set by the bar while quick settings (which has the same sliders) is open
    property bool settling: true // after startup and output switches, when volume "changes" on its own
    readonly property bool output: kind === "output"
    readonly property bool muted: kind !== "brightness" && Audio.muted
    readonly property real value: kind === "brightness" ? Brightness.value : Audio.volume
    // the default output's node name, to tell a real switch from the moment between two devices
    property string outputNode
    property string outputName
    Component.onCompleted: outputNode = Audio.sink?.name ?? ""

    function show(k: string) {
        kind = k;
        hide.restart();
    }

    visible: reveal.shown
    exclusiveZone: 0
    implicitWidth: 320
    implicitHeight: 56
    color: "transparent"
    mask: Region {} // clicks go through
    WlrLayershell.layer: WlrLayer.Overlay // above fullscreen windows

    Reveal {
        id: reveal
        open: hide.running && !root.suppressed
    }

    Timer {
        id: hide
        interval: root.output ? 2500 : 1500 // a name takes longer to read than a bar
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

        width: parent.width
        height: parent.height
        radius: height / 2
        color: Theme.bgAlt
        border.width: 1
        border.color: Theme.overlay2
        // fades in rising 12 px, and back
        opacity: reveal.progress
        y: 12 * (1 - reveal.progress)
        Accessible.role: Accessible.StatusBar
        Accessible.name: root.output ? `Output ${root.outputName}`
            : root.muted ? "Volume muted" : `${root.kind === "volume" ? "Volume" : "Brightness"} ${label.text} percent`

        Icon {
            id: icon
            x: 22
            anchors.verticalCenter: parent.verticalCenter
            size: 20
            paths: root.kind === "brightness" ? Icons.sun
                : root.output ? (Audio.isHeadphones(Audio.sink) ? Icons.headphones : Icons.speaker)
                : root.muted ? Icons.volumeMuted : Icons.volume
            color: root.muted ? Theme.subtext : Theme.textBright
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

        Rectangle {
            visible: !root.output
            anchors.left: icon.right
            anchors.leftMargin: 14
            anchors.right: label.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            height: 8
            radius: 4
            color: Theme.overlay

            Rectangle {
                width: parent.width * Math.min(1, root.value)
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
            visible: !root.output || (Audio.sink?.ready ?? false)
            horizontalAlignment: Text.AlignRight
            text: root.muted ? "Muted" : Math.round(root.value * 100)
            color: root.muted ? Theme.subtext : Theme.textBright
            font.family: Theme.fontUi
            font.pixelSize: 13
            font.weight: Font.ExtraBold
            font.features: { "tnum": 1 }
        }
    }
}
