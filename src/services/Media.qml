pragma Singleton

import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// The media player to show (MPRIS): the one playing, else the one that played last, else the
// first that has a track. Like other Quickshell modules it fills in a moment after first use.
Singleton {
    id: root

    property var last: null // the player that played most recently
    readonly property var players: Mpris.players.values
    readonly property var player: players.find(p => p.isPlaying) ?? (players.includes(last) ? last : players.find(p => p.trackTitle)) ?? null

    onPlayerChanged: if (player?.isPlaying) last = player

    // Headphones gone (owner's request, after phase 8): when the default output was a Bluetooth device
    // and that device goes (disconnected, or flat), whatever is playing pauses instead of carrying on
    // out of the speakers. Switching outputs by hand while it's still there doesn't pause, and nothing
    // plays again when it comes back. Its node goes before the default moves, else a moment later.
    readonly property var sink: Audio.sink
    property int bluetoothSink: -1 // the default output's node id while it's a Bluetooth one
    property int leftBluetooth: -1

    onSinkChanged: {
        if (!sink)
            return; // briefly null while the default changes
        const before = bluetoothSink;
        bluetoothSink = isBluetooth(sink) ? sink.id : -1;
        if (before >= 0 && sink.id !== before) {
            leftBluetooth = before;
            if (!Audio.sinks.some(n => n.id === before))
                pauseAll();
            else
                stillThere.restart();
        }
    }

    function isBluetooth(node): bool {
        return node.name.startsWith("bluez_output") || node.properties?.["device.api"] === "bluez5";
    }

    function pauseAll() {
        stillThere.stop();
        for (const p of players) {
            if (p.isPlaying && p.canPause)
                p.pause();
        }
    }

    Timer {
        id: stillThere
        interval: 400
        onTriggered: if (!Audio.sinks.some(n => n.id === root.leftBluetooth)) root.pauseAll()
    }

    function togglePlaying() {
        if (player?.canTogglePlaying)
            player.togglePlaying();
    }

    function next() {
        if (player?.canGoNext)
            player.next();
    }

    function previous() {
        if (player?.canGoPrevious)
            player.previous();
    }
}
