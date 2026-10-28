pragma Singleton

import Quickshell
import Quickshell.Bluetooth as Bz // namespaced: this file is itself called Bluetooth
import Quickshell.Io
import QtQuick

// The default adapter: power, devices, scanning and device actions, the pairing agent, and low battery
// warnings.
Singleton {
    id: root

    // false until BlueZ reports an adapter
    readonly property bool enabled: Bz.Bluetooth.defaultAdapter?.enabled ?? false
    // powered on and done switching, so it can scan: `enabled` turns true as soon as the shell asks
    readonly property bool ready: Bz.Bluetooth.defaultAdapter?.state === Bz.BluetoothAdapterState.Enabled
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
    // Low battery warnings (owner's request, after phase 8), from the shell's own notify-send: once at
    // 20 %, and urgent at 10 % (it stays, and shows in Do not disturb), per device; they start over once
    // it's back above 25 %.
    readonly property var levels: paired.filter(d => d.connected && d.batteryAvailable).map(d => ({ address: d.address, name: name(d), level: Math.round(d.battery * 100) }))
    property var warned: ({}) // address -> the level last warned about, 20 or 10
    onLevelsChanged: checkBatteries(levels)
    // for the quick settings tile and the launcher: "Off", "AirPods Pro · 74%", the connected device, "On"
    readonly property string summary: !enabled ? "Off"
        : batteryDevice ? `${name(batteryDevice)} · ${battery}%`
        : connectedName || "On"

    function checkBatteries(list) {
        const w = Object.assign({}, warned);
        for (const d of list) {
            const was = w[d.address] ?? 100;
            if (d.level > 25)
                delete w[d.address];
            else if (d.level <= 10 && was > 10)
                warnBattery(d, w[d.address] = 10);
            else if (d.level <= 20 && was > 20)
                warnBattery(d, w[d.address] = 20);
        }
        warned = w;
    }

    function warnBattery(d, at: int) {
        Quickshell.execDetached(["notify-send", "--app-name=Bluetooth", "--icon=battery-low", `--urgency=${at === 10 ? "critical" : "normal"}`, `${d.name}: battery low`, `${d.level} % left`]);
    }

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

    // codes and questions on the way come in as `request`
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

    // ---- pairing agent -------------------------------------------------------------------------
    // Quickshell has none, so services/bluetooth-agent.py registers one with BlueZ and passes its
    // questions here. BlueZ asks one at a time; the launcher shows it (and opens for it).

    readonly property bool agent: agentReady && agentProcess.running // registered as BlueZ's default agent
    property bool agentReady
    // the question waiting for an answer, or null: { id, kind, path, code, entered, uuid }; kinds
    // as in bluetooth-agent.py. Display kinds (a code to type on the device) need no answer: id 0.
    property var request: null
    readonly property var requestDevice: request ? devices.find(d => d.dbusPath === request.path) ?? null : null
    // the device's name, or its address while Quickshell hasn't listed it yet
    readonly property string requestName: requestDevice ? name(requestDevice) : request ? request.path.split("dev_")[1]?.replace(/_/g, ":") ?? "" : ""
    // a new question (not just a code display catching up with the keys typed)
    signal asked

    // Answers `request`. For a code on display, declining cancels the pairing. Accepting a pairing
    // also trusts the device, as pair() does, so it can reconnect without asking.
    function answer(accept: bool, value: string) {
        const r = request, device = requestDevice;
        if (!r)
            return;
        request = null;
        if (r.id)
            reply(r.id, accept, value);
        else if (!accept)
            device?.cancelPair();
        if (accept && r.kind !== "service" && device)
            device.trusted = true;
    }

    function reply(id: int, accept: bool, value: string) {
        agentProcess.write(JSON.stringify({ id: id, accept: accept, value: value }) + "\n");
    }

    function heard(line: string) {
        let m;
        try {
            m = JSON.parse(line);
        } catch (e) {
            console.warn("bluetooth agent:", line);
            return;
        }
        if (m.event === "ready") {
            agentReady = true;
        } else if (m.event === "lost") {
            agentReady = false;
            request = null;
        } else if (m.event === "cancel") {
            request = null;
        } else if (m.event === "request") {
            ask(m);
        }
    }

    function ask(m) {
        if (Session.locked) { // nobody can answer behind the lock screen
            if (m.id)
                reply(m.id, false, "");
            return;
        }
        if (request?.id && request.id !== m.id)
            reply(request.id, false, ""); // BlueZ moved on without saying so
        const update = request && !m.id && request.kind === m.kind && request.path === m.device;
        request = { id: m.id, kind: m.kind, path: m.device, code: m.code ?? "", entered: m.entered ?? -1, uuid: m.uuid ?? "" };
        if (!update)
            asked();
    }

    // "audio", "input", …, from the 16-bit part of a standard service UUID ("0000110d-…")
    function serviceName(uuid: string): string {
        const known = { "1101": "a serial port", "1105": "file sharing", "1106": "file transfer", "1108": "headset audio", "110a": "audio", "110b": "audio", "110c": "media controls", "110d": "audio", "110e": "media controls", "1112": "headset audio", "1115": "networking", "1116": "networking", "111e": "hands-free calls", "111f": "hands-free calls", "1124": "input", "112f": "your contacts", "1132": "messages", "1812": "input" };
        return known[uuid.slice(4, 8).toLowerCase()] ?? "a service";
    }

    // a code on display is done once the device has paired (if it fails, BlueZ sends Cancel)
    readonly property bool codeTyped: (request?.kind.startsWith("display") ?? false) && (requestDevice?.paired ?? false)
    onCodeTypedChanged: if (codeTyped) request = null

    Connections {
        target: Session
        function onLockedChanged() {
            if (Session.locked)
                root.answer(false, "");
        }
    }

    Process {
        id: agentProcess
        running: !!Bz.Bluetooth.defaultAdapter
        command: ["python3", "-I", Quickshell.shellPath("services/bluetooth-agent.py")]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => root.heard(data)
        }
        stderr: SplitParser {
            onRead: data => console.warn("bluetooth agent:", data)
        }
        onExited: code => {
            if (code !== 0 && !root.agentReady)
                console.warn("bluetooth agent exited with code", code, "before registering (is python-gobject installed?)");
            root.agentReady = false;
            root.request = null;
        }
    }
}
