pragma Singleton

import qs
import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel

// Desktop icons (owner's request, after phase 8; look B of the brainstorm mockups, the Pistachio tiles):
// the files and folders in the Desktop folder (~/Desktop, or the one xdg-user-dir names), kept up to
// date as they come and go, each with a kind for its glyph. Where each sits is kept in Store, by name,
// as [column, row]; panels/DesktopIcons.qml places the rest. Hidden files are left out. Switched off in
// the launcher's Shell settings.
Singleton {
    id: root

    property string folder: `${Quickshell.env("HOME")}/Desktop`
    readonly property bool enabled: Store.saved.desktopIcons ?? true
    // [{ name, path, url, folder, kind, app }], folders first, then by name; `app` is the desktop entry
    // of a .desktop file there, if the system knows it
    property var items: []
    readonly property var positions: Store.saved.desktopPositions ?? ({})
    // the folder is made before it's watched (FolderListModel can't watch one made later)
    property bool made

    readonly property var kinds: ({
        image: ["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif"],
        video: ["mp4", "mkv", "webm", "mov", "avi"],
        audio: ["mp3", "flac", "ogg", "opus", "wav", "m4a"],
        document: ["pdf", "doc", "docx", "odt", "rtf", "epub", "xls", "xlsx", "ods", "ppt", "pptx", "odp"],
        archive: ["zip", "tar", "gz", "xz", "zst", "7z", "rar", "bz2", "tgz"],
        code: ["py", "js", "ts", "qml", "rs", "c", "cpp", "h", "sh", "lua", "json", "toml", "yaml", "yml", "html", "css", "go", "java"],
        text: ["txt", "md", "log", "conf", "ini", "csv"]
    })

    function kindOf(name: string, isFolder: bool, app): string {
        if (isFolder)
            return "folder";
        if (app)
            return "app";
        const ext = name.includes(".") ? name.slice(name.lastIndexOf(".") + 1).toLowerCase() : "";
        for (const kind in kinds) {
            if (kinds[kind].includes(ext))
                return kind;
        }
        return "file";
    }

    function setEnabled(on: bool) {
        if (!Theme.tui)
            Store.saved.desktopIcons = on;
    }

    function place(name: string, cell) {
        placeAll({ [name]: cell });
    }

    // several at once (a group dragged, and the icons it pushed aside): name -> [column, row]
    function placeAll(moves) {
        Store.saved.desktopPositions = Object.assign({}, positions, moves);
    }

    // in its app (a folder in the file manager); a .desktop file starts its app
    function open(item) {
        if (item.app)
            Apps.launch(item.app);
        else
            Quickshell.execDetached(["xdg-open", item.path]);
    }

    function showFolder() {
        Quickshell.execDetached(["xdg-open", folder]);
    }

    // one or several items, in one go
    function trash(items) {
        Quickshell.execDetached(["gio", "trash", "--"].concat(items.map(i => i.path)));
    }

    // a name for a file here, or the problem with it, for the launcher's question
    function check(text: string, except: string, then) {
        if (Theme.tui)
            then(null, "Desktop actions are available in Classic.");
        else if (text.includes("/") || text === "." || text === "..")
            then(null, "A name can't have a / in it, or be . or ..");
        else if (text !== except && items.some(i => i.name === text))
            then(null, `There's already something called “${text}” on the desktop.`);
        else
            then(text, "");
    }

    // renaming keeps its place
    function rename(item, name: string) {
        if (name === item.name)
            return;
        const all = Object.assign({}, positions);
        if (all[item.name]) {
            all[name] = all[item.name];
            delete all[item.name];
        }
        Store.saved.desktopPositions = all;
        Quickshell.execDetached(["mv", "-n", "--", item.path, `${folder}/${name}`]);
    }

    // Files dropped on the desktop from another app (hyprfm): copied in, never moved, and nothing here
    // is overwritten; the first lands where it was dropped, the rest in the first free cells
    function copyIn(urls, cell) {
        const paths = urls.map(u => decodeURIComponent(u.toString().replace(/^file:\/\//, ""))).filter(p => p && !p.startsWith(`${folder}/`));
        if (!paths.length)
            return;
        place(paths[0].replace(/\/+$/, "").split("/").pop(), cell);
        Quickshell.execDetached(["cp", "-r", "-n", "--"].concat(paths, [`${folder}/`]));
    }

    // a new folder, at the place that was clicked
    function newFolder(name: string, cell) {
        place(name, cell);
        Quickshell.execDetached(["mkdir", "--", `${folder}/${name}`]);
    }

    function read() {
        const list = [];
        for (let i = 0; i < files.count; i++) {
            const name = files.get(i, "fileName");
            const isFolder = files.get(i, "fileIsDir");
            const app = !isFolder && name.endsWith(".desktop") ? DesktopEntries.byId(name.slice(0, -8)) : null;
            list.push({ name: name, path: files.get(i, "filePath"), url: files.get(i, "fileUrl").toString(), folder: isFolder, kind: kindOf(name, isFolder, app), app: app });
        }
        items = list;
        // forget the places of what's gone, once the folder has really been read
        if (files.status !== FolderListModel.Ready || !Store.ready)
            return;
        const names = new Set(list.map(i => i.name));
        if (Object.keys(positions).some(n => !names.has(n))) {
            const kept = {};
            for (const n in positions) {
                if (names.has(n))
                    kept[n] = positions[n];
            }
            Store.saved.desktopPositions = kept;
        }
    }

    FolderListModel {
        id: files
        folder: root.made ? `file://${root.folder}` : ""
        showDirsFirst: true
        showHidden: false
        sortCaseSensitive: false
        onCountChanged: reading.restart()
        onStatusChanged: reading.restart()
        onDataChanged: reading.restart()
        onModelReset: reading.restart()
    }

    // one reading per burst of changes (a rename is a removal and an addition)
    Timer {
        id: reading
        interval: 50
        onTriggered: root.read()
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
        command: ["xdg-user-dir", "DESKTOP"]
        stdout: StdioCollector {
            onStreamFinished: {
                const desktop = text.trim();
                if (desktop && desktop !== Quickshell.env("HOME"))
                    root.folder = desktop;
            }
        }
    }
}
