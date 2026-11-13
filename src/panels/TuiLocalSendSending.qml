import qs
import qs.components
import qs.services
import QtQuick

// LocalSend sending, in the TUI style (board design/TUI/launcher-and-shell/LocalSendSending.html):
// "sending to pixel-8 · 6.4 MB/s", then each file with its state and a bracket bar, and Cancel while it
// runs. The helper reports the whole transfer's bytes and each file's state, so a file's bar is full
// once sent, the one going gets what has arrived of it, the rest are empty. Over, it says how it ended
// and offers Back / Try again or Done (as the Classic page).
Column {
    id: root

    readonly property var t: LocalSend.send
    readonly property string state: t?.state ?? ""
    readonly property bool running: LocalSend.sendRunning
    readonly property string to: t?.device?.alias ?? "the device"
    readonly property var files: t?.files ?? []
    // bytes of the file being sent that have arrived: the total done less what the sent files hold
    readonly property real going: {
        let sent = 0;
        for (const f of files)
            if (f.state === "sent")
                sent += f.size;
        return Math.max(0, (t?.done ?? 0) - sent);
    }

    function shareOf(f): real {
        if (f.state === "sent" || root.state === "done")
            return 1;
        if (f.state === "sending")
            return f.size > 0 ? Math.min(1, going / f.size) : 0;
        return 0;
    }

    function stateOf(f): string {
        if (f.state === "sent" || root.state === "done")
            return "done";
        if (f.state === "sending")
            return `${Math.round(shareOf(f) * 100)}%`;
        if (f.state === "skipped")
            return "skipped";
        return root.running ? "waiting" : "not sent";
    }

    spacing: 10

    Row {
        spacing: 0

        Text {
            text: root.running ? "sending to " : root.state === "done" ? "sent to " : "not sent to "
            color: Theme.subtext
            font.family: Theme.fontTui
            font.pixelSize: Theme.tuiTextSize
        }
        Text {
            text: root.to
            color: Theme.textBright
            font.family: Theme.fontTui
            font.pixelSize: Theme.tuiTextSize
            font.weight: Font.Bold
        }
        Text {
            visible: root.running && (root.t?.speed ?? 0) > 0
            text: `  ·  ${LocalSend.size(root.t?.speed ?? 0)}/s`
            color: Theme.subtext
            font.family: Theme.fontTui
            font.pixelSize: Theme.tuiTextSize
        }
    }

    // each file (five at most, then a count)
    Repeater {
        model: root.files.slice(0, 5)

        Column {
            id: file
            required property var modelData
            readonly property real share: root.shareOf(modelData)
            width: root.width
            spacing: 2

            Row {
                spacing: 8
                Text {
                    text: file.modelData.name
                    width: Math.min(implicitWidth, root.width - 100)
                    elide: Text.ElideMiddle
                    color: Theme.text
                    font.family: Theme.fontTui
                    font.pixelSize: Theme.tuiTextSize
                }
                Text {
                    text: root.stateOf(file.modelData)
                    color: Theme.subtext
                    font.family: Theme.fontTui
                    font.pixelSize: Theme.tuiTextSize
                }
            }

            // [██████████      ]  45%
            Item {
                width: root.width
                height: Theme.tuiLineHeight

                Text {
                    id: open
                    anchors.verticalCenter: parent.verticalCenter
                    text: "["
                    color: Theme.subtext
                    font.family: Theme.fontTui
                    font.pixelSize: Theme.tuiTextSize
                }
                Rectangle {
                    id: track
                    x: open.width + 3
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.width - x - close.width - 3 - 52
                    height: 12
                    color: Theme.tuiRule
                    Rectangle {
                        width: parent.width * file.share
                        height: parent.height
                        color: Theme.pistachio
                        Behavior on width {
                            NumberAnimation { duration: Theme.motionDuration; easing.type: Theme.easing }
                        }
                    }
                }
                Text {
                    id: close
                    x: track.x + track.width + 3
                    anchors.verticalCenter: parent.verticalCenter
                    text: "]"
                    color: Theme.subtext
                    font.family: Theme.fontTui
                    font.pixelSize: Theme.tuiTextSize
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    text: `${Math.round(file.share * 100)}%`
                    color: file.share >= 1 ? Theme.textBright : Theme.subtext
                    font.family: Theme.fontTui
                    font.pixelSize: Theme.tuiTextSize
                    font.weight: file.share >= 1 ? Font.Bold : Font.Normal
                    font.features: { "tnum": 1 }
                }
            }
        }
    }

    Text {
        visible: root.files.length > 5
        text: `and ${root.files.length - 5} more`
        color: Theme.subtext
        font.family: Theme.fontTui
        font.pixelSize: Theme.tuiTextSize
    }

    // how it ended, when it isn't sending
    Text {
        visible: root.state !== "sending"
        width: root.width
        wrapMode: Text.Wrap
        text: ({
                waiting: `waiting for ${root.to} to accept…`,
                done: `everything arrived on ${root.to}.`,
                declined: `${root.to} declined.`,
                busy: `${root.to} is busy with another transfer. try again in a moment.`,
                pin: `${root.to} asks for a PIN, which the shell can't send yet. turn the PIN off on ${root.to}.`,
                failed: (root.t?.done ?? 0) > 0 ? `stopped at ${LocalSend.percent(root.t)}%: the connection to ${root.to} broke.` : `couldn't reach ${root.to}. is LocalSend still open there?`,
                cancelled: "cancelled."
            })[root.state] ?? ""
        color: root.state === "failed" || root.state === "declined" ? Theme.terracotta : Theme.subtext
        font.family: Theme.fontTui
        font.pixelSize: Theme.tuiTextSize
    }

    Item {
        width: root.width
        height: Theme.tuiButtonHeight + 8

        Row {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: 8

            ActionButton {
                visible: root.running
                height: Theme.tuiButtonHeight + 8
                text: "Cancel"
                tint: Theme.terracotta
                base: Theme.overlay
                onClicked: LocalSend.cancelSend()
            }
            ActionButton {
                visible: !root.running && root.state !== "done"
                height: Theme.tuiButtonHeight + 8
                text: "Back"
                onClicked: LocalSend.closeSend(false)
            }
            ActionButton {
                visible: !root.running
                height: Theme.tuiButtonHeight + 8
                primary: true
                text: root.state === "done" ? "Done" : "Try again"
                onClicked: LocalSend.closeSend(root.state !== "done")
            }
        }
    }
}
