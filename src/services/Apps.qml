pragma Singleton

import Quickshell
import QtQuick

// Installed applications (desktop entries), launching them, and icons from the system icon theme.
Singleton {
    // already excludes Hidden and NoDisplay entries
    readonly property var list: DesktopEntries.applications.values

    function launch(app) {
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
