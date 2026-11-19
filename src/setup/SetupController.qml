import qs
import qs.services
import Quickshell
import QtQuick

// Wires the first-run view to the shell's services, the way Settings' pages do: the view shows
// what the services report and every choice goes through the same setters Settings uses, so a
// choice applies at once and lands in the same saved state. Nothing new is stored but setupDone.
QtObject {
    id: root
    required property var wizard

    readonly property string home: Quickshell.env("HOME")
    function tilde(path: string): string { return path.startsWith(home) ? "~" + path.slice(home.length) : path; }
    function percent(v: real): string { return Math.round(v * 100) + "%"; }
    readonly property string lensPrefix: ShellSettings.lensProvider === "codex" ? "lensCodex" : "lensClaude"
    readonly property bool claude: FirstRun.found.claude === true
    readonly property bool codex: FirstRun.found.codex === true
    readonly property bool checked: Object.keys(FirstRun.found).length > 0

    // TEMPORARY dry run (FirstRun.dryRun): choices land here, over the live values, and go nowhere else
    property var dryValues: ({})
    readonly property Connections dryReset: Connections {
        target: FirstRun
        function onDryRunChanged() { root.dryValues = ({}); }
    }
    readonly property var values: Object.assign({}, liveValues, FirstRun.dryRun ? dryValues : {})
    readonly property var liveValues: ({
        colourScheme: ShellSettings.colourScheme,
        frostStyle: !ShellSettings.frosted ? "off" : ShellSettings.glassy ? "glassy" : "subtle",
        shadows: ShellSettings.shadows,
        desktopIcons: Desktop.enabled,
        wallpaper: Wallpapers.current,
        outputLevel: Audio.sink ? Audio.volume : undefined,
        inputLevel: Audio.source ? Audio.micVolume : undefined,
        outputDevice: Audio.sink?.id,
        inputDevice: Audio.source?.id,
        brightness: Brightness.available ? Brightness.value : undefined,
        nightLight: NightLight.available ? NightLight.enabled : undefined,
        quietFullscreen: ShellSettings.quietFullscreen,
        quietCalls: ShellSettings.quietCalls,
        notificationSound: ShellSettings.notificationSound,
        bluetooth: Bluetooth.present ? Bluetooth.enabled : undefined,
        localSend: LocalSend.available ? LocalSend.wanted : undefined,
        lensProvider: ShellSettings.lensProvider,
        lensModel: Store.saved[lensPrefix + "Model"],
        lensEffort: Store.saved[lensPrefix + "Effort"],
        lensFallback: Store.saved[lensPrefix + "Fallback"],
        terminal: Apps.terminal,
        weatherLocation: Weather.placeName
    })

    function devices(input: bool): var {
        return (input ? Audio.sources : Audio.sinks).map(n => ({ value: n.id, title: Audio.deviceName(n), disabled: Audio.isUnplugged(n) }));
    }
    readonly property var options: ({
        wallpaper: Wallpapers.images.slice(0, 8).map(i => ({ value: i.path, title: i.name, source: "file://" + i.path })),
        outputDevice: devices(false),
        inputDevice: devices(true),
        lensProvider: [
            { value: "claude", title: "Claude", subtitle: !checked ? "Not checked yet" : claude ? "Found" : "Not found · optional", disabled: checked && !claude },
            { value: "codex", title: "ChatGPT", subtitle: !checked ? "Not checked yet" : codex ? "Found" : "Not found · optional", disabled: checked && !codex }
        ],
        lensModel: ShellSettings.lensChoices[lensPrefix + "Model"],
        lensEffort: ShellSettings.lensChoices[lensPrefix + "Effort"],
        terminal: Apps.terminalChoices.map(v => ({ value: v, title: Apps.terminalName(v) }))
    })

    readonly property var details: ({
        outputDevice: Audio.sink ? Audio.deviceName(Audio.sink) : "",
        inputDevice: Audio.source ? Audio.deviceName(Audio.source) : "",
        brightness: Brightness.available ? "Your external display, over DDC/CI" : "Brightness unavailable: no DDC/CI display or ddcutil found",
        nightLight: NightLight.available ? `Warmth ${NightLight.temperature} K` : "Install hyprsunset to enable night light",
        bluetooth: !Bluetooth.present ? "No Bluetooth adapter found" : "Pair headphones, keyboards and speakers",
        localSendName: LocalSend.available ? LocalSend.name : "",
        ethernet: Network.connected ? `Wired · connected${Network.speed > 0 ? " · " + (Network.speed >= 1000 ? Network.speed / 1000 + " Gbps" : Network.speed + " Mbps") : ""}. The shell shows wired status only.`
            : Network.hasLink ? "Cable connected, waiting for a network" : "Not connected",
        lensFallback: ShellSettings.lensProvider === "codex" ? (claude ? "If ChatGPT is unavailable · one attempt" : "Needs Claude Code")
            : (codex ? "If Claude is unavailable · one attempt" : "Needs Codex CLI"),
        lensArchive: "Saved chats go to ~/lens-chats.",
        terminal: `${Apps.terminalName(Apps.terminal)} opens commands, terminal apps and showoff.`,
        weather: "Only the city’s coordinates are sent, every 30 minutes." + (weatherError ? " " + weatherError : ""),
        wallpaperFolder: tilde(Wallpapers.folder),
        wallpaperEmpty: `No pictures in ${tilde(Wallpapers.folder)} yet. Put some there and pick one in the wallpaper switcher.`,
        screenshotFolder: "Saved in " + tilde(Screenshots.folder),
        bindTip: 'hl.bind("SUPER + space", hl.dsp.exec_cmd("psc launcher toggle"))'
    })
    property string weatherError

    readonly property var available: ({
        desktopIcons: !Theme.tui, // Classic-only
        localSend: LocalSend.available,
        lensProvider: !checked || claude || codex,
        lensFallback: ShellSettings.lensProvider === "codex" ? claude : codex,
        wallpaper: Wallpapers.images.length > 0,
        restoreChoose: true
    })

    readonly property var devicesList: Bluetooth.paired.slice(0, 4).map(d => ({ title: Bluetooth.name(d), detail: Bluetooth.status(d) }))

    readonly property var summary: [
        { title: "Look", detail: `${ShellSettings.colourScheme === "noir" ? "Noir" : "Pistachio Noir"} · ${!ShellSettings.frosted ? "solid" : ShellSettings.glassy ? "glassy" : "subtle"} panels` },
        { title: "Sound", detail: Audio.sink ? `${Audio.deviceName(Audio.sink)}, ${percent(Audio.volume)}` : "No output" },
        { title: "Notifications", detail: (ShellSettings.quietFullscreen || ShellSettings.quietCalls ? "Quiet in " + [ShellSettings.quietFullscreen ? "fullscreen" : "", ShellSettings.quietCalls ? "calls" : ""].filter(x => x).join(" and ") + ", " : "") + (ShellSettings.notificationSound ? "sound on" : "sound off") },
        { title: "Connections", detail: `Bluetooth ${Bluetooth.enabled ? "on" : "off"}${LocalSend.available ? ", LocalSend " + (LocalSend.wanted ? "on" : "off") : ""}` },
        { title: "Lens", detail: !checked || claude || codex ? `${ShellSettings.lensProvider === "codex" ? "ChatGPT" : "Claude"}, ${ShellSettings.lensLabel(lensPrefix + "Model")}` : "No assistant installed" },
        { title: "Places", detail: [Apps.terminalName(Apps.terminal), Weather.placeName].filter(x => x).join(", ") }
    ]

    // examples from the README's keybind set (owner's call: a tip with psc commands, not a key list)
    readonly property var shortcuts: [
        { title: "Launcher", note: "Super Space", detail: "psc launcher toggle" },
        { title: "Quick settings", note: "Super A", detail: "psc quicksettings toggle" },
        { title: "Notifications", note: "Super N", detail: "psc notifications toggle" },
        { title: "Power menu", note: "Super Esc", detail: "psc power toggle" },
        { title: "Screenshot", note: "Print", detail: "psc screenshot region" },
        { title: "Overview", note: "Super O", detail: "psc overview toggle" }
    ]
    readonly property var commands: [
        { command: "psc status", detail: "Running? Memory and helpers" },
        { command: "psc doctor", detail: "What's installed, what's missing" },
        { command: "psc ipc", detail: "Every command you can bind" },
        { command: "psc log --errors", detail: "Recent errors only" },
        { command: "psc restart", detail: "Stop and start the shell" },
        { command: "psc setup", detail: "Open this setup again" }
    ]

    readonly property var restore: ({
        state: Preferences.busy ? "busy" : Preferences.reviewing ? "reviewing" : Preferences.missing ? "missing" : Preferences.failed ? "error" : "idle",
        path: tilde(Preferences.source),
        message: Preferences.missing ? `Nothing at ${tilde(Preferences.source)}. Choose the settings.toml you exported.` : Preferences.status,
        changes: Preferences.changes.map(c => ({ title: c.title, from: c.from, to: c.to })),
        skipped: Preferences.skipped.length
    })

    readonly property list<QtObject> bindings: [
        Binding { target: root.wizard; property: "values"; value: root.values },
        Binding { target: root.wizard; property: "options"; value: root.options },
        Binding { target: root.wizard; property: "details"; value: root.details },
        Binding { target: root.wizard; property: "available"; value: root.available },
        Binding { target: root.wizard; property: "devices"; value: root.devicesList },
        Binding { target: root.wizard; property: "summary"; value: root.summary },
        Binding { target: root.wizard; property: "shortcuts"; value: root.shortcuts },
        Binding { target: root.wizard; property: "commands"; value: root.commands },
        Binding { target: root.wizard; property: "restore"; value: root.restore },
        Binding { target: root.wizard; property: "checkState"; value: FirstRun.checkState },
        Binding { target: root.wizard; property: "checks"; value: FirstRun.checks },
        Binding { target: root.wizard; property: "checkTotal"; value: FirstRun.checkTotal },
        Binding { target: root.wizard; property: "checkNote"; value: FirstRun.checkNote },
        Binding { target: root.wizard; property: "reducedMotion"; value: GameMode.active }
    ]

    function setValue(key: string, value) {
        if (FirstRun.dryRun) { // TEMPORARY
            const next = Object.assign({}, dryValues);
            next[key] = value;
            dryValues = next;
            return;
        }
        const node = list => list.find(n => n.id === value);
        switch (key) {
        case "colourScheme": ShellSettings.setColourScheme(value); break;
        case "frostStyle": ShellSettings.setGlassy(value === "glassy"); ShellSettings.setFrosted(value !== "off"); break;
        case "shadows": ShellSettings.setShadows(value); break;
        case "desktopIcons": Desktop.setEnabled(value); break;
        case "wallpaper": Wallpapers.set(value); break;
        case "outputLevel": Audio.setVolume(value); break;
        case "inputLevel": Audio.setMicVolume(value); break;
        case "outputDevice": { const n = node(Audio.sinks); if (n && !Audio.isUnplugged(n)) Audio.setSink(n); break; }
        case "inputDevice": { const n = node(Audio.sources); if (n && !Audio.isUnplugged(n)) Audio.setSource(n); break; }
        case "brightness": Brightness.set(value); break;
        case "nightLight": NightLight.setEnabled(value); break;
        case "quietFullscreen": ShellSettings.setQuietFullscreen(value); break;
        case "quietCalls": ShellSettings.setQuietCalls(value); break;
        case "notificationSound": ShellSettings.setNotificationSound(value); break;
        case "bluetooth": Bluetooth.setEnabled(value); break;
        case "localSend": LocalSend.setReceive(value); break;
        case "lensProvider": ShellSettings.setLensChoice("lensProvider", value); break;
        case "lensModel": ShellSettings.setLensChoice(lensPrefix + "Model", value); break;
        case "lensEffort": ShellSettings.setLensChoice(lensPrefix + "Effort", value); break;
        case "lensFallback": ShellSettings.setLensFallback(ShellSettings.lensProvider, value); break;
        case "terminal": Apps.setTerminal(value); break;
        case "weatherLocation":
            weatherError = "";
            Weather.lookup(value, (place, problem) => {
                if (problem) root.weatherError = problem;
                else Weather.setCity(place.name);
            });
            break;
        }
    }

    readonly property Connections handlers: Connections {
        target: root.wizard
        function onCheckRequested() { FirstRun.check(); }
        function onValueRequested(key, value) { root.setValue(key, value); }
        function onActionRequested(action, payload) {
            if (action === "copyCommand" && payload) Clipboard.copyText(String(payload));
            else if (action === "playNotificationSound") FirstRun.playSound();
            else if (action === "restoreReview") Preferences.review("");
            else if (action === "restoreChoose") FirstRun.chooseRestoreFile();
            else if (action === "restoreApply") { if (!FirstRun.dryRun) Preferences.apply(); else Preferences.cancel(); } // TEMPORARY dry-run guard
            else if (action === "restoreCancel") Preferences.cancel();
        }
        function onFinished(destination) { FirstRun.finish(destination); }
    }
}
