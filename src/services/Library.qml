pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Other apps' things for the launcher (owner's picks, 8 November 2026): CLion's recent projects (and VS
// Code's, owner's request, 11 November 2026) and
// the installed games (Steam's, and Sober while its app is installed), read by `psc library`
// each time the launcher opens.
Singleton {
    id: root

    property var projects: [] // CLion: { name, path, opened }
    property var codeProjects: [] // VS Code: { name, path, opened }, while VS Code is installed
    property var steamGames: [] // { appid, name, cover }
    // each null while not installed or switched off in Settings → Integrations
    readonly property var sober: ShellSettings.integration("sober") ? Apps.list.find(a => a.id === "org.vinegarhq.Sober") ?? null : null
    readonly property var clion: ShellSettings.integration("clion") ? Apps.list.find(a => a.id === "jetbrains-clion") ?? null : null
    readonly property var vscode: ShellSettings.integration("vscode") ? Apps.list.find(a => a.id === "com.microsoft.VSCode" || a.id === "code") ?? null : null
    readonly property bool steam: ShellSettings.integration("steam")
    // every game: { key, name, cover (an image path or ""), icon (an app icon name, for Sober) }
    readonly property var games: (steam ? steamGames : []).map(g => ({ key: "steam:" + g.appid, name: g.name, cover: g.cover, appid: g.appid }))
        .concat(sober ? [{ key: "sober", name: "Sober (Roblox)", cover: "", icon: sober.icon }] : [])

    function load() {
        reader.running = true;
    }

    function openProject(p) {
        Quickshell.execDetached([p.ide === "code" ? "code" : "clion", p.path]);
    }

    function play(game) {
        if (game.appid)
            Quickshell.execDetached(["steam", `steam://rungameid/${game.appid}`]);
        else if (game.key === "sober" && sober)
            sober.execute();
    }

    Process {
        id: reader
        command: [Quickshell.env("HOME") + "/.local/bin/psc", "library"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.projects = d.clion ?? [];
                    root.codeProjects = (d.vscode ?? []).map(p => Object.assign(p, { ide: "code" }));
                    root.steamGames = d.steam ?? [];
                } catch (e) {
                    console.warn("library:", text);
                }
            }
        }
    }
}
