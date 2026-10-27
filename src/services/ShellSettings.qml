pragma Singleton

import Quickshell
import QtQuick

// The shell's own look, set in the launcher (System, Shell settings) and kept in Store.
Singleton {
    // drop shadows under panels and popups (components/Shadow.qml)
    readonly property bool shadows: Store.saved.shadows

    // hold toasts back while a fullscreen window has focus (owner's request); they still reach the centre
    readonly property bool quietFullscreen: Store.saved.quietFullscreen

    function setShadows(on: bool) {
        Store.saved.shadows = on;
    }

    function setQuietFullscreen(on: bool) {
        Store.saved.quietFullscreen = on;
    }
}
