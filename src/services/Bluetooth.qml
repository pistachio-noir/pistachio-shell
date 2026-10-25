pragma Singleton

import Quickshell
import Quickshell.Bluetooth as Bz // namespaced: this file is itself called Bluetooth
import QtQuick

// The default adapter: power, devices, scanning and device actions.
Singleton {
    id: root

    // false until BlueZ reports an adapter
    readonly property bool enabled: Bz.Bluetooth.defaultAdapter?.enabled ?? false
    readonly property bool discoverable: Bz.Bluetooth.defaultAdapter?.discoverable ?? false
    readonly property bool scanning: Bz.Bluetooth.defaultAdapter?.discovering ?? false
    // every device the adapter knows: paired ones and ones found while scanning
    readonly property var devices: Bz.Bluetooth.defaultAdapter?.devices.values ?? []
    // paired devices, connected ones first
    readonly property var paired: devices.filter(d => d.paired).sort((a, b) => b.connected - a.connected || a.name.localeCompare(b.name))
    // Unpaired devices that broadcast a name. Nameless ones (mostly anonymous BLE beacons) get their
    // address with dashes as a name, e.g. "54-41-93-57-D7-CB", so those are left out.
    readonly property var nearby: devices.filter(d => !d.paired && d.name.replace(/-/g, ":").toUpperCase() !== d.address.toUpperCase())
    // first connected device, or "" if none
    readonly property string connectedName: paired.find(d => d.connected)?.name ?? ""
    // the first connected device that reports its battery (e.g. headphones), or null; its level 0–100
    readonly property var batteryDevice: paired.find(d => d.connected && d.batteryAvailable) ?? null
    readonly property int battery: batteryDevice ? Math.round(batteryDevice.battery * 100) : -1
    // for the quick settings tile and the launcher: "Off", "AirPods Pro · 74%", the connected device, "On"
    readonly property string summary: !enabled ? "Off"
        : batteryDevice ? `${name(batteryDevice)} · ${battery}%`
        : connectedName || "On"

    function setEnabled(on: bool) {
        if (Bz.Bluetooth.defaultAdapter)
            Bz.Bluetooth.defaultAdapter.enabled = on;
    }

    // Scan only while something shows the results, and never longer than a minute.
    function setScanning(on: bool) {
        if (Bz.Bluetooth.defaultAdapter && Bz.Bluetooth.defaultAdapter.discovering !== on)
            Bz.Bluetooth.defaultAdapter.discovering = on;
        if (on)
            scanLimit.restart();
        else
            scanLimit.stop();
    }

    function toggleConnection(device) {
        if (device.connected)
            device.disconnect();
        else
            device.connect();
    }

    // shortcut: there is no pairing agent, so devices that show a PIN or passkey will not pair;
    // add one (or fall back to bluetoothctl) if a keyboard needs it
    function pair(device) {
        device.trusted = true; // so it can reconnect on its own later
        device.pair();
    }

    function forget(device) {
        device.forget();
    }

    function name(device): string {
        return device.name || device.address;
    }

    // "Connected · battery 74%", "Connecting…", "Not connected", "Nearby · not paired", …
    function status(device): string {
        if (device.pairing)
            return "Pairing…";
        if (device.state === Bz.BluetoothDeviceState.Connecting)
            return "Connecting…";
        if (device.state === Bz.BluetoothDeviceState.Disconnecting)
            return "Disconnecting…";
        if (device.connected)
            return "Connected" + (device.batteryAvailable ? ` · battery ${Math.round(device.battery * 100)}%` : "");
        return device.paired ? "Not connected" : "Nearby · not paired";
    }

    Timer {
        id: scanLimit
        interval: 60000
        onTriggered: root.setScanning(false)
    }
}
