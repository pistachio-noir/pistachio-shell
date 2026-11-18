pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The shell's own look, set in the launcher (System, Shell settings) and kept in Store.
Singleton {
    readonly property string publishedScheme: Store.ready ? colourScheme : ""
    onPublishedSchemeChanged: if (publishedScheme) themePublisher.exec(["python3", Quickshell.shellPath("services/shared-theme.py"), publishedScheme])
    property Process themePublisher: Process {}

    readonly property string appearanceStyle: Store.saved.appearanceStyle === "tui" ? "tui" : "classic"
    function setAppearanceStyle(value: string) {
        if (value === "classic" || value === "tui") Store.saved.appearanceStyle = value;
    }
    readonly property string colourScheme: Store.saved.colourScheme === "noir" ? "noir" : "pistachio"
    function setColourScheme(value: string) {
        if (value === "pistachio" || value === "noir") Store.saved.colourScheme = value;
    }
    readonly property bool desktopCat: Store.saved.desktopCat === true
    function setDesktopCat(value: bool) { Store.saved.desktopCat = value; }
    readonly property bool monochromeWallpaper: Store.saved.monochromeWallpaper === true
    function setMonochromeWallpaper(value: bool) { Store.saved.monochromeWallpaper = value; }
    readonly property bool clipboardHistory: Store.saved.clipboardHistory === true
    function setClipboardHistory(value: bool) { Store.saved.clipboardHistory = value; }
    readonly property bool phonePreview: Store.saved.phonePreview === true
    function setPhonePreview(value: bool) { Store.saved.phonePreview = value; }
    readonly property bool tuiTrayOpen: Store.saved.tuiTrayOpen === true
    function setTuiTrayOpen(value: bool) {
        Store.saved.tuiTrayOpen = value;
    }

    readonly property string lensProvider: Store.saved.lensProvider
    readonly property string lensClaudeModel: Store.saved.lensClaudeModel
    readonly property string lensClaudeEffort: Store.saved.lensClaudeEffort
    readonly property string lensCodexModel: Store.saved.lensCodexModel
    readonly property string lensCodexEffort: Store.saved.lensCodexEffort
    readonly property bool lensClaudeFallback: Store.saved.lensClaudeFallback
    readonly property bool lensCodexFallback: Store.saved.lensCodexFallback
    readonly property bool lensSuggestCoding: Store.saved.lensSuggestCoding
    readonly property bool quickChatTile: Store.saved.quickChatTile ?? true
    readonly property string lensClaudeCodingModel: Store.saved.lensClaudeCodingModel
    readonly property string lensClaudeCodingEffort: Store.saved.lensClaudeCodingEffort
    readonly property string lensCodexCodingModel: Store.saved.lensCodexCodingModel
    readonly property string lensCodexCodingEffort: Store.saved.lensCodexCodingEffort
    readonly property var lensClaudeModels: [{ value: "claude-haiku-5-5", title: "Haiku 5.5" }, { value: "sonnet", title: "Sonnet" }, { value: "opus", title: "Opus" }]
    readonly property var lensCodexModels: [{ value: "gpt-6-luna", title: "GPT-6 Luna" }, { value: "gpt-6.1-sol", title: "GPT-6.1 Sol" }, { value: "gpt-6.1-terra", title: "GPT-6.1 Terra" }, { value: "gpt-6-astra", title: "GPT-6 Astra" }]
    readonly property var lensEfforts: ["low", "medium", "high"].map(value => ({ value: value, title: value[0].toUpperCase() + value.slice(1) }))
    readonly property var lensChoices: ({
        lensProvider: [{ value: "claude", title: "Claude" }, { value: "codex", title: "ChatGPT (Codex)" }],
        lensClaudeModel: lensClaudeModels,
        lensCodexModel: lensCodexModels,
        lensClaudeEffort: lensEfforts,
        lensCodexEffort: lensEfforts,
        lensClaudeCodingModel: lensClaudeModels,
        lensCodexCodingModel: lensCodexModels,
        lensClaudeCodingEffort: lensEfforts,
        lensCodexCodingEffort: lensEfforts
    })

    function setLensChoice(key: string, value: string) {
        if (lensChoices[key]?.some(choice => choice.value === value))
            Store.saved[key] = value;
    }
    function lensLabel(key: string): string {
        return lensChoices[key]?.find(choice => choice.value === Store.saved[key])?.title ?? Store.saved[key];
    }
    function setLensFallback(provider: string, on: bool) {
        if (provider === "claude") Store.saved.lensClaudeFallback = on;
        else if (provider === "codex") Store.saved.lensCodexFallback = on;
    }
    function setLensSuggestCoding(on: bool) { Store.saved.lensSuggestCoding = on; }
    function setQuickChatTile(on: bool) { Store.saved.quickChatTile = on; }

    readonly property string screenshotOutput: ["save","copy","both"].includes(Store.saved.screenshotOutput) ? Store.saved.screenshotOutput : "save"
    readonly property string recordingAudio: ["off","system","mic","both"].includes(Store.saved.recordingAudio) ? Store.saved.recordingAudio : "system"
    readonly property int recordingCountdown: [0,3,5,10].includes(Store.saved.recordingCountdown) ? Store.saved.recordingCountdown : 0
    function setScreenshotOutput(value: string) { if (["save", "copy", "both"].includes(value)) Store.saved.screenshotOutput = value; }
    function setRecordingAudio(value: string) { if (["off", "system", "mic", "both"].includes(value)) Store.saved.recordingAudio = value; }
    function setRecordingCountdown(value: int) { if ([0, 3, 5, 10].includes(value)) Store.saved.recordingCountdown = value; }

    // drop shadows under panels and popups (components/Shadow.qml)
    readonly property bool shadows: Store.saved.shadows

    // hold toasts back while a fullscreen window has focus (owner's request); they still reach the centre
    readonly property bool quietFullscreen: Store.saved.quietFullscreen

    // the same while an app records from the microphone, as in a call (owner's pick, 30 October 2026)
    readonly property bool quietCalls: Store.saved.quietCalls

    // Frosted panels (owner's request, 31 October 2026): the bar, its pills and the panels turn
    // see-through and Hyprland blurs what's behind them, if its config has the layer rule (README).
    // Off by default, since without that rule they're see-through but not blurred. Subtle (88 %
    // opaque) or glassy (72 %; still above the rule's ignore_alpha of 0.66, which keeps the drop
    // shadows of solid panels unblurred). Drop shadows go while frosted (components/Shadow.qml).
    readonly property bool frosted: Store.saved.frosted
    readonly property bool glassy: Store.saved.frostStyle === "glassy"
    readonly property real frost: !frosted ? 1 : glassy ? 0.72 : 0.88

    // a short click as the output's volume changes, at the new level (owner's pick, 31 October 2026;
    // Audio plays it)
    readonly property bool volumeTick: Store.saved.volumeTick
    readonly property bool workspaceOsd: Store.saved.workspaceOsd
    readonly property bool tabbedOsd: Store.saved.tabbedOsd

    // Bluetooth headphones get the sound as they connect, whatever output was chosen (owner's request,
    // 31 October 2026; Audio does it)
    readonly property bool headphonesTakeOver: Store.saved.headphonesTakeOver

    // a soft sound with each toast (owner's request, after phase 8; Notifs plays it)
    readonly property bool notificationSound: Store.saved.notificationSound

    function setShadows(on: bool) {
        Store.saved.shadows = on;
    }

    function setQuietFullscreen(on: bool) {
        Store.saved.quietFullscreen = on;
    }

    readonly property bool calendarEvents: Store.saved.calendarEvents
    // Other apps' integrations (owner's request, 12 November 2026), each with a switch in Settings →
    // Integrations: off, the service acts as if the app weren't installed. JsonAdapter hands lists back
    // as QVariant sequences, hence Array.from.
    readonly property var integrationsOff: Array.from(Store.saved.integrationsOff ?? [])

    function integration(id: string): bool {
        return !integrationsOff.includes(id);
    }

    function setIntegration(id: string, on: bool) {
        const list = integrationsOff.filter(x => x !== id);
        if (!on)
            list.push(id);
        Store.saved.integrationsOff = list;
    }

    function setCalendarEvents(on: bool) {
        Store.saved.calendarEvents = on;
    }

    function setTabbedOsd(on: bool) {
        Store.saved.tabbedOsd = on;
    }

    function setWorkspaceOsd(on: bool) {
        Store.saved.workspaceOsd = on;
    }

    function setVolumeTick(on: bool) {
        Store.saved.volumeTick = on;
    }

    function setFrosted(on: bool) {
        Store.saved.frosted = on;
    }

    function setGlassy(on: bool) {
        Store.saved.frostStyle = on ? "glassy" : "subtle";
    }

    function setHeadphonesTakeOver(on: bool) {
        Store.saved.headphonesTakeOver = on;
    }

    function setQuietCalls(on: bool) {
        Store.saved.quietCalls = on;
    }

    function setNotificationSound(on: bool) {
        Store.saved.notificationSound = on;
    }
}
