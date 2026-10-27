import qs
import qs.services
import Quickshell.Widgets // ClippingRectangle, for the rounded cover art
import QtQuick

// What's playing (not on the boards; owner's request): cover, title and artist, previous, play/pause
// and next, for Media.player. In quick settings and on the lock screen; hidden while no player has
// anything.
Rectangle {
    id: media

    readonly property var player: Media.player

    visible: player !== null
    height: 76
    radius: Theme.tileRadius
    color: Theme.overlay
    Accessible.role: Accessible.Grouping
    Accessible.name: `Now playing: ${title.text}, ${artist.text}`

    ClippingRectangle {
        id: art

        x: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 52
        height: 52
        radius: 14
        color: Theme.overlay2

        Icon {
            anchors.centerIn: parent
            visible: cover.status !== Image.Ready
            paths: Icons.music
            color: Theme.subtext
        }

        Image {
            id: cover
            anchors.fill: parent
            source: media.player?.trackArtUrl ?? ""
            sourceSize: Qt.size(104, 104)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }

    Column {
        anchors.left: art.right
        anchors.leftMargin: 12
        anchors.right: controls.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            id: title
            width: parent.width
            text: media.player?.trackTitle || media.player?.identity || ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.textBright
            font.family: Theme.fontUi
            font.pixelSize: 13
            font.weight: Font.Bold
        }

        Text {
            id: artist
            width: parent.width
            text: media.player?.trackArtist || media.player?.identity || ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Font.Medium
        }
    }

    Row {
        id: controls

        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        MediaButton {
            icon: Icons.skipBack
            label: "Previous"
            enabled: media.player?.canGoPrevious ?? false
            onClicked: Media.previous()
        }

        MediaButton {
            icon: media.player?.isPlaying ? Icons.pause : Icons.play
            label: media.player?.isPlaying ? "Pause" : "Play"
            primary: true
            enabled: media.player?.canTogglePlaying ?? false
            onClicked: Media.togglePlaying()
        }

        MediaButton {
            icon: Icons.skipForward
            label: "Next"
            enabled: media.player?.canGoNext ?? false
            onClicked: Media.next()
        }
    }
}
