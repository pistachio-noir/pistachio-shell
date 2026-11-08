pragma Singleton

import Quickshell
import QtQuick

// The shell's own look, set in the launcher (System, Shell settings) and kept in Store.
Singleton {
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
