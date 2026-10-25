import qs
import qs.components
import qs.services
import QtQuick

// Ethernet, Bluetooth and volume. Off states turn subtext and get a slash. While a device that reports
// its battery is connected (e.g. headphones), its level replaces the Bluetooth icon; a muted microphone
// adds a mic icon. Opens quick settings.
Chip {
    id: chip

    spacing: 12
    Accessible.name: "Quick settings: Ethernet " + (Network.connected ? "connected" : "unplugged")
        + ", Bluetooth " + (Bluetooth.enabled ? "on" : "off")
        + (Bluetooth.battery >= 0 ? `, ${Bluetooth.name(Bluetooth.batteryDevice)} battery ${Bluetooth.battery}%` : "")
        + (Audio.micMuted ? ", microphone muted" : "")
        + (Audio.muted ? ", muted" : `, volume ${Math.round(Audio.volume * 100)}%`)

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
        visible: Audio.micMuted
        color: Theme.subtext
        paths: Icons.micOff
    }
}
