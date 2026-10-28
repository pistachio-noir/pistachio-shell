pragma Singleton

import Quickshell
import QtQuick

// The clipboard, through wl-copy (wl-clipboard): text and pictures, and the emoji copied lately from
// the launcher (kept in Store, newest first), which it lists first after a bare ":".
Singleton {
    readonly property var recentEmoji: Store.saved.recentEmoji ?? []

    function copyText(text: string) {
        Quickshell.execDetached(["wl-copy", "--", text]);
    }

    function copyImage(path: string) {
        Quickshell.execDetached(["sh", "-c", "wl-copy --type image/png < \"$1\"", "sh", path]);
    }

    function copyEmoji(emoji: string) {
        copyText(emoji);
        Store.saved.recentEmoji = [emoji].concat(recentEmoji.filter(e => e !== emoji)).slice(0, 16);
    }
}
