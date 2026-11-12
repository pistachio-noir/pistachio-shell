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

    // Background commands are tracked in volatile runtime storage and survive live reload.
    // Terminal commands keep the existing terminal/hold behaviour.
    function run(command: string, inTerminal: bool) {
        Store.saved.recentCommands = [command].concat(recentCommands.filter(c => c !== command)).slice(0, 20);
        if (inTerminal) Quickshell.execDetached(root.inTerminal(["sh", "-c", command], true, ""));
        else LauncherTools.run(command);
    }


    // Claude Desktop, if it's installed (its desktop entry), for the launcher's "claude …" (owner's
    // request, 1 November 2026)
    readonly property var claudeApp: ShellSettings.integration("claude") ? list.find(a => a.id === "com.anthropic.Claude") ?? null : null // or off in Settings → Integrations

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
        if (LauncherTools.pending[app.id]) return;
        const all = Object.assign({}, Store.saved.launches);
        all[app.id] = (all[app.id] ?? []).concat([Date.now()]).slice(-10);
        Store.saved.launches = all;
        LauncherTools.launch(app.id, app.runInTerminal ? inTerminal(app.command, false, "") : app.command, app.workingDirectory, app.runInTerminal ? terminalAppId : "");
    }

    // One of an app's own actions (its desktop file's, e.g. Helium's New incognito window; owner's
    // request, after phase 8). It counts as launching the app; like execute(), it ignores Terminal=true.
    function launchAction(app, action) {
        const all = Object.assign({}, Store.saved.launches);
        all[app.id] = (all[app.id] ?? []).concat([Date.now()]).slice(-10);
        Store.saved.launches = all;
        LauncherTools.launch(app.id, app.runInTerminal ? inTerminal(action.command, false, "") : action.command, app.workingDirectory, app.runInTerminal ? terminalAppId : "");
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

    // The program an app runs, lower case, for finding it by that name ("baobab" finds Disk Usage
    // Analyzer; owner's request, 12 November 2026): the command's own name, past `env` and its
    // settings; for a Flatpak its --command, else the last part of its id. "" when there's none.
    function programOf(app): string {
        const words = (app?.command ?? []).slice();
        const base = w => String(w).split("/").pop().toLowerCase();
        while (words.length && base(words[0]) === "env") {
            words.shift();
            while (words.length && (String(words[0]).startsWith("-") || String(words[0]).includes("=")))
                words.shift();
        }
        if (!words.length)
            return "";
        if (base(words[0]) === "flatpak") {
            const given = words.find(w => String(w).startsWith("--command="));
            if (given)
                return base(String(given).slice(10));
            const id = words.slice(1).find(w => !String(w).startsWith("-") && w !== "run");
            return id ? String(id).split(".").pop().toLowerCase() : "";
        }
        return base(words[0]);
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
