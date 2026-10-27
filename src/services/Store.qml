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
        property bool nightLight
        property int temperature: 4000 // kelvin
        property bool nightSchedule
        property int nightFrom: 1200 // minutes after midnight: 20:00
        property int nightTo: 420 // 07:00
        property bool shadows: true // drop shadows under panels and popups
        property var notifications: [] // newest first, plain records
    }

    FileView {
        id: file

        path: Quickshell.statePath("state.json")
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
