pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

// Default output and input, the output and input devices (and which inputs have nothing plugged in),
// the apps playing sound (per-app volume) and the apps recording.
Singleton {
    id: root

    // defaultAudioSink is briefly null when the default device changes
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    // default input; the status chip shows when it's muted (the mic key runs wpctl)
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool micMuted: source?.audio?.muted ?? false
    readonly property real micVolume: source?.audio?.volume ?? 0
    // hardware inputs (microphones); programs recording are streams
    readonly property var sources: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio)
    // Inputs with nothing plugged in: every jack reads "not available", and WirePlumber won't make
    // such an input the default (checked: it kept the old one). Quickshell doesn't see jacks, so pactl
    // lists them, and again after card or source events, which plugging in a jack sends.
    property var unplugged: [] // node names
    // Apps recording: capture streams read as not sinks, the opposite of playback streams (checked
    // with pw-record). Captures of an output (visualisers, peak meters) don't use the mic.
    readonly property var captures: Pipewire.nodes.values.filter(n => n.isStream && !n.isSink && n.audio)
    readonly property var recorders: captures.filter(n => n.properties?.["stream.capture.sink"] !== "true")
    // hardware outputs; programs are streams
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    // apps playing sound right now: Quickshell flags playback streams (media.class Stream/Output/Audio)
    // as sinks, despite what its docs suggest (checked with pw-cat after phase 8)
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream && n.isSink && n.audio)

    function deviceName(node): string {
        return node.nickname || node.description || node.name;
    }

    // headphones or a headset, wired or Bluetooth, rather than speakers (needs the node tracked).
    // A Bluetooth output doesn't carry its device's form factor, so BlueZ's icon for it decides.
    function isHeadphones(node): bool {
        const p = node?.properties ?? {};
        const bluez = p["api.bluez5.address"] ? Bluetooth.devices.find(d => d.address === p["api.bluez5.address"]) : null;
        return ["headphone", "headset"].includes(p["device.form-factor"]) || /headphone|headset/.test(bluez?.icon ?? p["device.icon-name"] ?? "");
    }

    function isUnplugged(node): bool {
        return unplugged.includes(node?.name);
    }

    function appName(node): string {
        return node.properties?.["application.name"] || node.description || node.name;
    }

    // the app's icon, or "" when the icon theme has none
    function appIcon(node): string {
        const p = node.properties ?? {};
        return Apps.icon(p["application.icon-name"] ?? "") || Apps.iconFor(p["application.process.binary"] ?? "");
    }

    function setStreamVolume(node, v: real) {
        if (!node.audio)
            return;
        node.audio.muted = false;
        node.audio.volume = Math.max(0, Math.min(1, v));
    }

    function toggleStreamMute(node) {
        if (node.audio)
            node.audio.muted = !node.audio.muted;
    }

    // A hint to PipeWire; `sink` shows what it actually picked.
    function setSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }

    // A hint to PipeWire, as setSink; `source` shows what it actually picked.
    function setSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    function toggleMicMute() {
        if (source?.audio)
            source.audio.muted = !source.audio.muted;
    }

    function setMicVolume(v: real) {
        const audio = Pipewire.defaultAudioSource?.audio;
        if (!audio)
            return;
        audio.muted = false; // as with the output: changing the level unmutes
        audio.volume = Math.max(0, Math.min(1, v));
    }

    function toggleMute() {
        if (sink?.audio)
            sink.audio.muted = !sink.audio.muted;
    }

    function setVolume(v: real) {
        const audio = Pipewire.defaultAudioSink?.audio;
        if (!audio)
            return;
        audio.muted = false; // changing the volume unmutes, as on most desktops
        audio.volume = Math.max(0, Math.min(1, v));
    }

    // volume, mute and properties read as invalid on unbound nodes
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource].concat(root.streams, root.captures)
    }

    Process {
        id: jacks
        running: true
        command: ["pactl", "-f", "json", "list", "sources"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.unplugged = JSON.parse(text).filter(s => s.ports.length > 0 && s.ports.every(p => p.availability === "not available")).map(s => s.name);
                } catch (e) {
                    root.unplugged = []; // no pipewire-pulse: nothing is greyed out
                }
            }
        }
    }

    // one listing after a burst of events (a volume drag sends them too)
    Timer {
        id: recheck
        interval: 300
        onTriggered: {
            if (jacks.running)
                restart();
            else
                jacks.running = true;
        }
    }

    Process {
        id: events
        running: true
        // pactl ignores SIGPIPE, so it would outlive a killed shell (checked); setpriv has the kernel
        // stop it when the shell goes
        command: ["setpriv", "--pdeathsig", "TERM", "pactl", "subscribe"]
        stdout: SplitParser {
            onRead: data => {
                if (/ on (card|source) #/.test(data))
                    recheck.restart();
            }
        }
        onExited: rejoin.start() // e.g. pipewire-pulse restarted
    }

    Timer {
        id: rejoin
        interval: 5000
        onTriggered: {
            events.running = true;
            recheck.restart();
        }
    }
}
