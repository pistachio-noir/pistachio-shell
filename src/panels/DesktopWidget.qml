import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Widgets // ClippingRectangle, for the cover art
import QtQuick

// One desktop widget (services/DesktopWidgets.qml; owner's request, 20 November 2026; laid out by
// Claude, no board): the Clock, the Weather, CPU/RAM, Now playing, Timers (Focus/Pomodoro, timers,
// the stopwatch) or Disk & GPU, sized to its cells on the desktop grid. Display only: no clicks.
// Classic: a soft tile over the wallpaper (bgAlt, see-through, radius 20). TUI: a square box with its
// name set in the top border, JetBrains Mono. The widget studio draws the same item while arranging.
Item {
    id: root

    required property string kind
    // CPU/RAM asks SystemStats for readings only while it's on screen
    property bool live: true

    readonly property bool tui: Theme.tui
    readonly property string title: ({ clock: "clock", weather: "weather", stats: "cpu / ram", media: "now playing", timers: "timers", system: "disk / gpu" })[kind] ?? kind

    readonly property bool watching: live && (kind === "stats" || kind === "system")
    property bool counted // this item is one of SystemStats' widget watchers
    function count() {
        if (watching !== counted) {
            SystemStats.watchWidget(watching);
            counted = watching;
        }
    }
    onWatchingChanged: count()
    Component.onCompleted: count()
    Component.onDestruction: if (counted) SystemStats.watchWidget(false)

    Rectangle {
        anchors.fill: parent
        radius: Theme.tileRadius
        color: Qt.rgba(root.tui ? Theme.bg.r : Theme.bgAlt.r, root.tui ? Theme.bg.g : Theme.bgAlt.g, root.tui ? Theme.bg.b : Theme.bgAlt.b, root.tui ? 0.88 : 0.78)
        border.width: 1
        border.color: root.tui ? Theme.tuiBorder : Qt.rgba(Theme.overlay2.r, Theme.overlay2.g, Theme.overlay2.b, 0.8)
    }

    // TUI: "─ clock ─" in the top border
    Rectangle {
        visible: root.tui
        x: 12
        y: -1
        width: label.implicitWidth + 8
        height: 2
        color: Theme.bg
    }
    Text {
        id: label
        visible: root.tui
        x: 16
        y: -implicitHeight / 2
        text: root.title
        color: Theme.subtext
        font.family: Theme.fontTui
        font.pixelSize: Theme.tuiTextSize
    }

    SystemClock {
        id: clock
        enabled: root.kind === "clock"
        precision: SystemClock.Minutes
    }

    // Clock: the time large, the day under it
    Column {
        visible: root.kind === "clock"
        anchors.centerIn: parent
        spacing: root.tui ? 2 : 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.date, "hh:mm")
            color: Theme.textBright
            font.family: Theme.fontUi
            font.pixelSize: root.tui ? 60 : 76
            font.weight: Font.ExtraBold
            font.features: { "tnum": 1 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.tui ? Qt.formatDate(clock.date, "ddd yyyy-MM-dd").toLowerCase() : Qt.formatDate(clock.date, "dddd, d MMMM")
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: root.tui ? Theme.tuiTextSize : 16
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }
    }

    // Weather: its icon and the temperature, what it's doing, where
    Item {
        visible: root.kind === "weather"
        anchors.fill: parent
        anchors.margins: 18

        Text {
            visible: !Weather.available
            anchors.centerIn: parent
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: !Weather.enabled ? (root.tui ? "weather off" : "Weather is off in Integrations") : (root.tui ? "waiting for weather" : "Waiting for the weather")
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: root.tui ? Theme.tuiTextSize : 13
            font.weight: Font.DemiBold
        }

        Column {
            visible: Weather.available
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: 6

            Row {
                spacing: 10
                Icon {
                    visible: !root.tui
                    anchors.verticalCenter: parent.verticalCenter
                    size: 36
                    paths: Weather.now ? WeatherLook.iconOf(Weather.now.code, Weather.now.day) : []
                    color: Weather.now ? WeatherLook.colourOf(Weather.now.code, Weather.now.day) : Theme.subtext
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Weather.now ? `${Math.round(Weather.now.temp)}°` : ""
                    color: Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: root.tui ? 40 : 46
                    font.weight: Font.ExtraBold
                    font.features: { "tnum": 1 }
                }
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: Weather.now ? (root.tui ? Weather.describe(Weather.now.code).text.toLowerCase() : Weather.describe(Weather.now.code).text) : ""
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: root.tui ? Theme.tuiTextSize : 14
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                // showoff mode hides where you are, as the TUI weather does
                text: Showoff.active ? (root.tui ? "local weather" : "Local weather") : (Weather.place?.name ?? Weather.city)
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: root.tui ? Theme.tuiTextSize : 12
                font.weight: Font.DemiBold
            }
        }
    }

    // CPU/RAM: two meters
    Column {
        visible: root.kind === "stats"
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 18
        spacing: 16

        Meter {
            name: "CPU"
            fill: Math.max(0, SystemStats.cpu)
            value: SystemStats.cpu < 0 ? "–" : `${Math.round(SystemStats.cpu * 100)} %`
        }
        Meter {
            name: "RAM"
            fill: SystemStats.memTotal > 0 ? SystemStats.memUsed / SystemStats.memTotal : 0
            value: SystemStats.memTotal > 0 ? `${SystemStats.memUsed.toFixed(1)} / ${Math.round(SystemStats.memTotal)} GiB` : "–"
        }
    }

    // Now playing: the cover, title and artist, how far it has played
    Item {
        id: nowPlaying
        readonly property var player: Media.player
        readonly property bool hasLength: (player?.lengthSupported ?? false) && player.length > 0
        visible: root.kind === "media"
        anchors.fill: parent
        anchors.margins: 18

        // MPRIS doesn't say when the position moves: read it again each second while playing and shown
        Timer {
            running: root.kind === "media" && root.live && nowPlaying.hasLength && (nowPlaying.player?.isPlaying ?? false)
            interval: 1000
            repeat: true
            onTriggered: nowPlaying.player.positionChanged()
        }

        Text {
            visible: !nowPlaying.player?.trackTitle
            anchors.centerIn: parent
            text: root.tui ? "nothing playing" : "Nothing playing"
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: root.tui ? Theme.tuiTextSize : 13
            font.weight: Font.DemiBold
        }

        Row {
            visible: !!nowPlaying.player?.trackTitle
            anchors.fill: parent
            spacing: 14

            ClippingRectangle {
                width: parent.height
                height: parent.height
                radius: root.tui ? 0 : 14
                color: Theme.overlay
                Icon {
                    anchors.centerIn: parent
                    size: 28
                    paths: Icons.music
                    color: Theme.subtext
                    visible: cover.status !== Image.Ready
                }
                Image {
                    id: cover
                    anchors.fill: parent
                    source: nowPlaying.player?.trackArtUrl ?? ""
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(192, 192)
                }
            }
            Column {
                width: parent.width - parent.height - 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: nowPlaying.player?.trackTitle ?? ""
                    color: Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: root.tui ? Theme.tuiTextSize : 15
                    font.weight: Font.ExtraBold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: (nowPlaying.player?.trackArtist ?? "") + ((nowPlaying.player?.isPlaying ?? false) ? "" : (root.tui ? "  · paused" : " · Paused"))
                    color: Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: root.tui ? Theme.tuiTextSize : 12
                    font.weight: Font.DemiBold
                }
                Item { width: 1; height: 6 }
                Rectangle {
                    visible: nowPlaying.hasLength
                    width: parent.width
                    height: root.tui ? 6 : 4
                    radius: root.tui ? 0 : 2
                    color: Theme.overlay
                    Rectangle {
                        width: parent.width * (nowPlaying.hasLength ? Math.min(1, nowPlaying.player.position / nowPlaying.player.length) : 0)
                        height: parent.height
                        radius: parent.radius
                        color: Theme.pistachio
                    }
                }
            }
        }
    }

    // Timers: Focus/Pomodoro, running timers and the stopwatch, up to three
    Column {
        id: timerList
        readonly property var entries: {
            const out = [];
            if (FocusMode.session)
                out.push({ name: FocusMode.phaseName(), value: FocusMode.clock(FocusMode.left()), paused: FocusMode.paused });
            for (const t of Clocks.timers)
                out.push({ name: t.label || "Timer", value: Clocks.clock(Clocks.left(t)), paused: !t.endsAt });
            if (Clocks.stopwatch)
                out.push({ name: "Stopwatch", value: Clocks.clock(Clocks.elapsed()), paused: !Clocks.stopwatch.since });
            return out.slice(0, 3);
        }
        visible: root.kind === "timers"
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 18
        spacing: 12

        Text {
            visible: timerList.entries.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.tui ? "no timers running" : "No timers running"
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: root.tui ? Theme.tuiTextSize : 13
            font.weight: Font.DemiBold
        }
        Repeater {
            model: timerList.entries
            Column {
                required property var modelData
                width: parent.width
                spacing: 0
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: (root.tui ? modelData.name.toLowerCase() : modelData.name) + (modelData.paused ? (root.tui ? " · paused" : " · Paused") : "")
                    color: Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: root.tui ? Theme.tuiTextSize : 12
                    font.weight: Font.Bold
                }
                Text {
                    text: modelData.value
                    color: modelData.paused ? Theme.subtext : Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: root.tui ? 22 : 24
                    font.weight: Font.ExtraBold
                    font.features: { "tnum": 1 }
                }
            }
        }
    }

    // Disk & GPU: free space on / (and /home), the GPU's load and temperature
    Column {
        visible: root.kind === "system"
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 18
        spacing: 14

        Repeater {
            model: SystemStats.disks.slice(0, 2)
            Meter {
                required property var modelData
                name: modelData.mount === "/" ? (SystemStats.disks.length === 1 ? "Disk" : "System") : "Home"
                fill: modelData.size > 0 ? 1 - modelData.free / modelData.size : 0
                value: `${Math.round(modelData.free)} GiB free`
                warn: modelData.low
            }
        }
        Meter {
            visible: SystemStats.gpuFound
            name: "GPU"
            fill: SystemStats.gpu
            value: `${Math.round(SystemStats.gpu * 100)} % · ${Math.round(SystemStats.gpuTemp)}°`
        }
    }

    component Meter: Column {
        id: meter
        required property string name
        required property real fill
        required property string value
        property bool warn: fill >= 0.9
        width: parent.width
        spacing: 6

        Item {
            width: parent.width
            height: nameText.implicitHeight
            Text {
                id: nameText
                text: root.tui ? meter.name.toLowerCase() : meter.name
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: root.tui ? Theme.tuiTextSize : 12
                font.weight: Font.Bold
            }
            Text {
                anchors.right: parent.right
                text: meter.value
                color: Theme.textBright
                font.family: Theme.fontUi
                font.pixelSize: root.tui ? Theme.tuiTextSize : 13
                font.weight: Font.ExtraBold
                font.features: { "tnum": 1 }
            }
        }
        Rectangle {
            width: parent.width
            height: root.tui ? 8 : 6
            radius: root.tui ? 0 : 3
            color: Theme.overlay
            Rectangle {
                width: parent.width * Math.min(1, Math.max(0, meter.fill))
                height: parent.height
                radius: parent.radius
                color: meter.warn ? Theme.terracotta : Theme.pistachio
                Behavior on width { NumberAnimation { duration: Theme.motionDuration; easing.type: Theme.easing } }
            }
        }
    }
}
