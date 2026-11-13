pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// What the launcher's About view shows (owner's request, 3 November 2026): the shell's commit from its
// git repo (the config folder is a link into it), and the versions of Quickshell, Hyprland and Qt.
// Read each time the view opens.
Singleton {
    id: root

    property string commit
    property string date // yyyy-mm-dd
    property string subject
    property int commits
    property int changed // files changed since the commit
    property string repo // the GitHub page
    property string branch // the git branch the shell runs from; "" while unknown or detached
    readonly property bool stable: branch === "main" // anything else may be unstable (owner's call)
    // main stable, experimental may be unstable, any other branch is a work in progress (owner's
    // request, 13 November 2026): its own words, glyph and colour in About
    readonly property string kind: stable ? "stable" : branch === "experimental" ? "experimental" : "cooking"
    readonly property string mood: kind === "stable" ? "stable" : kind === "experimental" ? "may be unstable" : "something's cooking…"
    readonly property string moodLong: kind === "stable" ? "Stable: the shell's main line"
        : kind === "experimental" ? "Experimental: may be unstable; main is the stable one"
        : "Something's cooking: a branch of its own, half-baked on purpose"
    property string quickshell
    property string hyprland
    property string qt

    function load() {
        reader.running = true;
    }

    Process {
        id: reader
        command: ["sh", "-c", `
            git -C "$1" log -1 --format='%h|%cs|%s'
            git -C "$1" rev-list --count HEAD
            git -C "$1" status --porcelain | wc -l
            git -C "$1" remote get-url origin
            qs --version | head -1
            hyprctl version -j | grep -m1 '"version"'
            qtpaths6 --qt-version 2>/dev/null || /usr/lib/qt6/bin/qtpaths6 --qt-version
            git -C "$1" branch --show-current`, "sh", Quickshell.shellPath("")]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n");
                const head = (l[0] ?? "").split("|");
                root.commit = head[0] ?? "";
                root.date = head[1] ?? "";
                root.subject = head.slice(2).join("|");
                root.commits = parseInt(l[1]) || 0;
                root.changed = parseInt(l[2]) || 0;
                root.repo = (l[3] ?? "").replace(/\.git$/, "").replace(/^git@github\.com:/, "https://github.com/");
                root.quickshell = ((l[4] ?? "").match(/[0-9][0-9.]*/) ?? [""])[0];
                root.hyprland = ((l[5] ?? "").match(/[0-9][0-9.]*/) ?? [""])[0];
                root.qt = (l[6] ?? "").trim();
                root.branch = (l[7] ?? "").trim();
            }
        }
    }
}
