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
        windows: [["↵", "switch"], ["Ctrl W", "close window"], ["Ctrl F", "float"], ["Ctrl P", "pin"], ["Ctrl 1–9", "move"], ["Esc", "close"]],
        workspaces: [["←→", "choose"], ["↵", "go"], ["Shift ↵", "move window here"], ["Esc", "close"]],
        system: [["↑↓", "navigate"], ["←→", "adjust"], ["↵", "switch / select"], ["Ctrl M", "mute"], ["Esc", "close"]],
        // Ctrl, unlike the board's plain ⌫: Backspace also edits the search, and forgetting is not undoable
        bluetooth: [["↑↓", "navigate"], ["↵", "connect / disconnect"], ["Ctrl ⌫", "forget device"], ["Esc", "close"]],
        terminals: [["↑↓", "navigate"], ["↵", "use"], ["Esc", "back"]],
        lenschoices: [["↑↓", "navigate"], ["↵", "use"], ["Esc", "back"]]
    })

    property bool open
    property string mode: "all"
    signal settingsRequested(string page)
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
    readonly property bool inputValid: editing && (editing?.allowEmpty || query.trim() !== "") && !editBusy
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
    onCurrentChanged: {if(rows[current]?.key!==heldKey)heldKey="";if(Theme.tui)Qt.callLater(scrollCurrent);}
    onColumnChanged: if(Theme.tui)Qt.callLater(scrollCurrent)
    // App actions (owner's request, after phase 8): → on an app opens its own actions as rows under it
    // (the key of the app's row; an app can be listed twice), ← or typing closes them.
    property string expandedKey
    property int column: 0 // selected tile or card within a grid row
    // A right click on a row or card (owner's request, 5 November 2026): what Enter and the keys do
    // there, as a menu: { x, y, entries: [{ text, glyph, danger, run }] }, or null
    property var menu: null

    function snapshot() {
        windows = Compositor.windows;
        workspaces = Compositor.workspaces;
    }

    // Bluetooth is a view inside System (LauncherBluetooth board), so it has no tab of its own;
    // the System tab stays highlighted. So is Terminals, from Shell settings (owner's request).
    readonly property string tab: mode === "bluetooth" || mode === "terminals" || mode === "about" || mode === "lenschoices" ? "system" : mode
    readonly property string placeholder: editing ? editing.placeholder
        : mode === "bluetooth" ? "Filter devices…" : mode === "terminals" ? "Filter terminals…" : mode === "lenschoices" ? `Filter ${lensChoice.includes("Model") ? "models" : lensChoice.includes("Effort") ? "effort levels" : "providers"}…` : mode === "about" ? "About the shell" : modes.find(m => m.id === mode).placeholder
    readonly property var keyHints: confirming ? [["←→", "choose"], ["↵", "confirm"], ["Esc", "back"]]
        : editing ? [["↵", "save"], ["Esc", "back"]]
        : rows[current]?.kind === "appaction" ? [["↑↓", "navigate"], ["↵", "open"], ["←", "back"], ["Esc", "close"]]
        : rows[current]?.kind === "claude" ? [["↑↓", "navigate"], ["↵", "ask Claude"], ["Esc", "close"]]
        : rows[current]?.kind === "ask" ? [["↑↓", "navigate"], ["↵", rows[current].prompt ? "ask" : "open the quick chat"], ["Esc", "close"]]
        : rows[current]?.kind === "preset" ? [["↑↓", "navigate"], ["↵", "load"], ["→", "delete"], ["Esc", "close"]]
        : rows[current]?.kind === "music" ? [["↵", "play"], ["Shift ↵", "play next"], ["→", "add to queue"], ["Esc", "close"]]
        : rows[current]?.kind === "process" ? [["↑↓", "navigate"], ["↵", rows[current].process.pids.length > 1 ? "end them all" : "end it"], ["Esc", "close"]]
        : rows[current]?.kind === "tldr" ? [["↑↓", "navigate"], ["↵", "copy"], ["Esc", "close"]]
        : rows[current]?.kind === "app" && rows[current].app.actions.length > 0 ? [["↑↓", "navigate"], ["↵", "open"], ["→", "more actions"], ["Tab", "switch mode"], ["Esc", "close"]]
        : rows[current]?.kind === "file" && !rows[current].entry.folder ? [["↑↓", "navigate"], ["↵", "open"], ["Space", "preview"], ["Shift ↵", "show in folder"], ["Esc", "close"]]
        : filesWanted ? [["↑↓", "navigate"], ["↵", "open"], ["Shift ↵", "show in folder"], ["Esc", "close"]]
        : (mode === "all" || mode === "apps") && query.startsWith("!") ? [["↑↓", "navigate"], ["↵", "show in centre"], ["Esc", "close"]]
        : cheatWanted ? [["↑↓", "navigate"], ["↵", "use a prefix"], ["Esc", "close"]]
        : Theme.tui && mode==="bluetooth" ? [["↑↓","navigate"],["↵","connect / disconnect"],["Ctrl ⌫","forget device"],["Esc","back"]] : hints[mode]
    // scan for new devices only while the Bluetooth view is on screen
    readonly property bool scanWanted: Theme.tui && open && mode === "bluetooth" && Bluetooth.ready
    onScanWantedChanged: Bluetooth.setScanning(scanWanted)
    Connections {target:Bluetooth;function onAsked(){if(Theme.tui&&root.open)root.open=false;}}
    // Discovery is owned by the Settings window.
    // and read the machine's load only while the System monitor card is
    readonly property bool statsWanted: open && rows.some(r => r.kind === "stat")
    // System monitor polling is owned by the Settings window.
    // and Hyprland's binds, each time the cheat sheet opens
    readonly property bool cheatWanted: open && (mode === "all" || mode === "apps") && query.startsWith("?")
    onCheatWantedChanged: if (cheatWanted) Compositor.loadBinds()
    readonly property bool clipboardWanted: open && (mode === "all" || mode === "apps") && query.startsWith(";")
    onClipboardWantedChanged: if (clipboardWanted) Clipboard.loadHistory()
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
        if ((!Theme.tui && m === "bluetooth") || m === "about") {
            open = false;
            settingsRequested(m);
            return;
        }
        list.enter();
        confirming = null;
        editing = null;
        expandedKey = "";
        lensChoice = "";
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

    function timerInput(text: string): var {
        const words = text.trim().split(/\s+/);
        let n = words.length;
        while (n > 0 && Clocks.parseDuration(words.slice(0, n).join(" ")) <= 0) n--;
        return n ? { ms: Clocks.parseDuration(words.slice(0, n).join(" ")), label: words.slice(n).join(" ") } : null;
    }

    function alarmInput(text: string): var {
        const m = /^(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)?\s*(.*)$/i.exec(text.trim());
        if (!m) return null;
        let hour = parseInt(m[1]);
        const minute = m[2] ? parseInt(m[2]) : 0;
        if (minute >= 60 || (m[3] ? hour < 1 || hour > 12 : hour > 23)) return null;
        if (m[3]) hour = hour % 12 + (m[3].toLowerCase() === "pm" ? 12 : 0);
        return { hour: hour, minute: minute, label: m[4] };
    }

    function clockRows(q: string): var {
        const m = /^(timer|alarm|stopwatch)(?:\s+(.*))?$/i.exec(q.trim());
        if (!m) return [];
        const kind = m[1].toLowerCase(), arg = (m[2] || "").trim();
        let title, action;
        if (kind === "timer") {
            const v = arg ? timerInput(arg) : null;
            if (arg && !v) return [{kind:"empty", key:"clock-invalid", title:"Try timer 5m tea or timer 1h 30m"}];
            title = arg ? `Start timer · ${arg}` : "Set a timer…";
            action = arg ? () => { Clocks.startTimer(v.ms, v.label); open = false; } : askTimer;
        } else if (kind === "alarm") {
            const v = arg ? alarmInput(arg) : null;
            if (arg && !v) return [{kind:"empty", key:"clock-invalid", title:"Try alarm 7:30 wake up"}];
            title = arg ? `Set alarm · ${arg}` : "Set an alarm…";
            action = arg ? () => { Clocks.addAlarm(v.hour, v.minute, v.label); open = false; } : askAlarm;
        } else {
            const watch = Clocks.stopwatch, running = !!watch?.since;
            const choice = arg.toLowerCase() || (!watch ? "start" : running ? "pause" : "resume");
            if (choice === "start" && !watch) { title="Start stopwatch"; action=Clocks.startStopwatch; }
            else if (choice === "pause" && running) { title="Pause stopwatch"; action=Clocks.pauseStopwatch; }
            else if (choice === "resume" && watch && !running) { title="Resume stopwatch"; action=Clocks.pauseStopwatch; }
            else if (choice === "stop" && watch) { title="Stop stopwatch"; action=Clocks.stopStopwatch; }
            else if (choice === "lap" && running) { title="Record stopwatch lap"; action=Clocks.lap; }
            else return [{kind:"empty", key:"clock-invalid", title:"Stopwatch: start, pause, resume, lap or stop (when available)"}];
            const run = action; action = () => { run(); open = false; };
        }
        return [{kind:"clock-command", key:"clock-command", title:title, glyph:Icons.clock, run:action}];
    }

    // From the clock's menu (owner's request, 9 November 2026): a timer's length and label ("25m tea",
    // "1h 30m", "90s", "10"), an alarm's time and label ("7:30 wake up", "6pm", "18:45")
    function askTimer() {
        show("all");
        startEditing({
            key: "",
            title: "Timer",
            icon: Icons.clock,
            placeholder: "25m tea",
            close: true,
            hint: () => "How long, and a name if you like: 25m tea, 1h 30m, 90s. Enter starts it.",
            check: (text, then) => then(timerInput(text), "Say how long: 25m, 1h 30m, 90s."),
            apply: v => Clocks.startTimer(v.ms, v.label)
        }, "");
    }

    function askAlarm() {
        show("all");
        startEditing({
            key: "",
            title: "Alarm",
            icon: Icons.bell,
            placeholder: "7:30 wake up",
            close: true,
            hint: () => "A time, and a name if you like: 7:30 wake up, 6pm, 18:45. It rings once, and shows in GNOME Clocks too.",
            check: (text, then) => then(alarmInput(text), "Say when: 7:30, 6pm, 18:45."),
            apply: v => Clocks.addAlarm(v.hour, v.minute, v.label)
        }, "");
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
            if (!value && !(asked.allowEmpty && value === "")) {
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
            subtitle: LauncherTools.pending[h.item.id] ? "Starting…" : h.program ? [h.program, h.item.genericName || h.item.comment].filter(t => t).join(" · ") : h.item.genericName || h.item.comment,
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
            [";", "Clipboard history; Enter copies an item"],
            ["timer", "Start a timer, e.g. timer 5m tea"],
            ["alarm", "Set an alarm, e.g. alarm 7:30 wake up"],
            ["stopwatch", "Start or control the stopwatch"],
            ["12*3", "A calculation: the answer shows at the top"]
        ].concat([["ask", "Ask AI: the quick chat above the bar, with a question or without"]], Apps.claudeApp ? [["claude", "Ask Claude: a new chat in Claude Desktop"]] : [],
            Cider.installed && Cider.enabled ? [["m", "Apple Music in Cider: Enter plays, Shift+Enter plays next"]] : [],
            Qalc.installed ? [["=", "libqalculate: equations, units, currencies, bases; Enter copies"]] : [],
            [["kill", "Your running programs; Enter ends one"]], ShellSettings.integration("tldr") ? [["tldr", "Examples for a command; Enter copies one"]] : [])
            .map(([k, t], i) => row("prefix", i, [k], t, { prefix: k === "12*3" ? "" : ["ask", "claude", "m", "kill", "tldr", "timer", "alarm", "stopwatch"].includes(k) ? k + " " : k }));
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
        // and by the program they run, as typed in a terminal ("baobab" finds Disk Usage Analyzer):
        // a program named exactly that comes first, one whose name starts with it after the name
        // matches; the row says which program it is
        if (q.length >= 2) {
            const ql = Fuzzy.fold(q).trim();
            const runs = byName.filter(a => !hits.some(h => h.item === a)).map(a => ({ item: a, indices: [], program: Apps.programOf(a) }))
                .filter(h => h.program.startsWith(ql) && !Fuzzy.fold(h.item.name).includes(ql));
            const exact = runs.filter(h => h.program === ql);
            hits = exact.concat(hits, runs.filter(h => h.program !== ql)).slice(0, limit);
        }
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
            subtitle: h.item.appId + (h.item.minimized ? " · minimised" : h.item.recency === 0 ? " · focused" : h.item.urgent ? " · needs attention" : "") + (h.item.floating ? " · floating" : ""),
            icon: Apps.iconFor(h.item.appId),
            badge: h.item.minimized ? "" : String(h.item.workspace), // a minimised one is on no workspace
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
        // a search keeps only the rows it matches (owner's request, 15 November 2026: "zen" showed
        // every quick control to scroll through); the card's own name still shows all of it
        if (q && !Fuzzy.match(q, name))
            rows = rows.filter(r => Fuzzy.match(q, r.title));
        return rows.map((r, i) => Object.assign({}, r, { card: rows.length === 1 ? "single" : i === 0 ? "top" : i === rows.length - 1 ? "bottom" : "middle" }));
    }

    // a switch row: on/off with a live status line; Enter or the switch toggles it
    function bluetoothSwitch(): var {
        return { kind: "switch", key: "bluetooth", title: "Bluetooth", icon: Icons.bluetooth, on: () => Bluetooth.enabled, status: () => Bluetooth.summary, toggle: () => Bluetooth.setEnabled(!Bluetooth.enabled) };
    }

    property string lensChoice
    readonly property string lensChoiceTitle: ({
        lensProvider: "Lens · Provider", lensClaudeModel: "Lens · Claude model", lensClaudeEffort: "Lens · Claude effort",
        lensCodexModel: "Lens · ChatGPT model", lensCodexEffort: "Lens · ChatGPT effort"
    })[lensChoice] ?? "Lens"

    function lensSetting(key: string, title: string): var {
        return [{ kind: "lenschoice", key: key, title: title, subtitle: ShellSettings.lensLabel(key), glyph: key.includes("Effort") ? Icons.sliders : Icons.sparkles }];
    }

    function lensChoiceRows(q: string): var {
        const choices = ShellSettings.lensChoices[lensChoice] ?? [];
        return [section(lensChoiceTitle)].concat(choices.filter(choice => !q || Fuzzy.match(q, choice.title) || Fuzzy.match(q, choice.value)).map(choice => ({
            kind: "lensoption", key: lensChoice + ":" + choice.value, title: choice.title,
            subtitle: choice.value === Store.saved[lensChoice] ? "Current" : lensChoice.includes("Model") ? choice.value : "",
            glyph: choice.value === Store.saved[lensChoice] ? Icons.check : lensChoice.includes("Effort") ? Icons.sliders : Icons.sparkles,
            settingKey: lensChoice, value: choice.value
        })));
    }

    function leaveLensChoices() {
        const key = lensChoice;
        field.text = "";
        mode = "system";
        lensChoice = "";
        const i = rows.findIndex(r => r.key === key);
        if (i >= 0) { current = i; heldKey = key; backToRow.restart(); }
    }

    // Detailed controls live in Settings; keep this list quick to use from the keyboard.
    function systemRows(q: string): var {
        const quick = [{ kind: "slider", key: "volume", title: "Volume" }];
        if (Brightness.available) quick.push({ kind: "slider", key: "brightness", title: "Brightness" });
        quick.push(bluetoothSwitch(),
            { kind: "btlink", key: "btlink", title: "Bluetooth devices" },
            { kind: "switch", key: "nightlight", title: "Night light", icon: Icons.moon, on: () => NightLight.enabled, status: () => NightLight.status, toggle: () => NightLight.setEnabled(!NightLight.enabled) },
            { kind: "switch", key: "dnd", title: "Do not disturb", icon: Icons.bellOff, on: () => Notifs.dnd, status: () => Notifs.dndStatus, toggle: () => Notifs.setDnd(!Notifs.dnd) },
            // Zen and Focus (FocusMode, owner's request, 11 November 2026): their launcher entries, no IPC
            { kind: "switch", key: "zen", title: "Zen mode", icon: Icons.moon, on: () => FocusMode.zen, status: () => FocusMode.zen ? (FocusMode.session?.owner === "zen" ? `${FocusMode.phaseName()} · ${FocusMode.clock(FocusMode.left())}` : "Bar hidden · toasts wait") : Store.saved.zenPomodoro ? "Off · with a Pomodoro" : "Off", toggle: () => FocusMode.toggleZen() },
            { kind: "switch", key: "pomodoro", title: "Pomodoro", icon: Icons.clock, on: () => FocusMode.pomodoring, status: () => FocusMode.pomodoring ? `${FocusMode.phaseName()} · ${FocusMode.clock(FocusMode.left())} left` : `Off · ${Store.saved.pomodoroWork}/${Store.saved.pomodoroBreak} min`, toggle: () => FocusMode.togglePomodoro() },
            { kind: "switch", key: "focus", title: "Focus session", icon: Icons.lightbulb, on: () => FocusMode.focusing, status: () => FocusMode.focusing ? `${FocusMode.phaseName()} · ${FocusMode.clock(FocusMode.left())} left` : Store.saved.focusPomodoro ? `Off · Pomodoro ${Store.saved.pomodoroWork}/${Store.saved.pomodoroBreak} min` : `Off · ${Store.saved.focusMinutes} min`, toggle: () => FocusMode.toggleFocus() });
        const experimental = card("Experimental", q, [{ kind: "switch", key: "tui-hyprland", title: "Hyprland integration",
            icon: Icons.sliders, on: () => ShellSettings.tuiHyprland, status: () => ShellSettings.tuiHyprland ? "On · square corners in TUI" : "Off · square corners in TUI",
            toggle: () => ShellSettings.setTuiHyprland(!ShellSettings.tuiHyprland) }]);
        return card("Quick controls", q, quick).concat(card("Settings", q, [
            { kind: "settingslink", key: "settings", title: "Settings", subtitle: "Sound, Bluetooth, appearance, Lens and more", glyph: Icons.sliders }
        ]), experimental.length ? [section("Experimental"), ...experimental] : []);
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

    // Other apps' things (owner's picks, 8 November 2026): CLion's recent projects and the games, found
    // by name in All and Apps ("clion" lists every project, "games" every game)
    function projectSubtitle(p, ide: string): string {
        const git = p.git;
        return ide + (git ? ` · ${git.dirty ? "● " : ""}${git.branch}` : "") + " · " + p.path.replace(Quickshell.env("HOME"), "~");
    }

    function projectRows(q: string): var {
        if (!Library.clion)
            return [];
        const all = Fuzzy.match(q, "clion") && q.length >= 3;
        return Library.projects.filter(p => all || Fuzzy.match(q, p.name)).slice(0, all ? 12 : 4).map(p => ({
            kind: "project", key: "project:" + p.path, title: p.name, subtitle: projectSubtitle(p, "CLion"), icon: Apps.icon(Library.clion?.icon ?? "clion"), glyph: Icons.fileCode, project: p
        }));
    }

    // VS Code's recent folders and workspaces (owner's request, 11 November 2026), as CLion's: "vscode"
    // or "code" lists them all; only while VS Code is installed
    function codeProjectRows(q: string): var {
        if (!Library.vscode)
            return [];
        const all = (Fuzzy.match(q, "vscode") && q.length >= 3) || Fuzzy.fold(q) === "code";
        return Library.codeProjects.filter(p => all || Fuzzy.match(q, p.name)).slice(0, all ? 12 : 4).map(p => ({
            kind: "project", key: "code:" + p.path, title: p.name, subtitle: projectSubtitle(p, "VS Code"), icon: Apps.icon(Library.vscode?.icon ?? "vscode"), glyph: Icons.fileCode, project: p
        }));
    }

    function gameRows(q: string): var {
        const all = Fuzzy.match(q, "games") && q.length >= 4;
        return Library.games.filter(g => all || Fuzzy.match(q, g.name)).map(g => ({
            kind: "game", key: "game:" + g.key, title: g.name, subtitle: g.appid ? "Steam" : "Game", icon: g.cover ? "file://" + g.cover : Apps.icon(g.icon ?? ""), glyph: Icons.sparkles, game: g
        }));
    }

    // `kill <name>`: your programs matching it, the busiest first
    function processRows(q: string): var {
        // one row per program, all its processes together (Enter ends them all, like killall)
        const rows = Processes.groups.filter(g => !q || Fuzzy.fold(g.name).includes(Fuzzy.fold(q)) || Fuzzy.fold(g.command).includes(Fuzzy.fold(q))).slice(0, 30).map(g => ({
            kind: "process", key: "process:" + g.name, title: g.name, subtitle: `${g.pids.length > 1 ? g.pids.length + " processes" : "PID " + g.pids[0]} · ${g.cpu.toFixed(1)} % CPU · ${g.memory >= 1024 ? (g.memory / 1024).toFixed(1) + " GB" : Math.round(g.memory) + " MB"} · ${g.command}`, icon: Apps.iconFor(g.name), glyph: Icons.cpu, process: g
        }));
        return [section(q ? `Programs matching “${q}”` : "Your programs · busiest first")].concat(rows.length ? rows : [{ kind: "empty", key: "noprocess", title: "Nothing by that name is running" }]);
    }

    // `tldr <command>`: its description and examples; Enter copies one
    function tldrRows(q: string): var {
        if (!q)
            return [{ kind: "empty", key: "tldr", title: "Type a command, e.g. tldr tar" }];
        Qt.callLater(Tldr.lookup, q); // not while the rows are being worked out: it changes what they read
        if (Tldr.busy || Tldr.page !== q.trim().toLowerCase().replace(/\s+/g, "-")) // (the page shown is the one asked for)
            return [{ kind: "empty", key: "tldr", title: "Looking it up…" }];
        if (Tldr.missing)
            return [{ kind: "empty", key: "tldr", title: `tldr has no page for “${q}”` }];
        // the whole description first (owner, 9 November: the heading cut it short), and the full manual
        return [section(Tldr.page), { kind: "note", key: "tldr:about", title: Tldr.description + (Tldr.more ? `\nMore: ${Tldr.more}` : "") }]
            .concat([section("Examples")], Tldr.examples.map((e, i) => ({
                kind: "tldr", key: "tldr:" + i, title: e.what, subtitle: e.command, glyph: Icons.terminal, command: e.command
            })), [{ kind: "tldrman", key: "tldr:man", title: `Open the full manual: man ${Tldr.page}`, subtitle: `In ${Apps.terminalName(Apps.terminal)}`, glyph: Icons.fileText, page: Tldr.page }]);
    }

    // `m <words>`: Apple Music through Cider; without its token, a row that asks for it
    function musicRows(q: string): var {
        if (!Cider.usable)
            return [section("Apple Music"), { kind: "setting", key: "ciderToken", title: "Set Cider's token to search Apple Music", subtitle: "Cider → Settings → Connectivity → Manage External Application Access", glyph: Icons.music, setting: ciderSetting }];
        Qt.callLater(Cider.search, q);
        const rows = Cider.results.map(r => ({ kind: "music", key: `music:${r.type}:${r.id}`, title: r.name, subtitle: r.detail, icon: r.art, glyph: Icons.music, item: r }));
        return [section("Apple Music")].concat(rows.length ? rows : [{ kind: "empty", key: "nomusic", title: !q ? "Type a song, an album or a playlist" : Cider.searching ? "Searching…" : Cider.reachable ? "No matches" : "Cider didn't answer: is it open?" }]);
    }

    // Cider's app token (Shell settings), checked with Cider before it's kept
    readonly property var ciderSetting: ({
        key: "ciderToken",
        title: "Cider token",
        icon: Icons.music,
        placeholder: "Paste the token",
        hint: () => "In Cider: Settings → Connectivity → Manage External Application Access, create one, copy it, paste it here and press Enter.",
        check: (text, then) => Cider.check(text.trim(), then),
        apply: token => Cider.setToken(token)
    })

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

    // what a right click on a row (and `col`, a card in a grid row) offers
    function descriptorFor(row): var {
        return row.descriptor ?? (row.kind === "app" ? {kind:"app",target:row.app.id} : row.kind === "preset" ? {kind:"preset",target:row.preset.name} : null);
    }
    function aliasItem(row) {
        const d=descriptorFor(row), initial=LauncherTools.aliasFor(d);
        startEditing({key:row.key,title:"Alias for "+row.title,allowEmpty:true,icon:Icons.pencil,placeholder:"Short name",hint:() => "Exact alias; Enter opens it. Clear to remove.",check:(text,then) => { const error=LauncherTools.checkAlias(text,d); then(error ? null : text,error); },apply:text => LauncherTools.setAlias(text,d)},initial);
    }
    function previewFile(row, view) { open=false; LauncherTools.showFile(Files.home+"/"+row.entry.path,view); }
    function menuFor(row, col: int): var {
        const out=baseMenuFor(row,col), d=descriptorFor(row);
        if (row.kind === "file" && !row.entry.folder) out.push({text:"Preview · Space",glyph:Icons.image,run:() => previewFile(row,"preview")},{text:"Open with…",glyph:Icons.folderOpen,run:() => previewFile(row,"handlers")});
        if (row.kind === "window" && Compositor.windows.find(w => w.address===row.address)?.floating) {
            out.splice(2,0,...[{text:"1280 × 720",size:[1280,720]},{text:"960 × 600",size:[960,600]},{text:"Centre",size:[0,0]}].map(p => ({text:p.text,glyph:Icons.window,run:() => Compositor.floatingPreset(row.address,p.size[0],p.size[1])})));
        }
        if (d) {
            out.push({text:LauncherTools.pinned(d) ? "Unpin from launcher" : "Pin to launcher",glyph:Icons.plus,run:() => LauncherTools.togglePin(d)});
            if (LauncherTools.pinned(d)) out.push({text:"Move pin up",glyph:Icons.chevronUp,run:() => LauncherTools.movePin(d,-1)},{text:"Move pin down",glyph:Icons.chevronDown,run:() => LauncherTools.movePin(d,1)});
            if (d.kind!=="preset") out.push({text:LauncherTools.aliasFor(d) ? "Change alias…" : "Set alias…",glyph:Icons.pencil,run:() => aliasItem(row)});
        }
        return out;
    }
    function baseMenuFor(row, col: int): var {
        switch (row.kind) {
        case "app":
            return [{ text: "Open", glyph: Icons.folderOpen, run: () => activate(row, 0, false) }]
                .concat(row.app.actions.map(a => ({ text: a.name, glyph: Icons.chevronRight, run: () => activate({ kind: "appaction", app: row.app, action: a }, 0, false) })));
        case "window":
            return [
                { text: "Switch to it", glyph: Icons.window, run: () => activate(row, 0, false) },
                { text: "Float or tile", glyph: Icons.layers, run: () => { Compositor.toggleFloating(row.address); resnap.restart(); } },
                { text: Compositor.windows.find(w => w.address === row.address)?.pinned ? "Unpin" : "Pin on top", glyph: Icons.window, run: () => { Compositor.togglePin(row.address); resnap.restart(); } },
                { text: "Close window", glyph: Icons.close, danger: true, run: () => { Compositor.close(row.address); resnap.restart(); } }
            ];
        case "workspaces": {
            const card = row.cards[col];
            if (!card)
                return [];
            const named = Compositor.nameOf(card.id) !== "";
            const count = windows.filter(w => w.workspace === card.id).length;
            return [
                { text: `Go to workspace ${card.id}`, glyph: Icons.chevronRight, run: () => activate(row, col, false) },
                { text: "Move the last window here", glyph: Icons.window, run: () => activate(row, col, true) },
                { text: named ? "Rename…" : "Name it…", glyph: Icons.pencil, run: () => renameWorkspace(card.id) },
                { text: Compositor.isTabbed(card.id) ? "Tabs off: tile again" : "Tabbed, i3-style", glyph: Icons.layers, run: () => { const on = !Compositor.isTabbed(card.id); if (on) Compositor.goto(card.id); Compositor.setTabbed(card.id, on); open = false; } }
            ].concat(named ? [{ text: "Clear its name", glyph: Icons.close, run: () => Compositor.setName(card.id, "") }] : [],
                count ? row.cards.filter(c => c.id !== card.id).map(c => ({ text: `Move its windows to ${c.id}${Compositor.nameOf(c.id) ? " · " + Compositor.nameOf(c.id) : ""}`, glyph: Icons.chevronRight, run: () => { windows.filter(w => w.workspace === card.id).forEach(w => Compositor.sendWindow(w.address, c.id)); resnap.restart(); } })) : [],
                count ? [{ text: `Close its ${count} window${count === 1 ? "" : "s"}…`, glyph: Icons.trash, danger: true, run: () => askCloseWorkspace(card.id) }] : []);
        }
        case "wsname":
            return [
                { text: "Go there", glyph: Icons.chevronRight, run: () => activate(row, 0, false) },
                { text: "Rename…", glyph: Icons.pencil, run: () => renameWorkspace(row.id) },
                { text: "Clear its name", glyph: Icons.close, run: () => Compositor.setName(row.id, "") }
            ];
        case "preset":
            return [
                { text: "Load", glyph: Icons.sparkles, run: () => activate(row, 0, false) },
                { text: "Delete…", glyph: Icons.trash, danger: true, run: () => askDeletePreset(row.preset.name) }
            ];
        case "btdevice":
            return [{ text: row.device.connected ? "Disconnect" : row.device.paired ? "Connect" : "Pair", glyph: Icons.bluetooth, run: () => activate(row, 0, false) }]
                .concat(row.device.paired ? [{ text: "Forget device", glyph: Icons.trash, danger: true, run: () => Bluetooth.forget(row.device) }] : []);
        case "project":
            return [{ text: row.project.ide === "code" ? "Open in VS Code" : "Open in CLion", glyph: Icons.fileCode, run: () => activate(row, 0, false) }, { text: "Show in file manager", glyph: Icons.folder, run: () => Quickshell.execDetached(["xdg-open", row.project.path]) }];
        case "game":
            return [{ text: "Play", glyph: Icons.play, run: () => activate(row, 0, false) }];
        case "process":
            return [
                { text: row.process.pids.length > 1 ? "End them all…" : "End it…", glyph: Icons.close, danger: true, run: () => activate(row, 0, false) },
                { text: row.process.pids.length > 1 ? "Force quit them all" : "Force quit", glyph: Icons.trash, danger: true, run: () => Processes.endAll(row.process, true) }
            ];
        case "tldr":
            return [{ text: "Copy the command", glyph: Icons.clipboard, run: () => activate(row, 0, false) }];
        case "music":
            return [
                { text: "Play now", glyph: Icons.play, run: () => { Cider.play(row.item, "now"); open = false; } },
                { text: "Play next", glyph: Icons.skipForward, run: () => Cider.play(row.item, "next") },
                { text: "Add to the queue", glyph: Icons.plus, run: () => Cider.play(row.item, "later") }
            ];
        case "file":
            return [
                { text: "Open", glyph: Icons.folderOpen, run: () => activate(row, 0, false) },
                { text: "Show in folder", glyph: Icons.folder, run: () => activate(row, 0, true) }
            ];
        }
        return [];
    }

    function openMenu(row, col: int, at: point) {
        const entries = menuFor(row, col);
        menu = entries.length ? { x: at.x, y: at.y, entries: entries } : null;
    }

    function askCloseWorkspace(id: int) {
        confirming = { id: "closews:" + id, title: "Close them", icon: Icons.close, danger: true, question: `Close the windows on workspace ${id}?`, confirm: "Unsaved work in them is lost.", run: () => Compositor.windows.filter(w => w.workspace === id).forEach(w => Compositor.close(w.address)) };
        current = 0;
        column = 0; // Cancel first
    }

    // A key hint, clicked (owner's request, 5 November 2026): does what its key does
    readonly property var hintKeys: ({
        "↵": [Qt.Key_Return, 0],
        "Shift ↵": [Qt.Key_Return, Qt.ShiftModifier],
        "Esc": [Qt.Key_Escape, 0],
        "Tab": [Qt.Key_Tab, 0],
        "Space": [Qt.Key_Space, 0],
        "→": [Qt.Key_Right, 0],
        "←": [Qt.Key_Left, 0],
        "Ctrl W": [Qt.Key_W, Qt.ControlModifier],
        "Ctrl F": [Qt.Key_F, Qt.ControlModifier],
        "Ctrl P": [Qt.Key_P, Qt.ControlModifier],
        "Ctrl M": [Qt.Key_M, Qt.ControlModifier],
        "Ctrl ⌫": [Qt.Key_Backspace, Qt.ControlModifier]
    })

    // back to typing after a click on a hint or a menu entry (from the menu's rows the field's id
    // read as undefined: "field is not defined", 9 November)
    function focusField() {
        field.forceActiveFocus();
    }

    function pressHint(label: string) {
        const k = hintKeys[label];
        if (!k)
            return;
        key({ key: k[0], modifiers: k[1], accepted: false });
        focusField();
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
            line("branch", "Branch", About.branch ? `${About.branch} · ${About.mood}` : "…", About.stable ? Icons.shieldCheck : Icons.flask),
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
    // `psc files` (Files). Its answer to the last query stays until the next one comes, kept to
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
        if (v !== null)
            return [{ kind: "calc", key: "calc", title: "= " + Calc.format(v), subtitle: q.trim() }];
        return looksLikeMaths(q) ? qalcRows(q) : [];
    }

    // what calc.js can't read but clearly is maths goes to qalc (owner, 9 November): digits with an
    // operator, a function call, or "to"/"in" between amounts; a plain name ("7zip", "firefox") doesn't
    function looksLikeMaths(q: string): bool {
        q = q.trim();
        return Qalc.installed && /\d/.test(q) && (/[\^*\/+=%!()]|\d\s*-\s*\d/.test(q) || /\b(sqrt|cbrt|sin|cos|tan|asin|acos|atan|log|ln|exp|abs|solve|integrate|diff|factorial|round|floor|ceil)\s*\(/i.test(q) || /\d\s*\S+\s+(to|in)\s+\S+/i.test(q));
    }

    // qalc's answer, as a row on top; Enter copies it. The last answer stays until the next comes.
    function qalcRows(q: string): var {
        Qt.callLater(Qalc.ask, q);
        const ready = Qalc.expression === q.trim();
        if (ready && Qalc.failed)
            return [];
        return [{ kind: "qalc", key: "qalc", title: ready ? "= " + Qalc.answer : "= …", subtitle: `${q.trim()} · libqalculate`, glyph: Icons.calculator, answer: ready ? Qalc.answer : "" }];
    }

    // (windows and workspaces are parameters only so the binding re-runs when a snapshot is taken)
    function buildRows(mode: string, q: string, windows, workspaces): var {
        if (editing)
            return [{ kind: "edit", key: "edit", question: { icon: editing.icon, title: editing.title, text: editBusy ? `Looking up “${q.trim()}”…` : editError || editing.hint(), error: editError !== "", code: "", entered: -1, input: true, choices: ["Cancel", "Save"] } }];
        if (confirming)
            return [{ kind: "confirm", key: "confirm:" + confirming.id, action: confirming, question: { icon: confirming.icon, danger: confirming.danger ?? false, title: confirming.question ?? `${confirming.title}?`, text: confirming.confirm, choices: ["Cancel", confirming.title] } }];
        let rows;
        if (/^(timer|alarm|stopwatch)(\s|$)/i.test(q) && (mode === "all" || mode === "apps")) {
            rows = clockRows(q);
        } else if (q.startsWith(";") && (mode === "all" || mode === "apps")) {
            const term = q.slice(1).trim();
            const items = (ShellSettings.clipboardHistory ? Clipboard.history : []).filter(item => !term || Fuzzy.match(term, item.text));
            rows = !ShellSettings.clipboardHistory ? [section("Clipboard history"), {kind:"empty", key:"clipboard-off", title:"Enable clipboard history in Settings → Apps & places"}] : [section("Clipboard history")].concat(items.map(item => ({kind:"clipboard", key:"clipboard:" + item.id, title:item.text, glyph:Icons.clipboard, clipId:item.id})),
                !term && Clipboard.history.length ? [{kind:"clipboard-clear", key:"clipboard-clear", title:"Clear clipboard history", glyph:Icons.close}] : [],
                !items.length ? [{kind:"empty", key:"clipboard-empty", title:term ? "No matching items" : "Clipboard history is empty"}] : []);
        } else if (q.startsWith(":") && (mode === "all" || mode === "apps")) {
            rows = emojiRows(q.slice(1).trim());
        } else if (q.startsWith("$") && (mode === "all" || mode === "apps")) {
            rows = commandRows(q.slice(1).trim());
        } else if (q.startsWith("/") && (mode === "all" || mode === "apps")) {
            rows = fileRows(q.slice(1).trim());
        } else if (q.startsWith("!") && (mode === "all" || mode === "apps")) {
            rows = notificationRows(q.slice(1).trim());
        } else if (q.startsWith("@") && (mode === "all" || mode === "apps")) {
            rows = webRows(q.slice(1).trim());
        } else if (q.startsWith("=") && Qalc.installed && (mode === "all" || mode === "apps")) {
            const e = q.slice(1).trim();
            rows = [section("libqalculate")].concat(e ? qalcRows(e) : [], e && Qalc.expression === e && Qalc.failed ? [{ kind: "empty", key: "qalcfail", title: "qalc couldn't read that" }] : [], e ? [] : [{ kind: "empty", key: "qalchint", title: "Equations, units, currencies, bases: = solve(x^2 = 4), = 5 km to mi" }]);
        } else if (/^kill(\s|$)/i.test(q) && (mode === "all" || mode === "apps")) {
            rows = processRows(q.slice(4).trim());
        } else if (/^tldr(\s|$)/i.test(q) && ShellSettings.integration("tldr") && (mode === "all" || mode === "apps")) {
            rows = tldrRows(q.slice(4).trim());
        } else if (/^m\s/i.test(q) && Cider.installed && Cider.enabled && (mode === "all" || mode === "apps")) {
            rows = musicRows(q.slice(2).trim());
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
        } else if (mode === "lenschoices") {
            rows = lensChoiceRows(q);
        } else if (mode === "about") {
            rows = aboutRows();
        } else if (!q) {
            const w = windowRows("", 5).map(r => Object.assign(r, { compact: true }));
            const frequent=frequentRows(3);
            rows = [section("Quick controls"), { kind: "controls", key: "controls" }].concat(frequent.length ? [section("Frequent")].concat(frequent) : []).concat(w.length ? [section("Open windows")].concat(w) : []);
        } else {
            // a search that names a quick control ("zen", "focus", "night") puts the controls first, so
            // the selection lands on that switch and Enter toggles it
            const words = q.trim().toLowerCase();
            const controlFirst = systemRows(q).some(r => r.kind !== "settingslink" && (r.title ?? "").toLowerCase().split(/\s+/).some(w => w.startsWith(words)));
            const a = appRows(q, 5), w = windowRows(q, 3), named = namedRows(q), presets = presetRows(q), projects = projectRows(q), codeProjects = codeProjectRows(q), games = gameRows(q);
            rows = calcRows(q).concat(a.length ? [section("Applications")].concat(a) : [], games.length ? [section("Games")].concat(games) : [], projects.length ? [section("CLion projects")].concat(projects) : [], codeProjects.length ? [section("VS Code")].concat(codeProjects) : []).concat(w.length ? [section("Windows")].concat(w) : [])
                .concat(named.length ? [section("Workspaces")].concat(named) : [], presets.length ? [section("Presets")].concat(presets) : [])
                .concat(powerRows(q), systemRows(q));
            if (controlFirst) {
                const controls = systemRows(q);
                rows = rows.filter(r => !controls.some(c => c.key === r.key)).filter((r, i, all) => r.kind !== "section" || (all[i + 1] && all[i + 1].kind !== "section"));
                rows = calcRows(q).concat(controls, rows.filter(r => !calcRows(q).some(c => c.key === r.key)));
            }
        }
        if ((mode === "all" || mode === "apps") && !q && !editing && !confirming) {
            const pins=LauncherTools.pins.map(d => LauncherTools.resolve(d)).filter(r => r);
            if (pins.length) rows=mode === "all" ? rows.slice(0,2).concat([section("Pinned")],pins,rows.slice(2)) : [section("Pinned")].concat(pins,rows);
        }
        if ((mode === "all" || mode === "apps") && q && !/^[\/$:=!@?]/.test(q)) {
            const alias=LauncherTools.resolve(LauncherTools.aliases[q.trim().toLowerCase()]);
            const actions=LauncherTools.actions.filter(a => a.available!==false && Fuzzy.match(q,a.name)).map(a => LauncherTools.resolve({kind:"action",target:a.id}));
            if (actions.length) rows=rows.concat([section("Shell actions")],actions);
            if (alias) rows=[section("Alias"),Object.assign({},alias,{key:"alias:"+q})].concat(rows);
        }
        if (expandedKey)
            rows = rows.reduce((all, r) => all.concat([r], r.key !== expandedKey ? [] : r.kind === "app" ? actionRows(r) : r.kind === "preset" ? [presetDeleteRow(r)] : []), []); // flatMap isn't there
        // "claude" and a question (owner's request, 1 November 2026): an Ask Claude row on top, while
        // Claude Desktop is installed; the usual results stay under it ("claude code" still finds apps)
        // "ask" (and a question): the quick chat, on top (owner's call, 13 November 2026)
        const asking = mode === "all" || mode === "apps" ? /^ask(?:\s+(.*))?$/i.exec(q) : null;
        if (asking) {
            const question = (asking[1] ?? "").trim();
            rows = [section("Ask AI"), { kind: "ask", key: "ask", title: question || "Quick chat", subtitle: question ? `Ask ${Chat.providerName} in the quick chat` : `A quick question to ${Chat.providerName}, above the bar`, glyph: Icons.sparkles, prompt: question }].concat(rows);
        }
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

    function scrollCurrent() {
        if(!list || current<0 || current>=rows.length)return;
        list.positionViewAtIndex(current,ListView.Contain);
        if(!Theme.tui || !["workspaces","controls"].includes(rows[current].kind))return;
        const item=list.itemAtIndex(current);if(!item)return;
        const top=item.y+column*Theme.tuiLauncherRowHeight;
        if(top<list.contentY)list.contentY=top;
        else if(top+Theme.tuiLauncherRowHeight>list.contentY+list.height)list.contentY=top+Theme.tuiLauncherRowHeight-list.height;
    }

    function selectable(i: int): bool {
        return i >= 0 && i < rows.length && !["section", "empty", "calc", "stat", "note"].includes(rows[i].kind) && !rows[i].off;
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
        if (row.kind === "clock-command") {
            row.run();
        } else if (row.kind === "shellaction") {
            open=false; LauncherTools.activateAction(row.descriptor);
        } else if (Theme.tui && row.kind === "btlink") {
            field.text="";mode="bluetooth";resetSelection();
        } else if (row.kind === "settingslink" || row.kind === "btlink") {
            open = false;
            settingsRequested(row.kind === "btlink" ? "bluetooth" : "appearance");
        } else if (row.kind === "app") {
            Apps.launch(row.app);
            open = false;
        } else if (row.kind === "cheat") {
            if (row.prefix)
                field.text = row.prefix;
        } else if (row.kind === "appaction") {
            Apps.launchAction(row.app, row.action);
            open = false;
        } else if (row.kind === "window") {
            if (Compositor.windows.find(w => w.address === row.address)?.minimized)
                Compositor.restore(row.address); // onto the workspace on screen, as the bar's pill does
            else
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
            if(Theme.tui && id==="bluetooth") {field.text="";mode="bluetooth";resetSelection();}
            else if (id === "bluetooth" || id === "ethernet") {
                open = false;
                settingsRequested(id === "bluetooth" ? "bluetooth" : "network");
            }
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
        } else if (row.kind === "ask") {
            askAfterFade.prompt = row.prompt;
            open = false;
            askAfterFade.restart(); // once the launcher has let the keyboard go
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
        } else if (row.kind === "project") {
            Library.openProject(row.project);
            open = false;
        } else if (row.kind === "game") {
            Library.play(row.game);
            open = false;
        } else if (row.kind === "process") {
            const g = row.process, many = g.pids.length > 1;
            confirming = { id: "kill:" + g.name, title: many ? "End all" : "End it", icon: Icons.close, danger: true, question: many ? `End all ${g.pids.length} ${g.name} processes?` : `End ${g.name} (PID ${g.pids[0]})?`, confirm: `${many ? "They close" : "It closes"} without asking, and unsaved work is lost.`, run: () => Processes.endAll(g, false) };
            current = 0;
            column = 0;
        } else if (row.kind === "qalc") {
            if (row.answer) {
                Clipboard.copyText(row.answer);
                open = false;
            }
        } else if (row.kind === "tldrman") {
            Quickshell.execDetached(Apps.inTerminal(["man", row.page], false, `man ${row.page}`));
            open = false;
        } else if (row.kind === "clipboard") {
            Clipboard.restoreHistory(row.clipId);
            open = false;
        } else if (row.kind === "clipboard-clear") {
            confirming = { id:"clear-clipboard", title:"Clear history", icon:Icons.close, danger:true, question:"Clear clipboard history?", confirm:"All saved clipboard items will be deleted.", run:() => Clipboard.clearHistory() };
            current = 0;
            column = 0;
        } else if (row.kind === "tldr") {
            Clipboard.copyText(row.command);
            open = false;
        } else if (row.kind === "music") {
            Cider.play(row.item, shift ? "next" : "now");
            open = false;
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
        } else if (row.kind === "lenschoice") {
            lensChoice = row.key;
            field.text = "";
            mode = "lenschoices";
        } else if (row.kind === "lensoption") {
            ShellSettings.setLensChoice(row.settingKey, row.value);
            leaveLensChoices();
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
        }
    }

    function key(event) {
        if (menu) {
            menu = null;
            if (event.key === Qt.Key_Escape) {
                event.accepted = true;
                return;
            }
        }
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
            if (confirming)
                confirming = null; // back to the results
            else if (editing)
                stopEditing();
            else if (mode === "lenschoices")
                leaveLensChoices();
            else if (mode === "terminals" || mode === "about")
                leaveTerminals();
            else if (Theme.tui && mode === "bluetooth") {field.text="";mode="system";}
            else
                open = false;
            break;
        case Qt.Key_Space:
            if (row?.kind!=="file" || row.entry.folder || editing) return;
            previewFile(row,"preview");
            break;
        case Qt.Key_F2:
            if (row?.kind === "workspaces" && row.cards[column] && !editing) {
                event.accepted = true;
                renameWorkspace(row.cards[column].id);
            }
            break;
        case Qt.Key_Tab:
        case Qt.Key_Backtab: {
            if (editing)
                break; // answer it first
            const i = modes.findIndex(m => m.id === mode);
            mode = modes[(i + (event.key === Qt.Key_Backtab ? -1 : 1) + modes.length) % modes.length].id;
            break;
        }
        case Qt.Key_Down:
        case Qt.Key_Up: {
            const direction=pressed===Qt.Key_Down?1:-1, previous=current;
            if(Theme.tui && row && ["workspaces","controls"].includes(row.kind) && column+direction>=0 && column+direction<gridLength(row)) column+=direction;
            else {
                current = step(current,direction);
                if(Theme.tui && current!==previous && rows[current] && ["workspaces","controls"].includes(rows[current].kind)) column=direction>0?0:gridLength(rows[current])-1;
            }
            scrollCurrent();
            break;
        }
        case Qt.Key_Left:
        case Qt.Key_Right:
            if (row?.kind === "slider" || row?.kind === "time")
                adjust(row, dir);
            else if (row && gridLength(row) > 0)
                column = Math.max(0, Math.min(gridLength(row) - 1, column + dir));
            // an app's actions: → opens them once the search's cursor is at its end (so → still moves
            // it while typing), ← closes them and goes back to the app
            else if (dir > 0 && row?.kind === "music" && field.cursorPosition === field.text.length)
                Cider.play(row.item, "later");
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
        case Qt.Key_P:
            if (!ctrl || row?.kind !== "window")
                return;
            Compositor.togglePin(row.address);
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
        if (/^kill(\s|$)/i.test(query))
            Processes.load();
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
        menu = null;
        if (open)
            Library.load();
        grab.active = open;
        hadKeyboard = false;
        if (!open) {
            editing = null; // closing leaves a setting as it was
        }
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
        onTriggered: root.scrollCurrent()
    }

    // the quick chat, once the launcher has faded and let the keyboard go (both take it exclusively)
    Timer {
        id: askAfterFade
        property string prompt
        interval: Theme.motionDuration + 60
        onTriggered: Chat.show(prompt)
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
            if(Theme.tui)root.toggleMode("bluetooth");
            else {root.open=false;root.settingsRequested("bluetooth");}
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

    PanelFrame {
        id: panel
        objectName:"launcher-panel"
        title:Theme.tui?"launcher":""
        detail:Theme.tui?(root.mode==="windows"?root.rows.filter(r=>r.kind==="window").length+" windows":root.mode==="workspaces"?root.workspaceCards(root.query).length+" workspaces":root.mode==="all"?"home":root.mode):""

        x: Math.round((root.width - width) / 2)
        width: Theme.tui?Theme.tuiLauncherWidth:640
        height: body.implicitHeight
        radius: Theme.tui?0:Theme.panelRadius
        color: Theme.tui?Theme.glass(Theme.bg):Theme.surface
        border.width: 1
        border.color: Theme.overlay2
        clip: !Theme.tui
        // fades in rising 12 px, and back
        opacity: reveal.progress
        y: Theme.tui?Theme.tuiLauncherTop:Math.round(root.height * 0.12) + 12 * (1 - reveal.progress) // its top at 12 % of the screen

        Item {
            id: body
            width: parent.width
            implicitHeight:searchArea.height+modeTabs.height+resultsArea.height+footer.height

            // search
            Item {
                id: searchArea
                width: parent.width
                height: Theme.tui?54:68
                y:Theme.tui?modeTabs.height:0
                Rectangle {visible:Theme.tui;x:12;anchors.bottom:parent.bottom;width:parent.width-24;height:1;color:Theme.tuiBorder}
                Text {visible:Theme.tui;x:12;anchors.verticalCenter:parent.verticalCenter;text:">";color:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize}

                Icon {
                    id: searchIcon
                    visible:!Theme.tui
                    x: Theme.tui?0:26
                    anchors.verticalCenter: parent.verticalCenter
                    size: Theme.tui?0:20
                    paths: root.editing ? root.editing.icon : Icons.search
                    color: Theme.subtext
                }

                TextInput {
                    id: field
                    objectName:"launcher-field"

                    anchors.left: searchIcon.right
                    anchors.leftMargin: Theme.tui?28:14
                    anchors.right: parent.right
                    anchors.rightMargin: 26
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.textBright
                    selectionColor: Theme.overlay2
                    selectedTextColor: Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.tui?Theme.tuiTextSize:20
                    font.weight: Theme.tui?Font.Medium:Font.DemiBold
                    focus: true
                    clip: true
                    Accessible.role: Accessible.EditableText
                    Accessible.name: root.placeholder
                    Keys.onPressed: event => root.key(event)

                    cursorDelegate: Rectangle {
                        width: Theme.tui?8:2
                        color: Theme.pistachio
                        opacity: field.readOnly ? 0 : 1
                    }

                    Text {
                        visible: field.text === ""
                        text: Theme.tui?root.placeholder.toLowerCase():root.placeholder
                        color: Theme.subtext
                        font: field.font
                    }
                }
            }

            // mode tabs
            Item {
                id: modeTabs
                width: parent.width
                height: Theme.tui?40:36+12
                y:Theme.tui?0:searchArea.height

                // the active tab's chip, one for all of them, so it slides to the next
                Rectangle {
                    visible:!Theme.tui
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

                    x: Theme.tui?12:18
                    y: Theme.tui?8:0
                    spacing: Theme.tui?0:6

                    Repeater {
                        id: tabs

                        model: root.modes

                        Item {
                            required property var modelData
                            readonly property bool active: modelData.id === root.tab

                            width: tabLabel.implicitWidth + (Theme.tui?12:32)
                            height: Theme.tui?32:36
                            Accessible.role: Accessible.PageTab
                            Accessible.name: modelData.label
                            Accessible.selected: active

                            Text {
                                id: tabLabel
                                anchors.centerIn: parent
                                text: Theme.tui?(parent.active?"[":"")+(parent.modelData.id==="all"?"home":parent.modelData.label.toLowerCase())+(parent.active?"]":""):parent.modelData.label
                                color: parent.active ? (Theme.tui?Theme.textBright:Theme.pistachio) : Theme.subtext
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.tui?Theme.tuiTextSize:13
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
                    visible:!Theme.tui
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.overlay
                }
            }

            // results
            Item {
                id:resultsArea
                y:searchArea.height+modeTabs.height
                width: parent.width
                height: list.height + (Theme.tui?0:22)

                ListView {
                    id: list
                    objectName:"launcher-results"

                    x: Theme.tui?0:8
                    y: Theme.tui?0:14
                    width: parent.width - (Theme.tui?0:16)
                    height: Math.min(contentHeight, 440, Math.max(0, root.height - (Theme.tui?Theme.tuiLauncherTop:Math.round(root.height*0.12)) - 24 - searchArea.height - modeTabs.height - (Theme.tui?0:22) - footer.height))
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    // A scroll bar while the mouse is in use (owner's request, 3 November 2026): it shows
                    // as the pointer moves over the list or the list is scrolled by wheel or drag, and
                    // fades a second later; it sits in the panel's margin right of the rows. Drag it, or
                    // click its track, to scroll.
                    HoverHandler {
                        id: listHover
                    }

                    Item {
                        id: scrollBar

                        readonly property bool needed: list.contentHeight > list.height + 1
                        readonly property point at: listHover.point.position
                        property bool awake

                        function wake() {
                            awake = true;
                            sleep.restart();
                        }

                        parent: list.parent // not in the list, which clips and scrolls its rows
                        x: Theme.tui?list.x+list.width-8:list.x+list.width+1
                        y: list.y
                        width: 6
                        height: list.height
                        visible: opacity > 0
                        opacity: needed && (awake || dragArea.containsMouse || dragArea.pressed) ? 1 : 0
                        onAtChanged: if (listHover.hovered) wake()

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.motionDuration
                                easing.type: Theme.easing
                            }
                        }

                        Connections {
                            target: list
                            function onMovingChanged() {
                                if (list.moving)
                                    scrollBar.wake();
                            }
                        }

                        Timer {
                            id: sleep
                            interval: 1000
                            onTriggered: scrollBar.awake = false
                        }

                        Rectangle {
                            id: thumb
                            width: parent.width
                            height: Math.max(32, parent.height * list.height / Math.max(1, list.contentHeight))
                            y: (parent.height - height) * Math.min(1, Math.max(0, (list.contentY - list.originY) / Math.max(1, list.contentHeight - list.height)))
                            radius: 3
                            color: dragArea.containsMouse || dragArea.pressed ? Theme.subtext : Theme.overlay2

                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.hoverDuration
                                    easing.type: Theme.easing
                                }
                            }
                        }

                        MouseArea {
                            id: dragArea

                            property real grabbed // where on the thumb it was taken

                            function scrollTo(y: real) {
                                const room = Math.max(1, scrollBar.height - thumb.height);
                                list.contentY = list.originY + Math.max(0, Math.min(1, (y - grabbed) / room)) * (list.contentHeight - list.height);
                            }

                            x: -4
                            width: parent.width + 8 // a wider target than the 6 px bar
                            height: parent.height
                            enabled: scrollBar.visible
                            hoverEnabled: true
                            onPressed: mouse => {
                                grabbed = mouse.y >= thumb.y && mouse.y <= thumb.y + thumb.height ? mouse.y - thumb.y : thumb.height / 2;
                                scrollTo(mouse.y);
                            }
                            onPositionChanged: mouse => {
                                if (pressed)
                                    scrollTo(mouse.y);
                            }
                        }
                    }
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
                    readonly property bool enterShown: glideShown && ((root.rows[root.current].prefix ?? "") !== "" || ["shellaction", "settingslink", "lenschoice", "lensoption", "app", "appaction", "window", "device", "btlink", "btdevice", "power", "emoji", "wplink", "setting", "termlink", "terminal", "showoff", "aboutlink", "abouturl", "wsname", "preset", "presetsave", "presetdelete", "project", "game", "process", "clock-command", "clipboard", "clipboard-clear", "tldr", "tldrman", "qalc", "music", "command", "file", "notification", "web", "drive", "claude", "ask"].includes(root.rows[root.current].kind))
                    // Opening and switching mode: for a moment, new rows rise into place one after
                    // another and the chip jumps to its row instead of gliding.
                    property bool entering

                    function enter() {
                        entering = !Theme.tui;
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
                        opacity: !Theme.tui && list.glideShown ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.motionDuration
                                easing.type: Theme.easing
                            }
                        }
                        Behavior on x {
                            enabled: !Theme.tui && !list.entering && !list.quick
                            NumberAnimation {
                                duration: Theme.motionDuration
                                easing.type: Theme.easing
                            }
                        }
                        Behavior on y {
                            enabled: !Theme.tui && !list.entering && !list.quick
                            NumberAnimation {
                                duration: Theme.motionDuration
                                easing.type: Theme.easing
                            }
                        }
                        Behavior on width {
                            enabled: !Theme.tui && !list.entering && !list.quick
                            NumberAnimation {
                                duration: Theme.motionDuration
                                easing.type: Theme.easing
                            }
                        }
                        Behavior on height {
                            enabled: !Theme.tui && !list.entering && !list.quick
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
                        readonly property int above: Theme.tui?0:(modelData.kind === "section" && index > 0 ? 10 : 0) + (modelData.gap ?? 0) + (cardTop ? 6 : 0)

                        width: ListView.view.width
                        height: above + loader.height + (!Theme.tui&&cardBottom ? 6 : 0)
                        transform: Translate {
                            id: rise
                        }

                        onSelectedChanged: if (selected) list.glideTo(box)
                        onBoxChanged: if (selected) list.glideTo(box)
                        // made while entering: fade in rising 8 px, 20 ms after the row above
                        Component.onCompleted: {
                            if (selected)
                                list.glideTo(box);
                            if (Theme.tui || !list.entering)
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
                            visible: !Theme.tui && entry.card !== ""
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
                            x: !Theme.tui && entry.card ? 6 : 0
                            y: entry.above
                            width: parent.width - (!Theme.tui && entry.card ? 12 : 0)
                            sourceComponent: Theme.tui?tuiView:({
                                section: sectionView,
                                empty: emptyView,
                                note: noteView,
                                tldrman: resultView,
                                qalc: resultView,
                                app: resultView,
                                shellaction: resultView,
                                appaction: resultView,
                                window: resultView,
                                device: resultView,
                                slider: sliderView,
                                stat: statView,
                                controls: controlsView,
                                workspaces: workspacesView,
                                btlink: resultView,
                                settingslink: resultView,
                                btdevice: resultView,
                                switch: switchView,
                                time: timeView,
                                calc: resultView,
                                emoji: resultView,
                                wplink: resultView,
                                setting: resultView,
                                termlink: resultView,
                                lenschoice: resultView,
                                lensoption: resultView,
                                aboutlink: resultView,
                                wsname: resultView,
                                preset: resultView,
                                presetsave: resultView,
                                presetdelete: resultView,
                                project: resultView,
                                game: resultView,
                                process: resultView,
                                "clock-command": resultView,
                                clipboard: resultView,
                                "clipboard-clear": resultView,
                                tldr: resultView,
                                music: resultView,
                                aboutline: resultView,
                                abouturl: resultView,
                                terminal: resultView,
                                showoff: resultView,
                                command: resultView,
                                file: resultView,
                                notification: resultView,
                                web: resultView,
                                claude: resultView,
                                ask: resultView,
                                drive: resultView,
                                cheat: cheatView,
                                power: resultView,
                                confirm: questionView,
                                edit: questionView
                            })[entry.modelData.kind]
                        }

                        Component {id:tuiView;TuiLauncherRow {width:loader.width;row:entry.modelData;rowIndex:entry.index;selected:entry.selected;controller:root}}
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

                                    TipHover {}
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

                                        TipHover {}
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

                                        TipHover {}
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

                        // a paragraph, wrapped (tldr's description)
                        Component {
                            id: noteView

                            Text {
                                width: loader.width
                                leftPadding: 18
                                rightPadding: 18
                                topPadding: 2
                                bottomPadding: 10
                                wrapMode: Text.Wrap
                                text: entry.modelData.title
                                textFormat: Text.PlainText
                                color: Theme.text
                                font.family: Theme.fontUi
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                lineHeight: 19
                                lineHeightMode: Text.FixedHeight
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
                                subtitle: row.kind === "app" && LauncherTools.pending[row.app.id] ? "Starting…" : row.off ? (current ? "current, nothing plugged in" : "Nothing plugged in")
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
                                    : row.kind === "window" ? (row.subtitle.includes(" · minimised") ? "Bring back" : "Switch")
                                    : row.kind === "device" && !current ? "Use"
                                    : row.kind === "emoji" ? "Copy"
                                    : row.kind === "wplink" ? "Open"
                                    : row.kind === "setting" ? "Change"
                                    : row.kind === "termlink" || row.kind === "lenschoice" ? "Choose"
                                    : row.kind === "lensoption" ? "Use"
                                    : row.kind === "aboutlink" ? "Show"
                                    : row.kind === "wsname" ? "Go"
                                    : row.kind === "preset" ? "Load"
                                    : row.kind === "presetsave" ? "Save"
                                    : row.kind === "presetdelete" ? "Delete"
                                    : row.kind === "project" ? "Open"
                                    : row.kind === "game" ? "Play"
                                    : row.kind === "process" ? "End"
                                    : row.kind === "tldr" ? "Copy"
                                    : row.kind === "tldrman" ? "Open"
                                    : row.kind === "qalc" ? "Copy"
                                    : row.kind === "music" ? "Play"
                                    : row.kind === "abouturl" ? "Open"
                                    : row.kind === "terminal" && row.name !== Apps.terminal ? "Use"
                                    : row.kind === "showoff" ? (Showoff.active ? "Stop" : "Start")
                                    : row.kind === "command" ? "Run"
                                    : row.kind === "file" ? "Open"
                                    : row.kind === "notification" ? "Show"
                                    : row.kind === "web" ? "Search"
                                    : row.kind === "claude" || row.kind === "ask" ? "Ask"
                                    : row.kind === "drive" ? "Eject"
                                    : row.kind === "btlink" ? "Devices"
                                    : row.kind === "btdevice" ? (bt.connected ? "Disconnect" : bt.paired ? "Connect" : "Pair")
                                    : ""
                                actionAlways: row.kind === "btdevice"
                                onClicked: {
                                    root.current = entry.index;
                                    root.activate(row, 0, false);
                                }
                                onMenuRequested: at => {
                                    root.current = entry.index;
                                    root.openMenu(row, 0, at);
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

                                    TipHover {}
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
                                readonly property real load: key === "shell" ? Math.max(0, SystemStats.shellCpu) : key === "cpu" ? Math.max(0, SystemStats.cpu) : key === "memory" ? SystemStats.memUsed / Math.max(1, SystemStats.memTotal) : disk ? 1 - disk.free / Math.max(1, disk.size) : SystemStats.gpu
                                readonly property bool known: key === "shell" ? SystemStats.shellCpu >= 0 : key !== "cpu" || SystemStats.cpu >= 0
                                // the shell's own: its CPU on the meter, its memory (with its helpers) here
                                readonly property string detail: key === "shell" ? `${SystemStats.shellMem >= 1024 ? (SystemStats.shellMem / 1024).toFixed(1) + " GB" : Math.round(SystemStats.shellMem) + " MB"} memory, with its helpers`
                                    : key === "cpu" ? (SystemStats.cpuTemp >= 0 ? `${Math.round(SystemStats.cpuTemp)} °C · ` : "") + SystemStats.cpuName
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
                                    paths: stat.key === "shell" ? Icons.sparkles : stat.key === "cpu" ? Icons.cpu : stat.key === "memory" ? Icons.memory : stat.disk ? Icons.hardDrive : Icons.gpu
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

                                        TipHover {}
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
                                        onMenuRequested: at => {
                                            root.current = entry.index;
                                            root.column = index;
                                            root.openMenu(entry.modelData, index, at);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Wrap hints within the same panel, preserving their click actions.
            KeyHints {
                id: footer
                y:resultsArea.y+resultsArea.height
                width: parent.width
                hints: root.keyHints
                clickableKeys: root.hintKeys
                onActivated: key => root.pressHint(key)
            }
        }
    }

    // the right-click menu, over everything; a click beside it (or Esc, or any key) closes it
    MouseArea {
        anchors.fill: parent
        visible: root.menu !== null
        acceptedButtons: Qt.AllButtons
        onPressed: root.menu = null
    }

    Item {
        id: menuCard

        visible: root.menu !== null
        x: Math.max(8, Math.min(root.menu?.x ?? 0, root.width - width - 8))
        y: Math.max(8, Math.min(root.menu?.y ?? 0, root.height - height - 8))
        width: 240
        height: menuColumn.implicitHeight + 12

        Shadow {
            kind: Theme.shadowSmall
            anchors.fill: menuPanel
            radius: menuPanel.radius
        }

        Rectangle {
            id: menuPanel
            anchors.fill: parent
            radius: Theme.tileRadius
            color: Theme.bgAlt
            border.width: 1
            border.color: Theme.overlay2
            Accessible.role: Accessible.PopupMenu
        }

        Column {
            id: menuColumn
            x: 6
            y: 6
            width: parent.width - 12

            Repeater {
                model: root.menu?.entries ?? []

                Rectangle {
                    id: menuEntry

                    required property var modelData

                    width: menuColumn.width
                    height: 36
                    radius: 14
                    color: menuEntryMouse.containsMouse ? Theme.overlay : "transparent"
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: modelData.text

                    Icon {
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        size: 16
                        paths: menuEntry.modelData.glyph
                        color: menuEntry.modelData.danger ? Theme.terracotta : Theme.subtext
                    }

                    Text {
                        x: 40
                        width: parent.width - 52
                        anchors.verticalCenter: parent.verticalCenter
                        text: menuEntry.modelData.text
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: menuEntryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // closing the menu destroys this entry, and `root` with its context: keep both first
                            const run = menuEntry.modelData.run, launcher = root;
                            launcher.menu = null;
                            run();
                            launcher.focusField();
                        }
                    }
                }
            }
        }
    }

    // HoverTip's card: the whole of a text cut short with "…", under it
    Rectangle {
        readonly property Item target: HoverTip.item
        readonly property point at: target ? target.mapToItem(null, 0, target.height) : Qt.point(0, 0)

        visible: HoverTip.shown && target !== null && root.open && root.menu === null
        x: Math.max(8, Math.min(at.x - 12, root.width - width - 8))
        y: at.y + 6
        width: tipText.width + 24
        height: tipText.implicitHeight + 16
        radius: 12
        color: Theme.bgAlt
        border.width: 1
        border.color: Theme.overlay2

        Text {
            id: tipText
            x: 12
            y: 8
            width: Math.min(implicitWidth, 480)
            wrapMode: Text.Wrap
            text: HoverTip.text
            textFormat: Text.PlainText
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Font.Medium
        }
    }
}
