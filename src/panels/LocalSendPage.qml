import qs
import qs.components
import qs.services
import QtQuick

// LocalSend in quick settings, in place of its usual content: files to send, devices nearby and the
// Receive switch (board localsend-send), then a transfer's progress (localsend-sending). The states the
// boards don't show (nothing picked, looking for devices, none found, receiving off or blocked, waiting
// for an answer, declined, done, failed) follow the boards' own pieces and the Pistachio Noir rules.
Item {
    id: page

    signal back
    signal settingsRequested

    readonly property bool sending: LocalSend.send !== null
    readonly property var t: LocalSend.send
    readonly property int shownDevices: Math.min(4, LocalSend.devices.length)

    implicitHeight: sending ? sendingView.implicitHeight : sendView.implicitHeight

    // files dropped from the desktop or a file manager join the list
    DropArea {
        id: drop
        anchors.fill: parent
        enabled: !page.sending
        keys: ["text/uri-list"]
        onDropped: event => LocalSend.add(event.urls.map(u => decodeURIComponent(u.toString().replace(/^file:\/\//, ""))))
    }

    Column {
        id: sendView

        visible: !page.sending
        width: parent.width
        spacing: 16

        Header {
            title: "LocalSend"
            settings: true
            onBackClicked: page.back()
            onSettingsClicked: page.settingsRequested()
        }

        // what goes: a count, its size and the three ways to add more, then the first files
        Rectangle {
            width: parent.width
            height: files.implicitHeight + 28
            radius: Theme.tileRadius
            color: drop.containsDrag ? Theme.overlay2 : Theme.overlay

            Behavior on color {
                ColorAnimation {
                    duration: Theme.hoverDuration
                    easing.type: Theme.easing
                }
            }

            Column {
                id: files

                x: 14
                y: 14
                width: parent.width - 28
                spacing: 10

                Item {
                    width: parent.width + 8
                    height: 44
                    y: -6

                    Column {
                        anchors.left: parent.left
                        anchors.right: buttons.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: drop.containsDrag ? "Drop to add" : LocalSend.items.length === 0 ? "Nothing to send yet" : `${LocalSend.items.length} ${LocalSend.items.length === 1 ? "item" : "items"} ready`
                            color: Theme.textBright
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.ExtraBold
                        }

                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: LocalSend.nothingToPaste ? "Nothing to paste" : LocalSend.items.length === 0 ? "Add files, or drop them here" : LocalSend.size(LocalSend.itemsSize)
                            color: Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                    }

                    Row {
                        id: buttons
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter

                        GhostButton {
                            icon: Icons.plus
                            label: "Add files"
                            onClicked: LocalSend.pickFiles(false)
                        }

                        GhostButton {
                            icon: Icons.folder
                            label: "Add folder"
                            onClicked: LocalSend.pickFiles(true)
                        }

                        GhostButton {
                            icon: Icons.clipboard
                            label: "Paste from clipboard"
                            onClicked: LocalSend.paste()
                        }

                        GhostButton {
                            visible: LocalSend.items.length > 0
                            icon: Icons.close
                            label: "Clear"
                            onClicked: LocalSend.clear()
                        }
                    }
                }

                Row {
                    visible: LocalSend.items.length > 0
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: LocalSend.items.slice(0, 2)

                        FileChip {
                            required property var modelData
                            item: modelData
                            maxWidth: (files.width - (LocalSend.items.length > 2 ? 52 : 0) - 8) / 2
                        }
                    }

                    Rectangle {
                        visible: LocalSend.items.length > 2
                        width: more.implicitWidth + 24
                        height: 28
                        radius: 14
                        color: Theme.overlay2

                        Text {
                            id: more
                            anchors.centerIn: parent
                            text: `+${LocalSend.items.length - 2}`
                            color: Theme.text
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }
                    }
                }
            }
        }

        // devices with LocalSend open, on this network
        Column {
            width: parent.width
            spacing: 10

            Item {
                width: parent.width
                height: 16

                Text {
                    x: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: "NEARBY"
                    color: Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 0.66
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: LocalSend.scanning ? "Searching…" : `${LocalSend.devices.length} ${LocalSend.devices.length === 1 ? "device" : "devices"}`
                    color: Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }

            Flickable {
                visible: LocalSend.devices.length > 0
                width: parent.width
                height: page.shownDevices * 56 + Math.max(0, page.shownDevices - 1) * 10
                contentHeight: list.implicitHeight
                interactive: LocalSend.devices.length > 4
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: list
                    width: parent.width
                    spacing: 10

                    Repeater {
                        model: LocalSend.devices

                        Rectangle {
                            id: row

                            required property var modelData
                            readonly property bool canSend: LocalSend.items.length > 0 && !LocalSend.sendRunning
                            readonly property bool lit: rowMouse.containsMouse && canSend

                            width: list.width
                            height: 56
                            radius: Theme.tileRadius
                            color: lit ? Theme.overlay2 : Theme.overlay
                            Accessible.role: Accessible.Button
                            Accessible.name: `Send to ${modelData.alias}`

                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.hoverDuration
                                    easing.type: Theme.easing
                                }
                            }

                            Rectangle {
                                id: disc
                                x: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 36
                                height: 36
                                radius: 18
                                color: row.lit ? Theme.overlay : Theme.overlay2

                                Icon {
                                    anchors.centerIn: parent
                                    paths: LocalSendLook.deviceIcon(row.modelData)
                                    color: LocalSendLook.deviceTint(row.modelData)
                                }
                            }

                            Column {
                                anchors.left: disc.right
                                anchors.leftMargin: 12
                                anchors.right: action.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Text {
                                    width: parent.width
                                    text: row.modelData.alias
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: Theme.textBright
                                    font.family: Theme.fontUi
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                }

                                Row {
                                    spacing: 8

                                    Text {
                                        text: LocalSend.kindLabel(row.modelData)
                                        textFormat: Text.PlainText
                                        color: Theme.subtext
                                        font.family: Theme.fontUi
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        text: row.modelData.ip
                                        color: Theme.subtext
                                        font.family: Theme.fontMono
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                    }
                                }
                            }

                            Item {
                                id: action
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: row.lit ? pill.width : 32
                                height: 32

                                Rectangle {
                                    id: pill
                                    visible: row.lit
                                    width: sendLabel.implicitWidth + 28
                                    height: 32
                                    radius: 16
                                    color: Theme.pistachio

                                    Text {
                                        id: sendLabel
                                        anchors.centerIn: parent
                                        text: "Send"
                                        color: Theme.bg
                                        font.family: Theme.fontUi
                                        font.pixelSize: 12
                                        font.weight: Font.ExtraBold
                                    }
                                }

                                // nothing to send yet: no arrow, and the row doesn't light up
                                Icon {
                                    visible: !row.lit && row.canSend
                                    anchors.centerIn: parent
                                    size: 16
                                    paths: Icons.send
                                    color: Theme.subtext
                                }
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: row.canSend ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: if (row.canSend) LocalSend.sendTo(row.modelData)
                            }
                        }
                    }
                }
            }

            // none yet: still looking, or nobody answered
            Rectangle {
                visible: LocalSend.devices.length === 0
                width: parent.width
                height: empty.implicitHeight + 28
                radius: Theme.tileRadius
                color: Theme.overlay

                Column {
                    id: empty
                    x: 14
                    y: 14
                    width: parent.width - 28
                    spacing: 10

                    Row {
                        width: parent.width
                        spacing: 12

                        Rectangle {
                            width: 36
                            height: 36
                            radius: 18
                            color: Theme.overlay2

                            Icon {
                                id: spinner
                                anchors.centerIn: parent
                                paths: LocalSend.scanning ? Icons.loader : Icons.share
                                color: Theme.subtext

                                RotationAnimation on rotation {
                                    running: LocalSend.scanning
                                    from: 0
                                    to: 360
                                    duration: 1000
                                    loops: Animation.Infinite
                                    onRunningChanged: if (!running) spinner.rotation = 0
                                }
                            }
                        }

                        Column {
                            width: parent.width - 48
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                text: LocalSend.scanning ? "Looking for devices…" : "No devices found"
                                color: Theme.text
                                font.family: Theme.fontUi
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }

                            Text {
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: "LocalSend has to be open on the other device, on the same network."
                                color: Theme.subtext
                                font.family: Theme.fontUi
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                lineHeight: 17
                                lineHeightMode: Text.FixedHeight
                            }
                        }
                    }

                    ActionButton {
                        visible: !LocalSend.scanning
                        text: "Search again"
                        base: Theme.overlay2
                        onClicked: LocalSend.scan()
                    }
                }
            }
        }

        // Receive files, at the bottom behind a line
        Item {
            width: parent.width
            height: 61

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.overlay
            }

            Column {
                y: 17
                anchors.left: parent.left
                anchors.right: receiveSwitch.left
                anchors.rightMargin: 12
                spacing: 1

                Text {
                    text: "Receive files"
                    color: Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    text: LocalSend.busy ? "The LocalSend app is running · quit it to receive here" : LocalSend.receiving ? `As <font face="${Theme.fontMono}">${LocalSend.name.replace(/&/g, "&amp;").replace(/</g, "&lt;")}</font> · Everyone` : "Off · others can't send to this PC"
                    color: Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }

            Switch {
                id: receiveSwitch
                anchors.right: parent.right
                y: 16
                checked: LocalSend.receiving
                Accessible.name: "Receive files"
                onToggled: LocalSend.setReceive(!LocalSend.receiving)
            }
        }
    }

    // a transfer out: who to, how far, each file, and Cancel; then what came of it
    Column {
        id: sendingView

        readonly property string state: page.t?.state ?? ""
        readonly property bool running: state === "waiting" || state === "sending"
        readonly property string to: page.t?.device.alias ?? ""

        visible: page.sending
        width: parent.width
        spacing: 16

        Header {
            title: sendingView.running ? "Sending" : sendingView.state === "done" ? "Sent" : "Not sent"
            onBackClicked: page.back()
        }

        Rectangle {
            width: parent.width
            height: card.implicitHeight + 28
            radius: Theme.tileRadius
            color: Theme.overlay

            Column {
                id: card
                x: 14
                y: 14
                width: parent.width - 28
                spacing: 14

                Item {
                    width: parent.width
                    height: 36

                    Rectangle {
                        id: toDisc
                        width: 36
                        height: 36
                        radius: 18
                        color: Theme.overlay2

                        Icon {
                            anchors.centerIn: parent
                            paths: page.t ? LocalSendLook.deviceIcon(page.t.device) : Icons.monitor
                            color: page.t ? LocalSendLook.deviceTint(page.t.device) : Theme.subtext
                        }
                    }

                    Column {
                        anchors.left: toDisc.right
                        anchors.leftMargin: 12
                        anchors.right: percent.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: `To ${sendingView.to}`
                            textFormat: Text.PlainText
                            color: Theme.textBright
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.ExtraBold
                        }

                        Text {
                            text: page.t?.device.ip ?? ""
                            color: Theme.subtext
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }

                    Text {
                        id: percent
                        visible: sendingView.state === "sending" || sendingView.state === "done"
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: sendingView.state === "done" ? "100%" : `${page.t ? LocalSend.percent(page.t) : 0}%`
                        color: Theme.textBright
                        font.family: Theme.fontUi
                        font.pixelSize: 20
                        font.weight: Font.ExtraBold
                        font.features: { "tnum": 1 }
                    }
                }

                // the bar while it goes, else one line on what's happening
                Column {
                    visible: sendingView.state === "sending"
                    width: parent.width
                    spacing: 8

                    Rectangle {
                        width: parent.width
                        height: 10
                        radius: 5
                        color: Theme.bg

                        Rectangle {
                            width: page.t && page.t.total > 0 ? parent.width * Math.min(1, page.t.done / page.t.total) : 0
                            height: parent.height
                            radius: 5
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
                            text: page.t ? `${LocalSend.size(page.t.done)} of ${LocalSend.size(page.t.total)}` : ""
                            color: Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }

                        Text {
                            anchors.right: parent.right
                            text: page.t ? LocalSend.pace(page.t) : ""
                            color: Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                    }
                }

                Text {
                    visible: sendingView.state !== "sending"
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: ({
                            waiting: `Waiting for ${sendingView.to} to accept…`,
                            done: `Everything arrived on ${sendingView.to}.`,
                            declined: `${sendingView.to} declined.`,
                            busy: `${sendingView.to} is busy with another transfer. Try again in a moment.`,
                            pin: `${sendingView.to} asks for a PIN, which the shell can't send yet. Turn the PIN off on ${sendingView.to}.`,
                            failed: page.t?.done > 0 ? `Stopped at ${LocalSend.percent(page.t)} %: the connection to ${sendingView.to} broke.` : `Couldn't reach ${sendingView.to}. Is LocalSend still open there?`,
                            cancelled: "Cancelled."
                        })[sendingView.state] ?? ""
                    color: sendingView.state === "failed" || sendingView.state === "declined" ? Theme.terracotta : Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    lineHeight: 17
                    lineHeightMode: Text.FixedHeight
                }
            }
        }

        // each file: sent, going, or waiting its turn (four at most, then a count)
        Column {
            width: parent.width
            spacing: 2

            Repeater {
                model: (page.t?.files ?? []).slice(0, 4)

                Item {
                    id: fileRow

                    required property var modelData
                    required property int index
                    readonly property var f: modelData
                    // how much of this one is there: what went, less the files before it
                    readonly property real sentHere: {
                        let before = 0;
                        for (let i = 0; i < index; i++)
                            if (page.t.files[i].state !== "skipped")
                                before += page.t.files[i].size;
                        return Math.max(0, Math.min(f.size, page.t.done - before));
                    }

                    width: parent.width
                    height: 44

                    Rectangle {
                        id: fileDisc
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36
                        height: 36
                        radius: 18
                        color: Theme.overlay2

                        Icon {
                            anchors.centerIn: parent
                            paths: LocalSendLook.fileIcon(fileRow.f)
                            color: LocalSendLook.fileTint(fileRow.f)
                        }
                    }

                    Column {
                        anchors.left: fileDisc.right
                        anchors.leftMargin: 12
                        anchors.right: fileState.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            width: parent.width
                            text: fileRow.f.name
                            textFormat: Text.PlainText
                            elide: Text.ElideMiddle
                            color: Theme.textBright
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }

                        Text {
                            text: `${LocalSend.size(fileRow.f.size)} · ${fileRow.f.state === "skipped" ? "not wanted" : fileRow.f.state}`
                            color: Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }

                    Item {
                        id: fileState
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 28

                        Rectangle {
                            visible: fileRow.f.state === "sent"
                            anchors.fill: parent
                            radius: 14
                            color: Theme.overlay2

                            Icon {
                                anchors.centerIn: parent
                                size: 14
                                paths: Icons.check
                                color: Theme.teal
                            }
                        }

                        Text {
                            visible: fileRow.f.state === "sending"
                            anchors.centerIn: parent
                            text: `${fileRow.f.size > 0 ? Math.floor(100 * fileRow.sentHere / fileRow.f.size) : 0}%`
                            color: Theme.textBright
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            font.weight: Font.ExtraBold
                            font.features: { "tnum": 1 }
                        }

                        Icon {
                            visible: fileRow.f.state === "waiting" || fileRow.f.state === "skipped"
                            anchors.centerIn: parent
                            size: 14
                            paths: Icons.file
                            color: Theme.subtext
                        }
                    }
                }
            }

            Text {
                visible: (page.t?.files.length ?? 0) > 4
                leftPadding: 48
                height: 28
                verticalAlignment: Text.AlignVCenter
                text: `and ${(page.t?.files.length ?? 0) - 4} more`
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: 12
                font.weight: Font.Medium
            }
        }

        // Cancel while it runs; Done, or Back and Try again, after
        Rectangle {
            visible: sendingView.running
            width: parent.width
            height: 44
            radius: 22
            color: cancelMouse.containsMouse ? Theme.overlay2 : Theme.overlay
            Accessible.role: Accessible.Button
            Accessible.name: "Cancel transfer"

            Row {
                anchors.centerIn: parent
                spacing: 8

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 16
                    paths: Icons.close
                    color: Theme.terracotta
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Cancel transfer"
                    color: Theme.terracotta
                    font.family: Theme.fontUi
                    font.pixelSize: 14
                    font.weight: Font.ExtraBold
                }
            }

            MouseArea {
                id: cancelMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: LocalSend.cancelSend()
            }
        }

        Row {
            visible: !sendingView.running
            width: parent.width
            spacing: 8

            ActionButton {
                visible: sendingView.state !== "done"
                width: (parent.width - 8) / 2
                height: 44
                text: "Back"
                onClicked: LocalSend.closeSend(false)
            }

            ActionButton {
                width: sendingView.state === "done" ? parent.width : (parent.width - 8) / 2
                height: 44
                primary: true
                text: sendingView.state === "done" ? "Done" : "Try again"
                onClicked: LocalSend.closeSend(sendingView.state !== "done")
            }
        }
    }

    // back, the title, and on the first view the settings card's button
    component Header: Item {
        id: header

        required property string title
        property bool settings

        signal backClicked
        signal settingsClicked

        width: parent.width
        height: 36

        GhostButton {
            x: -8
            anchors.verticalCenter: parent.verticalCenter
            icon: Icons.chevronLeft
            tint: Theme.text
            iconSize: 20
            label: "Back to quick settings"
            onClicked: header.backClicked()
        }

        Text {
            x: 44
            anchors.verticalCenter: parent.verticalCenter
            text: header.title
            color: Theme.textBright
            font.family: Theme.fontUi
            font.pixelSize: 17
            font.weight: Font.ExtraBold
        }

        GhostButton {
            visible: header.settings
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            icon: Icons.sliders
            label: "LocalSend settings"
            onClicked: header.settingsClicked()
        }
    }
}
