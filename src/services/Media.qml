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
