import qs
import qs.components
import qs.services
import QtQuick

// LocalSend's toast, below the notifications: a device asks to send (board localsend-incoming-request),
// then the transfer's progress (localsend-receiving); a text a device sent, with Copy and Close; and a
// short line when a transfer ends badly ("iPhone cancelled"). It waits for no countdown: a request stays
// until it's answered or the sender gives up, even with Do not disturb on (owner's call, without sound).
Rectangle {
    id: toast

    readonly property var request: LocalSend.request
    readonly property var incoming: LocalSend.incoming
    readonly property var message: LocalSend.message
    readonly property var from: request?.from ?? incoming?.from ?? message?.from ?? null
    readonly property string mode: request ? "request" : incoming ? "receiving" : message ? "message" : LocalSend.note ? "note" : ""

    visible: mode !== ""
    width: parent.width
    height: Math.max(disc.height, content.implicitHeight) + 32
    radius: 24
    color: Theme.surface
    border.width: 1
    border.color: Theme.overlay2
    Accessible.role: mode === "request" ? Accessible.AlertMessage : Accessible.StatusBar
    Accessible.name: title.text

    Shadow {
        frostable: true
        z: -1
        kind: Theme.shadowSmall
        anchors.fill: parent
        radius: parent.radius
    }

    Rectangle {
        id: disc
        x: 16
        y: 16
        width: 40
        height: 40
        radius: 20
        color: Theme.overlay

        Icon {
            anchors.centerIn: parent
            size: 20
            paths: toast.mode === "receiving" ? Icons.download : toast.from ? LocalSendLook.deviceIcon(toast.from) : Icons.share
            color: toast.mode === "receiving" ? Theme.pistachio : toast.from ? LocalSendLook.deviceTint(toast.from) : Theme.subtext
        }
    }

    Column {
        id: content

        anchors.left: disc.right
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 16
        y: 16
        spacing: 12

        Column {
            width: parent.width
            spacing: 2

            Item {
                width: parent.width
                height: title.implicitHeight

                Text {
                    id: title
                    anchors.left: parent.left
                    anchors.right: corner.left
                    anchors.rightMargin: 8
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: {
                        const name = toast.from?.alias ?? "";
                        return ({ request: `${name} wants to send files`, receiving: `Receiving from ${name}`, message: `${name} sent a message`, note: LocalSend.note })[toast.mode] ?? "";
                    }
                    color: Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: 14
                    font.weight: Font.Bold
                }

                Text {
                    id: corner
                    anchors.right: parent.right
                    anchors.baseline: title.baseline
                    text: toast.mode === "receiving" ? `${LocalSend.percent(toast.incoming)}%` : toast.mode === "note" ? "" : "now"
                    color: toast.mode === "receiving" ? Theme.textBright : Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    font.weight: toast.mode === "receiving" ? Font.Bold : Font.DemiBold
                    font.features: { "tnum": 1 }
                }
            }

            Text {
                visible: text !== ""
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: toast.mode === "request" ? `${toast.request.files.length} ${toast.request.files.length === 1 ? "file" : "files"} · ${LocalSend.size(toast.request.total)}` : toast.mode === "receiving" ? `${toast.incoming.file || "Starting"} · file ${toast.incoming.index} of ${toast.incoming.count}` : ""
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: 12
                font.weight: Font.Medium
                lineHeight: 17
                lineHeightMode: Text.FixedHeight
            }
        }

        // what's offered: the first two files and a count
        Row {
            visible: toast.mode === "request"
            width: parent.width
            spacing: 8

            Repeater {
                model: toast.request ? toast.request.files.slice(0, 2) : []

                FileChip {
                    required property var modelData
                    item: modelData
                    maxWidth: (content.width - (toast.request.files.length > 2 ? 52 : 0) - 8) / 2
                }
            }

            Rectangle {
                visible: (toast.request?.files.length ?? 0) > 2
                width: moreLabel.implicitWidth + 24
                height: 28
                radius: 14
                color: Theme.overlay2

                Text {
                    id: moreLabel
                    anchors.centerIn: parent
                    text: `+${(toast.request?.files.length ?? 0) - 2}`
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    font.weight: Font.Bold
                }
            }
        }

        Text {
            visible: toast.mode === "request"
            width: parent.width
            elide: Text.ElideMiddle
            textFormat: Text.StyledText
            text: `Save to <font face="${Theme.fontMono}" color="${Theme.text}">${LocalSend.folderShown.replace(/&/g, "&amp;").replace(/</g, "&lt;")}</font>`
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Font.Medium
        }

        // the text itself, four lines at most
        Text {
            visible: toast.mode === "message"
            width: parent.width
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: toast.message?.text ?? ""
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: 13
            font.weight: Font.Medium
            lineHeight: 18
            lineHeightMode: Text.FixedHeight
        }

        Column {
            visible: toast.mode === "receiving"
            width: parent.width
            spacing: 8

            Rectangle {
                width: parent.width
                height: 8
                radius: 4
                color: Theme.bg

                Rectangle {
                    width: toast.incoming && toast.incoming.total > 0 ? parent.width * Math.min(1, toast.incoming.done / toast.incoming.total) : 0
                    height: parent.height
                    radius: 4
                    color: Theme.pistachio

                    Behavior on width {
                        NumberAnimation {
                            duration: Theme.motionDuration
                            easing.type: Theme.easing
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: 14

                Text {
                    text: toast.incoming ? `${LocalSend.size(toast.incoming.done)} of ${LocalSend.size(toast.incoming.total)}` : ""
                    color: Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }

                Text {
                    anchors.right: parent.right
                    text: toast.incoming ? LocalSend.pace(toast.incoming) : ""
                    color: Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
            }
        }

        Row {
            visible: toast.mode !== "note"
            spacing: 8

            ActionButton {
                visible: toast.mode === "request" || toast.mode === "message"
                primary: true
                text: toast.mode === "message" ? "Copy" : "Accept"
                onClicked: toast.mode === "message" ? LocalSend.copyMessage() : LocalSend.accept()
            }

            ActionButton {
                visible: toast.mode === "request" || toast.mode === "message"
                text: toast.mode === "message" ? "Close" : "Decline"
                onClicked: {
                    if (toast.mode === "message")
                        LocalSend.message = null;
                    else
                        LocalSend.decline();
                }
            }

            // destructive: terracotta text on overlay, never a terracotta fill
            Rectangle {
                visible: toast.mode === "receiving"
                width: cancelLabel.implicitWidth + 32
                height: 40
                radius: 20
                color: cancelMouse.containsMouse ? Theme.overlay2 : Theme.overlay
                Accessible.role: Accessible.Button
                Accessible.name: "Cancel"

                Text {
                    id: cancelLabel
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Theme.terracotta
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    font.weight: Font.ExtraBold
                }

                MouseArea {
                    id: cancelMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: LocalSend.cancelReceive()
                }
            }
        }
    }
}
