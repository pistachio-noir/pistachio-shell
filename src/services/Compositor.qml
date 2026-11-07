pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// The only file that talks to the compositor; UI files use this API and nothing else.
Singleton {
    id: root

    // Window addresses, most recently focused first, from Hyprland's activewindowv2 events. Its own
    // focusHistoryID (lastIpcObject) only moves on a refresh, and a switch made while a layer held the
    // keyboard (Alt+Tab) reached the history only after the event, so the next refresh read it stale.
    property var focusOrder: []

    // Hyprland lists only workspaces that exist (occupied or shown); special and named ones have negative ids.
    readonly property var workspaces: Hyprland.workspaces.values.filter(w => w.id > 0).map(w => ({
        id: w.id,
        name: w.name,
        occupied: w.toplevels.values.length > 0,
        urgent: w.urgent,
        active: w.active
    }))

    // the workspace on screen, for the workspace OSD and the bar's scroll
    readonly property int activeWorkspace: Hyprland.focusedWorkspace?.id ?? 1

    // Workspace names (owner's request, 3 November 2026): the shell keeps them, not Hyprland, which
    // drops an empty workspace and its name as you leave it. They live in the runtime folder, so a
    // reload keeps them and logging out or a reboot clears them, as the owner wanted.
    readonly property var names: namesFile.adapter.names ?? ({})

    function nameOf(id: int): string {
        return names[String(id)] ?? "";
    }

    function setName(id: int, name: string) {
        const next = {};
        for (const [k, v] of Object.entries(names))
            if (k !== String(id))
                next[k] = v;
        if (name.trim())
            next[String(id)] = name.trim();
        namesFile.adapter.names = next;
        namesFile.writeAdapter();
    }

    // Presets (owner's request, 3 November 2026): every workspace's name, kept for good in Store, and,
    // when saved with them, the apps open on every workspace, opened again there on loading (in the
    // background, skipping one that already has a window on its workspace).
    readonly property var presets: Store.saved.workspacePresets ?? []

    function entryOf(appId: string): string {
        return appId ? DesktopEntries.heuristicLookup(appId)?.id ?? "" : ""; // ("" would find some app)
    }

    function savePreset(name: string, withApps: bool) {
        const apps = {};
        if (withApps)
            for (const w of windows) {
                const id = String(w.workspace), entry = entryOf(w.appId);
                if (w.workspace > 0 && entry) // one per window: two ghostty windows are two
                    apps[id] = (apps[id] ?? []).concat([{ entry: entry, appId: w.appId }]);
            }
        Store.saved.workspacePresets = presets.filter(p => p.name !== name).concat([{ name: name, names: Object.assign({}, names), apps: apps }]);
    }

    function loadPreset(preset) {
        namesFile.adapter.names = Object.assign({}, preset.names);
        namesFile.writeAdapter();
        const quote = a => /^[\w@%+=:,.\/-]+$/.test(a) ? a : `'${a.replace(/'/g, "'\\''")}'`;
        for (const [id, list] of Object.entries(preset.apps ?? {})) {
            const wanted = {}; // desktop entry id -> { count, appId } (older presets kept bare ids)
            for (const a of list) {
                const entryId = typeof a === "string" ? a : a.entry;
                wanted[entryId] = { count: (wanted[entryId]?.count ?? 0) + 1, appId: typeof a === "string" ? "" : a.appId };
            }
            for (const [entryId, want] of Object.entries(wanted)) {
                const entry = DesktopEntries.byId(entryId);
                const have = windows.filter(w => String(w.workspace) === id && entryOf(w.appId) === entryId).length;
                for (let i = have; entry && i < want.count; i++) {
                    exec((entry.runInTerminal ? Apps.inTerminal(entry.command, false, "") : entry.command).map(quote).join(" "), { workspace: `${id} silent` });
                    if (want.appId)
                        arriving = arriving.concat([{ appId: want.appId, workspace: parseInt(id), until: Date.now() + 15000 }]);
                }
            }
        }
    }

    // windows a preset opened, on their way: a single-instance app (ghostty, a browser) hands the launch
    // to its running copy, whose window the exec rule doesn't follow, so the first window of that app
    // to open goes to the preset's workspace
    property var arriving: [] // { appId, workspace, until }

    function placeArrival(data: string) {
        const [address, workspace, appId] = data.split(",");
        const now = Date.now();
        arriving = arriving.filter(a => a.until > now);
        const i = arriving.findIndex(a => a.appId === appId);
        if (i < 0)
            return;
        const target = arriving[i].workspace;
        arriving = arriving.filter((a, j) => j !== i);
        if (workspace !== String(target) && workspace !== nameOf(target))
            sendWindow(address, target);
    }

    function deletePreset(name: string) {
        Store.saved.workspacePresets = presets.filter(p => p.name !== name);
    }

    // For keybinds: qs -c pistachio ipc call workspace name "music" (empty clears it), workspace preset Work
    IpcHandler {
        target: "workspace"

        function name(text: string): void {
            root.setName(root.activeWorkspace, text);
        }

        function preset(name: string): void {
            const p = root.presets.find(x => x.name.toLowerCase() === name.toLowerCase());
            if (p)
                root.loadPreset(p);
        }
    }

    FileView {
        id: namesFile
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/pistachio-workspace-names.json`
        printErrors: false // none yet after a login
        adapter: JsonAdapter {
            property var names: ({})
        }
    }

    // Hyprland.activeToplevel stays null until the first focus change; the Wayland one is right from the start.
    readonly property Toplevel focusedWindow: ToplevelManager.activeToplevel
    // the focused window fills the screen (a game, a video): toasts wait meanwhile
    readonly property bool fullscreen: focusedWindow?.fullscreen ?? false

    // Every window, for the launcher. `address` is what focus(), moveWindow() and close() take.
    readonly property var windows: Hyprland.toplevels.values.map(t => ({
        address: t.address,
        title: t.title,
        appId: t.wayland?.appId ?? "",
        workspace: t.workspace?.id ?? 0,
        urgent: t.urgent,
        floating: t.lastIpcObject.floating ?? false,
        focused: t.wayland !== null && t.wayland === ToplevelManager.activeToplevel,
        // 0 = most recently focused; windows not focused since the shell started follow, in Hyprland's order
        recency: root.focusOrder.includes(t.address) ? root.focusOrder.indexOf(t.address) : 1000 + (t.lastIpcObject.focusHistoryID ?? 1000),
        toplevel: t.wayland, // the Wayland window, for a ScreencopyView still of it (Alt+Tab)
        bounds: t.lastIpcObject.size ? Qt.rect(t.lastIpcObject.at[0], t.lastIpcObject.at[1], t.lastIpcObject.size[0], t.lastIpcObject.size[1]) : Qt.rect(0, 0, 0, 0)
    }))

    // Rectangles of the windows on the active workspace, for auto-hide.
    // Single monitor, so Hyprland's layout coordinates are screen coordinates.
    readonly property var windowBounds: Hyprland.toplevels.values
        .filter(t => t.workspace?.active && t.lastIpcObject.size && !t.lastIpcObject.hidden)
        .map(t => Qt.rect(t.lastIpcObject.at[0], t.lastIpcObject.at[1], t.lastIpcObject.size[0], t.lastIpcObject.size[1]))

    // Hyprland's key binds, for the launcher's cheat sheet (owner's request, after phase 8), read by
    // loadBinds() from hyprctl: { keys: ["Super", "Shift", "S"], what } each. A bind made in Lua says
    // what it does only through its description (hl.bind(keys, action, { description = "…" })).
    property var binds: []

    function loadBinds() {
        bindsReader.running = true;
    }

    function readBinds(text: string): var {
        let list;
        try {
            list = JSON.parse(text);
        } catch (e) {
            return [];
        }
        const mods = [[64, "Super"], [4, "Ctrl"], [8, "Alt"], [1, "Shift"]];
        const names = {
            Return: "Enter", space: "Space", SPACE: "Space", Escape: "Esc", Print: "PrtSc", grave: "`",
            left: "←", right: "→", up: "↑", down: "↓",
            "mouse:272": "Left button", "mouse:273": "Right button", "mouse:274": "Middle button", mouse_down: "Wheel down", mouse_up: "Wheel up",
            XF86AudioRaiseVolume: "Volume up", XF86AudioLowerVolume: "Volume down", XF86AudioMute: "Mute", XF86AudioMicMute: "Mic mute",
            XF86MonBrightnessUp: "Brightness up", XF86MonBrightnessDown: "Brightness down",
            XF86AudioNext: "Next track", XF86AudioPrev: "Previous track", XF86AudioPlay: "Play", XF86AudioPause: "Pause"
        };
        return list.filter(b => !b.submap).map(b => ({
            keys: mods.filter(([bit]) => b.modmask & bit).map(([, name]) => name).concat([names[b.key] ?? (b.key.length === 1 ? b.key.toUpperCase() : b.key.replace(/^XF86/, "") || "?")]),
            what: b.has_description ? b.description : b.dispatcher === "__lua" ? "" : `${b.dispatcher} ${b.arg}`.trim()
        }));
    }

    Process {
        id: bindsReader
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.binds = root.readBinds(text)
        }
    }

    function goto(id: int) {
        dispatch(`hl.dsp.focus({ workspace = ${id} })`, `workspace ${id}`);
    }

    function focus(address: string) {
        dispatch(`hl.dsp.focus({ window = "address:0x${address}" })`, `focuswindow address:0x${address}`);
    }

    function moveWindow(address: string, workspace: int) {
        dispatch(`hl.dsp.window.move({ workspace = ${workspace}, window = "address:0x${address}" })`, `movetoworkspace ${workspace},address:0x${address}`);
    }

    // moves it without following it there (the launcher's Ctrl+1–9, which stays open)
    function sendWindow(address: string, workspace: int) {
        dispatch(`hl.dsp.window.move({ workspace = ${workspace}, follow = false, window = "address:0x${address}" })`, `movetoworkspacesilent ${workspace},address:0x${address}`);
    }

    function toggleFloating(address: string) {
        dispatch(`hl.dsp.window.float({ action = "toggle", window = "address:0x${address}" })`, `togglefloating address:0x${address}`);
    }

    function close(address: string) {
        dispatch(`hl.dsp.window.close({ window = "address:0x${address}" })`, `closewindow address:0x${address}`);
    }

    // Runs a command with rules for the window it opens (Hyprland's exec with rules, which follows the
    // process it starts): { float: true, size: [w, h], move: [x, y], workspace: "3" }; showoff's terminal.
    function exec(command: string, rules) {
        const entries = Object.entries(rules);
        const lua = entries.map(([k, v]) => `${k} = ${v === true ? "true" : Array.isArray(v) ? `{ ${v.join(", ")} }` : JSON.stringify(v)}`).join(", ");
        const legacy = entries.map(([k, v]) => v === true ? k : Array.isArray(v) ? `${k} ${v.join(" ")}` : `${k} ${v}`).join("; ");
        dispatch(`hl.dsp.exec_cmd(${JSON.stringify(command)}, { ${lua} })`, `exec [${legacy}] ${command}`);
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
            if (event.name === "openwindow" && root.arriving.length)
                root.placeArrival(event.data);
            if (event.name === "activewindowv2" && event.data)
                root.focusOrder = [event.data].concat(root.focusOrder.filter(a => a !== event.data));
            else if (event.name === "closewindow")
                root.focusOrder = root.focusOrder.filter(a => a !== event.data);
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
