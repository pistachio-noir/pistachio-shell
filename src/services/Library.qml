pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Other apps' things for the launcher (owner's picks, 8 November 2026): CLion's recent projects and
// the installed games (Steam's, and Sober while its app is installed), read by services/library.py
// each time the launcher opens.
Singleton {
    id: root

    property var projects: [] // CLion: { name, path, opened }
    property var steamGames: [] // { appid, name, cover }
    readonly property var sober: Apps.list.find(a => a.id === "org.vinegarhq.Sober") ?? null
    readonly property var clion: Apps.list.find(a => a.id === "jetbrains-clion") ?? null
    // every game: { key, name, cover (an image path or ""), icon (an app icon name, for Sober) }
    readonly property var games: steamGames.map(g => ({ key: "steam:" + g.appid, name: g.name, cover: g.cover, appid: g.appid }))
        .concat(sober ? [{ key: "sober", name: "Sober (Roblox)", cover: "", icon: sober.icon }] : [])

    function load() {
        reader.running = true;
    }

    function openProject(p) {
        Quickshell.execDetached(["clion", p.path]);
    }

    function play(game) {
        if (game.appid)
            Quickshell.execDetached(["steam", `steam://rungameid/${game.appid}`]);
        else if (game.key === "sober" && sober)
            sober.execute();
    }

    Process {
        id: reader
        command: ["python3", "-I", Quickshell.shellPath("services/library.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.projects = d.clion ?? [];
                    root.steamGames = d.steam ?? [];
                } catch (e) {
                    console.warn("library:", text);
                }
            }
        }
    }
}
