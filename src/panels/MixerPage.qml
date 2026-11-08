import qs
import qs.components
import qs.services
import QtQuick

// The sound mixer (owner's request, 8 November 2026): in quick settings, in place of its usual content,
// a volume for each app playing sound, those with a window on the workspace you're on first. The icon
// mutes the app; the slider and the wheel set its volume, as the launcher's System mode does.
Item {
    id: page

    signal back

    // apps with a window on this workspace first, then by name
    readonly property var streams: {
        const here = Compositor.windows.filter(w => w.workspace === Compositor.activeWorkspace).map(w => w.appId.toLowerCase());
        const on = n => here.some(a => a && (a === (n.properties?.["application.process.binary"] ?? "").toLowerCase() || a.includes(Audio.appName(n).toLowerCase())));
        return Audio.streams.slice().sort((a, b) => (on(b) - on(a)) || Audio.appName(a).localeCompare(Audio.appName(b)));
    }

    implicitHeight: column.implicitHeight

    Column {
        id: column

        width: parent.width
        spacing: 12

        Item {
            width: parent.width
            height: 36

            GhostButton {
                x: -8
                anchors.verticalCenter: parent.verticalCenter
                icon: Icons.chevronLeft
                tint: Theme.text
                iconSize: 20
                label: "Back to quick settings"
                onClicked: page.back()
            }

            Text {
                x: 44
                anchors.verticalCenter: parent.verticalCenter
                text: "Sound mixer"
                color: Theme.textBright
                font.family: Theme.fontUi
                font.pixelSize: 17
                font.weight: Font.ExtraBold
            }
        }

        Repeater {
            model: page.streams

            Item {
                id: app

                required property var modelData
                readonly property var node: modelData
                readonly property bool muted: node.audio?.muted ?? false

                width: column.width
                height: 56

                // the app's icon: a click mutes it
                Rectangle {
                    id: disc
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    height: 40
                    radius: 20
                    color: discMouse.containsMouse ? Theme.overlay2 : Theme.overlay
                    Accessible.role: Accessible.Button
                    Accessible.name: `${app.muted ? "Unmute" : "Mute"} ${name.text}`

                    Image {
                        id: appIcon
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        sourceSize: Qt.size(44, 44)
                        source: Audio.appIcon(app.node)
                        visible: status === Image.Ready && !app.muted
                        asynchronous: true
                    }

                    Icon {
                        anchors.centerIn: parent
                        visible: !appIcon.visible
                        paths: app.muted ? Icons.volumeMuted : Icons.volume
                        color: app.muted ? Theme.subtext : Theme.text
                    }

                    MouseArea {
                        id: discMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Audio.toggleStreamMute(app.node)
                    }
                }

                Text {
                    id: name
                    anchors.left: disc.right
                    anchors.leftMargin: 12
                    anchors.right: percent.left
                    anchors.rightMargin: 8
                    y: 6
                    text: Audio.appName(app.node)
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: app.muted ? Theme.subtext : Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }

                Slider {
                    id: slider
                    anchors.left: disc.right
                    anchors.leftMargin: 12
                    anchors.right: percent.left
                    anchors.rightMargin: 8
                    y: 18
                    height: 36
                    value: Number.isFinite(app.node.audio?.volume) ? app.node.audio.volume : 0
                    Accessible.name: `${name.text} volume`
                    onMoved: Audio.setStreamVolume(app.node, slider.value)
                }

                // (not called `value`: an id hides the slider's own value in this file)
                Text {
                    id: percent
                    anchors.right: parent.right
                    y: 26
                    width: 42
                    horizontalAlignment: Text.AlignRight
                    text: app.muted ? "Muted" : Math.round(slider.shownValue * 100)
                    color: Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                }
            }
        }

        Text {
            visible: page.streams.length === 0
            width: parent.width
            topPadding: 4
            bottomPadding: 8
            wrapMode: Text.Wrap
            text: "No app is playing sound right now. Apps show here while they play."
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Font.Medium
        }
    }
}
