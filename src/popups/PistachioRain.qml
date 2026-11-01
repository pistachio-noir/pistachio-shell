import qs
import Quickshell
import Quickshell.Wayland // the overlay layer (a Wayland protocol, not a compositor module)
import QtQuick

// The easter egg (owner's pick, 31 October 2026): the Konami code in the launcher (↑↑↓↓←→←→ B A) makes
// pistachios rain over the screen for a few seconds. Each is an open shell (gold) with the green nut
// showing, falling and turning at its own pace; the window lets every click through. (The one place
// pistachio green is decoration rather than the active state.)
PanelWindow {
    id: root

    property bool raining

    function start() {
        nuts.model = 0; // a fresh set each time
        nuts.model = 48;
        raining = true;
        stop.restart();
    }

    visible: raining
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {} // clicks go through
    WlrLayershell.layer: WlrLayer.Overlay

    Timer {
        id: stop
        interval: 5200
        onTriggered: root.raining = false
    }

    Repeater {
        id: nuts
        model: 0

        Item {
            id: nut

            readonly property real size: 0.7 + Math.random() * 0.6
            readonly property int wait: Math.random() * 2000 // they start one after another
            readonly property int fall: 1800 + Math.random() * 1200

            x: Math.random() * (root.width - width)
            y: -80
            width: 28 * size
            height: 36 * size

            SequentialAnimation on y {
                PauseAnimation {
                    duration: nut.wait
                }
                NumberAnimation {
                    from: -80
                    to: root.height + 80
                    duration: nut.fall
                    easing.type: Easing.InSine
                }
            }
            RotationAnimation on rotation {
                from: Math.random() * 360
                to: Math.random() * 360 + (Math.random() < 0.5 ? -1 : 1) * 540
                duration: nut.wait + nut.fall
            }

            // the shell
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Theme.gold
            }

            // the nut, where the shell has opened
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.12
                width: parent.width * 0.56
                height: parent.height * 0.62
                radius: width / 2
                color: Theme.pistachio
            }
        }
    }
}
