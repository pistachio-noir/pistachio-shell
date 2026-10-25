pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    // /proc/uptime is "<seconds since boot> <idle seconds>"
    readonly property int seconds: parseFloat(file.text()) || 0

    FileView {
        id: file
        path: "/proc/uptime"
    }

    // procfs sends no change events, so re-read once a minute
    Timer {
        running: true
        repeat: true
        interval: 60000
        onTriggered: file.reload()
    }
}
