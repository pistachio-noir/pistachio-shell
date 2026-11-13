import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland
import QtQuick
import "recording.js" as Layout

// No board: the owner's approved outline and small stop pill use the existing shell style.
// Everything is painted OUTSIDE the encoder's crop, with no shadow or slide into it.
PanelWindow {
    id: root
    readonly property rect captureArea: Screenshots.recordingArea
    readonly property bool areaRecording: Screenshots.recording && !Screenshots.recordingWhole
        && captureArea.width > 0 && captureArea.height > 0
    readonly property var pillPlacement: Layout.place(captureArea, width, height, pill.width, pill.height)
    property real now: Date.now()
    readonly property int seconds: Math.floor(Screenshots.elapsedMs(now) / 1000)
    onAreaRecordingChanged: if (areaRecording) Qt.callLater(() => root.now = Date.now())

    visible: reveal.shown
    // Resolve the screen before mapping; implicit screen selection depends on visibility.
    screen: Quickshell.screens.find(s => s.name === Screenshots.recordingMonitor) ?? Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region { item: root.pillPlacement ? pill : null; radius: 22 }
    WlrLayershell.namespace: "pistachio-recording"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Reveal { id: reveal; open: root.areaRecording }
    Timer { running: root.areaRecording; interval: 500; repeat: true; onTriggered: root.now = Date.now() }

    Item {
        anchors.fill: parent
        opacity: reveal.progress
        // Four solid strips avoid antialiased rounded corners entering the captured pixels.
        Repeater {
            model: [
                Qt.rect(root.captureArea.x - 2, root.captureArea.y - 2, root.captureArea.width + 4, 2),
                Qt.rect(root.captureArea.x - 2, root.captureArea.y + root.captureArea.height, root.captureArea.width + 4, 2),
                Qt.rect(root.captureArea.x - 2, root.captureArea.y, 2, root.captureArea.height),
                Qt.rect(root.captureArea.x + root.captureArea.width, root.captureArea.y, 2, root.captureArea.height)
            ]
            Rectangle {
                required property rect modelData
                required property int index
                objectName: "recording-frame-" + index
                x: modelData.x; y: modelData.y; width: modelData.width; height: modelData.height
                color: Theme.textBright
                opacity: 0.85
            }
        }
        Rectangle {
            id: pill
            objectName: "recording-region-control"
            visible: root.pillPlacement !== null
            x: root.pillPlacement?.x ?? 0; y: root.pillPlacement?.y ?? 0
            width: controls.implicitWidth + 24; height: 44; radius: Theme.tui ? 0 : 22
            color: Theme.bgAlt
            border.width: 1; border.color: Theme.overlay2
            Accessible.role: Accessible.Grouping
            Accessible.name: "Area recording"
            Row {
                id: controls
                x: 12; height: 44; spacing: 8
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8; height: 8; radius: Theme.tui ? 0 : 4; color: Theme.terracotta
                    SequentialAnimation on opacity {
                        running: root.areaRecording && !Screenshots.paused; loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 800; easing.type: Theme.easing }
                        NumberAnimation { to: 1; duration: 800; easing.type: Theme.easing }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Screenshots.paused ? "Paused" : "Recording"; color: Theme.textBright
                    font.family: Theme.fontUi; font.pixelSize: Theme.tui ? Theme.tuiTextSize : 13; font.weight: Font.Bold
                }
                Text {
                    objectName: "recording-region-time"
                    anchors.verticalCenter: parent.verticalCenter
                    text: `${Math.floor(root.seconds / 60)}:${String(root.seconds % 60).padStart(2, "0")}`
                    color: Theme.textBright; font.family: Theme.fontUi; font.pixelSize: Theme.tui ? Theme.tuiTextSize : 13; font.weight: Font.ExtraBold
                    font.features: { "tnum": 1 }
                }
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 1; height: 20; color: Theme.overlay2 }
                GhostButton {
                    objectName: "recording-region-pause"
                    icon: Screenshots.paused ? Icons.play : Icons.pause; label: Screenshots.paused ? "Resume recording" : "Pause recording"
                    enabled: root.areaRecording
                    onClicked: Screenshots.togglePause()
                }
                GhostButton {
                    objectName: "recording-region-stop"
                    icon: Icons.stop; tint: Theme.terracotta; label: "Stop recording"
                    enabled: root.areaRecording
                    onClicked: Screenshots.stopRecording()
                }
            }
        }
    }
}
