import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland // the layer's name, which a Hyprland blur rule matches (a Wayland protocol, not a compositor module)
import QtQuick

// Quick settings (QuickSettings board): tiles, sliders, uptime and power. The bar positions it and
// closes it on an outside click. A layer surface, not a popup: grabbing popups only open from a click.
PanelWindow {
    id: root

    function uptimeText(s: int): string {
        const m = Math.floor(s / 60) % 60, h = Math.floor(s / 3600) % 24, d = Math.floor(s / 86400);
        return d > 0 ? `${d} d ${h} h` : h > 0 ? `${h} h ${m} min` : `${m} min`;
    }

    function speedText(mbps: int): string {
        return mbps >= 1000 ? `${mbps / 1000} Gbps` : `${mbps} Mbps`;
    }

    property bool open
    property string popup // the card over the panel: "schedule", "dnd", "bluetooth", "localsend" or ""
    property string page // in place of the usual content: "localsend", "mixer" or ""

    signal powerRequested
    signal launcherRequested(string mode)

    // room around the panel for its shadow; the bar places the window with these
    readonly property int side: shadow.side
    readonly property int below: shadow.below
    // showoff mode: the bar places it right, and it slides in from there (px)
    property real slide
    readonly property real panelWidth: panel.width
    readonly property real panelHeight: panel.height

    visible: reveal.shown
    focusable: true // for Escape
    exclusiveZone: 0
    implicitWidth: side + panel.width + side
    implicitHeight: shadow.above + panel.height + below
    color: "transparent"
    WlrLayershell.namespace: "pistachio-panel" // frosted panels: Hyprland blurs the shell's layers by name
    mask: Region {
        item: panel // the shadow's room lets clicks through
    }

    onOpenChanged: {
        if (open) {
            brightnessLater.restart();
            if (LocalSend.sendRunning)
                page = "localsend"; // back where the transfer shows
        } else {
            popup = "";
            page = "";
        }
    }

    Reveal {
        id: reveal
        open: root.open
    }

    // the monitor's brightness, read once the panel is open: starting ddcutil holds the shell up
    // ~170 ms, which delayed quick settings' first frame (measured 9 November: first pixels at 360 ms
    // against the notification centre's 190; 190 without the read)
    Timer {
        id: brightnessLater
        interval: Theme.motionDuration + 60
        onTriggered: Brightness.refresh()
    }

    Shadow {
        id: shadow

        frostable: true
        kind: Theme.shadowPanel
        anchors.fill: panel
        radius: panel.radius
        opacity: panel.opacity
        scale: panel.scale
        transformOrigin: panel.transformOrigin
    }

    Rectangle {
        id: panel

        x: shadow.side + root.slide * (1 - reveal.progress)
        y: shadow.above
        width: 380
        height: (root.page === "localsend" ? localSendPage.implicitHeight : root.page === "mixer" ? mixerPage.implicitHeight : content.implicitHeight) + 40
        radius: Theme.panelRadius
        color: Theme.surface
        border.width: 1
        border.color: Theme.overlay2
        // fades and grows slightly from the status chip, and back
        opacity: reveal.progress
        scale: 0.96 + 0.04 * reveal.progress
        transformOrigin: Item.BottomRight
        focus: true
        Keys.onEscapePressed: {
            if (root.popup)
                root.popup = "";
            else if (root.page)
                root.page = "";
            else if (Showoff.active)
                Showoff.stop(); // the panels hold the keyboard meanwhile: Esc ends showoff mode
            else
                root.open = false;
        }

        LocalSendPage {
            id: localSendPage

            visible: root.page === "localsend"
            x: 20
            y: 20
            width: parent.width - 40
            onBack: root.page = ""
            onSettingsRequested: root.popup = "localsend"
            onVisibleChanged: if (visible && !LocalSend.sendRunning) LocalSend.scan()
        }

        MixerPage {
            id: mixerPage

            visible: root.page === "mixer"
            x: 20
            y: 20
            width: parent.width - 40
            onBack: root.page = ""
        }

        Column {
            id: content

            visible: root.page === ""
            x: 20
            y: 20
            width: parent.width - 40
            spacing: 16

            Grid {
                width: parent.width
                columns: 2
                spacing: 12

                Tile {
                    icon: Icons.ethernet
                    title: "Ethernet"
                    checked: Network.connected
                    subtitle: Network.connected ? root.speedText(Network.speed) : Network.hasLink ? "Off" : "Unplugged"
                    onClicked: Network.setEnabled(!Network.connected)
                }

                Tile {
                    icon: Icons.bluetooth
                    title: "Bluetooth"
                    checked: Bluetooth.enabled
                    subtitle: Bluetooth.summary
                    onRightClicked: root.popup = "bluetooth"
                    onClicked: Bluetooth.setEnabled(!Bluetooth.enabled)
                }

                Tile {
                    icon: Icons.bellOff
                    title: "Do not disturb"
                    checked: Notifs.dnd
                    subtitle: Notifs.dndStatus
                    onClicked: Notifs.setDnd(!Notifs.dnd)
                    onRightClicked: root.popup = "dnd"
                }

                Tile {
                    icon: Icons.moon
                    title: "Night light"
                    checked: NightLight.enabled
                    subtitle: NightLight.status
                    onClicked: NightLight.setEnabled(!NightLight.enabled)
                    onRightClicked: root.popup = "schedule"
                }
            }

            // LocalSend, while its app is installed (board quick-settings-localsend): opens its page
            Rectangle {
                visible: LocalSend.available
                width: parent.width
                height: 64
                radius: Theme.tileRadius
                color: Theme.overlay
                Accessible.role: Accessible.Button
                Accessible.name: `LocalSend, ${LocalSend.summary}. Open`

                Rectangle {
                    id: localSendDisc
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    height: 36
                    radius: 18
                    color: LocalSend.receiving ? Theme.pistachio : Theme.overlay2

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.hoverDuration
                            easing.type: Theme.easing
                        }
                    }

                    Icon {
                        anchors.centerIn: parent
                        paths: Icons.share
                        color: LocalSend.receiving ? Theme.bg : Theme.subtext
                    }
                }

                Column {
                    anchors.left: localSendDisc.right
                    anchors.leftMargin: 12
                    anchors.right: localSendChevron.left
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: "LocalSend"
                        color: Theme.textBright
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        lineHeight: 17
                        lineHeightMode: Text.FixedHeight
                    }

                    Text {
                        width: parent.width
                        text: LocalSend.summary
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

                Icon {
                    id: localSendChevron
                    anchors.right: parent.right
                    anchors.rightMargin: 21
                    anchors.verticalCenter: parent.verticalCenter
                    paths: Icons.chevronRight
                    color: Theme.subtext
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.page = "localsend"
                }

                // the disc itself switches receiving, like the page's Receive files (owner's request)
                MouseArea {
                    anchors.centerIn: localSendDisc
                    width: 44
                    height: 44
                    cursorShape: Qt.PointingHandCursor
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: "Receive files"
                    Accessible.checked: LocalSend.receiving
                    onClicked: LocalSend.setReceive(!LocalSend.receiving)
                }
            }

            // what's playing, while a media player has something (not on the board; owner's request)
            MediaCard {
                showQueue: true
                width: parent.width
            }

            Column {
                width: parent.width
                spacing: 4

                SliderRow {
                    icon: Audio.muted ? Icons.volumeMuted : Icons.volume
                    off: Audio.muted
                    iconAction: Audio.muted ? "Unmute" : "Mute"
                    label: "Volume"
                    onIconClicked: Audio.toggleMute()
                    value: Audio.volume
                    onMoved: v => Audio.setVolume(v)
                }

                SliderRow {
                    visible: Audio.source !== null
                    icon: Audio.micMuted ? Icons.micOff : Icons.mic
                    off: Audio.micMuted
                    iconAction: Audio.micMuted ? "Unmute microphone" : "Mute microphone"
                    label: "Microphone"
                    onIconClicked: Audio.toggleMicMute()
                    value: Audio.micVolume
                    onMoved: v => Audio.setMicVolume(v)
                }

                SliderRow {
                    visible: Brightness.available
                    icon: Icons.sun
                    label: "Brightness"
                    value: Brightness.value
                    onMoved: v => Brightness.set(v)
                }

                SliderRow {
                    visible: NightLight.enabled // the warmth slider appears while night light is on
                    icon: Icons.thermometer
                    label: "Night light warmth, kelvin"
                    from: 2500
                    to: 6500
                    stepSize: 250 // as the launcher's ← →
                    value: NightLight.temperature
                    format: k => `${Math.round(k)}K`
                    onMoved: v => NightLight.setTemperature(v)
                }
            }

            Item {
                width: parent.width
                height: 16 + 44

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.overlay
                }

                Row {
                    y: 16
                    height: 44
                    spacing: 10

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 20
                        paths: Icons.clock
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            text: root.uptimeText(Uptime.seconds)
                            color: Theme.textBright
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                            lineHeight: 17
                            lineHeightMode: Text.FixedHeight
                        }

                        Text {
                            text: "Uptime"
                            color: Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            lineHeight: 14
                            lineHeightMode: Text.FixedHeight
                        }
                    }
                }

                IconButton {
                    id: powerButton
                    anchors.right: parent.right
                    y: 16
                    icon: Icons.power
                    Accessible.name: "Power menu"
                    onClicked: root.powerRequested()
                }

                IconButton {
                    id: launcherButton
                    anchors.right: powerButton.left
                    anchors.rightMargin: 8
                    y: 16
                    icon: Icons.search
                    Accessible.name: "Launcher"
                    onClicked: root.launcherRequested("all")
                }

                IconButton {
                    id: mixerButton
                    anchors.right: launcherButton.left
                    anchors.rightMargin: 8
                    y: 16
                    icon: Icons.mixer
                    iconSize: 22
                    Accessible.name: "Sound mixer"
                    onClicked: root.page = "mixer"
                }

                IconButton {
                    anchors.right: mixerButton.left
                    anchors.rightMargin: 8
                    y: 16
                    icon: Icons.sliders
                    Accessible.name: "Settings"
                    onClicked: { root.open = false; SettingsHub.openPage("appearance", ""); }
                }
            }
        }

        // Night light schedule (right-click the Night light tile). Not on the board; owner's request.
        Popover {
            open: root.popup === "schedule"
            title: "Night light schedule"
            onDismissed: root.popup = ""

            Item {
                width: parent.width
                height: 44

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: "Night light schedule"
                        color: Theme.textBright
                        font.family: Theme.fontUi
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }

                    Text {
                        text: !NightLight.available ? "hyprsunset is not installed" : NightLight.scheduled ? "Switches on and off by itself" : "Off"
                        color: Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }

                Switch {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    checked: NightLight.scheduled
                    Accessible.name: "Night light schedule"
                    onToggled: NightLight.setSchedule(!NightLight.scheduled, NightLight.from, NightLight.to)
                }
            }

            TimeStepper {
                label: "Turns on"
                minutes: NightLight.from
                onStepped: m => NightLight.setSchedule(NightLight.scheduled, m, NightLight.to)
            }

            TimeStepper {
                label: "Turns off"
                minutes: NightLight.to
                onStepped: m => NightLight.setSchedule(NightLight.scheduled, NightLight.from, m)
            }

            Text {
                width: parent.width
                topPadding: 4
                text: "Switching night light by hand holds until the next scheduled change."
                wrapMode: Text.Wrap
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: 11
                font.weight: Font.Medium
            }
        }

        // Do not disturb schedule (right-click the Do not disturb tile): its own times, or night light's.
        // Not on the board; owner's request.
        Popover {
            open: root.popup === "dnd"
            title: "Do not disturb schedule"
            onDismissed: root.popup = ""

            Item {
                width: parent.width
                height: 44

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: "Do not disturb schedule"
                        color: Theme.textBright
                        font.family: Theme.fontUi
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }

                    Text {
                        text: Notifs.dndScheduled ? "Switches on and off by itself" : "Off"
                        color: Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }

                Switch {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Notifs.dndScheduled
                    Accessible.name: "Do not disturb schedule"
                    onToggled: Notifs.setDndSchedule(!Notifs.dndScheduled)
                }
            }

            Item {
                width: parent.width
                height: 44

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: "Night light's times"
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: `${NightLight.timeText(NightLight.from)}–${NightLight.timeText(NightLight.to)}`
                        color: Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        font.features: { "tnum": 1 }
                    }
                }

                Switch {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Notifs.dndFollowsNight
                    Accessible.name: "Use night light's times"
                    onToggled: Notifs.setDndFollowsNight(!Notifs.dndFollowsNight)
                }
            }

            // its own times, while it doesn't follow night light's
            TimeStepper {
                visible: !Notifs.dndFollowsNight
                label: "Turns on"
                minutes: Notifs.dndFrom
                onStepped: m => Notifs.setDndTimes(m, Notifs.dndTo)
            }

            TimeStepper {
                visible: !Notifs.dndFollowsNight
                label: "Turns off"
                minutes: Notifs.dndTo
                onStepped: m => Notifs.setDndTimes(Notifs.dndFrom, m)
            }

            Text {
                width: parent.width
                topPadding: 4
                text: "Switching Do not disturb by hand holds until the next scheduled change."
                wrapMode: Text.Wrap
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: 11
                font.weight: Font.Medium
            }
        }

        // Quick Bluetooth connections (right-click the Bluetooth tile): paired devices, connected first.
        // Pairing new ones happens in the launcher's Bluetooth view, which scans. Owner's request.
        Popover {
            open: root.popup === "bluetooth"
            title: "Bluetooth devices"
            onDismissed: root.popup = ""

            Item {
                width: parent.width
                height: 44

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: "Bluetooth"
                        color: Theme.textBright
                        font.family: Theme.fontUi
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }

                    Text {
                        text: Bluetooth.summary
                        color: Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }

                Switch {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Bluetooth.enabled
                    Accessible.name: "Bluetooth"
                    onToggled: Bluetooth.setEnabled(!Bluetooth.enabled)
                }
            }

            Repeater {
                model: Bluetooth.enabled ? Bluetooth.paired.slice(0, 5) : []

                // a paired device: click to connect or disconnect
                Rectangle {
                    id: device

                    required property var modelData
                    readonly property bool connected: modelData.connected

                    width: parent.width
                    height: 52
                    radius: 14
                    color: deviceMouse.containsMouse ? Theme.overlay2 : "transparent"
                    Accessible.role: Accessible.Button
                    Accessible.name: `${Bluetooth.name(modelData)}, ${Bluetooth.status(modelData)}`

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.hoverDuration
                            easing.type: Theme.easing
                        }
                    }

                    Icon {
                        id: deviceIcon
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        paths: Icons.bluetooth
                        color: device.connected ? Theme.sageBlue : Theme.subtext
                    }

                    Column {
                        anchors.left: deviceIcon.right
                        anchors.leftMargin: 12
                        anchors.right: deviceAction.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            width: parent.width
                            text: Bluetooth.name(device.modelData)
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: device.connected ? Theme.textBright : Theme.text
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }

                        Text {
                            width: parent.width
                            text: Bluetooth.status(device.modelData)
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }

                    Text {
                        id: deviceAction
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: device.connected ? "Disconnect" : "Connect"
                        color: deviceMouse.containsMouse ? Theme.textBright : Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: deviceMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Bluetooth.toggleConnection(device.modelData)
                    }
                }
            }

            Text {
                visible: !Bluetooth.enabled || Bluetooth.paired.length === 0
                width: parent.width
                topPadding: 6
                bottomPadding: 6
                text: Bluetooth.enabled ? "No paired devices yet." : "Bluetooth is off."
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            // more: scanning and pairing, in the launcher
            Rectangle {
                width: parent.width
                height: 44
                radius: 14
                color: moreMouse.containsMouse ? Theme.overlay2 : "transparent"
                Accessible.role: Accessible.Button
                Accessible.name: "Pair new devices"

                Text {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Pair new devices…"
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Icon {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    size: 16
                    paths: Icons.chevronRight
                    color: Theme.subtext
                }

                MouseArea {
                    id: moreMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.open = false; SettingsHub.openPage("bluetooth", ""); }
                }
            }
        }

        // LocalSend's settings (the sliders on its page): the name others see, where files go, and
        // accepting known devices without a question. Laid out like the Bluetooth card (owner's call).
        Popover {
            open: root.popup === "localsend"
            title: "LocalSend settings"
            onDismissed: root.popup = ""

            Text {
                width: parent.width
                height: 36
                verticalAlignment: Text.AlignVCenter
                text: "LocalSend settings"
                color: Theme.textBright
                font.family: Theme.fontUi
                font.pixelSize: 14
                font.weight: Font.Bold
            }

            Text {
                text: "Device name"
                leftPadding: 4
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }

            Rectangle {
                width: parent.width
                height: 44
                radius: 22
                color: Theme.bg

                TextInput {
                    id: nameField
                    anchors.fill: parent
                    leftPadding: 16
                    rightPadding: 16
                    verticalAlignment: TextInput.AlignVCenter
                    text: LocalSend.name
                    maximumLength: 40
                    clip: true
                    color: Theme.text
                    selectionColor: Theme.overlay2
                    selectedTextColor: Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    Accessible.name: "Device name"
                    onEditingFinished: LocalSend.setName(text || LocalSend.hostName)
                }
            }

            Item {
                width: parent.width
                height: 52

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.right: changeFolder.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: "Save to"
                        color: Theme.textBright
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }

                    Text {
                        width: parent.width
                        text: LocalSend.folderShown
                        textFormat: Text.PlainText
                        elide: Text.ElideMiddle
                        color: Theme.subtext
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                }

                ActionButton {
                    id: changeFolder
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Change"
                    base: Theme.overlay2
                    onClicked: LocalSend.pickFolder()
                }
            }

            Item {
                width: parent.width
                height: 52

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.right: knownSwitch.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: "Accept known devices"
                        color: Theme.textBright
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: "No question from devices you've accepted before"
                        color: Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }

                Switch {
                    id: knownSwitch
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    checked: LocalSend.acceptKnown
                    Accessible.name: "Accept known devices"
                    onToggled: LocalSend.setAcceptKnown(!LocalSend.acceptKnown)
                }
            }

            ActionButton {
                visible: LocalSend.known.length > 0
                text: `Forget ${LocalSend.known.length} known ${LocalSend.known.length === 1 ? "device" : "devices"}`
                base: Theme.overlay2
                onClicked: LocalSend.forgetKnown()
            }
        }
    }

    // Toggle tile: icon disc (pistachio while on), title and subtitle.
    component Tile: Item {
        id: tile

        required property list<string> icon
        required property string title
        property string subtitle
        property bool checked

        signal clicked
        signal rightClicked

        width: (parent.width - 12) / 2
        height: 64
        Accessible.role: Accessible.Button
        Accessible.checkable: true
        Accessible.checked: checked
        Accessible.name: title

        Rectangle {
            anchors.fill: parent
            radius: Theme.tileRadius
            color: Theme.overlay
        }

        Rectangle {
            id: disc

            x: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 36
            radius: 18
            color: tile.checked ? Theme.pistachio : Theme.overlay2

            Behavior on color {
                ColorAnimation {
                    duration: Theme.hoverDuration
                    easing.type: Theme.easing
                }
            }

            Icon {
                anchors.centerIn: parent
                paths: tile.icon
                color: tile.checked ? Theme.bg : Theme.subtext
            }
        }

        Column {
            anchors.left: disc.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: 10 // not 14: "Do not disturb" needs 90 px
            anchors.verticalCenter: parent.verticalCenter

            Text {
                width: parent.width
                text: tile.title
                elide: Text.ElideRight
                color: Theme.textBright
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Bold
                lineHeight: 17
                lineHeightMode: Text.FixedHeight
            }

            Text {
                width: parent.width
                text: tile.subtitle
                elide: Text.ElideRight
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: 11
                font.weight: Font.DemiBold
                lineHeight: 14
                lineHeightMode: Text.FixedHeight
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => mouse.button === Qt.RightButton ? tile.rightClicked() : tile.clicked()
        }
    }

    // Icon, slider and its value.
    component SliderRow: Item {
        id: row

        required property list<string> icon
        required property string label
        property string iconAction // e.g. "Mute": makes the icon a button with this name
        property bool off // icon in subtext, e.g. while muted
        property alias from: slider.from
        property alias to: slider.to
        property alias stepSize: slider.stepSize
        property real value
        property var format: v => Math.round(v * 100) // the value as shown beside the slider

        signal moved(real newValue)
        signal iconClicked

        width: parent.width
        height: 44

        Icon {
            id: rowIcon
            anchors.verticalCenter: parent.verticalCenter
            size: 20
            paths: row.icon
            color: iconMouse.containsMouse ? Theme.textBright : row.off ? Theme.subtext : Theme.text
        }

        // a bigger target than the 20 px icon
        MouseArea {
            id: iconMouse
            visible: row.iconAction !== ""
            anchors.centerIn: rowIcon
            width: 36
            height: 36
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            Accessible.role: Accessible.Button
            Accessible.name: row.iconAction
            onClicked: row.iconClicked()
        }

        Slider {
            id: slider
            anchors.left: rowIcon.right
            anchors.leftMargin: 12
            anchors.right: valueLabel.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            value: row.value
            Accessible.name: row.label
            onMoved: row.moved(value)
        }

        Text {
            id: valueLabel
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 42
            horizontalAlignment: Text.AlignRight
            text: row.format(slider.shownValue) // counts along as the slider eases
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Font.Bold
            font.features: { "tnum": 1 }
        }
    }
}
