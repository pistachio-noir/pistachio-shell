pragma Singleton

import Quickshell
import QtQuick

// Game mode (owner's call, 18 November 2026; Settings → Experimental, off by default): while a
// fullscreen game is focused, notifications stay quiet (Notifs.quiet) and Hyprland's animations and
// blur are off (Compositor.gameLayout, runtime only). A game is a Steam window (steam_app_<digits>,
// Proton included), Sober, gamescope, or a class the owner added. It turns off 2 s after the game
// leaves the front, so a quick alt-tab doesn't flip everything, and at once when the switch goes off.
Singleton {
    id: root

    readonly property var builtIn: ["org.vinegarhq.sober", "gamescope"]

    function isGame(appId: string): bool {
        const id = (appId ?? "").toLowerCase();
        return !!id && (/^steam_app_\d+$/.test(id) || builtIn.includes(id) || (ShellSettings.gameClasses ?? []).includes(id));
    }

    // The Settings dialog's text: comma-separated classes → { list, error } (error "" when valid)
    function parseClasses(text: string): var {
        const list = [];
        for (const part of (text ?? "").split(",")) {
            const c = part.trim().toLowerCase();
            if (!c) continue;
            if (c.length > 100) return { list: [], error: "A window class can be at most 100 characters." };
            if (!/^[a-z0-9._-]+$/.test(c)) return { list: [], error: `"${c}" isn't a window class: use letters, digits, dots, dashes and underscores.` };
            if (!list.includes(c)) list.push(c);
        }
        if (list.length > 20) return { list: [], error: "Up to 20 window classes." };
        return { list: list, error: "" };
    }

    readonly property bool wanted: ShellSettings.gameMode && !!Compositor.focusedWindow?.fullscreen && isGame(Compositor.focusedWindow?.appId ?? "")
    property bool active: false

    onWantedChanged: {
        if (wanted) {
            offDelay.stop();
            active = true;
        } else if (!ShellSettings.gameMode) {
            offDelay.stop();
            active = false;
        } else if (active) {
            offDelay.restart();
        }
    }
    onActiveChanged: Compositor.gameLayout(active)
    // the switch going off while the off-delay runs (wanted already false) must end it at once too
    Connections {
        target: ShellSettings
        function onGameModeChanged() {
            if (!ShellSettings.gameMode) {
                offDelay.stop();
                root.active = false;
            }
        }
    }

    Timer {
        id: offDelay
        interval: 2000
        onTriggered: if (!root.wanted) root.active = false
    }
}
