import qs
import qs.services
import QtQuick
import QtQuick.Effects

// A board's drop shadow under a rounded panel: put it just before the panel, filling it, with the same
// radius (and opacity and scale, if the panel animates them). A window that ends at the panel's edge
// cuts the shadow off, so it needs `side` px of room left and right, `above` and `below`.
RectangularShadow {
    // Theme.shadowPanel, shadowSmall or shadowModal
    required property var kind

    readonly property int side: kind.blur
    readonly property int above: Math.max(0, kind.blur - kind.y)
    readonly property int below: kind.blur + kind.y

    // off in the launcher (System, Shell settings); the windows keep the room, which costs nothing
    visible: ShellSettings.shadows
    offset.y: kind.y
    blur: kind.blur
    color: Qt.rgba(Theme.shadow.r, Theme.shadow.g, Theme.shadow.b, kind.alpha)
}
