pragma Singleton

import qs
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// The only file that talks to the compositor; UI files use this API and nothing else.
Singleton {
    id: root

    property bool magnifierOpen
    property real magnifierZoom: 2
    property point pointerPosition: Qt.point(0,0)
    Timer {
        interval: 40; repeat: true; running: root.magnifierOpen; triggeredOnStart: true
        onTriggered: if (!cursorProbe.running) cursorProbe.running=true
    }
    Process {
        id:cursorProbe
        command:["hyprctl","-j","cursorpos"]
        stdout:StdioCollector { onStreamFinished: { try { const p=JSON.parse(text); root.pointerPosition=Qt.point(p.x,p.y); } catch(e) {} } }
    }
    IpcHandler {
        target:"magnifier"
        function open(): void { root.magnifierOpen=true; root.magnifierZoom=2; }
        function close(): void { root.magnifierOpen=false; }
        function zoom(delta: real): void { if (root.magnifierOpen) root.magnifierZoom=Math.max(1.5,Math.min(6,root.magnifierZoom+delta)); }
        function status(): string { return JSON.stringify({open:root.magnifierOpen,zoom:root.magnifierZoom,x:root.pointerPosition.x,y:root.pointerPosition.y}); }
    }

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

    // Tabbed workspaces, i3-style (owner's request, 8 November 2026): a workspace's tiled windows
    // in one Hyprland group, shown one at a time under Hyprland's own tab bar, styled below. Kept with
    // the names, so until logout. A
    // window joins a group only while focused (into_group takes the focused one, toward the group), so
    // gathering goes to the workspace and takes them in one by one; new windows join by themselves
    // (Hyprland's auto_group), or are taken in as they open.
    readonly property var tabbed: namesFile.adapter.tabbed ?? []

    function isTabbed(id: int): bool {
        return tabbed.includes(id);
    }

    signal tabbedToggled(int workspace, bool on) // for the OSD

    function setTabbed(id: int, on: bool) {
        namesFile.adapter.tabbed = tabbed.filter(t => t !== id).concat(on ? [id] : []);
        namesFile.writeAdapter();
        tabbedToggled(id, on);
        if (on) {
            gathering = id;
            gatherSteps = 0;
            gather.restart();
        } else {
            const done = [];
            for (const t of Hyprland.toplevels.values) {
                const g = t.lastIpcObject.grouped ?? [];
                if (t.workspace?.id === id && g.length > 0 && !done.includes(g[0])) {
                    done.push(g[0]);
                    dispatch(`hl.dsp.group.toggle({ window = "address:0x${t.address}" })`, `togglegroup address:0x${t.address}`);
                }
            }
        }
    }

    property int gathering: 0 // the workspace being gathered into a group, or 0
    property int gatherSteps

    // one window a step, after Hyprland has moved the last one (its list is read again between)
    Timer {
        id: gather
        interval: 160
        onTriggered: {
            const id = root.gathering;
            if (!id || ++root.gatherSteps > 24) {
                root.gathering = 0;
                return;
            }
            Hyprland.refreshToplevels();
            const tiled = Hyprland.toplevels.values.filter(t => t.workspace?.id === id && t.title !== "Pistachio Settings" && !(t.lastIpcObject.floating ?? false) && t.lastIpcObject.size);
            const grouped = tiled.filter(t => (t.lastIpcObject.grouped ?? []).length > 0);
            if (tiled.length < 2 && grouped.length === 0) {
                root.gathering = 0; // one window: it becomes a group when the next opens
                return;
            }
            if (grouped.length === 0) {
                const lead = tiled.find(t => root.focusOrder[0] === t.address) ?? tiled[0];
                root.dispatch(`hl.dsp.group.toggle({ window = "address:0x${lead.address}" })`, `togglegroup address:0x${lead.address}`);
                gather.restart();
                return;
            }
            const group = grouped[0];
            const loose = tiled.filter(t => !(group.lastIpcObject.grouped ?? []).includes("0x" + t.address));
            if (loose.length === 0) {
                root.gathering = 0;
                return;
            }
            const w = loose[0], a = w.lastIpcObject, b = group.lastIpcObject;
            const dx = (b.at[0] + b.size[0] / 2) - (a.at[0] + a.size[0] / 2), dy = (b.at[1] + b.size[1] / 2) - (a.at[1] + a.size[1] / 2);
            const toward = Math.abs(dx) >= Math.abs(dy) ? (dx > 0 ? "r" : "l") : (dy > 0 ? "d" : "u");
            root.focus(w.address);
            root.dispatch(`hl.dsp.window.move({ into_group = "${toward}" })`, `moveintogroup ${toward}`);
            gather.restart();
        }
    }

    // Hyprland's own tab bar on groups, in the Pistachio look (owner's call, 9 November 2026: the shell's
    // strip, a layer above every window, covered windows and lagged when things moved): filled pill
    // tabs, the shown one pistachio with bg text, the rest overlay with subtext, Manrope titles; the
    // group's border as the owner's window border. Set at runtime (the config file is untouched), at
    // startup and after each config reload, which would undo it.
    function hex(c: color, alpha: real): string {
        const two = v => Math.round(v * 255).toString(16).padStart(2, "0");
        return `rgba(${two(c.r)}${two(c.g)}${two(c.b)}${two(alpha)})`;
    }

    function styleGroups() {
        if (!Hyprland.usingLua)
            return; // a hyprland.conf: the README gives its lines
        hl(`hl.config({ group = { groupbar = { gradients = true, gradient_rounding = 11, gradient_round_only_edges = false, rounding = 11, height = 22, indicator_height = 0, gaps_in = 4, gaps_out = 4, font_family = "${Theme.fontUi}", font_size = 11, font_weight_active = "heavy", font_weight_inactive = "bold", text_color = "${hex(Theme.bg, 1)}", text_color_inactive = "${hex(Theme.subtext, 1)}", col = { active = "${hex(Theme.pistachio, 1)}", inactive = "${hex(Theme.overlay, 1)}", locked_active = "${hex(Theme.clay, 1)}", locked_inactive = "${hex(Theme.overlay2, 1)}" } } } })`);
        borderReader.running = true;
    }

    // At login the shell can start before it knows Hyprland's config is Lua (`usingLua` false at
    // first): the styling was skipped and only came back with a config reload (owner, 9 November,
    // after a reboot). So again once that's known, and once more a few seconds in.
    Connections {
        target: Hyprland
        function onUsingLuaChanged() {
            root.styleGroups();
        }
    }

    Timer {
        running: true
        interval: 4000
        onTriggered: root.styleGroups()
    }

    function hl(lua: string) {
        Quickshell.execDetached(["hyprctl", "eval", lua]);
    }

    // the group's border: the owner's own window border colours, read from Hyprland
    Process {
        id: borderReader
        command: ["sh", "-c", "hyprctl getoption general:col.active_border | head -1; hyprctl getoption general:col.inactive_border | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const colours = text.split("\n").map(l => (/gradient data: ([0-9a-f]{8})/.exec(l) ?? [])[1]).map(v => v ? `rgba(${v.slice(2)}${v.slice(0, 2)})` : "");
                if (colours[0])
                    root.hl(`hl.config({ group = { col = { border_active = "${colours[0]}", border_inactive = "${colours[1] || "rgba(00000000)"}" } } })`);
            }
        }
    }

    // For keybinds: qs -c pistachio ipc call workspace name "music" (empty clears it), workspace preset Work
    IpcHandler {
        target: "workspace"

        function name(text: string): void {
            root.setName(root.activeWorkspace, text);
        }

        // tabbed on or off for the workspace on screen
        function tabbed(): void {
            root.setTabbed(root.activeWorkspace, !root.isTabbed(root.activeWorkspace));
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
            property var tabbed: [] // workspace ids
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
        pid: t.lastIpcObject.pid ?? -1,
        workspace: t.workspace?.id ?? 0,
        urgent: t.urgent,
        floating: t.lastIpcObject.floating ?? false,
        pinned: t.lastIpcObject.pinned ?? false,
        group: (t.lastIpcObject.grouped ?? []).map(a => a.replace(/^0x/, "")), // its tab group's windows, or []
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

    // Pin on top (owner's pick, 8 November 2026): above everything, on every workspace. Hyprland pins
    // only floating windows, so a tiled one floats first; unpinning leaves it floating.
    function togglePin(address: string) {
        const w = windows.find(x => x.address === address);
        if (w && !w.pinned && !w.floating)
            toggleFloating(address);
        dispatch(`hl.dsp.window.pin({ window = "address:0x${address}" })`, `pin address:0x${address}`);
    }

    function toggleFloating(address: string) {
        dispatch(`hl.dsp.window.float({ action = "toggle", window = "address:0x${address}" })`, `togglefloating address:0x${address}`);
    }

    function floatingPreset(address: string, width: int, height: int) {
        if (!/^[0-9a-fA-F]+$/.test(address) || !windows.some(w => w.address===address && w.floating)) return;
        const selector=`address:0x${address}`;
        if (width>0 && height>0) dispatch(`hl.dsp.window.resize({ window = "${selector}", x = ${width}, y = ${height}, relative = false })`, `resizewindowpixel exact ${width} ${height},${selector}`);
        if (!Hyprland.usingLua) focus(address);
        dispatch(`hl.dsp.window.center({ window = "${selector}" })`, "centerwindow");
    }

    // FloatingWindow is an xdg toplevel, so Hyprland otherwise tiles it (and can add it to tabs).
    // Apply to this window once on mapping; no config files or other windows are changed.
    function placeSettingsWindow(window, width: int, height: int) {
        const address = window.address, selector = `address:0x${address}`;
        if (!Hyprland.usingLua) focus(address);
        if (window.group.length > 1) {
            dispatch(`hl.dsp.window.move({ window = "${selector}", out_of_group = true })`, "moveoutofgroup");
        }
        dispatch(`hl.dsp.window.float({ action = "set", window = "${selector}" })`, `setfloating ${selector}`);
        dispatch(`hl.dsp.window.resize({ window = "${selector}", x = ${width}, y = ${height}, relative = false })`, `resizewindowpixel exact ${width} ${height},${selector}`);
        dispatch(`hl.dsp.window.center({ window = "${selector}" })`, "centerwindow");
        styleSettingsWindow(address);
    }

    // Settings draws its own neutral border and rounded content; avoid a second compositor frame.
    function styleSettingsWindow(address: string) {
        const selector = `address:0x${address}`;
        dispatch(`hl.dsp.window.set_prop({ window = "${selector}", prop = "border_size", value = "0" })`, `setprop ${selector} bordersize 0`);
        dispatch(`hl.dsp.window.set_prop({ window = "${selector}", prop = "rounding", value = "${Theme.panelRadius}" })`, `setprop ${selector} rounding ${Theme.panelRadius}`);
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
            if (event.name === "configreloaded") {
                root.styleGroups();
                const settings = root.windows.find(w => w.title === "Pistachio Settings" && w.pid === Quickshell.processId);
                if (settings) root.styleSettingsWindow(settings.address);
            }
            if (event.name === "openwindow" && root.arriving.length)
                root.placeArrival(event.data);
            if (event.name === "openwindow" && !event.data.endsWith(",Pistachio Settings") && root.isTabbed(parseInt(event.data.split(",")[1])) && !root.gathering) {
                root.gathering = parseInt(event.data.split(",")[1]);
                root.gatherSteps = 0;
                gather.restart();
            }
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

    Component.onCompleted: {
        Hyprland.refreshToplevels();
        styleGroups();
    }
}
