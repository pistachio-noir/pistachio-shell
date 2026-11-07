pragma Singleton

import Quickshell
import QtQuick

// The launcher's tooltip for text cut short with "…" (owner's request, 5 November 2026): a Text with a
// TipHover reports itself here while hovered, and the launcher draws its whole text under it after
// half a second.
Singleton {
    id: root

    property Item item: null
    property string text
    property bool shown

    function show(target: Item, full: string) {
        item = target;
        // a highlighted title is styled text: the tip shows it plain
        text = full.replace(/<[^>]*>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&amp;/g, "&");
        shown = false;
        delay.restart();
    }

    function hide(target: Item) {
        if (item !== target)
            return;
        item = null;
        shown = false;
        delay.stop();
    }

    Timer {
        id: delay
        interval: 500
        onTriggered: root.shown = root.item !== null
    }
}
