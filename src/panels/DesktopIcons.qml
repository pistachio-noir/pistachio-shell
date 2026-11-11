import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Widgets // ClippingRectangle, for a picture's thumbnail
import QtQuick

// Desktop icons (owner's request, after phase 8; look B of the brainstorm mockups, the Pistachio
// tiles), over the wallpaper in its window (panels/Wallpaper.qml): the files and folders in the Desktop
// folder (Desktop), on a grid from the top-left corner, down then right, clear of the bar. Each is a
// tile with a glyph coloured by its kind (a picture shows itself, an app its icon) and its name under
// it. A click selects one (the pistachio chip, as in the launcher), a double click opens it, a drag
// moves it to another cell (swapping with one already there; Store keeps where), and a right click
// opens its menu: Open, Rename, Move to trash, Show in file manager. On the desktop itself: New folder,
// Open Desktop folder, Wallpapers. Renaming and naming a folder use the launcher's question. Hidden in
// showoff mode, where names could be private.
// Several at once (owner's pick, 30 October 2026): a box dragged on the desktop selects the icons it
// touches, Ctrl+click adds or takes away one (Ctrl with a box adds to what's selected). A drag moves
// them all, keeping their shape; icons in the way go to the cells they left. The menu of a selected
// icon then opens or trashes them all.
// Drag and drop with apps (owner's pick, 30 October 2026): dragged over a window, the icons become a
// Wayland drag of their files (a Discord message, a browser upload); dropped back on the desktop they
// just move. Files dropped on the desktop from another app (hyprfm) are copied in (Desktop.copyIn).
Item {
    id: root

    readonly property int cellWidth: 104
    readonly property int cellHeight: 104
    readonly property int margin: 24
    // clear of the bar and the room above it
    readonly property int rows: Math.max(1, Math.floor((height - 2 * margin - Theme.barHeight - Theme.barMargin) / cellHeight))
    readonly property int columns: Math.max(1, Math.floor((width - 2 * margin) / cellWidth))
    // where each icon sits, name -> [column, row]: saved places first (if they still fit on the
    // screen and nothing else took them), then the rest in the first free cells, down then right
    readonly property var layout: {
        const at = {}, taken = {};
        const key = cell => `${cell[0]},${cell[1]}`;
        for (const item of Desktop.items) {
            const p = Desktop.positions[item.name];
            if (p && p[0] < columns && p[1] < rows && !taken[key(p)]) {
                at[item.name] = p;
                taken[key(p)] = true;
            }
        }
        let next = 0;
        for (const item of Desktop.items) {
            if (at[item.name])
                continue;
            while (taken[key([Math.floor(next / rows), next % rows])])
                next++;
            at[item.name] = [Math.floor(next / rows), next % rows];
            taken[key(at[item.name])] = true;
        }
        return at;
    }
    property var selection: [] // the selected icons' names
    readonly property var selectedItems: Desktop.items.filter(i => selection.includes(i.name))
    // a group being dragged: the icon the pointer holds, and how far it has gone (px)
    property string dragLead
    property point dragOffset
    // the box being dragged out on the desktop (x, y, width, height), or null; what was selected before
    // it, kept when Ctrl is held
    property var box: null
    property var boxBase: []
    // the dragged icons have left for a window, as a Wayland drag; where the pointer took the held one
    // (icon coordinates), to place them if they come back
    property bool exporting
    property point grabbedAt
    // the open menu: { item (null on the desktop itself), x, y, cell }, or null
    property var menu: null
    readonly property bool menuOpen: root.menu !== null // (root.: the menu's view below has its own id)

    signal renameRequested(var item)

    // Keys (owner's pick, 3 November 2026), once a click has given the desktop the keyboard, which it
    // takes only on a workspace without windows (Wallpaper.qml): the arrows move to the nearest icon
    // that way, Enter opens, Delete trashes, F2 renames, Ctrl+A selects all, Esc lets go.
    focus: true
    Keys.onPressed: event => root.key(event)

    function key(event) {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const chosen = selectedItems;
        event.accepted = true;
        if (event.key === Qt.Key_Escape) {
            if (root.menu)
                root.menu = null;
            else
                root.selection = [];
        } else if (ctrl && event.key === Qt.Key_A) {
            selection = Desktop.items.map(i => i.name);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            chosen.forEach(i => Desktop.open(i));
        } else if (event.key === Qt.Key_Space && chosen.length===1) {
            LauncherTools.showFile(chosen[0].path,"preview");
        } else if (event.key === Qt.Key_Delete) {
            if (chosen.length)
                Desktop.trash(chosen);
            selection = [];
        } else if (event.key === Qt.Key_F2) {
            if (chosen.length === 1)
                renameRequested(chosen[0]);
        } else {
            const way = ({ [Qt.Key_Left]: [-1, 0], [Qt.Key_Right]: [1, 0], [Qt.Key_Up]: [0, -1], [Qt.Key_Down]: [0, 1] })[event.key];
            if (way)
                step(way[0], way[1]);
            else
                event.accepted = false;
        }
    }

    // the nearest icon that way from the last one selected (the first in the grid when none is)
    function step(dx: int, dy: int) {
        const at = name => layout[name] ?? [0, 0];
        if (!selection.length) {
            const first = Desktop.items.slice().sort((a, b) => at(a.name)[0] - at(b.name)[0] || at(a.name)[1] - at(b.name)[1])[0];
            if (first)
                selection = [first.name];
            return;
        }
        const from = at(selection[selection.length - 1]);
        let best = null, score = Infinity;
        for (const item of Desktop.items) {
            const c = at(item.name);
            const along = (c[0] - from[0]) * dx + (c[1] - from[1]) * dy; // how far that way
            const across = Math.abs(dx ? c[1] - from[1] : c[0] - from[0]);
            if (along <= 0)
                continue;
            const s = along * 10 + across * 11;
            if (s < score) {
                score = s;
                best = item;
            }
        }
        if (best)
            selection = [best.name];
    }
    signal newFolderRequested(var cell)
    signal wallpapersRequested

    function cellAt(x: real, y: real): var {
        return [Math.max(0, Math.min(columns - 1, Math.floor((x - margin) / cellWidth))), Math.max(0, Math.min(rows - 1, Math.floor((y - margin) / cellHeight)))];
    }

    // the box from where it was pressed to the pointer; it selects every icon it touches (the part of
    // the cell that takes clicks)
    function drawBox(from: point, to: point, ctrl: bool) {
        box = Qt.rect(Math.min(from.x, to.x), Math.min(from.y, to.y), Math.abs(to.x - from.x), Math.abs(to.y - from.y));
        const touched = Desktop.items.filter(i => {
            const c = layout[i.name];
            const x = margin + c[0] * cellWidth + 6, y = margin + c[1] * cellHeight + 6;
            return x < box.x + box.width && box.x < x + cellWidth - 12 && y < box.y + box.height && box.y < y + cellHeight - 12;
        }).map(i => i.name);
        selection = (ctrl ? boxBase.filter(n => !touched.includes(n)) : []).concat(touched);
    }

    // The dragged group lands where the held icon's middle is, each keeping its place beside it (moved
    // back in if some would leave the grid). Icons already in those cells go to the ones the group left,
    // in grid order: for one icon that's a swap.
    function dropGroup() {
        const moved = selection.filter(n => layout[n]);
        const lead = layout[dragLead];
        const target = cellAt(margin + lead[0] * cellWidth + dragOffset.x + cellWidth / 2, margin + lead[1] * cellHeight + dragOffset.y + cellHeight / 2);
        const cells = moved.map(n => layout[n]);
        const columnsUsed = cells.map(c => c[0]), rowsUsed = cells.map(c => c[1]);
        const dc = Math.max(-Math.min(...columnsUsed), Math.min(columns - 1 - Math.max(...columnsUsed), target[0] - lead[0]));
        const dr = Math.max(-Math.min(...rowsUsed), Math.min(rows - 1 - Math.max(...rowsUsed), target[1] - lead[1]));
        // first back to the grid from where it was dropped, then on to the new cells (see the icons' x)
        dragLead = "";
        dragOffset = Qt.point(0, 0);
        if (dc === 0 && dr === 0)
            return;
        const key = c => `${c[0]},${c[1]}`;
        const moves = {};
        const targets = new Set();
        for (const n of moved) {
            moves[n] = [layout[n][0] + dc, layout[n][1] + dr];
            targets.add(key(moves[n]));
        }
        const left = cells.filter(c => !targets.has(key(c))).sort((a, b) => a[0] - b[0] || a[1] - b[1]);
        const inTheWay = Desktop.items.filter(i => !moved.includes(i.name) && layout[i.name] && targets.has(key(layout[i.name])));
        inTheWay.forEach((i, k) => moves[i.name] = left[k]);
        Desktop.placeAll(moves);
    }

    // the glyph and its colour for a kind (Desktop.kindOf)
    function glyphOf(kind: string): var {
        return kind === "folder" ? Icons.folder : kind === "image" ? Icons.image : kind === "video" ? Icons.film : kind === "audio" ? Icons.music
            : kind === "document" ? Icons.fileText : kind === "archive" ? Icons.archive : kind === "code" ? Icons.fileCode : kind === "text" ? Icons.fileText : Icons.file;
    }

    function colorOf(kind: string): color {
        return kind === "folder" ? Theme.sageBlue : kind === "image" ? Theme.lavender : kind === "video" ? Theme.clay : kind === "audio" ? Theme.gold
            : kind === "document" ? Theme.terracotta : kind === "archive" ? Theme.gold : kind === "code" ? Theme.teal : Theme.subtext;
    }

    visible: Desktop.enabled && opacity > 0
    enabled: !Showoff.active
    opacity: Showoff.active ? 0 : 1

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.motionDuration
            easing.type: Theme.easing
        }
    }

    // the desktop itself: a click clears the selection and closes a menu, a right click opens its menu,
    // a drag draws the selection box
    MouseArea {
        property point pressedAt

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => {
            root.forceActiveFocus(); // for the keys, once the layer has the keyboard
            pressedAt = Qt.point(mouse.x, mouse.y);
            root.boxBase = root.selection;
        }
        onPositionChanged: mouse => {
            if (pressedButtons === Qt.LeftButton && (root.box || Math.hypot(mouse.x - pressedAt.x, mouse.y - pressedAt.y) > 6))
                root.drawBox(pressedAt, Qt.point(mouse.x, mouse.y), !!(mouse.modifiers & Qt.ControlModifier));
        }
        onReleased: mouse => {
            if (root.box) {
                root.box = null;
                root.menu = null;
                return;
            }
            if (!(mouse.button === Qt.LeftButton && (mouse.modifiers & Qt.ControlModifier)))
                root.selection = [];
            root.menu = mouse.button === Qt.RightButton ? { item: null, x: mouse.x, y: mouse.y, cell: root.cellAt(mouse.x, mouse.y) } : null;
        }
        onCanceled: root.box = null
    }

    Repeater {
        model: Desktop.items

        Item {
            id: icon

            required property var modelData
            readonly property var cell: root.layout[modelData.name] ?? [0, 0]
            readonly property bool selected: root.selection.includes(modelData.name)
            // dragged, alone or with the others selected
            readonly property bool dragging: root.dragLead !== "" && selected
            property point pressedAt
            property point pressedOnDesktop // the same, on the desktop: the icon moves, the desktop doesn't
            property bool toggled // this press was a Ctrl+click
            property url dragPicture // the tile, for the Wayland drag's picture (taken on a press)
            property var dragGrab // keeps `dragPicture` valid

            // a Wayland drag of the selected files, started once the pointer is over a window
            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
            Drag.mimeData: ({ "text/uri-list": root.selectedItems.map(i => i.url).join("\r\n") + "\r\n" })
            Drag.imageSource: dragPicture
            Drag.hotSpot: Qt.point(28, 28)
            Drag.onDragFinished: {
                root.exporting = false;
                root.dragLead = "";
                root.dragOffset = Qt.point(0, 0);
            }

            x: root.margin + cell[0] * root.cellWidth + (dragging ? root.dragOffset.x : 0)
            y: root.margin + cell[1] * root.cellHeight + (dragging ? root.dragOffset.y : 0)
            z: dragging ? 1 : 0
            width: root.cellWidth
            height: root.cellHeight
            opacity: dragging ? 0.85 : 1
            Accessible.role: Accessible.Button
            Accessible.name: modelData.name

            Behavior on x {
                enabled: !icon.dragging
                NumberAnimation {
                    duration: Theme.motionDuration
                    easing.type: Theme.easing
                }
            }
            Behavior on y {
                enabled: !icon.dragging
                NumberAnimation {
                    duration: Theme.motionDuration
                    easing.type: Theme.easing
                }
            }

            Rectangle {
                id: tile

                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                width: 56
                height: 56
                radius: 18
                color: icon.selected || mouse.containsMouse ? Theme.overlay2 : Theme.overlay

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.hoverDuration
                        easing.type: Theme.easing
                    }
                }

                Icon {
                    anchors.centerIn: parent
                    visible: !thumbnail.visible && !appIcon.visible
                    size: 26
                    paths: root.glyphOf(icon.modelData.kind)
                    color: root.colorOf(icon.modelData.kind)
                }

                // a picture shows itself, cut to the tile
                ClippingRectangle {
                    id: thumbnail
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: 14
                    color: "transparent"
                    visible: icon.modelData.kind === "image" && picture.status === Image.Ready

                    Image {
                        id: picture
                        anchors.fill: parent
                        source: icon.modelData.kind === "image" ? icon.modelData.url : ""
                        sourceSize: Qt.size(96, 96)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }

                // a .desktop file: its app's icon
                Image {
                    id: appIcon
                    anchors.centerIn: parent
                    width: 32
                    height: 32
                    sourceSize: Qt.size(64, 64)
                    source: icon.modelData.app ? Apps.icon(icon.modelData.app.icon) : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    visible: status === Image.Ready
                }
            }

            // the name, in the pistachio chip while selected
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: tile.bottom
                anchors.topMargin: 5
                width: label.width + 12
                height: label.height + 4
                radius: 9
                color: icon.selected ? Theme.pistachio : "transparent"

                Text {
                    id: label
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, root.cellWidth - 16)
                    text: icon.modelData.name
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere // "test-" / "desktop.txt", not "test-desktop.tx" / "t"
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: icon.selected ? Theme.bg : Theme.text
                    // a dark edge under the letters, so they read on any wallpaper
                    style: icon.selected ? Text.Normal : Text.Raised
                    styleColor: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.85)
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }
            }

            MouseArea {
                id: mouse

                anchors.fill: parent
                anchors.margins: 6
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: true
                cursorShape: icon.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                // Ctrl+click adds or takes away this one; a press on one not yet selected selects it
                // alone (a press on a selected one keeps the rest, to drag them along)
                onPressed: mouse => {
                    root.forceActiveFocus();
                    const name = icon.modelData.name;
                    icon.toggled = mouse.button === Qt.LeftButton && !!(mouse.modifiers & Qt.ControlModifier);
                    if (icon.toggled)
                        root.selection = icon.selected ? root.selection.filter(n => n !== name) : root.selection.concat([name]);
                    else if (!icon.selected)
                        root.selection = [name];
                    root.menu = null;
                    icon.pressedAt = Qt.point(mouse.x, mouse.y);
                    icon.pressedOnDesktop = mapToItem(root, mouse.x, mouse.y);
                    tile.grabToImage(result => {
                        icon.dragGrab = result;
                        icon.dragPicture = result.url;
                    });
                }
                // a drag starts once the pointer has moved a few pixels
                onPositionChanged: mouse => {
                    if (!pressed || pressedButtons !== Qt.LeftButton || !icon.selected)
                        return;
                    if (!icon.dragging && Math.hypot(mouse.x - icon.pressedAt.x, mouse.y - icon.pressedAt.y) > 6)
                        root.dragLead = icon.modelData.name;
                    if (!icon.dragging || root.exporting)
                        return;
                    // measured on the desktop: measured on the icon, each move would shift the next
                    const p = mapToItem(root, mouse.x, mouse.y);
                    root.dragOffset = Qt.point(p.x - icon.pressedOnDesktop.x, p.y - icon.pressedOnDesktop.y);
                    // over a window (on this workspace): from here on it's the Wayland drag, its picture
                    // following the pointer while the icons wait at home
                    if (Compositor.windowBounds.some(r => p.x >= r.x && p.x < r.x + r.width && p.y >= r.y && p.y < r.y + r.height)) {
                        root.grabbedAt = Qt.point(icon.pressedAt.x + anchors.margins, icon.pressedAt.y + anchors.margins);
                        root.dragOffset = Qt.point(0, 0);
                        root.exporting = true;
                        icon.Drag.active = true;
                    }
                }
                // a plain click on one of several selects it alone
                onReleased: mouse => {
                    if (root.exporting)
                        return;
                    if (icon.dragging)
                        root.dropGroup();
                    else if (mouse.button === Qt.LeftButton && !icon.toggled)
                        root.selection = [icon.modelData.name];
                }
                onCanceled: if (icon.dragging && !root.exporting) root.dropGroup()
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        const p = mapToItem(root, mouse.x, mouse.y);
                        root.menu = { item: icon.modelData, x: p.x, y: p.y, cell: icon.cell };
                    }
                }
                onDoubleClicked: mouse => {
                    if (mouse.button === Qt.LeftButton)
                        Desktop.open(icon.modelData);
                }
            }
        }
    }

    // Drops: the desktop's own icons back from a window (moved as by a plain drag), or another app's
    // files (copied in)
    DropArea {
        anchors.fill: parent
        onEntered: drag => {
            if (!root.exporting && !drag.hasUrls)
                drag.accepted = false;
        }
        onDropped: drop => {
            if (root.exporting) {
                const home = root.layout[root.dragLead];
                if (home)
                    root.dragOffset = Qt.point(drop.x - root.margin - home[0] * root.cellWidth - root.grabbedAt.x, drop.y - root.margin - home[1] * root.cellHeight - root.grabbedAt.y);
                root.dropGroup();
                drop.accept(Qt.MoveAction);
            } else if (drop.hasUrls) {
                Desktop.copyIn(drop.urls, root.cellAt(drop.x, drop.y));
                drop.accept(Qt.CopyAction);
            }
        }
    }

    // the selection box: a faint veil with a soft edge, no accent
    Rectangle {
        x: root.box?.x ?? 0
        y: root.box?.y ?? 0
        z: 1
        width: root.box?.width ?? 0
        height: root.box?.height ?? 0
        visible: root.box !== null
        radius: 6
        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
        border.width: 1
        border.color: Qt.rgba(Theme.subtext.r, Theme.subtext.g, Theme.subtext.b, 0.6)
    }

    // The menu, drawn by the shell as the tray's is, at the click and kept on the screen; it goes
    // with a click elsewhere on the desktop (Wallpaper.qml also closes it on a click in a window).
    // the desktop's items into LocalSend's list, and its page open in quick settings
    function sendWithLocalSend(items) {
        LocalSend.add(items.map(i => i.path));
        LocalSend.openRequested();
    }

    Item {
        id: menuView

        // (each entry keeps its own item and cell: the menu is gone by the time one runs)
        readonly property var entries: {
            const m = root.menu;
            if (!m)
                return [];
            const several = m.item && root.selection.length > 1 && root.selection.includes(m.item.name) ? root.selectedItems : null;
            if (several)
                return [
                    { text: `Open ${several.length} items`, glyph: Icons.folderOpen, run: () => several.forEach(i => Desktop.open(i)) },
                    { text: `Move ${several.length} items to trash`, glyph: Icons.trash, danger: true, run: () => Desktop.trash(several) },
                    { text: "Show in file manager", glyph: Icons.folder, run: () => Desktop.showFolder() }
                ].concat(LocalSend.available ? [{ text: `Send ${several.length} items with LocalSend`, glyph: Icons.share, run: () => root.sendWithLocalSend(several) }] : []);
            if (m.item)
                return [
                    { text: m.item.app ? "Launch" : "Open", glyph: Icons.folderOpen, run: () => Desktop.open(m.item) },
                    { text: "Preview · Space", glyph: Icons.image, run: () => LauncherTools.showFile(m.item.path,"preview") },
                    { text: "Open with…", glyph: Icons.folderOpen, run: () => LauncherTools.showFile(m.item.path,"handlers") },
                    { text: "Rename…", glyph: Icons.pencil, run: () => root.renameRequested(m.item) },
                    { text: "Move to trash", glyph: Icons.trash, danger: true, run: () => Desktop.trash([m.item]) },
                    { text: "Show in file manager", glyph: Icons.folder, run: () => Desktop.showFolder() }
                ].concat(LocalSend.available && !m.item.app ? [{ text: "Send with LocalSend", glyph: Icons.share, run: () => root.sendWithLocalSend([m.item]) }] : []);
            return [
                { text: "New folder…", glyph: Icons.folderPlus, run: () => root.newFolderRequested(m.cell) },
                { text: "Open Desktop folder", glyph: Icons.folderOpen, run: () => Desktop.showFolder() },
                { text: "Wallpapers…", glyph: Icons.image, run: () => root.wallpapersRequested() }
            ];
        }

        x: root.menu ? Math.min(root.menu.x, root.width - width - 8) : 0
        y: root.menu ? Math.min(root.menu.y, root.height - height - 8) : 0
        z: 2
        width: 220
        height: menuColumn.implicitHeight + 12
        opacity: root.menuOpen ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.hoverDuration
                easing.type: Theme.easing
            }
        }

        Shadow {
            kind: Theme.shadowSmall
            anchors.fill: menuPanel
            radius: menuPanel.radius
        }

        Rectangle {
            id: menuPanel
            anchors.fill: parent
            radius: Theme.tileRadius
            color: Theme.bgAlt
            border.width: 1
            border.color: Theme.overlay2
            Accessible.role: Accessible.PopupMenu
        }

        Column {
            id: menuColumn
            x: 6
            y: 6
            width: parent.width - 12

            Repeater {
                model: menuView.entries

                Rectangle {
                    id: entry

                    required property var modelData

                    width: parent.width
                    height: 36
                    radius: 14
                    color: entryMouse.containsMouse ? Theme.overlay : "transparent"
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: modelData.text

                    Icon {
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        size: 16
                        paths: entry.modelData.glyph
                        color: entry.modelData.danger ? Theme.terracotta : Theme.subtext
                    }

                    Text {
                        x: 40
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData.text
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: entryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const run = entry.modelData.run;
                            root.menu = null;
                            run();
                        }
                    }
                }
            }
        }
    }
}
