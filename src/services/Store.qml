pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Settings and notification history kept across restarts, in Quickshell's per-shell state folder
// (~/.local/state/quickshell/by-shell/<id>/state.json; the test shell has its own). The file loads a
// moment after startup: `ready` turns true then, and nothing is saved before it, or the defaults
// would overwrite the file.
Singleton {
    id: root

    property bool ready
    // (named Store, not State: QtQuick's own State type would shadow it)
    readonly property JsonAdapter saved: JsonAdapter {
        property bool dnd
        property bool dndSchedule
        property bool dndFollowsNight // the schedule uses night light's times instead of its own
        property int dndFrom: 1320 // 22:00
        property int dndTo: 420 // 07:00
        property bool nightLight
        property int temperature: 4000 // kelvin
        property bool nightSchedule
        property int nightFrom: 1200 // minutes after midnight: 20:00
        property int nightTo: 420 // 07:00
        property string appearanceStyle: "classic"
        property string colourScheme: "pistachio" // or "noir" (owner's call, 14 November 2026)
        property bool tuiTrayOpen // TUI strip: tray icons and minimised windows shown (owner's call: collapsed by default)
        property bool shadows: true // drop shadows under panels and popups
        property bool quietFullscreen: true // toasts wait while a fullscreen window has focus
        property bool quietCalls: true // toasts wait while an app records from the microphone
        property bool headphonesTakeOver: true // Bluetooth headphones become the output as they connect
        property bool frosted // see-through bar and panels, blurred by Hyprland (needs the owner's layer rule)
        property bool volumeTick: true // a short click as the volume changes
        property bool workspaceOsd: true // the OSD names the workspace on a switch
        property bool tabbedOsd: true // the OSD says when a workspace's tabs go on or off
        property var integrationsOff: [] // ids of other apps' integrations switched off (Settings → Integrations)
        property bool calendarEvents: true // GNOME Calendar's events in the month calendar (Settings → Integrations)
        property bool zenPomodoro // Zen mode also runs a Pomodoro timer
        property bool focusPomodoro // a Focus session is Pomodoro rounds rather than one stretch
        property int focusMinutes: 25 // a single Focus session
        property bool focusZen // Focus also turns Zen mode on
        property var focusAllowed: [] // app names whose notifications still toast during Focus
        property int pomodoroWork: 25 // minutes
        property int pomodoroBreak: 5
        property int pomodoroLongBreak: 15
        property int pomodoroRounds: 4 // work rounds before the long break
        property var focusState: ({}) // FocusMode: Zen on, its session, carried over a reload or restart
        property var zenGaps: null // Hyprland's gaps and border before Zen, to put back (Compositor)
        property string ciderToken // Cider's local API (Up next, Apple Music search); "" until pasted
        property string lensProvider: "claude"
        property string lensClaudeModel: "claude-haiku-5-5"
        property string lensClaudeEffort: "medium"
        property string lensCodexModel: "gpt-6-luna"
        property string lensCodexEffort: "low"
        property bool lensClaudeFallback
        property bool lensCodexFallback
        property bool lensSuggestCoding: true
        property bool quickChatTile: true // the quick chat's tile beside LocalSend in quick settings (Settings → Lens and AI)
        property string lensClaudeCodingModel: "sonnet"
        property string lensClaudeCodingEffort: "high"
        property string lensCodexCodingModel: "gpt-6.1-sol"
        property string lensCodexCodingEffort: "high"
        property string screenshotOutput: "save"
        property string recordingAudio: "system"
        property int recordingCountdown: 0
        property var launcherPins: []
        property var launcherAliases: ({})
        property var workspacePresets: [] // { name, names: { "2": "code" }, apps: { "2": [desktop entry ids] } }
        property string frostStyle: "subtle" // or "glassy"
        property bool notificationSound: true // a soft sound with each toast
        property var launches: ({}) // app id -> its last launches (ms since epoch), at most 10, oldest first
        property var recentEmoji: [] // copied from the launcher, newest first, at most 16
        property var recentCommands: [] // run from the launcher after a "$", newest first, at most 20
        property string terminal // picked in Shell settings; "" until then (Apps falls back)
        property var notificationRules: ({}) // app name -> { until: ms } (silenced) or { noToasts: true }
        property string weatherCity // for Open-Meteo's geocoding; "" until set (Weather falls back)
        property string wallpaper // the image on the desktop
        property var wallpaperFits: ({}) // image path -> "fill", "fit", "center" or "tile"
        property bool desktopIcons: true // the Desktop folder's files and folders on the wallpaper
        property var desktopPositions: ({}) // a desktop icon's name -> [column, row]
        property bool localsendReceive // LocalSend: others on the network may send here (off until switched on)
        property string localsendName // the name others see; "" for the hostname
        property string localsendFolder // where received files go; "" for ~/Downloads
        property bool localsendAcceptKnown // accept at once from devices accepted before
        property var localsendKnown: [] // their fingerprints
        property var notifications: [] // newest first, plain records
    }

    FileView {
        id: file

        path: Quickshell.statePath("state.json")
        // v0.3.2 reapplies a completed write snapshot to its adapter. Finish each
        // debounced save before accepting newer edits, so an old snapshot cannot undo them.
        blockWrites: true
        printErrors: false // a missing file is normal on the first start; other errors are logged below
        onLoaded: root.ready = true
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.warn("state: can't read", path, "error", error, "(starting from defaults)");
            root.ready = true;
        }
        // a slider drag changes a value many times a second; save once it settles
        onAdapterUpdated: if (root.ready) saving.restart()
        onSaveFailed: error => console.warn("state: can't save", path, "error", error)
        adapter: root.saved
    }

    Timer {
        id: saving
        interval: 300
        onTriggered: file.writeAdapter()
    }
}
