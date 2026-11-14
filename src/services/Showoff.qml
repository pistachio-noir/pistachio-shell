pragma Singleton

import qs
import Quickshell
import Quickshell.Io
import QtQuick

// Showoff mode (owner's request, after phase 8; layout A from the brainstorm): everything open at once
// for a screenshot of the shell, private things hidden, and fastfetch in a terminal. It moves to an
// empty workspace and comes back after. The bar opens the panels, spread out, and asks for the
// terminal (openTerminal), which opens floating in the room between them: the owner's own terminal, with
// a fastfetch config of the shell's, written from Theme's colours. UI files read `active` to hide what's
// private. It ends with toggle() (the launcher's Shell settings, IPC `showoff toggle`), a click on the
// wallpaper, closing the terminal, or going to another workspace.
Singleton {
    id: root

    property bool active
    property int stage // the workspace it shows on
    property int back // the one to come back to, 0 if it didn't move
    property bool arrived // the stage is the active workspace by now
    property var before: [] // window addresses from before, so the terminal can be told apart
    property string terminal // the fastfetch window's address, once it's there
    readonly property string config: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/pistachio-showoff.jsonc`
    readonly property var windows: Compositor.windows
    readonly property int current: Compositor.workspaces.find(w => w.active)?.id ?? 0

    function toggle() {
        if (active)
            stop();
        else
            start();
    }

    function start() {
        const busy = id => Compositor.windows.some(w => w.workspace === id);
        const here = current || 1;
        stage = busy(here) ? [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].find(id => !busy(id)) ?? here : here;
        back = stage !== here ? here : 0;
        arrived = stage === here;
        before = Compositor.windows.map(w => w.address);
        terminal = "";
        if (back)
            Compositor.goto(stage);
        active = true;
    }

    function stop() {
        if (!active)
            return;
        active = false;
        if (terminal && Compositor.windows.some(w => w.address === terminal))
            Compositor.close(terminal);
        terminal = "";
        if (back && current === stage)
            Compositor.goto(back); // not if the owner went somewhere else themselves
        back = 0;
    }

    // fastfetch in the terminal, floating at `box` (screen px) on the stage; the config is written first
    function openTerminal(box: rect) {
        writer.box = box;
        writer.command = ["sh", "-c", 'printf "%s" "$2" > "$1"', "sh", config, fetchConfig()];
        writer.running = true;
    }

    // what fastfetch shows: a pistachio, the shell's name, then the system without anything that
    // names the machine or the owner (no user@host, model, BIOS, disks or addresses)
    function fetchConfig(): string {
        const icon = code => String.fromCodePoint(code); // from the owner's own fastfetch config
        const color = c => c.toString();
        // a pistachio: the green nut in its open shell
        const logo = [
            "$2      ▄▄████▄▄",
            "$2    ▄██████████▄",
            "$1  ▄▀▀$2██████████$1▀▀▄",
            "$1 █   $2▀▀▀▀▀▀▀▀▀▀$1   █",
            "$1 █                █",
            "$1  ▀▄            ▄▀",
            "$1    ▀▀▄▄▄▄▄▄▄▄▀▀"
        ].join("\n");
        const row = (type, code, key, extra) => Object.assign({ type: type, key: `${icon(code)}  ${key}` }, extra ?? {});
        return JSON.stringify({
            logo: { type: "data", source: logo, color: { "1": color(Theme.gold), "2": color(Theme.pistachio) }, padding: { top: 2, left: 2, right: 4 } },
            display: { separator: "  ", color: { keys: color(Theme.pistachio), title: color(Theme.textBright) }, key: { width: 13 } },
            modules: [
                { type: "custom", format: "pistachio noir", outputColor: color(Theme.pistachio) },
                { type: "custom", format: "a shell for hyprland", outputColor: color(Theme.subtext) },
                "break",
                row("os", 0xF303, "os"),
                row("kernel", 0xF033D, "kernel"),
                row("wm", 0xF10AC, "wm"),
                row("custom", 0xF0266, "shell", { format: "pistachio (quickshell)" }),
                row("terminal", 0xF018D, "terminal"),
                row("packages", 0xF03D7, "packages"),
                row("uptime", 0xF0150, "uptime"),
                "break",
                row("cpu", 0xF0EE0, "cpu", { format: "{name}" }), // no clock speed or GPU type: the lines fit
                row("gpu", 0xF0379, "gpu", { format: "{name}" }),
                row("memory", 0xF046D, "memory"),
                "break",
                { type: "colors", symbol: "circle", paddingLeft: 0 }
            ]
        });
    }

    // the terminal: noticed as it opens, and its closing ends showoff
    onWindowsChanged: {
        if (!active)
            return;
        if (!terminal) {
            terminal = windows.find(w => w.appId === Apps.terminalAppId && w.workspace === stage && !before.includes(w.address))?.address ?? "";
        } else if (!windows.some(w => w.address === terminal)) {
            terminal = "";
            stop();
        }
    }

    // going to another workspace ends it, once it has got there
    onCurrentChanged: {
        if (!active)
            return;
        if (current === stage)
            arrived = true;
        else if (arrived)
            stop();
    }

    Process {
        id: writer

        property rect box

        onExited: code => {
            if (code !== 0 || !root.active)
                return;
            // fastfetch, then the terminal just stays, cursor hidden: holding it with the terminal's own
            // "wait after command" left Ghostty's "Command Succeeded" bar and a cursor in the picture
            // (owner's report, 14 November 2026); closing the window still ends showoff
            const command = Apps.inTerminal(["sh", "-c", 'fastfetch --config "$1"; printf "\\033[?25l"; exec sleep infinity', "sh", root.config], false, "fastfetch");
            Compositor.exec(command.map(a => `'${a.replace(/'/g, "'\\''")}'`).join(" "), Object.assign(Theme.tui ? { rounding: 0 } : {}, {
                float: true,
                size: [Math.round(box.width), Math.round(box.height)],
                move: [Math.round(box.x), Math.round(box.y)],
                workspace: String(root.stage)
            }));
        }
    }
}
