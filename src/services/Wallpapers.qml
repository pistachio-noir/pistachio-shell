pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel

// The wallpaper (owner's request, after phase 8; boards wallpaper-switcher and -empty). The shell draws
// it itself (panels/Wallpaper.qml, on the background layer), so hyprpaper retires. The images are the
// PNG, JPG and WebP files in ~/Pictures/Wallpapers (in the Pictures folder xdg-user-dir names), kept
// up to date as files come and go. The one in use and each image's fit are kept in Store.
Singleton {
    id: root

    property string folder: `${Quickshell.env("HOME")}/Pictures/Wallpapers`
    readonly property string current: Store.saved.wallpaper ?? ""
    property var images: [] // [{ path, name, size }], by name
    // FolderListModel can't watch a folder that doesn't exist yet (images put in a folder made after
    // the shell started never showed), so the folder is made first and watched after
    property bool made

    function set(path: string) {
        Store.saved.wallpaper = path;
    }

    // another image at random
    function random() {
        const others = images.filter(i => i.path !== current);
        if (others.length > 0)
            set(others[Math.floor(Math.random() * others.length)].path);
    }

    // "fill" (the default), "fit", "center" or "tile", per image
    function fitOf(path: string): string {
        return Store.saved.wallpaperFits?.[path] ?? "fill";
    }

    function setFit(path: string, fit: string) {
        const all = Object.assign({}, Store.saved.wallpaperFits);
        all[path] = fit;
        Store.saved.wallpaperFits = all;
    }

    function openFolder() {
        Quickshell.execDetached(["sh", "-c", "mkdir -p \"$1\" && xdg-open \"$1\"", "sh", folder]);
    }

    function read() {
        const list = [];
        for (let i = 0; i < files.count; i++)
            list.push({ path: files.get(i, "filePath"), name: files.get(i, "fileName"), size: files.get(i, "fileSize") });
        images = list;
    }

    FolderListModel {
        id: files
        folder: root.made ? `file://${root.folder}` : ""
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
        caseSensitive: false
        showDirs: false
        onCountChanged: root.read()
        onStatusChanged: root.read()
    }

    onFolderChanged: {
        made = false;
        mkdir.running = true;
    }

    Process {
        id: mkdir
        running: true
        command: ["mkdir", "-p", root.folder]
        onExited: root.made = true
    }

    Process {
        running: true
        command: ["xdg-user-dir", "PICTURES"]
        stdout: StdioCollector {
            onStreamFinished: {
                const pictures = text.trim();
                if (pictures && pictures !== Quickshell.env("HOME"))
                    root.folder = `${pictures}/Wallpapers`;
            }
        }
    }
}
