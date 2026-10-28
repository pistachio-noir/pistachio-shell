pragma Singleton

import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// Apps sharing the screen through the desktop portal (owner's request, after phase 8: a privacy cue,
// like the mic's). xdg-desktop-portal-hyprland makes a video source node for each screencast while it
// runs, named after itself (checked with a real Vesktop share; "xdph-streaming-…", a string in its
// binary, wasn't it); the streams linked to it are the apps sharing, named from their desktop entry.
// A webcam is a video source too, but not the portal's, so it doesn't count; nor do the shell's own
// captures (lock screen, power menu), which don't go through PipeWire.
Singleton {
    id: root

    readonly property var casts: Pipewire.nodes.values.filter(n => !n.audio && (n.name === "xdg-desktop-portal-hyprland" || n.name.startsWith("xdph-streaming-")))
    // the nodes reading from them, once linked
    readonly property var readers: Pipewire.linkGroups.values.filter(g => casts.includes(g.source)).map(g => g.target)
    // shared while something reads it: a cast can outlive its app for a moment as the portal closes it
    readonly property bool sharing: readers.length > 0
    readonly property var apps: {
        const names = readers.map(n => Apps.nameFor(Audio.appName(n))); // "vesktop" -> "Vesktop"
        return names.filter((a, i) => names.indexOf(a) === i);
    }

    // properties read as invalid on unbound nodes
    PwObjectTracker {
        objects: root.readers
    }
}
