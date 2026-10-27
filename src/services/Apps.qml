pragma Singleton

import Quickshell
import QtQuick

// Installed applications (desktop entries), launching them, and icons from the system icon theme.
Singleton {
    // already excludes Hidden and NoDisplay entries
    readonly property var list: DesktopEntries.applications.values

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
