import qs
import QtQuick
import QtQuick.Controls.Basic as Basic // namespaced: this file is itself called Slider

// Slider from the quick settings board: 10 px track, pistachio fill up to a 20 px knob.
Basic.Slider {
    id: root

    implicitHeight: 44
    padding: 0

    background: Rectangle {
        y: (root.height - height) / 2
        width: root.width
        height: 10
        radius: 5
        color: Theme.overlay

        Rectangle {
            width: root.handle.x + root.handle.width / 2
            height: parent.height
            radius: 5
            color: Theme.pistachio
        }
    }

    handle: Rectangle {
        x: root.visualPosition * (root.width - width)
        y: (root.height - height) / 2
        width: 20
        height: 20
        radius: 10
        color: Theme.textBright
    }
}
