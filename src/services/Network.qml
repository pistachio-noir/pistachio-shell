pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick

// Wired only: this is a desktop with Ethernet and no Wi-Fi.
Singleton {
    id: root
    property bool watching
    property var details: ({ipv4: [], ipv6: [], gateways: [], dns: []})
    readonly property string interfaceName: device?.name ?? ""
    onInterfaceNameChanged: { details = {ipv4: [], ipv6: [], gateways: [], dns: []}; if (watching) refresh(); }
    onWatchingChanged: if (watching) refresh()
    function refresh() {
        if (reading.running || !interfaceName) return;
        readingInterface = interfaceName;
        reading.command = ["python3", "-I", Quickshell.shellPath("services/system-tools.py"), "network", interfaceName];
        reading.running = true;
    }
    property string readingInterface
    function copyDetail(key: string) {
        if (["ipv4", "ipv6", "gateways", "dns"].includes(key)) Clipboard.copyText((details[key] || []).join("\n"));
    }
    Timer { running: root.watching; repeat: true; interval: 10000; onTriggered: root.refresh() }
    Process {
        id: reading
        stdout: StdioCollector { onStreamFinished: {
            if (root.readingInterface !== root.interfaceName) return;
            try { root.details = JSON.parse(text); } catch (e) { root.details = {ipv4: [], ipv6: [], gateways: [], dns: []}; }
        } }
    }
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
