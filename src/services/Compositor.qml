pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

// The only file that talks to the compositor; UI files use this API and nothing else.
Singleton {
    // Hyprland lists only workspaces that exist (occupied or shown); special and named ones have negative ids.
    readonly property var workspaces: Hyprland.workspaces.values.filter(w => w.id > 0).map(w => ({
        id: w.id,
        name: w.name,
        occupied: w.toplevels.values.length > 0,
        urgent: w.urgent,
        active: w.active
    }))

    // Hyprland.activeToplevel stays null until the first focus change; the Wayland one is right from the start.
    readonly property Toplevel focusedWindow: ToplevelManager.activeToplevel

    // Every window, for the launcher. `address` is what focus(), moveWindow() and close() take.
    readonly property var windows: Hyprland.toplevels.values.map(t => ({
        address: t.address,
        title: t.title,
        appId: t.wayland?.appId ?? "",
        workspace: t.workspace?.id ?? 0,
        urgent: t.urgent,
        focused: t.wayland !== null && t.wayland === ToplevelManager.activeToplevel,
        recency: t.lastIpcObject.focusHistoryID ?? 1e6, // 0 = most recently focused
        bounds: t.lastIpcObject.size ? Qt.rect(t.lastIpcObject.at[0], t.lastIpcObject.at[1], t.lastIpcObject.size[0], t.lastIpcObject.size[1]) : Qt.rect(0, 0, 0, 0)
    }))

    // Rectangles of the windows on the active workspace, for auto-hide.
    // Single monitor, so Hyprland's layout coordinates are screen coordinates.
    readonly property var windowBounds: Hyprland.toplevels.values
        .filter(t => t.workspace?.active && t.lastIpcObject.size && !t.lastIpcObject.hidden)
        .map(t => Qt.rect(t.lastIpcObject.at[0], t.lastIpcObject.at[1], t.lastIpcObject.size[0], t.lastIpcObject.size[1]))

    function goto(id: int) {
        dispatch(`hl.dsp.focus({ workspace = ${id} })`, `workspace ${id}`);
    }

    function focus(address: string) {
        dispatch(`hl.dsp.focus({ window = "address:0x${address}" })`, `focuswindow address:0x${address}`);
    }

    function moveWindow(address: string, workspace: int) {
        dispatch(`hl.dsp.window.move({ workspace = ${workspace}, window = "address:0x${address}" })`, `movetoworkspace ${workspace},address:0x${address}`);
    }

    function close(address: string) {
        dispatch(`hl.dsp.window.close({ window = "address:0x${address}" })`, `closewindow address:0x${address}`);
    }

    // ends the session (log out)
    function exit() {
        dispatch("hl.dsp.exit()", "exit");
    }

    // Hyprland 0.55+ takes Lua dispatchers; the old hyprlang ones still work with a hyprland.conf.
    function dispatch(lua: string, legacy: string) {
        Hyprland.dispatch(Hyprland.usingLua ? lua : legacy);
    }

    // Window geometry (lastIpcObject) only updates on a refresh, so refresh after Hyprland events.
    // Title changes are frequent and move nothing, so they are skipped.
    // shortcut: Hyprland sends no event for resizing or mouse-dragging a window, so those bounds update
    // on the next event; poll while the pointer is down if auto-hide (phase 8) needs it sooner.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!event.name.startsWith("windowtitle"))
                refresh.restart();
        }
    }

    Timer {
        id: refresh
        interval: 50 // one refresh per burst of events
        onTriggered: Hyprland.refreshToplevels()
    }

    Component.onCompleted: Hyprland.refreshToplevels()
}
