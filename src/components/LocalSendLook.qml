pragma Singleton

import qs
import qs.services
import Quickshell
import QtQuick

// LocalSend's icons and tints for files and devices, as on its boards: videos teal, documents gold,
// pictures sage blue; phones sage blue, tablets lavender, computers teal.
Singleton {
    function fileIcon(item): list<string> {
        if (item.text !== undefined)
            return Icons.message;
        if (item.dir)
            return Icons.folder;
        const mime = item.mime ?? "";
        return mime.startsWith("video/") ? Icons.video : mime.startsWith("image/") ? Icons.image : mime.startsWith("text/") || mime === "application/pdf" ? Icons.fileText : Icons.file;
    }

    function fileTint(item): color {
        if (item.text !== undefined)
            return Theme.lavender;
        if (item.dir)
            return Theme.clay;
        const mime = item.mime ?? "";
        return mime.startsWith("video/") ? Theme.teal : mime.startsWith("image/") ? Theme.sageBlue : mime.startsWith("text/") || mime === "application/pdf" ? Theme.gold : Theme.subtext;
    }

    function deviceIcon(d): list<string> {
        const kind = LocalSend.kind(d);
        return kind === "phone" ? Icons.smartphone : kind === "tablet" ? Icons.tablet : Icons.monitor;
    }

    function deviceTint(d): color {
        const kind = LocalSend.kind(d);
        return kind === "phone" ? Theme.sageBlue : kind === "tablet" ? Theme.lavender : Theme.teal;
    }
}
