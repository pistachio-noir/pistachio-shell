pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Installed applications (desktop entries), launching them, icons from the system icon theme, and
// commands typed into the launcher after a "$".
Singleton {
    id: root

    // already excludes Hidden and NoDisplay entries
    readonly property var list: DesktopEntries.applications.values
    readonly property var recentCommands: Store.saved.recentCommands ?? [] // newest first

    // The terminal for Terminal=true apps, "$" commands and showoff's fastfetch (owner's request,
    // 30 October 2026): the one picked in Shell settings, else $TERMINAL, else the first one installed.
    // Each runs a command its own way: `exec` goes before it, `hold` keeps the window open after it
    // ends (none: a shell waits for Enter instead), `title` names the window.
    readonly property var terminals: ({
        kitty: { exec: [], hold: ["--hold"], title: t => ["--title", t], appId: "kitty" },
        ghostty: { exec: ["--gtk-single-instance=false", "-e"], hold: ["--wait-after-command=true"], title: t => [`--title=${t}`], appId: "com.mitchellh.ghostty" },
        foot: { exec: [], hold: ["--hold"], title: t => ["--title", t], appId: "foot" },
        alacritty: { exec: ["-e"], hold: ["--hold"], title: t => ["--title", t], appId: "Alacritty" },
        wezterm: { exec: ["start", "--"], hold: null, title: t => [], appId: "org.wezfurlong.wezterm" },
        konsole: { exec: ["-e"], hold: ["--hold"], title: t => [], appId: "org.kde.konsole" }
    })
    property var installed: [] // of the terminals above, in that order
    readonly property string terminal: Store.saved.terminal || (Quickshell.env("TERMINAL") ?? "").split("/").pop() || installed[0] || "kitty"
    readonly property string terminalAppId: terminals[terminal]?.appId ?? terminal

    // the command line that runs `command` (a list) in the terminal
    function inTerminal(command, hold: bool, title: string): var {
        const t = terminals[terminal] ?? { exec: ["-e"], hold: null, title: t => [] };
        const held = hold && !t.hold ? ["sh", "-c", '"$@"; printf "\n[exited %s] Enter closes" "$?"; read _', "sh"].concat(command) : command;
        return [terminal].concat(title ? t.title(title) : [], hold && t.hold ? t.hold : [], t.exec, held);
    }

    // the terminals to choose from in the launcher: the installed ones, and the one in use if it isn't
    // among them ($TERMINAL naming another)
    readonly property var terminalChoices: installed.includes(terminal) ? installed : [terminal].concat(installed)

    function setTerminal(name: string) {
        Store.saved.terminal = name;
    }

    // its app's name ("Ghostty"), else the command
    function terminalName(name: string): string {
        return nameFor(terminals[name]?.appId ?? name) || name;
    }

    function terminalIcon(name: string): string {
        return iconFor(terminals[name]?.appId ?? name);
    }

    // run()'s background commands: the command, then a notification with how it went
    readonly property string background: 'out=$(sh -c "$1" 2>&1); code=$?; last=$(printf "%s\n" "$out" | grep -v "^[[:space:]]*$" | tail -n 1); '
        + 'if [ "$code" -eq 0 ]; then notify-send --app-name=Command --icon=utilities-terminal "Finished: $1" "${last:-No output}"; '
        + 'else notify-send --app-name=Command --icon=utilities-terminal "Failed: $1" "Exit $code${last:+ · $last}"; fi'

    // A command typed in the launcher (owner's request, after phase 8): in the terminal, which stays open to
    // show what it printed, or in the background without a window. It runs exactly as typed, as in a
    // terminal. In the background a notification says when it's done (owner's request): "Finished"
    // or "Failed" with its exit code, and the last line it printed. A detached shell waits for it, so
    // a live reload doesn't stop it.
    function run(command: string, inTerminal: bool) {
        Store.saved.recentCommands = [command].concat(recentCommands.filter(c => c !== command)).slice(0, 20);
        Quickshell.execDetached(inTerminal ? root.inTerminal(["sh", "-c", command], true, "") : ["sh", "-c", root.background, "sh", command]);
    }


    // Claude Desktop, if it's installed (its desktop entry), for the launcher's "claude …" (owner's
    // request, 1 November 2026)
    readonly property var claudeApp: list.find(a => a.id === "com.anthropic.Claude") ?? null

    // A question for Claude: a new chat in Claude Desktop with it, through the app's own claude:// link,
    // which it turns into claude.ai/new?q=… (read in its app.asar, version 3.6556)
    function askClaude(prompt: string) {
        Quickshell.execDetached(["xdg-open", `claude://claude.ai/new?surface=chat&q=${encodeURIComponent(prompt)}`]);
    }

    // A web search after an "@" in the launcher (owner's request, 30 October 2026): DuckDuckGo (owner's
    // call), in the default browser
    function searchWeb(query: string) {
        Quickshell.execDetached(["xdg-open", `https://duckduckgo.com/?q=${encodeURIComponent(query)}`]);
    }

    // How much and how lately an app is launched, for the launcher's order (owner's request): each of
    // its last 10 launches counts 1, halving every week since.
    function frecency(app): real {
        const now = Date.now();
        return (Store.saved.launches[app.id] ?? []).reduce((sum, at) => sum + Math.pow(0.5, (now - at) / 604800000), 0);
    }

    function launch(app) {
        const all = Object.assign({}, Store.saved.launches);
        all[app.id] = (all[app.id] ?? []).concat([Date.now()]).slice(-10);
        Store.saved.launches = all;
        // execute() ignores Terminal=true, so terminal apps get a terminal here
        if (app.runInTerminal)
            Quickshell.execDetached({
                command: inTerminal(app.command, false, ""),
                workingDirectory: app.workingDirectory
            });
        else
            app.execute();
    }

    // One of an app's own actions (its desktop file's, e.g. Helium's New incognito window; owner's
    // request, after phase 8). It counts as launching the app; like execute(), it ignores Terminal=true.
    function launchAction(app, action) {
        const all = Object.assign({}, Store.saved.launches);
        all[app.id] = (all[app.id] ?? []).concat([Date.now()]).slice(-10);
        Store.saved.launches = all;
        if (app.runInTerminal)
            Quickshell.execDetached({
                command: inTerminal(action.command, false, ""),
                workingDirectory: app.workingDirectory
            });
        else
            action.execute();
    }

    // An image source for an icon name, or "" if the theme has no such icon.
    function icon(name: string): string {
        return name ? Quickshell.iconPath(name, true) : "";
    }

    // The icon and name of the app a window belongs to, found from its app id. An empty id finds
    // nothing: the lookup answered "" with whatever app it met first ("Qt V4L2 video capture utility").
    function iconFor(appId: string): string {
        return appId ? icon(DesktopEntries.heuristicLookup(appId)?.icon ?? "") : "";
    }

    function nameFor(appId: string): string {
        return appId ? DesktopEntries.heuristicLookup(appId)?.name ?? appId : "";
    }

    Process {
        running: true
        command: ["sh", "-c", 'for t in "$@"; do command -v "$t" >/dev/null && echo "$t"; done', "sh"].concat(Object.keys(root.terminals))
        stdout: StdioCollector {
            onStreamFinished: root.installed = text.split("\n").filter(t => t)
        }
    }
}
