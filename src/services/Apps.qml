pragma Singleton

import Quickshell
import QtQuick

// Installed applications (desktop entries), launching them, icons from the system icon theme, and
// commands typed into the launcher after a "$".
Singleton {
    id: root

    // already excludes Hidden and NoDisplay entries
    readonly property var list: DesktopEntries.applications.values
    readonly property var recentCommands: Store.saved.recentCommands ?? [] // newest first
    // run()'s background commands: the command, then a notification with how it went
    readonly property string background: 'out=$(sh -c "$1" 2>&1); code=$?; last=$(printf "%s\n" "$out" | grep -v "^[[:space:]]*$" | tail -n 1); '
        + 'if [ "$code" -eq 0 ]; then notify-send --app-name=Command --icon=utilities-terminal "Finished: $1" "${last:-No output}"; '
        + 'else notify-send --app-name=Command --icon=utilities-terminal "Failed: $1" "Exit $code${last:+ · $last}"; fi'

    // A command typed in the launcher (owner's request, after phase 8): in kitty, which stays open to
    // show what it printed, or in the background without a window. It runs exactly as typed, as in a
    // terminal. In the background a notification says when it's done (owner's request): "Finished"
    // or "Failed" with its exit code, and the last line it printed. A detached shell waits for it, so
    // a live reload doesn't stop it.
    // shortcut: kitty, as for Terminal=true apps, until the owner's terminal is read from config
    function run(command: string, inTerminal: bool) {
        Store.saved.recentCommands = [command].concat(recentCommands.filter(c => c !== command)).slice(0, 20);
        Quickshell.execDetached(inTerminal ? ["kitty", "--hold", "sh", "-c", command] : ["sh", "-c", root.background, "sh", command]);
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
        // execute() ignores Terminal=true, so terminal apps get a terminal here.
        // shortcut: falls back to kitty when $TERMINAL is unset; read the owner's terminal from config once it exists
        if (app.runInTerminal)
            Quickshell.execDetached({
                command: [Quickshell.env("TERMINAL") || "kitty", "-e", ...app.command],
                workingDirectory: app.workingDirectory
            });
        else
            app.execute();
    }

    // An image source for an icon name, or "" if the theme has no such icon.
    function icon(name: string): string {
        return name ? Quickshell.iconPath(name, true) : "";
    }

    // The icon and name of the app a window belongs to, found from its app id.
    function iconFor(appId: string): string {
        return icon(DesktopEntries.heuristicLookup(appId)?.icon ?? "");
    }

    function nameFor(appId: string): string {
        return DesktopEntries.heuristicLookup(appId)?.name ?? appId;
    }
}
