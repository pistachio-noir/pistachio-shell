pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Theming integration (owner's call, 19 November 2026; spec docs/superpowers/specs/2026-11-19-theming-
// integration-design.md): one switch, on by default, under which the shell sets Kitty and Neovim up
// itself to follow Colours. An app with its own theme is asked about first (`conflict`, shown by
// Settings' dialog), and the answer is kept per app; switching off removes only the shell's own lines.
// `psc theme` (rust/psc/src/theme.rs) does the work and answers {"apps": [{id, name, state, detail}]}.
Singleton {
    id: root

    readonly property bool enabled: Store.saved.themingIntegration !== false
    readonly property var kept: Array.from(Store.saved.themingKeep ?? [])
    property var apps: []
    readonly property var conflict: enabled ? (apps.find(a => a.state === "own" && !kept.includes(a.id)) ?? null) : null

    property var queue: []
    property var tried: [] // apps set up quietly this session, so a failing setup isn't retried in a loop
    property bool started

    function run(args: var) {
        queue = queue.concat([args]);
        Qt.callLater(next);
    }
    function next() {
        if (helper.running || queue.length === 0)
            return;
        const args = queue[0];
        queue = queue.slice(1);
        helper.exec({ command: [Quickshell.env("HOME") + "/.local/bin/psc", "theme"].concat(args) });
    }
    function refresh() { run(["status"]); }

    function setEnabled(on: bool) { Store.saved.themingIntegration = on; }
    // however the switch changes (Settings, a page reset, an import): off drops queued setups and undoes
    // what a fresh status says is wired; on reads status again and sets up what it can
    onEnabledChanged: {
        if (!started)
            return;
        tried = [];
        if (!enabled)
            queue = queue.filter(args => args[0] !== "setup" && args[0] !== "use");
        refresh();
    }
    function undoWired() {
        for (const a of apps)
            if (a.state === "following" && !queue.some(q => q[0] === "undo" && q[1] === a.id))
                run(["undo", a.id]);
    }
    function keep(id: string) {
        if (!kept.includes(id))
            Store.saved.themingKeep = kept.concat([id]);
    }
    function use(id: string) {
        Store.saved.themingKeep = kept.filter(k => k !== id);
        run(["use", id]);
    }

    // the quiet part: apps with no theme of their own are wired up as soon as they're seen
    function setUpAvailable() {
        if (!enabled)
            return;
        for (const a of apps) {
            if (a.state === "available" && !tried.includes(a.id)) {
                tried = tried.concat([a.id]);
                run(["setup", a.id]);
            }
        }
    }

    function start() {
        if (started || !Store.ready)
            return;
        started = true;
        refresh();
    }
    Connections {
        target: Store
        function onReadyChanged() { root.start(); }
    }
    Component.onCompleted: start()

    Process {
        id: helper
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (data.apps) {
                        root.apps = data.apps;
                        if (root.enabled)
                            root.setUpAvailable();
                        else
                            root.undoWired();
                    } else if (data.error) {
                        console.warn("theming:", data.error);
                    }
                } catch (e) {
                    console.warn("theming:", text);
                }
            }
        }
        onExited: Qt.callLater(root.next)
    }
}
