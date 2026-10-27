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
        windows: [["↑↓", "navigate"], ["↵", "switch"], ["Ctrl W", "close window"], ["Esc", "close"]],
        workspaces: [["←→", "choose"], ["↵", "go"], ["Shift ↵", "move window here"], ["Esc", "close"]],
        system: [["↑↓", "navigate"], ["←→", "adjust"], ["↵", "switch / select"], ["Ctrl M", "mute"], ["Esc", "close"]],
        // Ctrl, unlike the board's plain ⌫: Backspace also edits the search, and forgetting is not undoable
        bluetooth: [["↑↓", "navigate"], ["↵", "connect / disconnect"], ["Ctrl ⌫", "forget device"], ["Esc", "close"]]
    })

    property bool open
    property string mode: "all"
    property var confirming: null // a power action waiting for a yes: the results make way for the question
    readonly property string query: field.text
    // The pairing agent's question (Bluetooth.request) also takes the place of the results; the
    // launcher opens for it. A PIN or passkey is typed into the search field.
    readonly property bool codeWanted: Bluetooth.request?.kind === "pin" || Bluetooth.request?.kind === "passkey"
    readonly property bool codeValid: Bluetooth.request?.kind === "pin" ? query.length > 0 : /^\d{1,6}$/.test(query)
    // Windows and workspaces as they were when the launcher opened, so the rows only change when you
    // type or switch mode, not under the cursor (window titles change all the time).
    property var windows: []
    property var workspaces: []
    readonly property var rows: buildRows(mode, query, windows, workspaces)
    property int current: -1 // selected row
    property int column: 0 // selected tile or card within a grid row

    function snapshot() {
        windows = Compositor.windows;
        workspaces = Compositor.workspaces;
    }

    // Bluetooth is a view inside System (LauncherBluetooth board), so it has no tab of its own;
    // the System tab stays highlighted.
    readonly property string tab: mode === "bluetooth" ? "system" : mode
    readonly property string placeholder: Bluetooth.request ? (Bluetooth.request.kind === "pin" ? "PIN" : Bluetooth.request.kind === "passkey" ? "6-digit code" : "Bluetooth")
        : mode === "bluetooth" ? "Filter devices…" : modes.find(m => m.id === mode).placeholder
    readonly property var keyHints: Bluetooth.request ? (codeWanted ? [["↵", "pair"], ["Esc", "cancel"]]
            : Bluetooth.request.id ? [["←→", "choose"], ["↵", "confirm"], ["Esc", "decline"]]
            : [["Esc", "cancel pairing"]])
        : confirming ? [["←→", "choose"], ["↵", "confirm"], ["Esc", "back"]]
        : hints[mode]
    // scan for new devices only while the Bluetooth view is on screen
    readonly property bool scanWanted: open && mode === "bluetooth" && Bluetooth.ready
    onScanWantedChanged: Bluetooth.setScanning(scanWanted)

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
        snapshot();
        mode = m === "bluetooth" || modes.some(x => x.id === m) ? m : "all";
        field.text = "";
        resetSelection();
        open = true;
        field.forceActiveFocus();
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

    function appRows(q: string, limit: int): var {
        const byName = Apps.list.slice().sort((a, b) => a.name.localeCompare(b.name));
        let hits = ranked(byName, q, a => a.name, limit);
        // also find apps by what they are ("browser" finds Firefox), below name matches, unhighlighted;
        // this needs the whole query in the description, not scattered letters
        if (q && hits.length < limit) {
            const ql = q.toLowerCase();
            const extra = byName.filter(a => !hits.some(h => h.item === a) && [a.genericName, ...a.keywords].join(" ").toLowerCase().includes(ql));
            hits = hits.concat(extra.slice(0, limit - hits.length).map(a => ({ item: a, indices: [] })));
        }
        return hits.map(h => ({
            kind: "app",
            key: "app:" + h.item.id,
            title: h.item.name,
            indices: h.indices,
            subtitle: h.item.genericName || h.item.comment,
            icon: Apps.icon(h.item.icon),
            app: h.item
        }));
    }

    function windowRows(q: string, limit: int): var {
        const active = workspaces.find(w => w.active)?.id ?? 0;
        const recent = windows.slice().sort((a, b) => a.recency - b.recency);
        return ranked(recent, q, w => w.title || w.appId, limit).map(h => ({
            kind: "window",
            key: "window:" + h.item.address,
            title: h.item.title || h.item.appId,
            indices: h.indices,
            subtitle: h.item.appId + (h.item.recency === 0 ? " · focused" : h.item.urgent ? " · needs attention" : ""),
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
            if (q && !String(id).startsWith(q) && !apps.some(a => a.toLowerCase().includes(q.toLowerCase())))
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
        if (Brightness.available)
            audio.push({ kind: "slider", key: "brightness", title: "Brightness" });
        const night = [{ kind: "switch", key: "nightlight", title: "Night light", icon: Icons.moon, on: () => NightLight.enabled, status: () => NightLight.status, toggle: () => NightLight.setEnabled(!NightLight.enabled) }];
        if (NightLight.available)
            night.push({ kind: "slider", key: "warmth", title: "Warmth" },
                { kind: "switch", key: "schedule", title: "Schedule", icon: Icons.clock, on: () => NightLight.scheduled, status: () => NightLight.scheduleText, toggle: () => NightLight.setSchedule(!NightLight.scheduled, NightLight.from, NightLight.to) },
                { kind: "time", key: "from", title: "Turns on" },
                { kind: "time", key: "to", title: "Turns off" });
        const bluetooth = [bluetoothSwitch(), { kind: "btlink", key: "btlink", title: "Scan for devices" }];
        const cards = card("Audio", q, audio).concat(card("Night light", q, night), card("Bluetooth", q, bluetooth));
        cards.forEach((r, i) => r.gap = i > 0 && (r.card === "top" || r.card === "single") ? 10 : 0);
        const streams = Audio.streams.map(n => ({ kind: "slider", key: "stream:" + n.id, title: Audio.appName(n), node: n }));
        const devices = Audio.sinks.map(n => ({ kind: "device", key: "device:" + n.id, title: Audio.deviceName(n), node: n }));
        const keep = r => !q || Fuzzy.match(q, r.title);
        const a = streams.filter(keep), d = devices.filter(keep);
        // the shell's own look, at the end (owner's request; not on the board)
        const shell = card("Shell settings", q, [
            { kind: "switch", key: "shadows", title: "Drop shadows", icon: Icons.layers, on: () => ShellSettings.shadows, status: () => ShellSettings.shadows ? "Under panels and popups" : "Off", toggle: () => ShellSettings.setShadows(!ShellSettings.shadows) },
            { kind: "switch", key: "quietFullscreen", title: "Quiet in fullscreen", icon: Icons.bellOff, on: () => ShellSettings.quietFullscreen, status: () => ShellSettings.quietFullscreen ? "Toasts wait while a fullscreen window has focus" : "Off", toggle: () => ShellSettings.setQuietFullscreen(!ShellSettings.quietFullscreen) }
        ]);
        return cards.concat(a.length ? [section("Apps")].concat(a) : []).concat(d.length ? [section("Output device")].concat(d) : []).concat(shell.length ? [section("Shell settings")].concat(shell) : []);
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
        const lower = q.toLowerCase();
        const hits = powerActions.map(a => ({ a: a, m: Fuzzy.match(q, a.title) })).filter(h => h.m || h.a.words.some(w => w.includes(lower)));
        const rows = hits.map(h => ({ kind: "power", key: "power:" + h.a.id, title: h.a.title, subtitle: h.a.confirm ? "Asks first" : "Locks the screen right away", indices: h.m?.indices ?? [], glyph: h.a.icon, danger: h.a.danger ?? false, action: h.a }));
        return rows.length ? [section("Power")].concat(rows) : [];
    }

    // the answer when the query is a calculation, e.g. "12*3"; shown only (no clipboard, owner's call)
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
        if (confirming)
            return [{ kind: "confirm", key: "confirm:" + confirming.id, action: confirming, question: { icon: confirming.icon, danger: confirming.danger ?? false, title: `${confirming.title}?`, text: confirming.confirm, choices: ["Cancel", confirming.title] } }];
        let rows;
        if (mode === "apps") {
            rows = calcRows(q).concat([section("Applications")], appRows(q, 200));
        } else if (mode === "windows") {
            const w = windowRows(q, 50);
            rows = [section(`${w.length} window${w.length === 1 ? "" : "s"} · most recent first`)].concat(w);
        } else if (mode === "workspaces") {
            const cards = workspaceCards(q);
            rows = [section(`${cards.length} workspaces`)].concat(cards.length ? [{ kind: "workspaces", key: "workspaces", cards: cards }] : []);
        } else if (mode === "system") {
            rows = systemRows(q).concat(powerRows(q));
        } else if (mode === "bluetooth") {
            rows = bluetoothRows(q);
        } else if (!q) {
            const w = windowRows("", 5).map(r => Object.assign(r, { compact: true }));
            rows = [section("Quick controls"), { kind: "controls", key: "controls" }].concat(w.length ? [section("Open windows")].concat(w) : []);
        } else {
            const a = appRows(q, 5), w = windowRows(q, 3);
            rows = calcRows(q).concat(a.length ? [section("Applications")].concat(a) : []).concat(w.length ? [section("Windows")].concat(w) : []).concat(powerRows(q), systemRows(q));
        }
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
        return i >= 0 && i < rows.length && !["section", "empty", "calc"].includes(rows[i].kind);
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
        else if (row.key === "brightness")
            Brightness.set(Brightness.value + dir * 0.05);
        else if (row.key === "warmth")
            NightLight.setTemperature(Math.max(2500, Math.min(6500, NightLight.temperature + dir * 250)));
        else if (row.kind === "time")
            NightLight.setSchedule(NightLight.scheduled, NightLight.from + (row.key === "from" ? dir * 15 : 0), NightLight.to + (row.key === "to" ? dir * 15 : 0));
    }

    function activate(row, col: int, shift: bool) {
        if (row.kind === "app") {
            Apps.launch(row.app);
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
            Audio.setSink(row.node);
        } else if (row.kind === "slider" && row.node) {
            Audio.toggleStreamMute(row.node);
        } else if (row.kind === "slider" && row.key === "volume") {
            Audio.toggleMute();
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
        event.accepted = false; // unhandled keys go on to the search field
        switch (pressed) {
        case Qt.Key_Escape:
            if (Bluetooth.request)
                Bluetooth.answer(false, ""); // back to the devices
            else if (confirming)
                confirming = null; // back to the results
            else
                open = false;
            break;
        case Qt.Key_Tab:
        case Qt.Key_Backtab: {
            if (Bluetooth.request)
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
            else if (vim)
                field.cursorPosition = Math.max(0, Math.min(field.text.length, field.cursorPosition + dir));
            else
                return; // the search field moves its cursor
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (selectable(current))
                activate(row, column, shift);
            break;
        case Qt.Key_W:
            if (!ctrl || row?.kind !== "window")
                return;
            Compositor.close(row.address);
            resnap.restart();
            break;
        case Qt.Key_M:
            if (!ctrl)
                return;
            Audio.toggleMute();
            break;
        case Qt.Key_Backspace:
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
        list.enter(); // the new rows rise into place
        resetSelection();
    }
    onConfirmingChanged: list.enter() // a question in place of the results, or back from it
    onQueryChanged: {
        confirming = null; // typing goes back to searching
        resetSelection();
    }
    // rows also change under the launcher (windows open and close); keep the selection valid
    onRowsChanged: if (!selectable(current)) resetSelection()

    onOpenChanged: {
        grab.active = open;
        if (!open)
            Bluetooth.answer(false, ""); // closing declines a question still waiting
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

    visible: reveal.shown
    anchors.top: true // only the top edge is anchored, so the compositor centres it horizontally
    margins.top: Math.round(screen.height * 0.12) - shadow.above // the panel's top at 12 % of the screen
    exclusiveZone: 0
    implicitWidth: shadow.side + panel.width + shadow.side
    implicitHeight: shadow.above + panel.height + shadow.below
    color: "transparent"
    mask: Region {
        item: panel // the shadow's room lets clicks through (and a click there closes, as outside)
    }
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

    // after closing a window, show the list without it once Hyprland has reported the close
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
    Shadow {
        id: shadow
        kind: Theme.shadowModal
        anchors.fill: panel
        radius: panel.radius
        opacity: panel.opacity
    }

    Rectangle {
        id: panel

        x: shadow.side
        width: 640
        height: body.implicitHeight
        radius: Theme.panelRadius
        color: Theme.bgAlt
        border.width: 1
        border.color: Theme.overlay2
        clip: true
        // fades in rising 12 px, and back
        opacity: reveal.progress
        y: shadow.above + 12 * (1 - reveal.progress)

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
                    paths: Bluetooth.request ? Icons.bluetooth : Icons.search
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
                    readonly property bool glideShown: root.selectable(root.current) && !["controls", "workspaces", "confirm", "pairing"].includes(root.rows[root.current].kind)
                    // the ↵ chip rides on it, shown on result rows (ResultRow leaves it room)
                    readonly property bool enterShown: glideShown && ["app", "window", "device", "btlink", "btdevice", "power"].includes(root.rows[root.current].kind)
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
                                window: resultView,
                                device: resultView,
                                slider: sliderView,
                                controls: controlsView,
                                workspaces: workspacesView,
                                btlink: resultView,
                                btdevice: resultView,
                                switch: switchView,
                                time: timeView,
                                calc: resultView,
                                power: resultView,
                                confirm: questionView,
                                pairing: questionView
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
                                readonly property bool start: entry.modelData.key === "from"

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
                                    minutes: parent.start ? NightLight.from : NightLight.to
                                    onStepped: m => parent.start ? NightLight.setSchedule(NightLight.scheduled, m, NightLight.to) : NightLight.setSchedule(NightLight.scheduled, NightLight.from, m)
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
                                        wrapMode: Text.Wrap
                                        color: Theme.subtext
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
                                            readonly property bool disabled: (question.q.input ?? false) && index === 1 && !root.codeValid
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
                                readonly property bool current: row.kind === "device" && Audio.sink === row.node
                                readonly property var bt: row.device // Bluetooth device rows; read live

                                width: loader.width
                                compact: row.compact ?? false
                                selected: entry.selected
                                title: row.title
                                indices: row.indices ?? []
                                subtitle: row.kind === "device" ? (current ? "current" : "")
                                    : row.kind === "btdevice" ? Bluetooth.status(bt)
                                    : row.kind === "btlink" ? (Bluetooth.enabled ? "Pair, connect and forget devices" : "Bluetooth is off")
                                    : row.subtitle ?? ""
                                icon: row.icon ?? ""
                                glyph: row.glyph ?? (row.kind === "device" ? Icons.volume : row.kind.startsWith("bt") ? Icons.bluetooth : row.kind === "calc" ? Icons.calculator : Icons.window)
                                glyphColor: row.danger ? Theme.terracotta : row.kind === "btdevice" && bt.connected ? Theme.sageBlue : Theme.subtext
                                badge: row.badge ?? ""
                                badgeActive: row.badgeActive ?? false
                                action: row.kind === "power" ? (row.action.confirm ? `${row.title}…` : row.title)
                                    : row.kind === "window" ? "Switch"
                                    : row.kind === "device" && !current ? "Use"
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
                                readonly property real value: node ? node.audio?.volume ?? 0 : volume ? Audio.volume : warmth ? NightLight.temperature : Brightness.value
                                readonly property bool muted: node ? node.audio?.muted ?? false : volume && Audio.muted

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
                                    paths: parent.volume || parent.node ? (parent.muted ? Icons.volumeMuted : Icons.volume) : parent.warmth ? Icons.thermometer : Icons.sun
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
                                    onMoved: parent.node ? Audio.setStreamVolume(parent.node, value) : parent.volume ? Audio.setVolume(value) : parent.warmth ? NightLight.setTemperature(value) : Brightness.set(value)
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
