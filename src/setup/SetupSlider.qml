import qs
import QtQuick
import QtQuick.Controls.Basic as Basic

// The Classic slider (components/Slider.qml without its TUI meter): 10 px track, pistachio fill.
Basic.Slider {
    id: root
    property real shown: position
    readonly property real shownValue: from + shown * (to - from)

    implicitHeight: 44
    padding: 0
    wheelEnabled: true
    stepSize: (to - from) / 20

    Behavior on shown {
        enabled: !root.pressed
        NumberAnimation { duration: Classic.motionDuration; easing.type: Theme.easing }
    }
    background: Rectangle {
        y: (root.height - height) / 2
        width: root.width; height: 10; radius: 5
        color: Theme.overlay
        Rectangle {
            width: root.handle.x + root.handle.width / 2
            height: parent.height; radius: 5
            color: Theme.pistachio
        }
    }
    handle: Rectangle {
        x: (root.mirrored ? 1 - root.shown : root.shown) * (root.width - width)
        y: (root.height - height) / 2
        width: 20; height: 20; radius: 10
        color: Theme.textBright
        scale: root.pressed ? 1.15 : 1
        Behavior on scale { NumberAnimation { duration: Classic.hoverDuration; easing.type: Theme.easing } }
    }
}
