import qs
import QtQuick

// One of the calendar's two copies of its title or grid, which take turns (see Calendar.qml).
// When it turns `live` it comes in from `distance` px towards `heading`, fading in; when it hands
// the month over it carries on the same way and fades out, from wherever it was. A (0, 0) heading
// switches at once. Its own file: as an inline component in Calendar.qml it was "not a type".
Item {
    id: root

    property int year
    property int month // 0–11
    property bool live
    property point heading // e.g. (0, 1): the next month by the wheel, coming up from below
    property real distance
    property real dx
    property real dy

    visible: opacity > 0
    transform: Translate {
        x: root.dx
        y: root.dy
    }
    Component.onCompleted: opacity = live ? 1 : 0

    onLiveChanged: {
        motion.stop();
        if (heading.x === 0 && heading.y === 0) {
            dx = dy = 0;
            opacity = live ? 1 : 0;
            return;
        }
        if (live) {
            dx = distance * heading.x;
            dy = distance * heading.y;
            opacity = 0;
        }
        motion.start();
    }

    ParallelAnimation {
        id: motion

        NumberAnimation {
            target: root
            property: "dx"
            to: root.live ? 0 : -root.distance * root.heading.x
            duration: Theme.motionDuration
            easing.type: Theme.easing
        }
        NumberAnimation {
            target: root
            property: "dy"
            to: root.live ? 0 : -root.distance * root.heading.y
            duration: Theme.motionDuration
            easing.type: Theme.easing
        }
        NumberAnimation {
            target: root
            property: "opacity"
            to: root.live ? 1 : 0
            duration: Theme.motionDuration
            easing.type: Theme.easing
        }
    }
}
