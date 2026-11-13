import qs
import QtQuick
import QtQuick.Controls.Basic as Basic // namespaced: this file is itself called Slider

// Slider from the quick settings board: 10 px track, pistachio fill up to a 20 px knob.
Basic.Slider {
    id: root

    // What's drawn: it eases to a new value (keys, the wheel, a change made elsewhere) but follows a
    // drag as it is. shownValue is the same in the slider's units, for a label that counts along.
    property real shown: position
    property color bracketColor: Theme.subtext
    property color fillColor: Theme.pistachio
    property color trackColor: Theme.overlay
    readonly property real shownValue: from + shown * (to - from)

    readonly property int cells: Math.max(1, Math.floor(width / (Theme.tuiTextSize * 0.6)) - 2)
    readonly property int filledCells: Math.round(Math.max(0, Math.min(1, shown)) * cells)

    implicitHeight: 44
    padding: 0
    // the wheel moves it a step per notch (a touchpad smoothly) and emits moved(), like a drag
    wheelEnabled: true
    stepSize: (to - from) / 20 // 5 %, as the launcher's ← →

    Behavior on shown {
        enabled: !root.pressed
        NumberAnimation {
            duration: Theme.motionDuration
            easing.type: Theme.easing
        }
    }

    background: Rectangle {
        y: (root.height - height) / 2
        width: root.width
        height: 10
        radius: 5
        color: Theme.tui ? "transparent" : root.trackColor

        Rectangle {
            visible: !Theme.tui
            width: root.handle.x + root.handle.width / 2
            height: parent.height
            radius: 5
            color: root.fillColor
        }
    }

    Text {
        objectName: "slider-meter"
        visible: Theme.tui
        anchors.centerIn: parent
        textFormat: Text.RichText
        text: "[" + (root.mirrored ? "&nbsp;".repeat(root.cells-root.filledCells) : "")
            + "<font color='" + root.fillColor + "'>" + "█".repeat(root.filledCells) + "</font>"
            + (root.mirrored ? "" : "&nbsp;".repeat(root.cells-root.filledCells)) + "]"
        color: root.bracketColor
        font.family: Theme.fontTui
        font.pixelSize: Theme.tuiTextSize
        font.kerning: false
    }

    handle: Rectangle {
        visible: !Theme.tui
        x: (root.mirrored ? 1 - root.shown : root.shown) * (root.width - width)
        y: (root.height - height) / 2
        width: 20
        height: 20
        radius: 10
        color: Theme.textBright
    }
}
