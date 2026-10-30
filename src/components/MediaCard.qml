import qs
import qs.services
import Quickshell.Widgets // ClippingRectangle, for the rounded cover art
import QtQuick

// What's playing (not on the boards; owner's request): cover, title and artist, previous, play/pause
// and next, for Media.player. In quick settings, on the lock screen and above the media pill; hidden
// while no player has anything. Under them, while the track has a length, the time played, a bar and
// the length (owner's request, after phase 8): a click or a drag on the bar jumps, if the player lets
// it. MPRIS doesn't say when the position moves, so it's read again each second while playing.
Rectangle {
    id: media

    readonly property var player: Media.player
    readonly property bool hasLength: (player?.lengthSupported ?? false) && player.length > 0
    readonly property bool canSeek: (player?.canSeek ?? false) && hasLength
    property bool dragging
    property real dragTo // 0–1 while dragging
    readonly property real fraction: dragging ? dragTo : hasLength ? Math.min(1, player.position / player.length) : 0

    // "3:07", "1:02:45"
    function time(seconds: real): string {
        const s = Math.max(0, Math.floor(seconds));
        const two = n => String(n).padStart(2, "0");
        return s >= 3600 ? `${Math.floor(s / 3600)}:${two(Math.floor(s % 3600 / 60))}:${two(s % 60)}` : `${Math.floor(s / 60)}:${two(s % 60)}`;
    }

    function seek(to: real) {
        if (player.positionSupported)
            player.position = to * player.length;
        else
            player.seek(to * player.length - player.position);
    }

    visible: player !== null
    height: 76 + (hasLength ? 22 : 0)
    radius: Theme.tileRadius
    color: Theme.overlay
    Accessible.role: Accessible.Grouping
    Accessible.name: `Now playing: ${title.text}, ${artist.text}`

    Behavior on height {
        NumberAnimation {
            duration: Theme.motionDuration
            easing.type: Theme.easing
        }
    }

    Timer {
        running: media.hasLength && (media.player?.isPlaying ?? false)
        interval: 1000
        repeat: true
        onTriggered: media.player.positionChanged()
    }

    // the cover, the words and the buttons, in the card's first 76 px
    Item {
        id: top
        width: parent.width
        height: 76
    }

    ClippingRectangle {
        id: art

        x: 12
        anchors.verticalCenter: top.verticalCenter
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
        anchors.verticalCenter: top.verticalCenter
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
        anchors.verticalCenter: top.verticalCenter
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

    // time played, the bar, the length
    Item {
        x: 14
        y: 72
        width: parent.width - 28
        height: 16
        visible: media.hasLength
        opacity: media.hasLength ? 1 : 0
        Accessible.role: media.canSeek ? Accessible.Slider : Accessible.ProgressBar
        Accessible.name: `Played ${played.text} of ${length.text}`

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.motionDuration
                easing.type: Theme.easing
            }
        }

        Text {
            id: played
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            text: media.time(media.fraction * (media.player?.length ?? 0))
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }

        Text {
            id: length
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            horizontalAlignment: Text.AlignRight
            text: media.time(media.player?.length ?? 0)
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }

        Rectangle {
            id: track

            anchors.left: played.right
            anchors.right: length.left
            anchors.verticalCenter: parent.verticalCenter
            height: 4
            radius: 2
            color: Theme.overlay2

            Rectangle {
                width: parent.width * media.fraction
                height: parent.height
                radius: 2
                color: Theme.pistachio
            }

            // the knob, while pointing at a bar that can jump
            Rectangle {
                x: parent.width * media.fraction - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 10
                height: 10
                radius: 5
                color: Theme.textBright
                opacity: seekArea.containsMouse || media.dragging ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.hoverDuration
                        easing.type: Theme.easing
                    }
                }
            }

            MouseArea {
                id: seekArea

                function at(x: real): real {
                    return Math.max(0, Math.min(1, x / track.width));
                }

                anchors.fill: parent
                anchors.topMargin: -6
                anchors.bottomMargin: -6
                enabled: media.canSeek
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => {
                    media.dragTo = at(mouse.x);
                    media.dragging = true;
                }
                onPositionChanged: mouse => {
                    if (pressed)
                        media.dragTo = at(mouse.x);
                }
                onReleased: {
                    media.seek(media.dragTo);
                    media.dragging = false;
                }
                onCanceled: media.dragging = false
            }
        }
    }
}
