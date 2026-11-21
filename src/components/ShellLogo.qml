import qs
import QtQuick

// The Pistachio Shell icon (pistachio-shell-design/pistachio-shell.svg: a desktop with two windows and the bar, and
// the launcher badge), drawn from Theme colours so it follows Noir. First-run setup's logo.
Item {
    id: root
    property real size: 92
    readonly property real k: size / 256
    implicitWidth: size
    implicitHeight: size

    // [x, y, width, height, radius, colour] in the SVG's 256 units
    readonly property var shapes: [
        [8, 8, 240, 240, 56, Theme.bgAlt],
        [44, 44, 168, 132, 22, Theme.overlay],
        [62, 62, 70, 42, 12, Theme.overlay2],
        [140, 62, 54, 42, 12, Theme.overlay2],
        [62, 116, 96, 24, 12, Theme.bg],
        [75, 123, 10, 10, 5, Theme.subtext],
        [91, 123, 10, 10, 5, Theme.subtext],
        [110, 123, 36, 10, 5, Theme.textBright],
        [134, 138, 96, 96, 48, Theme.bgAlt], // the launcher badge, ringed in the tile's colour
        [142, 146, 80, 80, 40, Theme.pistachio],
        [160, 164, 36, 36, 18, Theme.bg], // its magnifier
        [172, 176, 12, 12, 6, Theme.pistachio]
    ]
    Repeater {
        model: root.shapes
        Rectangle {
            required property var modelData
            required property int index
            x: modelData[0] * root.k; y: modelData[1] * root.k
            width: modelData[2] * root.k; height: modelData[3] * root.k
            radius: modelData[4] * root.k
            color: modelData[5]
            border.color: index === 0 ? Theme.overlay2 : "transparent"
            border.width: index === 0 ? Math.max(1, 4 * root.k) : 0
        }
    }
    Rectangle { // the magnifier's handle: (187, 191) to (199, 203), 12 wide with round ends
        x: 193 * root.k - width / 2; y: 197 * root.k - height / 2
        width: 12 * root.k; height: 29 * root.k
        radius: width / 2
        rotation: -45
        color: Theme.bg
    }
}
