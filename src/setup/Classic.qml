pragma Singleton

import Quickshell
import QtQuick

// The Classic look's tokens for first-run setup, which always looks like its boards (owner's call,
// 19 November 2026): Theme's radii, fonts and timings switch with the TUI style, these don't.
// Colours still come from Theme (they follow Pistachio Noir / Noir).
Singleton {
    readonly property int tileRadius: 20
    readonly property int panelRadius: 28
    readonly property string fontUi: "Manrope"
    readonly property string fontMono: "JetBrains Mono"
    readonly property int hoverDuration: 120
    readonly property int motionDuration: 200
}
