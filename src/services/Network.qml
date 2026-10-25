pragma Singleton

import Quickshell
import Quickshell.Networking
import QtQuick

// Wired only: this is a desktop with Ethernet and no Wi-Fi.
Singleton {
    // the connected wired device, else the first one
    readonly property var device: Networking.devices.values.filter(d => d.type === DeviceType.Wired).sort((a, b) => b.connected - a.connected)[0] ?? null
    readonly property bool connected: device?.connected ?? false
    readonly property bool hasLink: device?.hasLink ?? false // cable plugged in
    readonly property int speed: device?.linkSpeed ?? 0 // Mb/s

    function setEnabled(on: bool) {
        // the network object only exists while a cable is plugged in
        if (on)
            device?.network?.connect();
        else
            device?.network?.disconnect();
    }
}
