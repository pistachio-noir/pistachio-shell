import qs
import QtQuick

// Open/close motion for a window: `progress` eases between 0 (closed) and 1 (open); bind the
// content's opacity, scale or offset to it, and the window's visible to `shown`, which stays true
// until the fade-out ends.
QtObject {
    property bool open
    property real progress: open ? 1 : 0
    readonly property bool shown: open || progress > 0

    Behavior on progress {
        NumberAnimation {
            duration: Theme.motionDuration
            easing.type: Theme.easing
        }
    }
}
