pragma Singleton

import Quickshell
import Quickshell.Services.SystemTray
import QtQuick

// Apps' tray icons (StatusNotifierItem). Passive ones ("nothing to see right now") are left out,
// as the spec suggests.
Singleton {
    readonly property var items: SystemTray.items.values.filter(i => i.status !== Status.Passive)

    function activate(item) {
        item.activate();
    }

    function secondaryActivate(item) {
        item.secondaryActivate();
    }

    function scroll(item, delta: int, horizontal: bool) {
        item.scroll(delta, horizontal);
    }
}
