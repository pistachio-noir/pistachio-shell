pragma Singleton

import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// Default output, the output devices, and the apps playing sound (per-app volume).
Singleton {
    id: root

    // defaultAudioSink is briefly null when the default device changes
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    // default input; the status chip shows when it's muted (the mic key runs wpctl)
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool micMuted: source?.audio?.muted ?? false
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
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource].concat(root.streams)
    }
}
