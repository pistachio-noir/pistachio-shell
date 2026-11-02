import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland // layer-shell keyboard focus for this window (a Wayland protocol, not a compositor module)
import QtQuick
import QtQuick.Shapes
import "fuzzy.js" as Fuzzy
import "calc.js" as Calc
import "emoji.js" as Emoji

// The launcher (Launcher boards): search, mode tabs, results, key hints. Every mode is a flat list of
// rows built from the services; the selected row gets the keys. Opened by keybind:
//   qs -c pistachio ipc call launcher toggle        (All)
//   qs -c pistachio ipc call launcher open apps     (or windows, workspaces, system)
PanelWindow {
    id: root

    readonly property var modes: [
        { id: "all", label: "All", placeholder: "Search apps, windows, system…" },
        { id: "apps", label: "Apps", placeholder: "Search applications…" },
        { id: "windows", label: "Windows", placeholder: "Find a window by title or app…" },
        { id: "workspaces", label: "Workspaces", placeholder: "Jump to a workspace…" },
        { id: "system", label: "System", placeholder: "Search system controls…" }
    ]
    readonly property var hints: ({
        all: [["↑↓", "navigate"], ["↵", "open"], ["Tab", "switch mode"], ["Esc", "close"]],
        apps: [["↑↓", "navigate"], ["↵", "open"], ["Tab", "switch mode"], ["Esc", "close"]],
        // (no ↑↓ here, to make room for the window actions)
        windows: [["↵", "switch"], ["Ctrl W", "close window"], ["Ctrl F", "float"], ["Ctrl 1–9", "move"], ["Esc", "close"]],
        workspaces: [["←→", "choose"], ["↵", "go"], ["Shift ↵", "move window here"], ["Esc", "close"]],
        system: [["↑↓", "navigate"], ["←→", "adjust"], ["↵", "switch / select"], ["Ctrl M", "mute"], ["Esc", "close"]],
        // Ctrl, unlike the board's plain ⌫: Backspace also edits the search, and forgetting is not undoable
        bluetooth: [["↑↓", "navigate"], ["↵", "connect / disconnect"], ["Ctrl ⌫", "forget device"], ["Esc", "close"]],
        terminals: [["↑↓", "navigate"], ["↵", "use"], ["Esc", "back"]]
    })

    property bool open
    property string mode: "all"
    signal wallpapersRequested // the Wallpapers row: shell.qml opens the switcher
    signal notificationRequested(var n) // a "!" result: shell.qml has the bar show it in the centre
    signal rainRequested // the Konami code: shell.qml has pistachios rain

    // the easter egg (owner's pick, 31 October 2026): the last ten keys, against ↑↑↓↓←→←→ B A
    property var konami: []
    readonly property var konamiCode: [Qt.Key_Up, Qt.Key_Up, Qt.Key_Down, Qt.Key_Down, Qt.Key_Left, Qt.Key_Right, Qt.Key_Left, Qt.Key_Right, Qt.Key_B, Qt.Key_A]
    property var confirming: null // a power action waiting for a yes: the results make way for the question
    // A text setting being changed (owner's request, after phase 8: the weather's city): the results
    // make way for a question, as for a power action, and the value is typed into the search field.
    // Save checks it first (`check`, which may take a moment: `editBusy`) and keeps the question
    // open with the problem (`editError`) if it fails, so a wrong value is never saved.
    property var editing: null // { key, title, icon, hint(), check(text, then(value, problem)), apply(value) }
    property bool editBusy
    property string editError
    readonly property string query: field.text
    // The pairing agent's question (Bluetooth.request) also takes the place of the results; the
    // launcher opens for it. A PIN or passkey is typed into the search field.
    readonly property bool codeWanted: Bluetooth.request?.kind === "pin" || Bluetooth.request?.kind === "passkey"
    readonly property bool codeValid: Bluetooth.request?.kind === "pin" ? query.length > 0 : /^\d{1,6}$/.test(query)
    // what the question's typed answer needs before its last choice (Pair, Save) can be picked
    readonly property bool inputValid: editing ? query.trim() !== "" && !editBusy : codeValid
    // Windows and workspaces as they were when the launcher opened, so the rows only change when you
    // type or switch mode, not under the cursor (window titles change all the time).
    property var windows: []
    property var workspaces: []
    readonly property var rows: buildRows(mode, query, windows, workspaces)
    property int current: -1 // selected row
    // a row to stay on while rows above it come and go (back from a setting or the Terminals view:
    // the System monitor's GPU and disk rows arrive a moment after System opens); let go of once
    // another row is selected
    property string heldKey
    onCurrentChanged: if (rows[current]?.key !== heldKey) heldKey = ""
    // App actions (owner's request, after phase 8): → on an app opens its own actions as rows under it
    // (the key of the app's row; an app can be listed twice), ← or typing closes them.
    property string expandedKey
    property int column: 0 // selected tile or card within a grid row

    function snapshot() {
        windows = Compositor.windows;
        workspaces = Compositor.workspaces;
    }

    // Bluetooth is a view inside System (LauncherBluetooth board), so it has no tab of its own;
    // the System tab stays highlighted. So is Terminals, from Shell settings (owner's request).
    readonly property string tab: mode === "bluetooth" || mode === "terminals" || mode === "about" ? "system" : mode
    readonly property string placeholder: Bluetooth.request ? (Bluetooth.request.kind === "pin" ? "PIN" : Bluetooth.request.kind === "passkey" ? "6-digit code" : "Bluetooth")
        : editing ? editing.placeholder
        : mode === "bluetooth" ? "Filter devices…" : mode === "terminals" ? "Filter terminals…" : mode === "about" ? "About the shell" : modes.find(m => m.id === mode).placeholder
    readonly property var keyHints: Bluetooth.request ? (codeWanted ? [["↵", "pair"], ["Esc", "cancel"]]
            : Bluetooth.request.id ? [["←→", "choose"], ["↵", "confirm"], ["Esc", "decline"]]
            : [["Esc", "cancel pairing"]])
        : confirming ? [["←→", "choose"], ["↵", "confirm"], ["Esc", "back"]]
        : editing ? [["↵", "save"], ["Esc", "back"]]
        : rows[current]?.kind === "appaction" ? [["↑↓", "navigate"], ["↵", "open"], ["←", "back"], ["Esc", "close"]]
        : rows[current]?.kind === "claude" ? [["↑↓", "navigate"], ["↵", "ask Claude"], ["Esc", "close"]]
        : rows[current]?.kind === "preset" ? [["↑↓", "navigate"], ["↵", "load"], ["→", "delete"], ["Esc", "close"]]
        : rows[current]?.kind === "app" && rows[current].app.actions.length > 0 ? [["↑↓", "navigate"], ["↵", "open"], ["→", "more actions"], ["Tab", "switch mode"], ["Esc", "close"]]
        : filesWanted ? [["↑↓", "navigate"], ["↵", "open"], ["Shift ↵", "show in folder"], ["Esc", "close"]]
        : (mode === "all" || mode === "apps") && query.startsWith("!") ? [["↑↓", "navigate"], ["↵", "show in centre"], ["Esc", "close"]]
        : cheatWanted ? [["↑↓", "navigate"], ["↵", "use a prefix"], ["Esc", "close"]]
        : hints[mode]
    // scan for new devices only while the Bluetooth view is on screen
    readonly property bool scanWanted: open && mode === "bluetooth" && Bluetooth.ready
    onScanWantedChanged: Bluetooth.setScanning(scanWanted)
    // and read the machine's load only while the System monitor card is
    readonly property bool statsWanted: open && rows.some(r => r.kind === "stat")
    onStatsWantedChanged: SystemStats.setWatching(statsWanted)
    // and Hyprland's binds, each time the cheat sheet opens
    readonly property bool cheatWanted: open && (mode === "all" || mode === "apps") && query.startsWith("?")
    onCheatWantedChanged: if (cheatWanted) Compositor.loadBinds()
    // and look through the home folder only while a "/" search is
    readonly property bool filesWanted: open && (mode === "all" || mode === "apps") && query.startsWith("/")
    onFilesWantedChanged: {
        Files.setActive(filesWanted);
        if (filesWanted)
            Files.search(query.slice(1).trim());
    }

    // opens in mode m, switches to it, or closes if it's already showing it
    function toggleMode(m: string) {
        if (open && mode === m)
            open = false;
        else
            show(m);
    }

    function show(m: string) {
        list.enter();
        confirming = null;
        editing = null;
        expandedKey = "";
        snapshot();
        mode = m === "bluetooth" || m === "about" || modes.some(x => x.id === m) ? m : "all";
        if (m === "about")
            About.load();
        field.text = "";
        resetSelection();
        open = true;
        field.forceActiveFocus();
    }

    // The weather's city (Shell settings), checked with Open-Meteo before it's saved; Store keeps it.
    readonly property var weatherSetting: ({
        key: "weatherCity",
        title: "Weather location",
        icon: Icons.mapPin,
        placeholder: "City",
        hint: () => `Type a city, then press Enter. Now: ${Weather.placeName}.`,
        check: (text, then) => Weather.lookup(text, then),
        apply: place => Weather.setCity(place.name)
    })

    // `initial`: what the field starts with, its first `chosen` characters selected (a file's name
    // without its extension), so typing replaces them
    function startEditing(setting, initial, chosen) {
        editing = setting;
        editBusy = false;
        editError = "";
        field.text = initial ?? "";
        field.select(0, chosen ?? field.text.length);
        resetSelection(); // on Save: Enter saves what's typed
    }

    // back to the results, at the setting's row; a question from elsewhere (`close`) closes the launcher
    function stopEditing() {
        const key = editing?.key;
        if (editing?.close)
            open = false;
        editing = null;
        editBusy = false;
        editError = "";
        field.text = "";
        const i = rows.findIndex(r => r.key === key);
        if (i >= 0) {
            current = i;
            heldKey = key;
            backToRow.restart();
        }
    }

    // A desktop icon's new name, and a new folder's (owner's request, after phase 8): the same question,
    // asked over the launcher opened for it.
    function renameDesktopItem(item) {
        show("all");
        const dot = item.folder ? -1 : item.name.lastIndexOf(".");
        startEditing({
            key: "",
            title: `Rename “${item.name}”`,
            icon: Icons.pencil,
            placeholder: "Name",
            close: true,
            hint: () => "Type the new name, then press Enter.",
            check: (text, then) => Desktop.check(text, item.name, then),
            apply: name => Desktop.rename(item, name)
        }, item.name, dot > 0 ? dot : item.name.length);
    }

    // A workspace's name (owner's request, 3 November 2026): F2 on its card; empty clears it
    function renameWorkspace(id: int) {
        startEditing({
            key: "workspaces",
            title: `Name workspace ${id}`,
            icon: Icons.pencil,
            placeholder: `Workspace ${id}`,
            hint: () => "Type a name, then press Enter. Empty clears it; it lasts until you log out.",
            check: (text, then) => then({ name: text.slice(0, 24) }, ""),
            apply: v => Compositor.setName(id, v.name)
        }, Compositor.nameOf(id));
    }

    function newDesktopFolder(cell) {
        show("all");
        startEditing({
            key: "",
            title: "New folder on the desktop",
            icon: Icons.folderPlus,
            placeholder: "Name",
            close: true,
            hint: () => "Type its name, then press Enter.",
            check: (text, then) => Desktop.check(text, "", then),
            apply: name => Desktop.newFolder(name, cell)
        }, "New folder");
    }

    function saveEditing() {
        const asked = editing, text = query.trim();
        editBusy = true;
        editError = "";
        asked.check(text, (value, problem) => {
            if (editing !== asked)
                return; // cancelled meanwhile: nothing changes
            editBusy = false;
            if (!value) {
                editError = problem;
                return;
            }
            asked.apply(value);
            stopEditing();
        });
    }

    // ---- rows ----------------------------------------------------------------------------------

    function section(title: string): var {
        return { kind: "section", key: "section:" + title, title: title };
    }

    // Fuzzy-rank `items` by textOf(item); ties go to the shorter text. Empty query keeps the order.
    function ranked(items, q: string, textOf, limit: int): var {
        if (!q)
            return items.slice(0, limit).map(item => ({ item: item, indices: [] }));
        const out = [];
        for (const item of items) {
            const m = Fuzzy.match(q, textOf(item));
            if (m)
                out.push({ item: item, indices: m.indices, score: m.score, length: textOf(item).length });
        }
        return out.sort((a, b) => b.score - a.score || a.length - b.length).slice(0, limit);
    }

    // An app as a result row; `prefix` keeps the key apart when it's listed twice (Frequent).
    function appRow(h, prefix: string): var {
        return {
            kind: "app",
            key: prefix + h.item.id,
            title: h.item.name,
            indices: h.indices,
            subtitle: h.item.genericName || h.item.comment,
            icon: Apps.icon(h.item.icon),
            app: h.item
        };
    }

    // The cheat sheet after a "?" (owner's request, after phase 8): the search prefixes, the launcher's
    // keys and Hyprland's binds, found by any word or key; Enter on a prefix puts it in the search.
    function cheatRows(q: string): var {
        const row = (kind, i, keys, title, extra) => Object.assign({ kind: "cheat", key: `${kind}:${i}`, keys: keys, title: title }, extra);
        const prefixes = [
            ["/", "Files and folders in your home folder"],
            ["!", "Notifications, newest first; Enter shows one in the centre"],
            ["$", `Run a command in ${Apps.terminal} (Shift+Enter: in the background)`],
            ["@", "Search the web with DuckDuckGo"],
            [":", "Emoji; Enter copies one"],
            ["?", "This cheat sheet"],
            ["12*3", "A calculation: the answer shows at the top"]
        ].concat(Apps.claudeApp ? [["claude", "Ask Claude: a new chat in Claude Desktop"]] : [])
            .map(([k, t], i) => row("prefix", i, [k], t, { prefix: k === "12*3" ? "" : k === "claude" ? "claude " : k }));
        const keys = [
            [["Tab"], "Next mode; Shift+Tab goes back"],
            [["↑", "↓"], "Move between results (or Ctrl+K, Ctrl+J)"],
            [["←", "→"], "Change a slider or a time, move across a grid (or Ctrl+H, Ctrl+L)"],
            [["→"], "An app's own actions; ← closes them"],
            [["Enter"], "Open, switch, select, or flip a switch"],
            [["Shift", "Enter"], "Workspace: move the last window there · file: open its folder · command: in the background"],
            [["Ctrl", "W"], "Close the window (or Ctrl+Q)"],
            [["Ctrl", "F"], "Float the window, or tile it"],
            [["Ctrl", "1–9"], "Send the window to that workspace"],
            [["Ctrl", "M"], "Mute"],
            [["Ctrl", "⌫"], "Forget the Bluetooth device"],
            [["Esc"], "Close, or back from a question"]
        ].map(([k, t], i) => row("launcherkey", i, k, t, {}));
        const binds = Compositor.binds.map((b, i) => row("bind", i, b.keys, b.what || "No description", { dim: !b.what }));
        const folded = Fuzzy.fold(q);
        const keep = r => !q || Fuzzy.match(q, r.title) || Fuzzy.fold(r.keys.join(" ")).includes(folded);
        const p = prefixes.filter(keep), k = keys.filter(keep), b = binds.filter(keep);
        const hint = binds.length && !binds.some(r => !r.dim) ? [{ kind: "empty", key: "binds-hint", title: "Give a bind a description in hyprland.lua to see here what it does" }] : [];
        return (p.length ? [section("Search prefixes")].concat(p) : [])
            .concat(k.length ? [section("Launcher keys")].concat(k) : [])
            .concat(b.length ? [section(`Hyprland binds · ${b.length}`)].concat(hint, b) : []);
    }

    // an app's own actions, under its row
    function actionRows(appRow): var {
        const app = appRow.app;
        return app.actions.map(a => ({ kind: "appaction", key: `${appRow.key}:${a.id}`, title: a.name, subtitle: app.name, icon: Apps.icon(a.icon) || appRow.icon, compact: true, indent: 24, app: app, action: a }));
    }

    // the apps launched most and most lately (Apps.frecency), for the top of Apps mode
    function frequentRows(limit: int): var {
        return Apps.list.map(a => ({ item: a, f: Apps.frecency(a), indices: [] })).filter(h => h.f > 0.05)
            .sort((a, b) => b.f - a.f).slice(0, limit).map(h => appRow(h, "frequent:"));
    }

    function appRows(q: string, limit: int): var {
        const byName = Apps.list.slice().sort((a, b) => a.name.localeCompare(b.name));
        let hits = ranked(byName, q, a => a.name, q ? byName.length : limit);
        // Apps you launch often rise among equally good matches: up to 250 points on top of the match's
        // score, less than the gap between a match at the start, at a word start and a scattered one.
        const top = Math.max(0, ...Apps.list.map(a => Apps.frecency(a)));
        if (q && top > 0) {
            for (const h of hits)
                h.score += 250 * Apps.frecency(h.item) / top;
            hits.sort((a, b) => b.score - a.score || a.length - b.length);
        }
        hits = hits.slice(0, limit);
        // also find apps by what they are ("browser" finds Firefox), below name matches, unhighlighted;
        // this needs the whole query in the description, not scattered letters
        if (q && hits.length < limit) {
            const ql = Fuzzy.fold(q);
            const extra = byName.filter(a => !hits.some(h => h.item === a) && Fuzzy.fold([a.genericName, ...a.keywords].join(" ")).includes(ql));
            hits = hits.concat(extra.slice(0, limit - hits.length).map(a => ({ item: a, indices: [] })));
        }
        return hits.map(h => appRow(h, "app:"));
    }

    function windowRows(q: string, limit: int): var {
        const active = workspaces.find(w => w.active)?.id ?? 0;
        const recent = windows.slice().sort((a, b) => a.recency - b.recency);
        return ranked(recent, q, w => w.title || w.appId, limit).map(h => ({
            kind: "window",
            key: "window:" + h.item.address,
            title: h.item.title || h.item.appId,
            indices: h.indices,
            subtitle: h.item.appId + (h.item.recency === 0 ? " · focused" : h.item.urgent ? " · needs attention" : "") + (h.item.floating ? " · floating" : ""),
            icon: Apps.iconFor(h.item.appId),
            badge: String(h.item.workspace),
            badgeActive: h.item.workspace === active,
            address: h.item.address
        }));
    }

    function workspaceCards(q: string): var {
        const count = Math.max(5, ...workspaces.map(w => w.id));
        const cards = [];
        for (let id = 1; id <= count; id++) {
            const ws = workspaces.find(w => w.id === id);
            const wins = windows.filter(w => w.workspace === id);
            const apps = [...new Set(wins.map(w => Apps.nameFor(w.appId)))];
            if (q && !String(id).startsWith(q) && !apps.some(a => Fuzzy.fold(a).includes(Fuzzy.fold(q))))
                continue;
            cards.push({
                id: id,
                active: ws?.active ?? false,
                urgent: ws?.urgent ?? false,
                apps: apps,
                count: wins.length,
                // the most recently focused window of the workspace is drawn lighter
                windows: wins.map(w => ({ bounds: w.bounds, recent: w.recency === Math.min(...wins.map(x => x.recency)) }))
            });
        }
        return cards;
    }

    // A card of rows (System mode). The whole card shows when the query matches its name or any row.
    function card(name: string, q: string, rows): var {
        if (q && !Fuzzy.match(q, name) && !rows.some(r => Fuzzy.match(q, r.title)))
            return [];
        return rows.map((r, i) => Object.assign({}, r, { card: rows.length === 1 ? "single" : i === 0 ? "top" : i === rows.length - 1 ? "bottom" : "middle" }));
    }

    // a switch row: on/off with a live status line; Enter or the switch toggles it
    function bluetoothSwitch(): var {
        return { kind: "switch", key: "bluetooth", title: "Bluetooth", icon: Icons.bluetooth, on: () => Bluetooth.enabled, status: () => Bluetooth.summary, toggle: () => Bluetooth.setEnabled(!Bluetooth.enabled) };
    }

    function systemRows(q: string): var {
        const audio = [{ kind: "slider", key: "volume", title: "Volume" }];
        if (Audio.source)
            audio.push({ kind: "slider", key: "mic", title: "Microphone" });
        if (Brightness.available)
            audio.push({ kind: "slider", key: "brightness", title: "Brightness" });
        const night = [{ kind: "switch", key: "nightlight", title: "Night light", icon: Icons.moon, on: () => NightLight.enabled, status: () => NightLight.status, toggle: () => NightLight.setEnabled(!NightLight.enabled) }];
        if (NightLight.available)
            night.push({ kind: "slider", key: "warmth", title: "Warmth" },
                { kind: "switch", key: "schedule", title: "Schedule", icon: Icons.clock, on: () => NightLight.scheduled, status: () => NightLight.scheduleText, toggle: () => NightLight.setSchedule(!NightLight.scheduled, NightLight.from, NightLight.to) },
                { kind: "time", key: "from", title: "Turns on", minutes: () => NightLight.from, set: m => NightLight.setSchedule(NightLight.scheduled, m, NightLight.to) },
                { kind: "time", key: "to", title: "Turns off", minutes: () => NightLight.to, set: m => NightLight.setSchedule(NightLight.scheduled, NightLight.from, m) });
        // Do not disturb and its schedule, with its own times or night light's (owner's request, after phase 8)
        const dnd = [
            { kind: "switch", key: "dnd", title: "Do not disturb", icon: Icons.bellOff, on: () => Notifs.dnd, status: () => Notifs.dndStatus, toggle: () => Notifs.setDnd(!Notifs.dnd) },
            { kind: "switch", key: "dndSchedule", title: "Schedule", icon: Icons.clock, on: () => Notifs.dndScheduled, status: () => Notifs.dndScheduleText, toggle: () => Notifs.setDndSchedule(!Notifs.dndScheduled) },
            { kind: "switch", key: "dndNight", title: "Night light's times", icon: Icons.moon, on: () => Notifs.dndFollowsNight, status: () => Notifs.dndFollowsNight ? `${NightLight.timeText(Notifs.dndFrom)}–${NightLight.timeText(Notifs.dndTo)}, as night light` : "Its own times below", toggle: () => Notifs.setDndFollowsNight(!Notifs.dndFollowsNight) }
        ];
        if (!Notifs.dndFollowsNight)
            dnd.push({ kind: "time", key: "dndFrom", title: "Turns on", minutes: () => Notifs.dndFrom, set: m => Notifs.setDndTimes(m, Notifs.dndTo) },
                { kind: "time", key: "dndTo", title: "Turns off", minutes: () => Notifs.dndTo, set: m => Notifs.setDndTimes(Notifs.dndFrom, m) });
        const bluetooth = [bluetoothSwitch(), { kind: "btlink", key: "btlink", title: "Scan for devices" }];
        // the apps with a notification rule (set from a card's right click); switching one off undoes it
        const rules = Object.keys(Notifs.rules).sort().map(app => ({ kind: "switch", key: "rule:" + app, title: app || "Unnamed app", icon: Icons.bellOff, on: () => true, status: () => Notifs.ruleText(app), toggle: () => Notifs.setRule(app, null) }));
        const cards = card("Audio", q, audio).concat(card("Night light", q, night), card("Do not disturb", q, dnd), card("Notification rules", q, rules), card("Bluetooth", q, bluetooth));
        cards.forEach((r, i) => r.gap = i > 0 && (r.card === "top" || r.card === "single") ? 10 : 0);
        const streams = Audio.streams.map(n => ({ kind: "slider", key: "stream:" + n.id, title: Audio.appName(n), node: n }));
        const devices = Audio.sinks.map(n => ({ kind: "device", key: "device:" + n.id, title: Audio.deviceName(n), node: n }));
        // an input with nothing plugged in is greyed out, and the keys pass it by
        const inputs = Audio.sources.map(n => ({ kind: "device", key: "input:" + n.id, title: Audio.deviceName(n), node: n, input: true, off: Audio.isUnplugged(n) }));
        const keep = r => !q || Fuzzy.match(q, r.title);
        // mounted USB drives (owner's request, 30 October 2026): Enter ejects one
        const drives = Drives.mounted.map(m => ({ kind: "drive", key: "drive:" + m.path, title: m.name, subtitle: `${m.mountpoint} · ${m.size}`, glyph: Icons.hardDrive, drive: m })).filter(keep);
        const a = streams.filter(keep), d = devices.filter(keep), i = inputs.filter(keep);
        // the machine's load (owner's request; not on a board): readings, not controls, so the keys
        // pass them by; the GPU once nvidia-smi has answered
        const stats = [{ kind: "stat", key: "cpu", title: "CPU" }, { kind: "stat", key: "memory", title: "Memory" }];
        if (SystemStats.gpuFound)
            stats.push({ kind: "stat", key: "gpu", title: "GPU" });
        // free space (owner's request, after phase 8): one row when /home is on the root filesystem
        const mounts = SystemStats.diskMounts;
        for (const m of mounts)
            stats.push({ kind: "stat", key: "disk:" + m, title: mounts.length === 1 ? "Disk" : m === "/" ? "System disk" : "Home" });
        const monitor = card("System monitor", q, stats);
        // the shell's own look, at the end (owner's request; not on the board)
        const shell = card("Shell settings", q, [
            { kind: "switch", key: "frosted", title: "Frosted panels", icon: Icons.layers, on: () => ShellSettings.frosted, status: () => ShellSettings.frosted ? "See-through bar and panels, blurred behind" : "Off: needs a line in Hyprland's config (README)", toggle: () => ShellSettings.setFrosted(!ShellSettings.frosted) },
            ...(ShellSettings.frosted ? [{ kind: "switch", key: "glassy", title: "Glassy", icon: Icons.sparkles, on: () => ShellSettings.glassy, status: () => ShellSettings.glassy ? "More see-through, less contrast" : "Subtle: easier to read", toggle: () => ShellSettings.setGlassy(!ShellSettings.glassy) }] : []),
            { kind: "switch", key: "shadows", title: "Drop shadows", icon: Icons.layers, on: () => ShellSettings.shadows, status: () => ShellSettings.shadows ? "Under panels and popups" : "Off", toggle: () => ShellSettings.setShadows(!ShellSettings.shadows) },
            { kind: "wplink", key: "wplink", title: "Wallpapers", subtitle: Wallpapers.current.split("/").pop() || "None", glyph: Icons.image },
            { kind: "showoff", key: "showoff", title: "Showoff mode", subtitle: "Everything open for a screenshot, private things hidden", glyph: Icons.sparkles },
            { kind: "aboutlink", key: "about", title: "About", subtitle: "Pistachio Noir Shell: version, commit, Quickshell and Hyprland", glyph: Icons.info },
            { kind: "termlink", key: "terminal", title: "Terminal", subtitle: Apps.terminalName(Apps.terminal), glyph: Icons.terminal },
            { kind: "setting", key: "weatherCity", title: "Weather location", subtitle: Weather.placeName, glyph: Icons.mapPin, setting: weatherSetting },
            { kind: "switch", key: "desktopIcons", title: "Desktop icons", icon: Icons.folder, on: () => Desktop.enabled, status: () => Desktop.enabled ? "The Desktop folder, on the wallpaper" : "Off", toggle: () => Desktop.setEnabled(!Desktop.enabled) },
            { kind: "switch", key: "workspaceOsd", title: "Workspace OSD", icon: Icons.layers, on: () => ShellSettings.workspaceOsd, status: () => ShellSettings.workspaceOsd ? "Shows which workspace you switched to" : "Off", toggle: () => ShellSettings.setWorkspaceOsd(!ShellSettings.workspaceOsd) },
            { kind: "switch", key: "volumeTick", title: "Volume tick", icon: Icons.volume, on: () => ShellSettings.volumeTick, status: () => ShellSettings.volumeTick ? "A short click as the volume changes" : "Off", toggle: () => ShellSettings.setVolumeTick(!ShellSettings.volumeTick) },
            { kind: "switch", key: "notificationSound", title: "Notification sound", icon: Icons.volume, on: () => ShellSettings.notificationSound, status: () => ShellSettings.notificationSound ? "A soft sound with each toast" : "Off", toggle: () => ShellSettings.setNotificationSound(!ShellSettings.notificationSound) },
            { kind: "switch", key: "quietFullscreen", title: "Quiet in fullscreen", icon: Icons.bellOff, on: () => ShellSettings.quietFullscreen, status: () => ShellSettings.quietFullscreen ? "Toasts wait while a fullscreen window has focus" : "Off", toggle: () => ShellSettings.setQuietFullscreen(!ShellSettings.quietFullscreen) },
            { kind: "switch", key: "headphonesTakeOver", title: "Headphones take over", icon: Icons.headphones, on: () => ShellSettings.headphonesTakeOver, status: () => ShellSettings.headphonesTakeOver ? "Bluetooth headphones get the sound as they connect" : "Off: the output stays as you chose", toggle: () => ShellSettings.setHeadphonesTakeOver(!ShellSettings.headphonesTakeOver) },
            { kind: "switch", key: "quietCalls", title: "Quiet during calls", icon: Icons.mic, on: () => ShellSettings.quietCalls, status: () => ShellSettings.quietCalls ? "Toasts wait while an app uses the microphone" : "Off", toggle: () => ShellSettings.setQuietCalls(!ShellSettings.quietCalls) }
        ]);
        return cards.concat(drives.length ? [section("Drives")].concat(drives) : [], a.length ? [section("Apps")].concat(a) : []).concat(d.length ? [section("Output device")].concat(d) : []).concat(i.length ? [section("Input device")].concat(i) : []).concat(monitor.length ? [section("System monitor")].concat(monitor) : []).concat(shell.length ? [section("Shell settings")].concat(shell) : []);
    }

    function bluetoothRows(q: string): var {
        const rows = [bluetoothSwitch()];
        if (!Bluetooth.enabled)
            return rows;
        const device = (h, compact) => ({ kind: "btdevice", key: "bt:" + h.item.address, title: Bluetooth.name(h.item), indices: h.indices, compact: compact, device: h.item });
        const paired = ranked(Bluetooth.paired, q, d => Bluetooth.name(d), 100).map(h => device(h, false));
        const nearby = ranked(Bluetooth.nearby, q, d => Bluetooth.name(d), 100).map(h => device(h, true));
        return rows
            .concat(paired.length ? [section("Paired devices")].concat(paired) : [])
            .concat([{ kind: "section", key: "section:scan", title: "Scanning for new devices", spinner: true }])
            .concat(nearby.length ? nearby : [{ kind: "empty", key: "nearby", title: Bluetooth.scanning ? "Looking…" : "No new devices found" }]);
    }

    // The terminals to choose from (owner's request, 30 October 2026), opened from Shell settings as
    // Bluetooth's devices are from its card; Enter uses one and goes back
    function terminalRows(q: string): var {
        const rows = Apps.terminalChoices.filter(t => !q || Fuzzy.match(q, Apps.terminalName(t)) || Fuzzy.match(q, t)).map(t => ({
            kind: "terminal", key: "term:" + t, title: Apps.terminalName(t), subtitle: t === Apps.terminal ? "current" : "", icon: Apps.terminalIcon(t), glyph: Icons.terminal, name: t
        }));
        return [section(`Terminals installed · for $ commands, terminal apps and showoff`)].concat(rows);
    }

    // back from Terminals to System, at its Terminal row
    function leaveTerminals() {
        const key = mode === "about" ? "about" : "terminal";
        field.text = "";
        mode = "system";
        const i = rows.findIndex(r => r.key === key);
        if (i >= 0) {
            current = i;
            heldKey = key;
            backToRow.restart();
        }
    }

    // Named workspaces matching the search, and presets (owner's request, 3 November 2026): Enter goes
    // to the workspace, or loads the preset
    function namedRows(q: string): var {
        return Object.entries(Compositor.names).filter(([id, name]) => !q || Fuzzy.match(q, name)).map(([id, name]) => {
            const apps = [...new Set(windows.filter(w => String(w.workspace) === id).map(w => Apps.nameFor(w.appId)))];
            return { kind: "wsname", key: "wsname:" + id, title: name, subtitle: `Workspace ${id} · ${apps.length ? apps.join(", ") : "empty"}`, glyph: Icons.layers, id: parseInt(id) };
        });
    }

    function presetRows(q: string): var {
        return Compositor.presets.filter(p => !q || Fuzzy.match(q, p.name)).map(p => {
            const names = Object.entries(p.names).sort((a, b) => a[0] - b[0]).map(([id, n]) => `${id} ${n}`).join(", ");
            const apps = Object.values(p.apps ?? {}).reduce((sum, list) => sum + list.length, 0);
            return { kind: "preset", key: "preset:" + p.name, title: p.name, subtitle: names + (apps ? ` · opens ${apps} app${apps === 1 ? "" : "s"}` : ""), glyph: Icons.sparkles, preset: p };
        });
    }

    // every workspace: its name, and with the second its apps too
    function presetSaveRows(): var {
        const count = Object.keys(Compositor.names).length;
        return [
            { kind: "presetsave", key: "presetsave", title: "Save workspaces as preset…", subtitle: count ? `Their names: ${count} named` : "Name a workspace first: F2 on its card", glyph: Icons.plus, withApps: false, off: !count },
            { kind: "presetsave", key: "presetsave:apps", title: "Save workspaces and apps as preset…", subtitle: "Every workspace's name and apps; loading opens the apps again there", glyph: Icons.plus, withApps: true }
        ];
    }

    // → on a preset: its Delete row, under it (as an app's actions)
    function presetDeleteRow(presetRow): var {
        return { kind: "presetdelete", key: presetRow.key + ":delete", title: `Delete “${presetRow.preset.name}”`, subtitle: "Asks first", glyph: Icons.trash, compact: true, indent: 24, preset: presetRow.preset };
    }

    function askDeletePreset(name: string) {
        confirming = { id: "preset:" + name, title: "Delete", icon: Icons.trash, danger: true, question: `Delete the preset “${name}”?`, confirm: "Only the preset goes: your workspaces and their names stay as they are.", run: () => Compositor.deletePreset(name) };
        current = 0;
        column = 0; // Cancel first
    }

    // About the shell (owner's request, 3 November 2026), opened from Shell settings like Terminals:
    // read-only lines, and Enter on the repository's opens it
    function aboutRows(): var {
        const line = (key, title, subtitle, glyph, url) => ({ kind: url ? "abouturl" : "aboutline", key: "about:" + key, title: title, subtitle: subtitle, glyph: glyph, url: url ?? "" });
        const version = About.commit ? `${About.commits} commits · ${About.commit}, ${Qt.formatDate(new Date(About.date + "T12:00"), "d MMMM yyyy")}` : "Reading…";
        return [section("Pistachio Noir Shell")].concat([
            line("version", "Version", version + (About.changed ? ` · ${About.changed} files changed since` : ""), Icons.sparkles),
            line("commit", "Last change", About.subject || "…", Icons.pencil),
            line("quickshell", "Quickshell", About.quickshell || "…", Icons.layers),
            line("hyprland", "Hyprland", About.hyprland || "…", Icons.monitor),
            line("qt", "Qt", About.qt || "…", Icons.cpu),
            line("repo", "Source", About.repo || "…", Icons.folderOpen, About.repo)
        ]);
    }

    // Power actions, found by name or a common word for them. All but Lock ask first.
    readonly property var powerActions: [
        { id: "lock", title: "Lock", icon: Icons.lock, words: ["lock screen"], run: () => Session.lock() },
        { id: "logout", title: "Log out", icon: Icons.logOut, words: ["logout", "sign out"], confirm: "Open apps close, and unsaved work in them is lost.", run: () => Session.logout() },
        { id: "suspend", title: "Suspend", icon: Icons.moon, words: ["sleep"], confirm: "The screen locks first.", run: () => Session.suspend() },
        { id: "reboot", title: "Reboot", icon: Icons.reboot, words: ["restart"], confirm: "Open apps close, and unsaved work in them is lost.", run: () => Session.reboot() },
        { id: "shutdown", title: "Shut down", icon: Icons.power, words: ["shutdown", "power off", "poweroff", "turn off"], confirm: "Open apps close, and unsaved work in them is lost.", danger: true, run: () => Session.shutdown() }
    ]

    function powerRows(q: string): var {
        if (!q)
            return [];
        const lower = Fuzzy.fold(q);
        const hits = powerActions.map(a => ({ a: a, m: Fuzzy.match(q, a.title) })).filter(h => h.m || h.a.words.some(w => w.includes(lower)));
        const rows = hits.map(h => ({ kind: "power", key: "power:" + h.a.id, title: h.a.title, subtitle: h.a.confirm ? "Asks first" : "Locks the screen right away", indices: h.m?.indices ?? [], glyph: h.a.icon, danger: h.a.danger ?? false, action: h.a }));
        return rows.length ? [section("Power")].concat(rows) : [];
    }

    // the answer when the query is a calculation, e.g. "12*3"; shown only (no clipboard, owner's call)
    // Emoji, only after a ":" (owner's request, after phase 8): names first, then keywords; with
    // nothing after it, the ones copied lately, then all of them in Unicode's order.
    function emojiRows(q: string): var {
        const row = (e, indices, prefix) => ({ kind: "emoji", key: prefix + e[0], title: e[1], subtitle: e[2], emoji: e[0], indices: indices });
        if (!q) {
            const recent = Clipboard.recentEmoji.map(c => Emoji.list.find(e => e[0] === c)).filter(e => e);
            return (recent.length ? [section("Recently used")].concat(recent.map(e => row(e, [], "recent:"))) : [])
                .concat([section("Emoji")], Emoji.list.map(e => row(e, [], "emoji:")));
        }
        const named = ranked(Emoji.list, q, e => e[1], 60);
        const seen = new Set(named.map(h => h.item[0]));
        const tagged = ranked(Emoji.list.filter(e => !seen.has(e[0])), q, e => e[2], 60 - named.length);
        const hits = named.map(h => row(h.item, h.indices, "emoji:")).concat(tagged.map(h => row(h.item, [], "emoji:")));
        return hits.length ? [section("Emoji")].concat(hits) : [];
    }

    // A command after a "$" (owner's request, after phase 8): the typed one first, then the recent
    // ones that match; Enter runs it in the terminal, Shift+Enter in the background.
    function commandRows(q: string): var {
        const row = (c, prefix) => ({ kind: "command", key: prefix + c, title: c, command: c, subtitle: `In ${Apps.terminal} · Shift+Enter: in the background`, glyph: Icons.terminal });
        const recent = ranked(Apps.recentCommands.filter(c => c !== q), q, c => c, 20).map(h => Object.assign(row(h.item, "recent:"), { indices: h.indices }));
        const typed = q ? [section("Run"), row(q, "run:")] : [];
        const rows = typed.concat(recent.length ? [section("Recent commands")].concat(recent) : []);
        return rows.length ? rows : [{ kind: "empty", key: "empty", title: `Type a command to run it in ${Apps.terminal}` }];
    }

    // A web search after an "@" (owner's request, 30 October 2026)
    function webRows(q: string): var {
        return q ? [section("Web"), { kind: "web", key: "web", title: q, subtitle: "Search DuckDuckGo", glyph: Icons.search }]
            : [{ kind: "empty", key: "empty", title: "Type to search the web with DuckDuckGo" }];
    }

    // Files and folders in the home folder after a "/" (owner's request, after phase 8), found by
    // services/files.py (Files). Its answer to the last query stays until the next one comes, kept to
    // what still matches, so typing narrows the list at once. A query with a "/" matches the path.
    function fileRows(q: string): var {
        const waiting = { kind: "empty", key: "empty", title: "Looking through your home folder…" };
        if (!q)
            return [Files.ready ? { kind: "empty", key: "empty", title: `Type to search ${Files.count.toLocaleString()} files and folders in your home folder` } : waiting];
        const byPath = q.includes("/");
        const rows = [];
        for (const e of Files.results) {
            const m = Fuzzy.match(q, byPath ? e.path : e.name);
            if (!m)
                continue;
            const from = e.path.length - e.name.length; // the name's place in the path
            rows.push({ kind: "file", key: "file:" + e.path, title: e.name, indices: byPath ? m.indices.filter(i => i >= from).map(i => i - from) : m.indices, subtitle: Files.place(e), glyph: e.folder ? Icons.folder : Icons.file, entry: e });
        }
        return rows.length ? [section("Home folder")].concat(rows) : [Files.ready ? { kind: "empty", key: "empty", title: "No matches" } : waiting];
    }

    // Notifications after a "!" (owner's request, after phase 8): matches in the summary first, then
    // the body or the app, newest first otherwise; Enter shows one in the notification centre. With
    // nothing typed, all of them under Clear all, which asks first.
    function notificationRows(q: string): var {
        const all = Notifs.notifications;
        if (!all.length)
            return [{ kind: "empty", key: "empty", title: "No notifications" }];
        const now = new Date();
        const row = (n, indices) => ({
            kind: "notification",
            key: "notification:" + all.indexOf(n),
            title: n.summary || n.appName || "Notification",
            indices: n.summary ? indices : [],
            subtitle: [n.appName, Notifs.age(Notifs.received(n), now), n.body.replace(/\s+/g, " ")].filter(x => x).join(" · "),
            icon: Notifs.iconSource(n),
            glyph: Notifs.own(n) ? Icons.region : Icons.bell,
            danger: Notifs.isCritical(n),
            notification: n
        });
        if (!q) {
            const clear = { id: "clearNotifications", title: "Clear all", question: "Clear all notifications?", icon: Icons.trash, danger: true, confirm: `All ${all.length} go, from the notification centre too.`, run: () => Notifs.clearAll() };
            return [{ kind: "power", key: "power:clear", title: clear.title, subtitle: `${all.length} notification${all.length === 1 ? "" : "s"} · asks first`, glyph: clear.icon, danger: true, action: clear }, section("Notifications")].concat(all.map(n => row(n, [])));
        }
        const named = ranked(all, q, n => n.summary, 100);
        const seen = new Set(named.map(h => h.item));
        const folded = Fuzzy.fold(q);
        const other = all.filter(n => !seen.has(n) && Fuzzy.fold(`${n.body} ${n.appName ?? ""}`).includes(folded));
        const rows = named.map(h => row(h.item, h.indices)).concat(other.map(n => row(n, [])));
        return rows.length ? [section("Notifications")].concat(rows) : [];
    }

    function calcRows(q: string): var {
        const v = Calc.evaluate(q);
        return v === null ? [] : [{ kind: "calc", key: "calc", title: "= " + Calc.format(v), subtitle: q.trim() }];
    }

    // The agent's question, worded for the launcher; the last choice accepts. Codes to type on the
    // device show a cursor under the next key once the device reports the keys typed.
    function pairingQuestion(r): var {
        const name = Bluetooth.requestName;
        const q = { icon: Icons.bluetooth, title: `Pair with ${name}?`, text: "", code: "", entered: -1, input: false, choices: ["Cancel", "Pair"] };
        if (r.kind === "confirm") {
            q.text = "Pair only if the device shows the same code.";
            q.code = r.code;
        } else if (r.kind === "authorize") {
            q.text = "The device asks to pair with this computer.";
            q.choices = ["Decline", "Pair"];
        } else if (r.kind === "service") {
            q.title = `Let ${name} use ${Bluetooth.serviceName(r.uuid)}?`;
            q.text = "The device is paired but not trusted, so it asks each time.";
            q.choices = ["Decline", "Allow"];
        } else if (r.kind === "pin") {
            q.text = "Type the PIN the device shows or its manual gives (often 0000), then press Enter.";
            q.input = true;
        } else if (r.kind === "passkey") {
            q.text = "Type the 6-digit code the device shows, then press Enter.";
            q.input = true;
        } else { // display-pin, display-passkey
            q.title = `Pairing with ${name}`;
            q.text = "Type this code on the device, then press Enter on it.";
            q.code = r.code;
            q.entered = r.entered;
            q.choices = ["Cancel"];
        }
        return q;
    }

    // (windows and workspaces are parameters only so the binding re-runs when a snapshot is taken)
    function buildRows(mode: string, q: string, windows, workspaces): var {
        if (Bluetooth.request)
            return [{ kind: "pairing", key: "pairing", question: pairingQuestion(Bluetooth.request) }];
        if (editing)
            return [{ kind: "edit", key: "edit", question: { icon: editing.icon, title: editing.title, text: editBusy ? `Looking up “${q.trim()}”…` : editError || editing.hint(), error: editError !== "", code: "", entered: -1, input: true, choices: ["Cancel", "Save"] } }];
        if (confirming)
            return [{ kind: "confirm", key: "confirm:" + confirming.id, action: confirming, question: { icon: confirming.icon, danger: confirming.danger ?? false, title: confirming.question ?? `${confirming.title}?`, text: confirming.confirm, choices: ["Cancel", confirming.title] } }];
        let rows;
        if (q.startsWith(":") && (mode === "all" || mode === "apps")) {
            rows = emojiRows(q.slice(1).trim());
        } else if (q.startsWith("$") && (mode === "all" || mode === "apps")) {
            rows = commandRows(q.slice(1).trim());
        } else if (q.startsWith("/") && (mode === "all" || mode === "apps")) {
            rows = fileRows(q.slice(1).trim());
        } else if (q.startsWith("!") && (mode === "all" || mode === "apps")) {
            rows = notificationRows(q.slice(1).trim());
        } else if (q.startsWith("@") && (mode === "all" || mode === "apps")) {
            rows = webRows(q.slice(1).trim());
        } else if (q.startsWith("?") && (mode === "all" || mode === "apps")) {
            rows = cheatRows(q.slice(1).trim());
        } else if (mode === "apps") {
            const frequent = q ? [] : frequentRows(5);
            rows = calcRows(q).concat(frequent.length ? [section("Frequent")].concat(frequent) : [], [section("Applications")], appRows(q, 200));
        } else if (mode === "windows") {
            const w = windowRows(q, 50);
            rows = [section(`${w.length} window${w.length === 1 ? "" : "s"} · most recent first`)].concat(w);
        } else if (mode === "workspaces") {
            const cards = workspaceCards(q), named = q ? namedRows(q) : [], presets = presetRows(q);
            rows = [section(`${cards.length} workspaces`)].concat(cards.length ? [{ kind: "workspaces", key: "workspaces", cards: cards }] : [])
                .concat(named.length ? [section("Named")].concat(named) : [])
                .concat([section("Presets")], presets, q ? [] : presetSaveRows());
        } else if (mode === "system") {
            rows = systemRows(q).concat(powerRows(q));
        } else if (mode === "bluetooth") {
            rows = bluetoothRows(q);
        } else if (mode === "terminals") {
            rows = terminalRows(q);
        } else if (mode === "about") {
            rows = aboutRows();
        } else if (!q) {
            const w = windowRows("", 5).map(r => Object.assign(r, { compact: true }));
            rows = [section("Quick controls"), { kind: "controls", key: "controls" }].concat(w.length ? [section("Open windows")].concat(w) : []);
        } else {
            const a = appRows(q, 5), w = windowRows(q, 3), named = namedRows(q), presets = presetRows(q);
            rows = calcRows(q).concat(a.length ? [section("Applications")].concat(a) : []).concat(w.length ? [section("Windows")].concat(w) : [])
                .concat(named.length ? [section("Workspaces")].concat(named) : [], presets.length ? [section("Presets")].concat(presets) : [])
                .concat(powerRows(q), systemRows(q));
        }
        if (expandedKey)
            rows = rows.reduce((all, r) => all.concat([r], r.key !== expandedKey ? [] : r.kind === "app" ? actionRows(r) : r.kind === "preset" ? [presetDeleteRow(r)] : []), []); // flatMap isn't there
        // "claude" and a question (owner's request, 1 November 2026): an Ask Claude row on top, while
        // Claude Desktop is installed; the usual results stay under it ("claude code" still finds apps)
        const asked = (mode === "all" || mode === "apps") && Apps.claudeApp ? /^claude\s+(\S.*)$/i.exec(q) : null;
        if (asked)
            rows = [section("Claude"), { kind: "claude", key: "claude", title: asked[1].trim(), subtitle: "Ask Claude: a new chat in Claude Desktop", icon: Apps.icon(Apps.claudeApp.icon), prompt: asked[1].trim() }].concat(rows);
        return rows.some(r => r.kind !== "section") ? rows : rows.concat([{ kind: "empty", key: "empty", title: "No matches" }]);
    }

    // Quick controls (All mode): Volume and Brightness open System mode, Bluetooth its device view.
    readonly property var controls: [
        { id: "volume", label: "Volume", value: Audio.muted ? "Muted" : `${Math.round(Audio.volume * 100)}%`, icon: Audio.muted ? Icons.volumeMuted : Icons.volume },
        { id: "brightness", label: "Brightness", value: Brightness.available ? `${Math.round(Brightness.value * 100)}%` : "—", icon: Icons.sun },
        { id: "bluetooth", label: "Bluetooth", value: Bluetooth.enabled ? "On" : "Off", icon: Icons.bluetooth },
        { id: "ethernet", label: "Ethernet", value: Network.connected ? (Network.speed >= 1000 ? `${Network.speed / 1000} Gbps` : `${Network.speed} Mbps`) : "Off", icon: Icons.ethernet }
    ]

    // ---- selection and actions ------------------------------------------------------------------

    function selectable(i: int): bool {
        return i >= 0 && i < rows.length && !["section", "empty", "calc", "stat"].includes(rows[i].kind) && !rows[i].off;
    }

    function step(from: int, dir: int): int {
        for (let i = from + dir; i >= 0 && i < rows.length; i += dir) {
            if (selectable(i))
                return i;
        }
        return selectable(from) ? from : -1;
    }

    // a workspace grid starts at the active one; a question at Cancel, unless a code is typed for it
    function resetSelection() {
        current = step(-1, 1);
        const row = rows[current];
        column = row?.cards ? Math.max(0, row.cards.findIndex(c => c.active)) : row?.question?.input ? 1 : 0;
    }

    // (while a code is typed, ←→ move the cursor in it)
    function gridLength(row): int {
        return row.kind === "workspaces" ? row.cards.length : row.kind === "controls" ? controls.length : row.question && !row.question.input ? row.question.choices.length : 0;
    }

    function adjust(row, dir: int) {
        if (row.node) // an app's volume
            Audio.setStreamVolume(row.node, row.node.audio.volume + dir * 0.05);
        else if (row.key === "volume")
            Audio.setVolume(Audio.volume + dir * 0.05);
        else if (row.key === "mic")
            Audio.setMicVolume(Audio.micVolume + dir * 0.05);
        else if (row.key === "brightness")
            Brightness.set(Brightness.value + dir * 0.05);
        else if (row.key === "warmth")
            NightLight.setTemperature(Math.max(2500, Math.min(6500, NightLight.temperature + dir * 250)));
        else if (row.kind === "time")
            row.set(row.minutes() + dir * 15);
    }

    function activate(row, col: int, shift: bool) {
        if (row.kind === "app") {
            Apps.launch(row.app);
            open = false;
        } else if (row.kind === "cheat") {
            if (row.prefix)
                field.text = row.prefix;
        } else if (row.kind === "appaction") {
            Apps.launchAction(row.app, row.action);
            open = false;
        } else if (row.kind === "window") {
            Compositor.focus(row.address);
            open = false;
        } else if (row.kind === "workspaces") {
            const card = row.cards[col];
            if (!card)
                return;
            // the launcher holds the keyboard, so "the focused window" is the most recently focused one
            const last = windows.slice().sort((a, b) => a.recency - b.recency)[0];
            if (shift && last)
                Compositor.moveWindow(last.address, card.id);
            else
                Compositor.goto(card.id);
            open = false;
        } else if (row.kind === "controls") {
            const id = controls[col].id;
            if (id === "bluetooth")
                mode = "bluetooth";
            else if (id === "volume" || id === "brightness")
                mode = "system";
        } else if (row.kind === "device") {
            if (row.input)
                Audio.setSource(row.node);
            else
                Audio.setSink(row.node);
        } else if (row.kind === "slider" && row.node) {
            Audio.toggleStreamMute(row.node);
        } else if (row.kind === "slider" && row.key === "volume") {
            Audio.toggleMute();
        } else if (row.kind === "slider" && row.key === "mic") {
            Audio.toggleMicMute();
        } else if (row.kind === "command") {
            Apps.run(row.command, !shift);
            open = false;
        } else if (row.kind === "drive") {
            Drives.eject(row.drive);
        } else if (row.kind === "claude") {
            Apps.askClaude(row.prompt);
            open = false;
        } else if (row.kind === "web") {
            Apps.searchWeb(row.title);
            open = false;
        } else if (row.kind === "notification") {
            open = false;
            notificationRequested(row.notification);
        } else if (row.kind === "file") {
            if (shift)
                Files.reveal(row.entry);
            else
                Files.open(row.entry);
            open = false;
        } else if (row.kind === "wplink") {
            open = false;
            wallpapersRequested();
        } else if (row.kind === "setting") {
            startEditing(row.setting);
        } else if (row.kind === "wsname") {
            Compositor.goto(row.id);
            open = false;
        } else if (row.kind === "preset") {
            Compositor.loadPreset(row.preset);
            open = false;
        } else if (row.kind === "presetdelete") {
            askDeletePreset(row.preset.name);
        } else if (row.kind === "presetsave") {
            const withApps = row.withApps;
            startEditing({
                key: row.key,
                title: withApps ? "Save workspaces and apps as preset" : "Save workspaces as preset",
                icon: Icons.sparkles,
                placeholder: "Preset name",
                hint: () => "Type its name, then press Enter. The same name replaces the old preset.",
                check: (text, then) => text.trim() ? then(text.trim().slice(0, 32), "") : then(null, "Type a name first."),
                apply: name => Compositor.savePreset(name, withApps)
            }, "");
        } else if (row.kind === "aboutlink") {
            field.text = "";
            About.load();
            mode = "about";
        } else if (row.kind === "abouturl") {
            Quickshell.execDetached(["xdg-open", row.url]);
            open = false;
        } else if (row.kind === "termlink") {
            field.text = "";
            mode = "terminals";
        } else if (row.kind === "terminal") {
            Apps.setTerminal(row.name);
            leaveTerminals();
        } else if (row.kind === "showoff") {
            open = false;
            Showoff.toggle();
        } else if (row.kind === "edit") {
            if (col === 0)
                stopEditing();
            else if (inputValid)
                saveEditing();
        } else if (row.kind === "emoji") {
            Clipboard.copyEmoji(row.emoji);
            open = false;
        } else if (row.kind === "btlink") {
            mode = "bluetooth";
        } else if (row.kind === "switch") {
            row.toggle();
        } else if (row.kind === "power" && row.action.confirm) {
            confirming = row.action;
            current = 0;
            column = 0; // Cancel first: a double Enter does nothing
        } else if (row.kind === "power") {
            open = false;
            row.action.run();
        } else if (row.kind === "confirm") {
            const action = row.action;
            confirming = null;
            if (col === 1) {
                open = false;
                action.run();
            }
        } else if (row.kind === "btdevice") {
            if (row.device.paired)
                Bluetooth.toggleConnection(row.device);
            else
                Bluetooth.pair(row.device);
        } else if (row.kind === "pairing") {
            if (row.question.input && col === 1 && !codeValid)
                return; // nothing to send yet
            Bluetooth.answer(col === 1, row.question.input ? query : "");
        }
    }

    function key(event) {
        const ctrl = event.modifiers & Qt.ControlModifier, shift = event.modifiers & Qt.ShiftModifier;
        const row = rows[current];
        // vim motions while Ctrl is held: Ctrl+H J K L work like ← ↓ ↑ → (the arrows still work)
        const vim = ctrl ? ({ [Qt.Key_H]: Qt.Key_Left, [Qt.Key_J]: Qt.Key_Down, [Qt.Key_K]: Qt.Key_Up, [Qt.Key_L]: Qt.Key_Right })[event.key] : undefined;
        const pressed = vim ?? event.key;
        const dir = pressed === Qt.Key_Right ? 1 : -1;
        konami = konami.concat([event.key]).slice(-konamiCode.length);
        if (konami.join() === konamiCode.join()) {
            konami = [];
            event.accepted = true;
            open = false;
            rainRequested();
            return;
        }
        event.accepted = false; // unhandled keys go on to the search field
        switch (pressed) {
        case Qt.Key_Escape:
            if (Bluetooth.request)
                Bluetooth.answer(false, ""); // back to the devices
            else if (confirming)
                confirming = null; // back to the results
            else if (editing)
                stopEditing();
            else if (mode === "terminals" || mode === "about")
                leaveTerminals();
            else
                open = false;
            break;
        case Qt.Key_F2:
            if (row?.kind === "workspaces" && row.cards[column] && !editing) {
                event.accepted = true;
                renameWorkspace(row.cards[column].id);
            }
            break;
        case Qt.Key_Tab:
        case Qt.Key_Backtab: {
            if (Bluetooth.request || editing)
                break; // answer it first
            const i = modes.findIndex(m => m.id === mode);
            mode = modes[(i + (event.key === Qt.Key_Backtab ? -1 : 1) + modes.length) % modes.length].id;
            break;
        }
        case Qt.Key_Down:
        case Qt.Key_Up:
            current = step(current, pressed === Qt.Key_Down ? 1 : -1);
            list.positionViewAtIndex(current, ListView.Contain);
            break;
        case Qt.Key_Left:
        case Qt.Key_Right:
            if (row?.kind === "slider" || row?.kind === "time")
                adjust(row, dir);
            else if (row && gridLength(row) > 0)
                column = Math.max(0, Math.min(gridLength(row) - 1, column + dir));
            // an app's actions: → opens them once the search's cursor is at its end (so → still moves
            // it while typing), ← closes them and goes back to the app
            else if (dir > 0 && (row?.kind === "app" && row.app.actions.length > 0 || row?.kind === "preset") && expandedKey !== row.key && field.cursorPosition === field.text.length) {
                expandedKey = row.key;
                current = step(current, 1);
            } else if (dir < 0 && expandedKey && (row?.kind === "appaction" || row?.kind === "presetdelete" || row?.key === expandedKey)) {
                const key = expandedKey;
                expandedKey = "";
                current = rows.findIndex(r => r.key === key);
            } else if (vim)
                field.cursorPosition = Math.max(0, Math.min(field.text.length, field.cursorPosition + dir));
            else
                return; // the search field moves its cursor
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (selectable(current))
                activate(row, column, shift);
            break;
        // Window actions on a window row (owner's request, after phase 8): Ctrl+W or Ctrl+Q close it,
        // Ctrl+F floats or tiles it, Ctrl+1–9 sends it to that workspace without following it. The
        // launcher stays open, and the row shows the change once Hyprland has made it.
        case Qt.Key_W:
        case Qt.Key_Q:
            if (!ctrl || row?.kind !== "window")
                return;
            Compositor.close(row.address);
            resnap.restart();
            break;
        case Qt.Key_F:
            if (!ctrl || row?.kind !== "window")
                return;
            Compositor.toggleFloating(row.address);
            resnap.restart();
            break;
        case Qt.Key_1:
        case Qt.Key_2:
        case Qt.Key_3:
        case Qt.Key_4:
        case Qt.Key_5:
        case Qt.Key_6:
        case Qt.Key_7:
        case Qt.Key_8:
        case Qt.Key_9:
            if (!ctrl || row?.kind !== "window")
                return;
            Compositor.sendWindow(row.address, pressed - Qt.Key_0);
            resnap.restart();
            break;
        case Qt.Key_M:
            if (!ctrl)
                return;
            Audio.toggleMute();
            break;
        case Qt.Key_Backspace:
            if (ctrl && row?.kind === "preset") { // asks first, Cancel chosen
                askDeletePreset(row.preset.name);
                break;
            }
            if (!ctrl || row?.kind !== "btdevice" || !row.device.paired)
                return;
            Bluetooth.forget(row.device);
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    onModeChanged: {
        expandedKey = "";
        list.enter(); // the new rows rise into place
        resetSelection();
    }
    onConfirmingChanged: list.enter() // a question in place of the results, or back from it
    onEditingChanged: list.enter()
    onQueryChanged: {
        confirming = null; // typing goes back to searching
        expandedKey = "";
        if (filesWanted)
            Files.search(query.slice(1).trim());
        resetSelection();
    }
    // rows also change under the launcher (windows open and close); keep the selection valid
    onRowsChanged: {
        const held = heldKey ? rows.findIndex(r => r.key === heldKey) : -1;
        if (held >= 0 && held !== current) {
            current = held;
            backToRow.restart();
        } else if (!selectable(current)) {
            resetSelection();
        }
    }

    onOpenChanged: {
        grab.active = open;
        hadKeyboard = false;
        if (!open) {
            editing = null; // closing leaves a setting as it was
            Bluetooth.answer(false, ""); // closing declines a question still waiting
        }
    }

    Connections {
        target: Bluetooth

        function onAsked() {
            if (!root.open)
                root.show("bluetooth");
            root.confirming = null;
            root.mode = "bluetooth"; // the devices are there once it's answered
            field.text = "";
            root.resetSelection();
        }

        function onRequestChanged() {
            if (!Bluetooth.request)
                field.text = ""; // never leave a typed code in the search
        }
    }

    // what a PIN (1–16 letters and digits) and a passkey (up to 6 digits) may hold
    RegularExpressionValidator {
        id: pinChars
        regularExpression: /[0-9A-Za-z]{0,16}/
    }
    RegularExpressionValidator {
        id: passkeyChars
        regularExpression: /\d{0,6}/
    }

    // ---- window ---------------------------------------------------------------------------------

    // The whole screen, clear around the panel, so a click anywhere beside it closes it (owner's request,
    // 1 November 2026): with the keyboard held exclusively, Hyprland's focus grab didn't clear on a
    // click in a window, and the launcher stayed up. That click only closes it, as with the power menu.
    visible: reveal.shown
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "pistachio-panel" // frosted panels: Hyprland blurs the shell's layers by name
    WlrLayershell.layer: WlrLayer.Overlay // above fullscreen windows
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive // typing goes here while it is open

    Reveal {
        id: reveal
        open: root.open
    }

    FocusGrab {
        id: grab
        windows: [root]
        onCleared: root.open = false
    }

    // It also closes when the keyboard goes elsewhere (owner's request, 1 November 2026): another layer
    // that takes it (the Alt+Tab switcher, a screenshot) or Hyprland focusing a window. Only once it has
    // had the keyboard, which comes a moment after it opens.
    property bool hadKeyboard

    Item {
        Window.onActiveChanged: {
            if (Window.active)
                root.hadKeyboard = true;
            else if (root.open && root.hadKeyboard)
                root.open = false;
        }
    }

    // A setting saved or left: its row, once the list has laid its rows out again (it scrolls to the
    // top as it does; Qt.callLater came too soon)
    Timer {
        id: backToRow
        interval: 50
        onTriggered: list.positionViewAtIndex(root.current, ListView.Contain)
    }

    // after a window action, show the list as it is once Hyprland has reported the change
    Timer {
        id: resnap
        interval: 300
        onTriggered: root.snapshot()
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            if (root.open)
                root.open = false;
            else
                root.show("all");
        }

        function open(mode: string): void {
            root.show(mode);
        }

        // opens with the search field filled in, e.g. `search apps fire`
        function search(mode: string, text: string): void {
            root.show(mode);
            field.text = text;
        }

        // one toggle per mode, for keybinds: `windows` opens Windows, switches to it, or closes it
        function apps(): void {
            root.toggleMode("apps");
        }
        function windows(): void {
            root.toggleMode("windows");
        }
        function workspaces(): void {
            root.toggleMode("workspaces");
        }
        function system(): void {
            root.toggleMode("system");
        }
        function bluetooth(): void {
            root.toggleMode("bluetooth");
        }
    }

    // beside the panel, not in it: the panel clips its children
    // a click beside the panel closes it
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: mouse => {
            if (!panel.contains(mapToItem(panel, mouse.x, mouse.y)))
                root.open = false;
        }
    }

    Shadow {
        id: shadow
        frostable: true
        kind: Theme.shadowModal
        anchors.fill: panel
        radius: panel.radius
        opacity: panel.opacity
    }

    Rectangle {
        id: panel

        x: Math.round((root.width - width) / 2)
        width: 640
        height: body.implicitHeight
        radius: Theme.panelRadius
        color: Theme.surface
        border.width: 1
        border.color: Theme.overlay2
        clip: true
        // fades in rising 12 px, and back
        opacity: reveal.progress
        y: Math.round(root.height * 0.12) + 12 * (1 - reveal.progress) // its top at 12 % of the screen

        Column {
            id: body
            width: parent.width

            // search
            Item {
                width: parent.width
                height: 68

                Icon {
                    id: searchIcon
                    x: 26
                    anchors.verticalCenter: parent.verticalCenter
                    size: 20
                    paths: Bluetooth.request ? Icons.bluetooth : root.editing ? root.editing.icon : Icons.search
                    color: Theme.subtext
                }

                TextInput {
                    id: field

                    anchors.left: searchIcon.right
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.rightMargin: 26
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.textBright
                    selectionColor: Theme.overlay2
                    selectedTextColor: Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    focus: true
                    clip: true
                    // takes only a code while the agent wants one, and nothing during its other questions
                    readOnly: !!Bluetooth.request && !root.codeWanted
                    validator: Bluetooth.request?.kind === "pin" ? pinChars : Bluetooth.request?.kind === "passkey" ? passkeyChars : null
                    Accessible.role: Accessible.EditableText
                    Accessible.name: root.placeholder
                    Keys.onPressed: event => root.key(event)

                    cursorDelegate: Rectangle {
                        width: 2
                        color: Theme.pistachio
                        opacity: field.readOnly ? 0 : 1
                    }

                    Text {
                        visible: field.text === ""
                        text: root.placeholder
                        color: Theme.subtext
                        font: field.font
                    }
                }
            }

            // mode tabs
            Item {
                width: parent.width
                height: 36 + 12

                // the active tab's chip, one for all of them, so it slides to the next
                Rectangle {
                    readonly property Item active: tabs.count > 0 ? tabs.itemAt(root.modes.findIndex(m => m.id === root.tab)) : null

                    x: tabRow.x + (active?.x ?? 0)
                    width: active?.width ?? 0
                    height: 36
                    radius: 18
                    color: Theme.overlay

                    Behavior on x {
                        NumberAnimation {
                            duration: Theme.motionDuration
                            easing.type: Theme.easing
                        }
                    }
                    Behavior on width {
                        NumberAnimation {
                            duration: Theme.motionDuration
                            easing.type: Theme.easing
                        }
                    }
                }

                Row {
                    id: tabRow

                    x: 18
                    spacing: 6

                    Repeater {
                        id: tabs

                        model: root.modes

                        Item {
                            required property var modelData
                            readonly property bool active: modelData.id === root.tab

                            width: tabLabel.implicitWidth + 32
                            height: 36
                            Accessible.role: Accessible.PageTab
                            Accessible.name: modelData.label
                            Accessible.selected: active

                            Text {
                                id: tabLabel
                                anchors.centerIn: parent
                                text: parent.modelData.label
                                color: parent.active ? Theme.pistachio : Theme.subtext
                                font.family: Theme.fontUi
                                font.pixelSize: 13
                                font.weight: Font.Bold

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.motionDuration
                                        easing.type: Theme.easing
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.mode = parent.modelData.id
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.overlay
                }
            }

            // results
            Item {
                width: parent.width
                height: list.height + 14 + 8

                ListView {
                    id: list

                    x: 8
                    y: 14
                    width: parent.width - 16
                    height: Math.min(contentHeight, 440)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    // The selection: one chip under the rows that glides from row to row (the rows don't
                    // draw their own). Grid rows and questions mark their choice inside, so it fades out
                    // on them.
                    property rect glide // the selected row's box, in the list's content
                    // A held arrow key repeats every 30 ms or so, faster than a glide: the chip lagged
                    // rows behind the selection. A move that soon after the last one jumps instead.
                    property real movedAt
                    property bool quick
                    readonly property bool glideShown: root.selectable(root.current) && !["controls", "workspaces", "confirm", "pairing", "edit"].includes(root.rows[root.current].kind)
                    // the ↵ chip rides on it, shown on result rows (ResultRow leaves it room)
                    readonly property bool enterShown: glideShown && ((root.rows[root.current].prefix ?? "") !== "" || ["app", "appaction", "window", "device", "btlink", "btdevice", "power", "emoji", "wplink", "setting", "termlink", "terminal", "showoff", "aboutlink", "abouturl", "wsname", "preset", "presetsave", "presetdelete", "command", "file", "notification", "web", "drive", "claude"].includes(root.rows[root.current].kind))
                    // Opening and switching mode: for a moment, new rows rise into place one after
                    // another and the chip jumps to its row instead of gliding.
                    property bool entering

                    function enter() {
                        entering = true;
                        entered.restart();
                    }

                    function glideTo(box: rect) {
                        const now = Date.now();
                        quick = now - movedAt < 100;
                        movedAt = now;
                        glide = box;
                    }

                    // a plain array, not a ScriptModel: with a ScriptModel, rows from the previous mode
                    // stayed on screen after a mode switch (seen in phase 6)
                    model: root.rows

                    Timer {
                        id: entered
                        interval: 100 // the rows are made at the next layout, well within this
                        onTriggered: list.entering = false
                    }

                    Rectangle {
                        // with the rows, so it scrolls with them: declared in a ListView it isn't put
                        // there by itself, and sat contentY off once the list scrolled (seen by the owner)
                        parent: list.contentItem
                        z: -1 // under the rows
                        x: list.glide.x
                        y: list.glide.y
                        width: list.glide.width
                        height: list.glide.height
                        radius: Theme.tileRadius
                        color: Theme.overlay2
                        opacity: list.glideShown ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.motionDuration
                                easing.type: Theme.easing
                            }
                        }
                        Behavior on x {
                            enabled: !list.entering && !list.quick
                            NumberAnimation {
                                duration: Theme.motionDuration
                                easing.type: Theme.easing
                            }
                        }
                        Behavior on y {
                            enabled: !list.entering && !list.quick
                            NumberAnimation {
                                duration: Theme.motionDuration
                                easing.type: Theme.easing
                            }
                        }
                        Behavior on width {
                            enabled: !list.entering && !list.quick
                            NumberAnimation {
                                duration: Theme.motionDuration
                                easing.type: Theme.easing
                            }
                        }
                        Behavior on height {
                            enabled: !list.entering && !list.quick
                            NumberAnimation {
                                duration: Theme.motionDuration
                                easing.type: Theme.easing
                            }
                        }

                        // ↵, at the right end as ResultRow lays it out (12 px in, centred)
                        Rectangle {
                            x: parent.width - 12 - width
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 26
                            radius: 13
                            color: Theme.pistachio
                            opacity: list.enterShown ? 1 : 0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Theme.motionDuration
                                    easing.type: Theme.easing
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "↵"
                                color: Theme.bg
                                font.family: Theme.fontUi
                                font.pixelSize: 12
                                font.weight: Font.ExtraBold
                            }
                        }
                    }

                    delegate: Item {
                        id: entry

                        required property var modelData
                        required property int index
                        readonly property bool selected: root.current === index
                        readonly property rect box: Qt.rect(loader.x, y + loader.y, loader.width, loader.height)

                        readonly property string card: modelData.card ?? "" // in a card: top, middle, bottom or single
                        readonly property bool cardTop: card === "top" || card === "single"
                        readonly property bool cardBottom: card === "bottom" || card === "single"
                        // space above: before a section, between cards, and a card's inner padding
                        readonly property int above: (modelData.kind === "section" && index > 0 ? 10 : 0) + (modelData.gap ?? 0) + (cardTop ? 6 : 0)

                        width: ListView.view.width
                        height: above + loader.height + (cardBottom ? 6 : 0)
                        transform: Translate {
                            id: rise
                        }

                        onSelectedChanged: if (selected) list.glideTo(box)
                        onBoxChanged: if (selected) list.glideTo(box)
                        // made while entering: fade in rising 8 px, 20 ms after the row above
                        Component.onCompleted: {
                            if (selected)
                                list.glideTo(box);
                            if (!list.entering)
                                return;
                            opacity = 0;
                            rise.y = 8;
                            arrive.start();
                        }

                        SequentialAnimation {
                            id: arrive

                            PauseAnimation {
                                duration: Math.min(entry.index, 8) * 20
                            }
                            ParallelAnimation {
                                NumberAnimation {
                                    target: entry
                                    property: "opacity"
                                    to: 1
                                    duration: Theme.motionDuration
                                    easing.type: Theme.easing
                                }
                                NumberAnimation {
                                    target: rise
                                    property: "y"
                                    to: 0
                                    duration: Theme.motionDuration
                                    easing.type: Theme.easing
                                }
                            }
                        }

                        // This row's slice of its card's outline: the outline is drawn taller than the row and
                        // clipped, so the slices of a card's rows join into one rounded card.
                        Item {
                            visible: entry.card !== ""
                            y: entry.modelData.gap ?? 0
                            width: parent.width
                            height: parent.height - y
                            clip: true

                            Rectangle {
                                y: entry.cardTop ? 0 : -40
                                width: parent.width
                                height: parent.height + (entry.cardTop ? 0 : 40) + (entry.cardBottom ? 0 : 40)
                                radius: Theme.tileRadius
                                color: "transparent"
                                border.width: 1
                                border.color: Theme.overlay2
                            }
                        }

                        Loader {
                            id: loader
                            x: entry.card ? 6 : 0
                            y: entry.above
                            width: parent.width - (entry.card ? 12 : 0)
                            sourceComponent: ({
                                section: sectionView,
                                empty: emptyView,
                                app: resultView,
                                appaction: resultView,
                                window: resultView,
                                device: resultView,
                                slider: sliderView,
                                stat: statView,
                                controls: controlsView,
                                workspaces: workspacesView,
                                btlink: resultView,
                                btdevice: resultView,
                                switch: switchView,
                                time: timeView,
                                calc: resultView,
                                emoji: resultView,
                                wplink: resultView,
                                setting: resultView,
                                termlink: resultView,
                                aboutlink: resultView,
                                wsname: resultView,
                                preset: resultView,
                                presetsave: resultView,
                                presetdelete: resultView,
                                aboutline: resultView,
                                abouturl: resultView,
                                terminal: resultView,
                                showoff: resultView,
                                command: resultView,
                                file: resultView,
                                notification: resultView,
                                web: resultView,
                                claude: resultView,
                                drive: resultView,
                                cheat: cheatView,
                                power: resultView,
                                confirm: questionView,
                                pairing: questionView,
                                edit: questionView
                            })[entry.modelData.kind]
                        }

                        Component {
                            id: sectionView

                            Row {
                                leftPadding: 18
                                bottomPadding: 8
                                spacing: 8

                                // turns while Bluetooth scans (the "Scanning for new devices" header)
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.verticalCenterOffset: -4
                                    visible: entry.modelData.spinner ?? false
                                    size: 12
                                    paths: Icons.loader
                                    color: Theme.subtext

                                    RotationAnimation on rotation {
                                        running: (entry.modelData.spinner ?? false) && Bluetooth.scanning
                                        loops: Animation.Infinite
                                        from: 0
                                        to: 360
                                        duration: 1000
                                    }
                                }

                                Text {
                                    text: entry.modelData.title.toUpperCase()
                                    color: Theme.subtext
                                    font.family: Theme.fontUi
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.9
                                }
                            }
                        }

                        Component {
                            id: cheatView

                            // A cheat sheet row: the keys or the prefix, drawn as the key hints are, and
                            // what it does. Rows for reading; Enter on a prefix puts it in the search.
                            Rectangle {
                                width: loader.width
                                height: 42
                                radius: Theme.tileRadius
                                color: "transparent" // selected: the list's chip shows through
                                Accessible.role: Accessible.ListItem
                                Accessible.name: `${entry.modelData.keys.join(" ")}: ${entry.modelData.title}`

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: entry.modelData.prefix ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        root.current = entry.index;
                                        root.activate(entry.modelData, 0, false);
                                    }
                                }

                                Row {
                                    x: 18
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 190
                                    clip: true
                                    spacing: 4

                                    Repeater {
                                        model: entry.modelData.keys

                                        Rectangle {
                                            required property string modelData

                                            width: Math.max(24, cheatKey.implicitWidth + 14)
                                            height: 24
                                            radius: 7
                                            color: Theme.overlay

                                            Text {
                                                id: cheatKey
                                                anchors.centerIn: parent
                                                text: parent.modelData
                                                textFormat: Text.PlainText
                                                color: Theme.text
                                                font.family: Theme.fontUi
                                                font.pixelSize: 12
                                                font.weight: Font.ExtraBold
                                            }
                                        }
                                    }
                                }

                                Text {
                                    x: 18 + 190 + 14
                                    width: parent.width - x - 50
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: entry.modelData.title
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: entry.modelData.dim ? Theme.subtext : Theme.text
                                    font.family: Theme.fontUi
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        Component {
                            id: switchView

                            // on/off with a live status line (Night light, its schedule, Bluetooth), as on the
                            // LauncherBluetooth board's power row
                            Rectangle {
                                readonly property var row: entry.modelData
                                readonly property bool on: row.on()

                                width: loader.width
                                height: 60
                                radius: Theme.tileRadius
                                // selected: the list's chip shows through, as this fades while it arrives
                                color: entry.selected || entry.card ? "transparent" : Theme.overlay
                                Accessible.role: Accessible.CheckBox
                                Accessible.name: row.title
                                Accessible.checked: on

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.motionDuration
                                        easing.type: Theme.easing
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.current = entry.index;
                                        root.activate(entry.modelData, 0, false);
                                    }
                                }

                                Rectangle {
                                    id: switchDisc
                                    x: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 38
                                    height: 38
                                    radius: 19
                                    color: Theme.overlay2

                                    Icon {
                                        anchors.centerIn: parent
                                        paths: parent.parent.row.icon
                                        color: parent.parent.on ? Theme.pistachio : Theme.subtext
                                    }
                                }

                                Column {
                                    anchors.left: switchDisc.right
                                    anchors.leftMargin: 14
                                    anchors.right: rowSwitch.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1

                                    Text {
                                        text: parent.parent.row.title
                                        color: Theme.textBright
                                        font.family: Theme.fontUi
                                        font.pixelSize: 15
                                        font.weight: Font.Bold
                                    }

                                    Text {
                                        width: parent.width
                                        text: parent.parent.row.status()
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        color: Theme.subtext
                                        font.family: Theme.fontUi
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }
                                }

                                Switch {
                                    id: rowSwitch
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    checked: parent.on
                                    Accessible.name: parent.row.title
                                    onToggled: parent.row.toggle()
                                }
                            }
                        }

                        Component {
                            id: timeView

                            // a schedule time: ←→ or − + move it by 15 minutes
                            Rectangle {
                                width: loader.width
                                height: 56
                                radius: Theme.tileRadius
                                color: "transparent" // selected: the list's chip shows through

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.current = entry.index
                                }

                                TimeStepper {
                                    x: 56 // lines up with the slider labels
                                    width: parent.width - x - 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: entry.modelData.title
                                    minutes: entry.modelData.minutes()
                                    onStepped: m => entry.modelData.set(m)
                                }
                            }
                        }

                        Component {
                            id: questionView

                            // A question in place of the results: "Shut down?" with Cancel and the action, or the
                            // pairing agent's, perhaps with a code to compare or to type on the device. The first
                            // choice (Cancel) is chosen first, except where a code is typed in the search field.
                            Rectangle {
                                id: question

                                readonly property var q: entry.modelData.question
                                readonly property bool hasCode: !!q.code

                                width: loader.width
                                height: choices.y + choices.height + 14
                                radius: Theme.tileRadius
                                color: Theme.overlay
                                Accessible.role: Accessible.AlertMessage
                                Accessible.name: `${q.title} ${q.text}${hasCode ? " " + q.code.split("").join(" ") : ""}`

                                Rectangle {
                                    id: questionDisc
                                    x: 14
                                    y: 16
                                    width: 38
                                    height: 38
                                    radius: 19
                                    color: Theme.overlay2

                                    Icon {
                                        anchors.centerIn: parent
                                        paths: question.q.icon
                                        color: question.q.danger ? Theme.terracotta : Theme.textBright
                                    }
                                }

                                Column {
                                    id: questionText
                                    anchors.left: questionDisc.right
                                    anchors.leftMargin: 14
                                    anchors.right: parent.right
                                    anchors.rightMargin: 14
                                    y: 16
                                    spacing: 2

                                    Text {
                                        width: parent.width
                                        text: question.q.title
                                        textFormat: Text.PlainText // device names come from the device
                                        elide: Text.ElideRight
                                        color: Theme.textBright
                                        font.family: Theme.fontUi
                                        font.pixelSize: 15
                                        font.weight: Font.Bold
                                    }

                                    Text {
                                        width: parent.width
                                        text: question.q.text
                                        textFormat: Text.PlainText // a setting's question repeats what was typed
                                        wrapMode: Text.Wrap
                                        color: question.q.error ? Theme.terracotta : Theme.subtext
                                        font.family: Theme.fontUi
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }
                                }

                                // the code, a pistachio cursor under the next key to type on the device
                                Row {
                                    id: code
                                    anchors.left: questionText.left
                                    anchors.top: questionText.bottom
                                    anchors.topMargin: 14
                                    visible: question.hasCode
                                    spacing: 6

                                    Repeater {
                                        model: question.hasCode ? question.q.code.split("") : []

                                        Text {
                                            required property string modelData
                                            required property int index

                                            text: modelData
                                            color: index < question.q.entered ? Theme.subtext : Theme.textBright
                                            font.family: Theme.fontUi
                                            font.pixelSize: 28
                                            font.weight: Font.ExtraBold
                                            font.features: { "tnum": 1 }

                                            Rectangle {
                                                anchors.top: parent.bottom
                                                width: parent.width
                                                height: 2
                                                radius: 1
                                                color: Theme.pistachio
                                                visible: parent.index === question.q.entered
                                            }
                                        }
                                    }
                                }

                                Row {
                                    id: choices
                                    anchors.right: parent.right
                                    anchors.rightMargin: 14
                                    // 82 keeps the power question as tall as before (136)
                                    y: Math.max(82, (question.hasCode ? code.y + code.height : questionText.y + questionText.height) + 20)
                                    spacing: 8

                                    Repeater {
                                        model: question.q.choices

                                        Rectangle {
                                            id: choice

                                            required property string modelData
                                            required property int index
                                            // Pair waits for a code that can be sent
                                            readonly property bool disabled: (question.q.input ?? false) && index === 1 && !root.inputValid
                                            readonly property bool chosen: root.column === index && !disabled

                                            width: choiceLabel.implicitWidth + 32
                                            height: 40
                                            radius: 20
                                            color: chosen ? Theme.pistachio : choiceMouse.containsMouse && !disabled ? Theme.overlay2 : Theme.bgAlt
                                            Accessible.role: Accessible.Button
                                            Accessible.name: modelData

                                            Text {
                                                id: choiceLabel
                                                anchors.centerIn: parent
                                                text: choice.modelData
                                                color: choice.chosen ? Theme.bg : choice.disabled ? Theme.subtext : Theme.text
                                                font.family: Theme.fontUi
                                                font.pixelSize: 13
                                                font.weight: choice.chosen ? Font.ExtraBold : Font.Bold
                                            }

                                            MouseArea {
                                                id: choiceMouse
                                                anchors.fill: parent
                                                enabled: !choice.disabled
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.column = choice.index;
                                                    root.activate(entry.modelData, choice.index, false);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Component {
                            id: emptyView

                            Text {
                                leftPadding: 18
                                topPadding: 8
                                bottomPadding: 16
                                text: entry.modelData.title
                                color: Theme.subtext
                                font.family: Theme.fontUi
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                        }

                        Component {
                            id: resultView

                            ResultRow {
                                readonly property var row: entry.modelData
                                readonly property bool current: row.kind === "device" && (row.input ? Audio.source : Audio.sink) === row.node
                                readonly property var bt: row.device // Bluetooth device rows; read live

                                width: loader.width
                                enabled: !row.off
                                compact: row.compact ?? false
                                indent: row.indent ?? 0
                                selected: entry.selected
                                title: row.title
                                indices: row.indices ?? []
                                subtitle: row.off ? (current ? "current, nothing plugged in" : "Nothing plugged in")
                                    : row.kind === "device" ? (current ? "current" : "")
                                    : row.kind === "btdevice" ? Bluetooth.status(bt)
                                    : row.kind === "btlink" ? (Bluetooth.enabled ? "Pair, connect and forget devices" : "Bluetooth is off")
                                    : row.subtitle ?? ""
                                icon: row.icon ?? ""
                                emoji: row.emoji ?? ""
                                glyph: row.glyph ?? (row.kind === "device" ? (row.input ? Icons.mic : Icons.volume) : row.kind.startsWith("bt") ? Icons.bluetooth : row.kind === "calc" ? Icons.calculator : Icons.window)
                                glyphColor: row.danger ? Theme.terracotta : row.kind === "btdevice" && bt.connected ? Theme.sageBlue : Theme.subtext
                                badge: row.badge ?? ""
                                badgeActive: row.badgeActive ?? false
                                action: row.kind === "power" ? (row.action.confirm ? `${row.title}…` : row.title)
                                    : row.kind === "appaction" ? "Open"
                                    : row.kind === "window" ? "Switch"
                                    : row.kind === "device" && !current ? "Use"
                                    : row.kind === "emoji" ? "Copy"
                                    : row.kind === "wplink" ? "Open"
                                    : row.kind === "setting" ? "Change"
                                    : row.kind === "termlink" ? "Choose"
                                    : row.kind === "aboutlink" ? "Show"
                                    : row.kind === "wsname" ? "Go"
                                    : row.kind === "preset" ? "Load"
                                    : row.kind === "presetsave" ? "Save"
                                    : row.kind === "presetdelete" ? "Delete"
                                    : row.kind === "abouturl" ? "Open"
                                    : row.kind === "terminal" && row.name !== Apps.terminal ? "Use"
                                    : row.kind === "showoff" ? (Showoff.active ? "Stop" : "Start")
                                    : row.kind === "command" ? "Run"
                                    : row.kind === "file" ? "Open"
                                    : row.kind === "notification" ? "Show"
                                    : row.kind === "web" ? "Search"
                                    : row.kind === "claude" ? "Ask"
                                    : row.kind === "drive" ? "Eject"
                                    : row.kind === "btlink" ? "Devices"
                                    : row.kind === "btdevice" ? (bt.connected ? "Disconnect" : bt.paired ? "Connect" : "Pair")
                                    : ""
                                actionAlways: row.kind === "btdevice"
                                onClicked: {
                                    root.current = entry.index;
                                    root.activate(row, 0, false);
                                }
                            }
                        }

                        Component {
                            id: sliderView

                            Rectangle {
                                readonly property var node: entry.modelData.node ?? null // an app's stream
                                readonly property bool volume: entry.modelData.key === "volume"
                                readonly property bool warmth: entry.modelData.key === "warmth" // night light, in kelvin
                                readonly property bool mic: entry.modelData.key === "mic"
                                readonly property real value: node ? node.audio?.volume ?? 0 : volume ? Audio.volume : mic ? Audio.micVolume : warmth ? NightLight.temperature : Brightness.value
                                readonly property bool muted: node ? node.audio?.muted ?? false : volume ? Audio.muted : mic && Audio.micMuted

                                width: loader.width
                                height: 60
                                radius: Theme.tileRadius
                                color: "transparent" // selected: the list's chip shows through

                                Icon {
                                    id: sliderIcon
                                    x: 22
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: 20
                                    visible: !appIcon.visible
                                    paths: parent.volume || parent.node ? (parent.muted ? Icons.volumeMuted : Icons.volume) : parent.mic ? (parent.muted ? Icons.micOff : Icons.mic) : parent.warmth ? Icons.thermometer : Icons.sun
                                }

                                Image {
                                    id: appIcon
                                    anchors.centerIn: sliderIcon
                                    width: 22
                                    height: 22
                                    sourceSize: Qt.size(44, 44)
                                    source: parent.node ? Audio.appIcon(parent.node) : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    opacity: parent.muted ? 0.5 : 1
                                    visible: status === Image.Ready
                                }

                                Text {
                                    id: sliderLabel
                                    anchors.left: sliderIcon.right
                                    anchors.leftMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 130
                                    elide: Text.ElideRight
                                    textFormat: Text.StyledText // app names are escaped
                                    text: `${Fuzzy.escape(entry.modelData.title)}  <font color="${Theme.subtext}">${parent.muted ? "Muted" : parent.warmth ? Math.round(rowSlider.shownValue) + " K" : Math.round(rowSlider.shownValue * 100) + "%"}</font>`
                                    color: Theme.textBright
                                    font.family: Theme.fontUi
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                }

                                Slider {
                                    id: rowSlider
                                    anchors.left: sliderLabel.right
                                    anchors.right: parent.right
                                    anchors.rightMargin: 22
                                    anchors.verticalCenter: parent.verticalCenter
                                    focusPolicy: Qt.NoFocus // keep typing in the search field
                                    from: parent.warmth ? 2500 : 0
                                    to: parent.warmth ? 6500 : 1
                                    stepSize: parent.warmth ? 250 : 0.05 // a wheel notch, as ← →
                                    value: parent.value
                                    Accessible.name: entry.modelData.title
                                    onMoved: parent.node ? Audio.setStreamVolume(parent.node, value) : parent.volume ? Audio.setVolume(value) : parent.mic ? Audio.setMicVolume(value) : parent.warmth ? NightLight.setTemperature(value) : Brightness.set(value)
                                }
                            }
                        }

                        Component {
                            id: statView

                            // A reading (System monitor card): icon, name and details, a meter and the
                            // load, which ease to each new reading. Lined up with the slider rows. A disk
                            // shows how full it is, in terracotta once under 10 % is free.
                            Item {
                                id: stat

                                readonly property string key: entry.modelData.key
                                readonly property var disk: key.startsWith("disk:") ? SystemStats.disks.find(d => d.mount === key.slice(5)) ?? null : null
                                readonly property bool low: disk?.low ?? false
                                readonly property real load: key === "cpu" ? Math.max(0, SystemStats.cpu) : key === "memory" ? SystemStats.memUsed / Math.max(1, SystemStats.memTotal) : disk ? 1 - disk.free / Math.max(1, disk.size) : SystemStats.gpu
                                readonly property bool known: key !== "cpu" || SystemStats.cpu >= 0
                                readonly property string detail: key === "cpu" ? (SystemStats.cpuTemp >= 0 ? `${Math.round(SystemStats.cpuTemp)} °C · ` : "") + SystemStats.cpuName
                                    : key === "memory" ? `${SystemStats.memUsed.toFixed(1)} of ${SystemStats.memTotal.toFixed(1)} GB`
                                    : disk ? `${gigabytes(disk.free)} free of ${gigabytes(disk.size)}`
                                    : `${Math.round(SystemStats.gpuTemp)} °C · ${SystemStats.vramUsed.toFixed(1)} of ${SystemStats.vramTotal.toFixed(1)} GB`

                                // "463 GB", "8.4 GB", "1.8 TB"
                                function gigabytes(g: real): string {
                                    return g >= 1000 ? `${(g / 1024).toFixed(1)} TB` : `${g >= 100 ? Math.round(g) : g.toFixed(1)} GB`;
                                }
                                property real shown: load

                                width: loader.width
                                height: 56
                                Accessible.role: Accessible.ProgressBar
                                Accessible.name: `${entry.modelData.title}${key === "gpu" ? " " + SystemStats.gpuName : ""} ${known ? Math.round(load * 100) + " percent" : "reading"}, ${detail}`

                                Behavior on shown {
                                    NumberAnimation {
                                        duration: Theme.motionDuration
                                        easing.type: Theme.easing
                                    }
                                }

                                Icon {
                                    id: statIcon
                                    x: 22
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: 20
                                    paths: stat.key === "cpu" ? Icons.cpu : stat.key === "memory" ? Icons.memory : stat.disk ? Icons.hardDrive : Icons.gpu
                                    color: stat.low ? Theme.terracotta : Theme.text
                                }

                                Column {
                                    id: statText
                                    anchors.left: statIcon.right
                                    anchors.leftMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 130
                                    spacing: 1

                                    Text {
                                        text: entry.modelData.title
                                        color: Theme.textBright
                                        font.family: Theme.fontUi
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                    }

                                    Text {
                                        width: parent.width
                                        text: stat.detail
                                        elide: Text.ElideRight
                                        color: stat.low ? Theme.terracotta : Theme.subtext
                                        font.family: Theme.fontUi
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                        font.features: { "tnum": 1 }
                                    }
                                }

                                Rectangle {
                                    anchors.left: statText.right
                                    anchors.right: statValue.left
                                    anchors.rightMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 6
                                    radius: 3
                                    color: Theme.overlay

                                    Rectangle {
                                        width: parent.width * Math.min(1, stat.shown)
                                        height: parent.height
                                        radius: 3
                                        color: stat.low ? Theme.terracotta : Theme.sageBlue
                                    }
                                }

                                Text {
                                    id: statValue
                                    anchors.right: parent.right
                                    anchors.rightMargin: 22
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 38
                                    horizontalAlignment: Text.AlignRight
                                    text: stat.known ? `${Math.round(stat.shown * 100)}%` : "—"
                                    color: Theme.textBright
                                    font.family: Theme.fontUi
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    font.features: { "tnum": 1 }
                                }
                            }
                        }

                        Component {
                            id: controlsView

                            Grid {
                                width: loader.width
                                columns: root.controls.length
                                spacing: 8

                                Repeater {
                                    model: root.controls

                                    Rectangle {
                                        required property var modelData
                                        required property int index
                                        readonly property bool chosen: entry.selected && root.column === index

                                        width: (entry.width - 8 * (root.controls.length - 1)) / root.controls.length
                                        height: 80
                                        radius: Theme.tileRadius
                                        color: chosen ? Theme.overlay2 : Theme.overlay
                                        Accessible.role: Accessible.Button
                                        Accessible.name: modelData.label + " " + modelData.value

                                        Column {
                                            x: 16
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 6

                                            Icon {
                                                size: 20
                                                paths: modelData.icon
                                                color: Theme.text
                                            }

                                            Text {
                                                textFormat: Text.StyledText
                                                text: `${modelData.label}  <font color="${Theme.subtext}">${modelData.value}</font>`
                                                color: Theme.textBright
                                                font.family: Theme.fontUi
                                                font.pixelSize: 13
                                                font.weight: Font.Bold
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.current = entry.index;
                                                root.column = index;
                                                root.activate(entry.modelData, index, false);
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Component {
                            id: workspacesView

                            Grid {
                                width: loader.width
                                columns: 5
                                spacing: 8

                                Repeater {
                                    model: entry.modelData.cards

                                    WorkspaceCard {
                                        required property var modelData
                                        required property int index

                                        width: (entry.width - 8 * 4) / 5
                                        card: modelData
                                        chosen: entry.selected && root.column === index
                                        screenSize: Qt.size(root.screen.width, root.screen.height)
                                        onClicked: {
                                            root.current = entry.index;
                                            root.column = index;
                                            root.activate(entry.modelData, index, false);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // key hints
            Item {
                width: parent.width
                height: 46

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.overlay
                }

                Row {
                    x: 26
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 20

                    Repeater {
                        model: root.keyHints

                        Row {
                            required property var modelData
                            spacing: 8

                            Rectangle {
                                width: Math.max(22, keyText.implicitWidth + 12)
                                height: 22
                                radius: 7
                                color: Theme.overlay

                                Text {
                                    id: keyText
                                    anchors.centerIn: parent
                                    text: modelData[0]
                                    color: Theme.text
                                    font.family: Theme.fontUi
                                    font.pixelSize: 12
                                    font.weight: Font.ExtraBold
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData[1]
                                color: Theme.subtext
                                font.family: Theme.fontUi
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }
            }
        }
    }
}
