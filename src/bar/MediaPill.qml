import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland // the layer's name, which a Hyprland blur rule matches (a Wayland protocol, not a compositor module)
import Quickshell.Widgets // ClippingRectangle, for the round cover
import QtQuick

// The media pill (owner's request, after phase 8; not on a board): what's playing, left of the bar as
// the tray pill is right of it, while a player has a track, paused too. A click opens the media card
// above it (as on the lock screen), the wheel skips tracks, and its button or a middle click plays or
// pauses. The bar positions it and hides and reveals it with itself.
PanelWindow {
    id: root

    property bool shown: true // the bar's state
    property bool instant // the bar's: a change of `shown` jumps instead of easing
    readonly property var player: Media.player
    readonly property bool hovered: hover.hovered
    readonly property bool cardOpen: card.open // the bar stays up meanwhile
    // a notch skips a track (a touchpad's steps add up to one), at most one every 400 ms
    property real wheelSum

    onPlayerChanged: if (!player) card.open = false

    visible: !!player?.trackTitle
    exclusiveZone: 0
    implicitWidth: pill.width
    implicitHeight: Theme.barHeight + Theme.barMargin // like the bar, so it slides off the same way
    color: "transparent"
    WlrLayershell.namespace: "pistachio-bar" // frosted panels: Hyprland blurs the shell's layers by name

    // takes no clicks while hidden; the bar's edge strip brings both back
    mask: Region {
        width: root.shown ? root.width : 0
        height: root.shown ? Theme.barHeight : 0
    }

    HoverHandler {
        id: hover
    }

    Timer {
        id: skipped
        interval: 400
    }

    // 0 hidden, 1 shown, on the bar's curve: the pill buds out of its edge beside the bar as the bar's
    // content shows, and goes with it
    property real grown: shown ? 1 : 0

    Behavior on grown {
        enabled: !root.instant

        NumberAnimation {
            duration: Theme.growDuration
            easing.type: Theme.easing
        }
    }

    Rectangle {
        id: pill

        readonly property real shownPart: Math.max(0, 2 * root.grown - 1)

        // 1 px border + 8 px padding, as in the bar; the 36 px button sits as a 40 px chip would
        width: 9 + art.width + 10 + text.width + 8 + play.width + 11
        height: Theme.barHeight
        opacity: shownPart
        scale: 0.8 + 0.2 * shownPart
        transformOrigin: Item.Right // the edge nearest the bar
        radius: Theme.barRadius
        color: Theme.surface
        border.width: 1
        border.color: Theme.overlay2
        Accessible.role: Accessible.Button
        Accessible.name: `Now playing: ${title.text}, ${artist.text}`

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: event => {
                if (event.button === Qt.MiddleButton)
                    Media.togglePlaying();
                else
                    card.open = !card.open;
            }
            onWheel: event => {
                root.wheelSum += event.angleDelta.y || event.angleDelta.x; // down or right: next
                if (Math.abs(root.wheelSum) < 120)
                    return;
                if (!skipped.running) {
                    if (root.wheelSum < 0)
                        Media.next();
                    else
                        Media.previous();
                    skipped.restart();
                }
                root.wheelSum = 0;
            }
        }

        ClippingRectangle {
            id: art

            x: 9
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.chipHeight
            height: Theme.chipHeight
            radius: Theme.chipRadius
            color: Theme.overlay

            Icon {
                anchors.centerIn: parent
                visible: cover.status !== Image.Ready
                paths: Icons.music
                color: Theme.subtext
            }

            Image {
                id: cover
                anchors.fill: parent
                source: root.player?.trackArtUrl ?? ""
                sourceSize: Qt.size(80, 80)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }

        // title over artist, as the bar's window title
        Column {
            id: text

            anchors.left: art.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(200, Math.max(title.implicitWidth, artist.implicitWidth))

            Text {
                id: title
                width: parent.width
                text: root.player?.trackTitle ?? ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.textBright
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Bold
                lineHeight: 17
                lineHeightMode: Text.FixedHeight
            }

            Text {
                id: artist
                width: parent.width
                text: root.player?.trackArtist || root.player?.identity || ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: 11
                font.weight: Font.DemiBold
                lineHeight: 14
                lineHeightMode: Text.FixedHeight
            }
        }

        MediaButton {
            id: play
            anchors.left: text.right
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            icon: root.player?.isPlaying ? Icons.pause : Icons.play
            label: root.player?.isPlaying ? "Pause" : "Play"
            enabled: root.player?.canTogglePlaying ?? false
            onClicked: Media.togglePlaying()
        }
    }

    // The media card, 12 px above the pill and centred on it (kept on screen), as on the lock screen:
    // it fades and grows slightly from the pill. Esc or a click outside closes it.
    PanelWindow {
        id: card

        property bool open

        visible: reveal.shown
        focusable: true // for Esc
        exclusiveZone: 0
        anchors.bottom: true
        anchors.left: true
        margins.left: Math.max(8, root.margins.left + (root.width - media.width) / 2) - shadow.side
        margins.bottom: root.height + 12 - shadow.below
        implicitWidth: shadow.side + media.width + shadow.side
        implicitHeight: shadow.above + media.height + shadow.below
        color: "transparent"
        WlrLayershell.namespace: "pistachio-panel"
        mask: Region {
            item: media // the shadow's room lets clicks through
        }

        onOpenChanged: grab.active = open

        Reveal {
            id: reveal
            open: card.open
        }

        Shadow {
            id: shadow

            frostable: true
            kind: Theme.shadowSmall
            anchors.fill: media
            radius: media.radius
            opacity: media.opacity
            scale: media.scale
            transformOrigin: Item.Bottom
        }

        MediaCard {
            id: media

            x: shadow.side
            y: shadow.above
            width: 360
            color: Theme.surface
            border.width: 1
            border.color: Theme.overlay2
            opacity: reveal.progress
            scale: 0.96 + 0.04 * reveal.progress
            transformOrigin: Item.Bottom
            focus: true
            Keys.onEscapePressed: card.open = false
        }
    }

    // a click outside the card and the pill closes the card; the pill stays clickable
    FocusGrab {
        id: grab
        windows: [card, root]
        onCleared: card.open = false
    }
}
