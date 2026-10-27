pragma Singleton

import Quickshell
import QtQuick

// The shell's own look, set in the launcher (System, Shell settings) and kept in Store.
Singleton {
    // drop shadows under panels and popups (components/Shadow.qml)
    readonly property bool shadows: Store.saved.shadows

    function setShadows(on: bool) {
        Store.saved.shadows = on;
    }
}
