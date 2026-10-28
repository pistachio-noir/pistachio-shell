import qs
import qs.components
import qs.services
import QtQuick

// Ethernet, Bluetooth and volume. Off states turn subtext and get a slash. While a device that reports
// its battery is connected (e.g. headphones), its level replaces the Bluetooth icon. A muted
// microphone adds a slashed mic icon, and one an app is recording from a mic in clay (a privacy
// cue, like a phone's); a screen shared through the portal adds a screen icon in clay. Opens quick
// settings.
Chip {
    id: chip

    spacing: 12
    Accessible.name: "Quick settings: Ethernet " + (Network.connected ? "connected" : "unplugged")
        + ", Bluetooth " + (Bluetooth.enabled ? "on" : "off")
        + (Bluetooth.battery >= 0 ? `, ${Bluetooth.name(Bluetooth.batteryDevice)} battery ${Bluetooth.battery}%` : "")
        + (Audio.micMuted ? ", microphone muted" : Audio.recorders.length ? `, microphone in use by ${Audio.recorders.map(n => Audio.appName(n)).join(", ")}` : "")
        + (ScreenShare.sharing ? `, screen shared with ${ScreenShare.apps.join(", ")}` : "")
        + (Audio.muted ? ", muted" : `, volume ${Math.round(Audio.volume * 100)}%`)
    // each thing the chip shows, named, with the output device and the microphone
    tooltip: {
        const lines = [
            ["Ethernet", Network.connected ? (Network.speed >= 1000 ? `${Network.speed / 1000} Gbps` : `${Network.speed} Mbps`) : "unplugged"],
            ["Bluetooth", Bluetooth.summary],
            [Audio.sink ? Audio.deviceName(Audio.sink) : "Sound", Audio.muted ? "muted" : `${Math.round(Audio.volume * 100)}%`]
        ];
        if (Audio.source)
            lines.push(["Microphone", Audio.micMuted ? "muted" : Audio.recorders.length ? `in use by ${Audio.recorders.map(n => Audio.appName(n)).join(", ")}` : `${Math.round(Audio.micVolume * 100)}%`]);
        if (ScreenShare.sharing)
            lines.push(["Screen", `shared with ${ScreenShare.apps.join(", ")}`]);
        return lines;
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        color: Network.connected ? chip.foreground : Theme.subtext
        paths: Network.connected ? Icons.ethernet : Icons.ethernet.concat(Icons.slash)
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        visible: Bluetooth.battery < 0
        color: Bluetooth.enabled ? chip.foreground : Theme.subtext
        paths: Bluetooth.enabled ? Icons.bluetooth : Icons.bluetooth.concat(Icons.slash)
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: Bluetooth.battery >= 0
        text: `${Bluetooth.battery}%`
        color: Bluetooth.battery <= 20 ? Theme.terracotta : chip.foreground
        font.family: Theme.fontUi
        font.pixelSize: 12
        font.weight: Font.ExtraBold
        font.features: { "tnum": 1 }
    }

    Icon {
        readonly property bool silent: Audio.muted || Audio.volume === 0

        anchors.verticalCenter: parent.verticalCenter
        color: silent ? Theme.subtext : chip.foreground
        paths: silent ? Icons.volumeMuted : Icons.volume
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        visible: Audio.micMuted || Audio.recorders.length > 0
        color: Audio.micMuted ? Theme.subtext : Theme.clay
        paths: Audio.micMuted ? Icons.micOff : Icons.mic
    }

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        visible: ScreenShare.sharing
        color: Theme.clay
        paths: Icons.screenShare
    }
}
