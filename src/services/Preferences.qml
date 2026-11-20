pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Export and import of the shell's preferences (owner's call, 15 November 2026): a one-off snapshot in
// ~/.config/pistachio/pistachio-shell/settings.toml, written and read by `psc prefs` (rust/psc/src/prefs.rs), which owns the TOML layout and
// checks every value. Import never writes straight away: it lists what would change (old → new) and
// applies only on Apply, like the page reset. Never the Cider token, LocalSend's known devices,
// notification or usage history, running state, the wallpaper or desktop icon positions.
Singleton {
    id: root

    readonly property string path: `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/pistachio/pistachio-shell/settings.toml`
    readonly property string shownPath: Quickshell.env("XDG_CONFIG_HOME") ? path : "~/.config/pistachio/pistachio-shell/settings.toml"
    property bool busy
    property string status // the last export's or import's outcome, shown under its row
    property bool failed // the status is an error
    property bool reviewing
    property var changes: [] // [{ key, title, from, to, value }] while reviewing
    property var skipped: [] // [{ key, reason }] from the file
    property string source: path // the file the last review read (first-run setup may pick another)
    property bool missing // the last review found no file there

    // The Store keys that travel, the same list as psc's prefs SCHEMA (tests/prefs.test.py checks it),
    // with the names Settings gives them
    readonly property var titles: ({
        catSkin: "Cat skin",
        frosted: "Frosted panels", frostStyle: "Frost style", shadows: "Drop shadows", desktopIcons: "Desktop icons",
        workspaceOsd: "Workspace OSD", tabbedOsd: "Tabbed OSD",
        desktopCat: "Desktop cat", clipboardHistory: "Clipboard history", monochromeWallpaper: "Monochrome wallpaper", phonePreview: "Phone timer preview", gameMode: "Game mode", desktopWidgets: "Desktop widgets", themingIntegration: "Theming integration", themingKeep: "Apps keeping their own theme", gameClasses: "Extra game windows", appearanceStyle: "Style", tuiHyprland: "Hyprland integration", colourScheme: "Colours", tuiTrayOpen: "Tray icons shown (TUI)",
        nightLight: "Night light", temperature: "Night light warmth", nightSchedule: "Night light schedule",
        nightFrom: "Night light start", nightTo: "Night light end",
        headphonesTakeOver: "Headphones take over", volumeTick: "Volume tick",
        dnd: "Do not disturb", dndSchedule: "Quiet schedule", dndFollowsNight: "Quiet follows night light",
        dndFrom: "Quiet start", dndTo: "Quiet end", quietFullscreen: "Quiet in fullscreen", quietCalls: "Quiet during calls",
        notificationSound: "Notification sound", notificationRules: "App notification rules",
        zenPomodoro: "Pomodoro in Zen", focusPomodoro: "Focus as Pomodoro", focusMinutes: "Focus length",
        focusZen: "Zen during Focus", focusAllowed: "Allowed during Focus", pomodoroWork: "Pomodoro work",
        pomodoroBreak: "Pomodoro break", pomodoroLongBreak: "Pomodoro long break", pomodoroRounds: "Pomodoro rounds",
        lensProvider: "Preferred provider", lensClaudeModel: "Claude model", lensClaudeEffort: "Claude effort",
        lensCodexModel: "Codex model", lensCodexEffort: "Codex effort", lensClaudeFallback: "Claude fallback",
        lensCodexFallback: "Codex fallback", lensSuggestCoding: "Suggest a coding model",
        lensClaudeCodingModel: "Claude coding model", lensClaudeCodingEffort: "Claude coding effort",
        lensCodexCodingModel: "Codex coding model", lensCodexCodingEffort: "Codex coding effort",
        quickChatTile: "Quick chat in quick settings",
        screenshotOutput: "Screenshots go to", recordingAudio: "Recording audio", recordingCountdown: "Recording countdown",
        terminal: "Terminal", weatherCity: "Weather location",
        integrationsOff: "Integrations switched off", calendarEvents: "Calendar events",
        localsendReceive: "LocalSend receive", localsendName: "LocalSend device name", localsendFolder: "LocalSend folder",
        localsendAcceptKnown: "Accept known devices",
        launcherPins: "Launcher pins", launcherAliases: "Launcher aliases", workspacePresets: "Workspace presets"
    })
    readonly property var times: ["nightFrom", "nightTo", "dndFrom", "dndTo"]

    // how a value reads in the review
    function shown(key: string, value): string {
        if (times.includes(key))
            return `${String(Math.floor(value / 60)).padStart(2, "0")}:${String(value % 60).padStart(2, "0")}`;
        if (typeof value === "boolean")
            return value ? "On" : "Off";
        if (value === undefined || value === null || value === "")
            return "Automatic";
        if (key === "temperature")
            return `${value} K`;
        if (Array.isArray(value) || (value && value.length !== undefined && typeof value !== "string"))
            return value.length === 0 ? "None" : `${value.length} item${value.length === 1 ? "" : "s"}`;
        if (typeof value === "object")
            return Object.keys(value).length === 0 ? "None" : `${Object.keys(value).length} item${Object.keys(value).length === 1 ? "" : "s"}`;
        return String(value);
    }

    // JSON-safe copies: JsonAdapter hands lists back as QVariant sequences
    function plain(value) {
        return JSON.parse(JSON.stringify(value ?? null));
    }

    function exportNow() {
        if (busy || !Store.ready)
            return;
        const values = {};
        for (const key of Object.keys(titles))
            if (Store.saved[key] !== undefined)
                values[key] = plain(Store.saved[key]);
        busy = true;
        exporter.payload = JSON.stringify({ values: values });
        exporter.running = true;
    }

    function review(file) {
        if (busy || !Store.ready)
            return;
        busy = true;
        source = typeof file === "string" && file ? file : path;
        missing = false;
        reader.payload = JSON.stringify({
            actions: LauncherTools.actions.map(a => a.id),
            claudeModels: ShellSettings.lensClaudeModels.map(m => m.value),
            codexModels: ShellSettings.lensCodexModels.map(m => m.value)
        });
        reader.running = true;
    }

    function cancel() {
        reviewing = false;
        changes = [];
        skipped = [];
    }

    function apply() {
        if (!reviewing || !Store.ready)
            return;
        for (const c of changes) {
            if (c.key === "temperature")
                NightLight.setTemperature(c.value); // reaches hyprsunset while it runs
            else
                Store.saved[c.key] = c.value;
        }
        status = `Imported ${changes.length} setting${changes.length === 1 ? "" : "s"}.`;
        failed = false;
        cancel();
    }

    Process {
        id: exporter
        property string payload
        command: [Quickshell.env("HOME") + "/.local/bin/psc", "prefs", "export", root.path, payload]
        stdout: StdioCollector {
            onStreamFinished: {
                let reply = null;
                try { reply = JSON.parse(text); } catch (e) {}
                root.failed = !reply?.ok;
                root.status = reply?.ok ? `Saved to ${root.shownPath} at ${Qt.formatTime(new Date(), "hh:mm")}.` : `Couldn't export: ${reply?.error ?? "the helper didn't answer"}`;
            }
        }
        onExited: root.busy = false
    }

    Process {
        id: reader
        property string payload
        command: [Quickshell.env("HOME") + "/.local/bin/psc", "prefs", "read", root.source, payload]
        stdout: StdioCollector {
            onStreamFinished: {
                let reply = null;
                try { reply = JSON.parse(text); } catch (e) {}
                if (!reply?.ok) {
                    root.failed = true;
                    root.missing = /^no settings file/.test(reply?.error ?? "");
                    root.status = `Couldn't import: ${reply?.error ?? "the helper didn't answer"}`;
                    return;
                }
                const list = [];
                for (const key of Object.keys(reply.values)) {
                    const now = root.plain(Store.saved[key]);
                    if (JSON.stringify(now) !== JSON.stringify(reply.values[key]))
                        list.push({ key: key, title: root.titles[key] ?? key, from: root.shown(key, now), to: root.shown(key, reply.values[key]), value: reply.values[key] });
                }
                root.changes = list;
                root.skipped = reply.skipped;
                root.reviewing = true;
                root.status = "";
                root.failed = false;
            }
        }
        onExited: root.busy = false
    }
}
