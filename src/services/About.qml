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
        // one line per fact, always: a tool that's missing or fails prints an empty line, so the rest
        // can't shift into the wrong rows (Gentoo, 21 November 2026: no qtpaths6 where Arch has it, and
        // the branch showed as the Qt version). Qt: qtpaths under its Arch or Gentoo name, else qmake6.
        command: ["sh", "-c", `
            one() { out=$("$@" 2>/dev/null | head -n 1); printf '%s\\n' "$out"; }
            qt() {
                for q in qtpaths6 qtpaths /usr/lib/qt6/bin/qtpaths6 /usr/lib64/qt6/bin/qtpaths6 /usr/lib64/qt6/bin/qtpaths; do
                    v=$("$q" --qt-version 2>/dev/null) && [ -n "$v" ] && { echo "$v"; return; }
                done
                qmake6 -query QT_VERSION
            }
            one git -C "$1" log -1 --format='%h|%cs|%s'
            one git -C "$1" rev-list --count HEAD
            one sh -c 'git -C "$1" status --porcelain | wc -l' sh "$1"
            one git -C "$1" remote get-url origin
            one qs --version
            one sh -c 'hyprctl version -j | grep -m1 "\\"version\\""'
            one qt
            one git -C "$1" branch --show-current`, "sh", Quickshell.shellPath("")]
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
