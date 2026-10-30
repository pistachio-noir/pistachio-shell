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
