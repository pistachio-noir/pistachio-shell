import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland // the layer's level, keyboard and name (a Wayland protocol, not a compositor module)
import QtQuick
import QtQuick.Effects
import "../launcher/fuzzy.js" as Fuzzy

// The Overview (owner's request and boards, 11 November 2026: design/Overview.html, OverviewAll,
// OverviewDrag, OverviewEmpty, OverviewSearch), reopening "no overview in the shell". Over a dimmed
// wallpaper: the workspaces along the top (a sketch of each one's windows, New at the end), this
// workspace's windows as live pictures, and the keys. Tab shows every window by workspace; typing
// searches them all; a window dragged onto a workspace goes there. The bar hides meanwhile (owner's
// call, 12 November; the boards had it showing). This layer is mapped first (shell.qml) and never
// unmapped, only emptied and click-through while closed, so the bar stays above it as it hides.
PanelWindow {
    id: root

    property bool open
    property string mode: "here" // "here" | "all"
    property string query
    property int current // the selected card in the list on screen
    property var drag: null // { card, x, y } while a window is dragged
    property int dropTarget: 0 // the workspace under a dragged window; -1 for New
    property point pointer: Qt.point(-1, -1) // to tell a real move from a card arriving under it

    signal launcherRequested(string mode)

    readonly property bool shown: reveal.shown
    readonly property int active: Compositor.activeWorkspace
    readonly property var everyWindow: Compositor.windows.filter(w => w.workspace > 0)
    // the workspaces to show: those with windows, and the one on screen (empty ones in between would
    // crowd the strip: with a window on 10, 1–10 ran off the screen)
    readonly property var spaces: [...new Set(Compositor.workspaces.filter(w => w.occupied).map(w => w.id).concat([active]))].filter(id => id > 0).sort((a, b) => a - b)
    readonly property int newSpace: Math.max(0, ...spaces) + 1
    readonly property var hereCards: cards(everyWindow.filter(w => w.workspace === active))
    readonly property var columns: spaces.map(id => ({ id: id, cards: cards(everyWindow.filter(w => w.workspace === id)) })).filter(c => c.cards.length > 0)
    readonly property var allCards: columns.reduce((all, c) => all.concat(c.cards), [])
    readonly property bool searching: query !== ""
    readonly property var found: searching ? search(query) : []
    readonly property int matches: found.filter(c => c.match).length
    readonly property var list: searching ? found.filter(c => c.match) : mode === "all" ? allCards : hereCards
    readonly property var selected: list[Math.min(current, list.length - 1)] ?? null

    function title(id: int): string {
        return Compositor.nameOf(id) || String(id);
    }

    function count(id: int): int {
        return everyWindow.filter(w => w.workspace === id).length;
    }

    // a tabbed group is one card, its showing tab in front; lone windows are cards of their own, left
    // to right as they're laid out
    function cards(windows: var): var {
        const out = [], seen = {};
        for (const w of windows) {
            if (w.group.length > 1) {
                const key = w.group[0];
                if (seen[key])
                    continue;
                seen[key] = true;
                const tabs = w.group.map(a => windows.find(x => x.address === a)).filter(x => x);
                out.push({ key: key, w: tabs.find(x => !x.hidden) ?? tabs[0], tabs: tabs });
            } else
                out.push({ key: w.address, w: w, tabs: [] });
        }
        return out.sort((a, b) => a.w.bounds.x - b.w.bounds.x || a.w.bounds.y - b.w.bounds.y);
    }

    function label(w): string {
        return w ? w.title || Apps.nameFor(w.appId) || w.appId || "Window" : "";
    }

    // every window, matches first (by recent use), then the rest dimmed; at most 12
    function search(q: string): var {
        // by title, app and workspace name, of every tab in a group too
        const words = c => (c.tabs.length ? c.tabs : [c.w]).reduce((all, w) => all.concat([label(w), Apps.nameFor(w.appId), w.appId]), [title(c.w.workspace)]);
        const all = allCards.map(c => Object.assign({}, c, { match: words(c).some(s => s && Fuzzy.match(q, s) !== null) }));
        const hits = all.filter(c => c.match).sort((a, b) => a.w.recency - b.w.recency);
        return hits.concat(all.filter(c => !c.match)).slice(0, 12);
    }

    function show() {
        mode = "here";
        query = "";
        current = Math.max(0, hereCards.findIndex(c => c.w.focused || c.tabs.some(t => t.focused)));
        drag = null;
        open = true;
    }

    function hide() {
        open = false;
        drag = null;
    }

    // focus first, then let the keyboard go as the layer fades (Hyprland would hand it back otherwise)
    function activate(card) {
        if (!card)
            return;
        Compositor.focus(card.w.address);
        hide();
    }

    function gotoSpace(id: int) {
        Compositor.goto(id);
        mode = "here";
        query = "";
        current = 0;
    }

    // the workspace a digit key names: 1–9, and 0 for 10; 0 for any other key
    function digit(event): int {
        const code = event.nativeScanCode;
        if (code >= 10 && code <= 19)
            return code - 9;
        if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9)
            return event.key - Qt.Key_0;
        return event.key === Qt.Key_0 ? 10 : 0;
    }

    function step(by: int) {
        if (list.length)
            current = (Math.min(current, list.length - 1) + by + list.length) % list.length;
    }

    function finishDrag() {
        if (!drag) return;
        const target = dropTarget, card = drag.card;
        drag = null;
        dropTarget = 0;
        if (target === -1)
            Compositor.sendWindow(card.w.address, newSpace);
        else if (target > 0 && target !== active)
            Compositor.sendWindow(card.w.address, target);
    }

    function key(event) {
            const ctrl = event.modifiers & Qt.ControlModifier;
            const w = root.selected?.w;
            event.accepted = true;
            if (event.key === Qt.Key_Escape) {
                if (root.drag)
                    root.drag = null;
                else if (root.searching)
                    root.query = "";
                else
                    root.hide();
            } else if (event.key === Qt.Key_Tab && !root.searching) {
                root.mode = root.mode === "all" ? "here" : "all";
                root.current = 0;
            } else if (event.key === Qt.Key_Left || ctrl && event.key === Qt.Key_H)
                root.step(-1);
            else if (event.key === Qt.Key_Right || ctrl && event.key === Qt.Key_L)
                root.step(1);
            else if (event.key === Qt.Key_Up || ctrl && event.key === Qt.Key_K)
                root.step(root.searching ? -3 : -1);
            else if (event.key === Qt.Key_Down || ctrl && event.key === Qt.Key_J)
                root.step(root.searching ? 3 : 1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                root.activate(root.selected);
            else if (event.key === Qt.Key_Backspace && root.searching)
                root.query = ctrl ? "" : root.query.slice(0, -1);
            // Ctrl+1…9/0 goes to workspace 1–10, Ctrl+Shift+1…9/0 sends the selected window there (owner's
            // request, 12 November). The digit row by scan code (10–19), so Shift's symbols and other
            // layouts don't matter; Qt's digit keys as a fallback.
            else if (ctrl && root.digit(event) > 0) {
                if (event.modifiers & Qt.ShiftModifier) {
                    if (w)
                        Compositor.sendWindow(w.address, root.digit(event));
                } else
                    root.gotoSpace(root.digit(event));
            }
            // Ctrl+W and Ctrl+F, as in the launcher's Windows mode: plain letters always type into the
            // search (the boards' plain Q and F kept "q…" and "f…" apps from being searched, owner's report)
            else if (ctrl && event.key === Qt.Key_W && w)
                Compositor.close(w.address);
            else if (ctrl && event.key === Qt.Key_F && w)
                Compositor.toggleFloating(w.address);
            else if (!ctrl && !(event.modifiers & Qt.AltModifier) && event.text.length === 1 && event.text >= " " && event.text !== "\u007f") {
                if (!root.searching && event.text === " ")
                    return;
                root.query += event.text;
                root.current = 0;
            } else
                event.accepted = false;
    }

    Connections {
        target: Theme
        function onTuiChanged() { root.drag = null; root.dropTarget = 0; root.pointer = Qt.point(-1, -1); }
    }

    onListChanged: if (current >= list.length) current = Math.max(0, list.length - 1)

    visible: true // always mapped (see above)
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "pistachio-overview"
    WlrLayershell.layer: Theme.tui ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: Region {
        width: root.shown ? root.width : 0
        height: root.shown ? root.height : 0 // the TUI strip hides under the Overview now (owner's bug report)
    }

    // For a keybind: qs -c pistachio ipc call overview toggle
    IpcHandler {
        target: "overview"

        function toggle(): void {
            if (root.open)
                root.hide();
            else
                root.show();
        }
        function open(): void {
            root.show();
        }
        function close(): void {
            root.hide();
        }
        function status(): string {
            return JSON.stringify({ open: root.open, mode: root.mode, query: root.query, cards: root.list.length, current: root.current, workspace: root.active });
        }
    }

    Reveal {
        id: reveal
        open: root.open
    }

    Loader {
        anchors.fill: parent
        focus: true
        sourceComponent: Theme.tui ? tuiView : classicView
    }
    Component { id: tuiView; TuiOverview { controller: root; progress: reveal.progress } }
    Component {
        id: classicView
        Item {
            objectName: "classic-overview"
            anchors.fill: parent
    // the wallpaper, dimmed, over the windows; a click on it leaves
    Item {
        id: backdrop
        anchors.fill: parent
        opacity: reveal.progress
        visible: root.shown

        // blurred, and settling from a slight zoom as it opens: a step back from the desktop
        Loader {
            anchors.fill: parent
            active: root.shown
            scale: 1.12 - 0.07 * reveal.progress // never under 1.05, so the blur's soft edge stays off screen
            sourceComponent: WallpaperView {
                path: Wallpapers.current
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1
                    blurMax: 48
                    autoPaddingEnabled: false
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.deep
            opacity: 0.5
        }

        MouseArea {
            anchors.fill: parent
            onClicked: if (!root.drag) root.hide()
        }
    }

    Item {
        id: content

        anchors.fill: parent
        visible: root.shown
        opacity: reveal.progress
        scale: 0.97 + 0.03 * reveal.progress
        focus: root.open

        Keys.onPressed: event => root.key(event)

        // the workspaces along the top (not with All windows or a search)
        Row {
            id: strip

            // the boards' 208 × 117, smaller when many workspaces wouldn't fit
            readonly property real cardW: Math.min(208, (root.width - 80 - (root.spaces.length) * 16) / (root.spaces.length + 1))
            readonly property real cardH: cardW * 117 / 208

            visible: !root.searching && root.mode === "here"
            anchors.horizontalCenter: parent.horizontalCenter
            y: 28
            spacing: 16

            Repeater {
                model: root.spaces.concat([-1])

                Item {
                    id: space

                    required property int modelData
                    required property int index
                    readonly property bool isNew: modelData === -1
                    // arriving one after another as the Overview opens (a little life, owner's request)
                    property real appear: root.open ? 1 : 0
                    Behavior on appear {
                        SequentialAnimation {
                            PauseAnimation {
                                duration: root.open ? 60 + Math.min(index, 8) * 35 : 0
                            }
                            NumberAnimation {
                                duration: Theme.motionDuration + 60
                                easing.type: Theme.easing
                            }
                        }
                    }
                    opacity: appear
                    transform: Translate {
                        y: (1 - space.appear) * -14
                    }

                    readonly property bool here: modelData === root.active
                    readonly property var windows: isNew ? [] : root.everyWindow.filter(w => w.workspace === modelData && !w.hidden)
                    readonly property bool target: root.drag !== null && root.dropTarget === modelData

                    width: strip.cardW
                    height: strip.cardH + 9 + 28

                    Shadow {
                        visible: !space.isNew && ShellSettings.shadows
                        kind: Theme.shadowSmall
                        anchors.fill: sketch
                        radius: sketch.radius
                    }

                    // a sketch of its windows, where they are on screen
                    Rectangle {
                        id: sketch

                        width: strip.cardW
                        height: strip.cardH
                        radius: 20
                        scale: spaceMouse.containsMouse && !root.drag ? 1.03 : 1
                        color: space.isNew ? "transparent" : Theme.deep

                        Behavior on scale {
                            NumberAnimation {
                                duration: Theme.hoverDuration
                                easing.type: Theme.easing
                            }
                        }
                        border.width: space.isNew ? 0 : space.here || space.target ? 2 : 1
                        border.color: space.here || space.target ? Theme.textBright : spaceMouse.containsMouse ? Theme.overlay2 : Theme.overlay
                        clip: true

                        Behavior on border.color {
                            ColorAnimation {
                                duration: Theme.hoverDuration
                                easing.type: Theme.easing
                            }
                        }

                        Repeater {
                            model: space.windows

                            Rectangle {
                                required property var modelData
                                readonly property real sx: (sketch.width - 20) / Math.max(1, root.width)
                                readonly property real sy: (sketch.height - 20) / Math.max(1, root.height)

                                x: 10 + modelData.bounds.x * sx
                                y: 10 + modelData.bounds.y * sy
                                width: Math.max(12, modelData.bounds.width * sx)
                                height: Math.max(10, modelData.bounds.height * sy)
                                radius: 7
                                color: Theme.bg
                                border.width: 1
                                border.color: Theme.overlay2
                                clip: true

                                Rectangle {
                                    width: parent.width
                                    height: 8
                                    color: Theme.bgAlt
                                    radius: 7
                                }

                                Image {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: 4
                                    width: Math.min(18, parent.height - 14)
                                    height: width
                                    sourceSize: Qt.size(36, 36)
                                    source: Apps.iconFor(parent.modelData.appId)
                                    asynchronous: true
                                    opacity: 0.8
                                }
                            }
                        }

                        DashedFrame {
                            visible: space.isNew
                            anchors.fill: parent
                            radius: 20
                            color: space.target ? Theme.textBright : spaceMouse.containsMouse ? Theme.subtext : Theme.muted
                        }

                        Icon {
                            visible: space.isNew
                            anchors.centerIn: parent
                            size: 20
                            paths: Icons.plus
                            color: Theme.subtext
                        }

                        // "Move here" while a window is dragged over it
                        OverviewChip {
                            visible: space.target
                            x: 12
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 12
                            text: "Move here"
                            glyph: Icons.chevronRight
                            active: true
                        }
                    }

                    OverviewChip {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: strip.cardH + 9
                        small: true
                        maxWidth: strip.cardW + 16
                        active: space.here
                        text: space.isNew ? "New" : root.title(space.modelData)
                        detail: space.isNew ? "" : space.here && space.windows.length === 0 ? "empty" : space.windows.length === 0 ? "" : `${root.count(space.modelData)} window${root.count(space.modelData) === 1 ? "" : "s"}`
                    }

                    MouseArea {
                        id: spaceMouse
                        anchors.fill: sketch
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.gotoSpace(space.isNew ? root.newSpace : space.modelData)
                        Accessible.role: Accessible.Button
                        Accessible.name: space.isNew ? "New workspace" : `Workspace ${root.title(space.modelData)}`
                    }
                }
            }
        }

        // This workspace / All windows (with All windows)
        Rectangle {
            visible: !root.searching && root.mode === "all"
            anchors.horizontalCenter: parent.horizontalCenter
            y: 24
            width: modes.implicitWidth + 12
            height: 58
            radius: 29
            color: Theme.bgAlt
            border.width: 1
            border.color: Theme.overlay2

            Row {
                id: modes
                anchors.centerIn: parent
                spacing: 4

                Repeater {
                    model: [["here", "This workspace"], ["all", "All windows"]]

                    Rectangle {
                        required property var modelData
                        readonly property bool on: root.mode === modelData[0]

                        width: modeText.implicitWidth + 40
                        height: 46
                        radius: 23
                        color: on ? Theme.pistachio : modeMouse.containsMouse ? Theme.overlay : "transparent"

                        Text {
                            id: modeText
                            anchors.centerIn: parent
                            text: parent.modelData[1]
                            color: parent.on ? Theme.bg : Theme.text
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            font.weight: parent.on ? Font.ExtraBold : Font.Bold
                        }

                        MouseArea {
                            id: modeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.mode = parent.modelData[0];
                                root.current = 0;
                            }
                        }
                    }
                }
            }
        }

        // the search field (while typing)
        Rectangle {
            visible: root.searching
            anchors.horizontalCenter: parent.horizontalCenter
            y: 24
            width: 520
            height: 56
            radius: 28
            color: Theme.bgAlt
            border.width: 1
            border.color: Theme.overlay2

            Icon {
                x: 22
                anchors.verticalCenter: parent.verticalCenter
                size: 18
                paths: Icons.search
                color: Theme.subtext
            }

            Text {
                id: queryText
                x: 52
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, foundCount.x - x - 16)
                elide: Text.ElideLeft
                text: root.query
                color: Theme.textBright
                font.family: Theme.fontUi
                font.pixelSize: 16
                font.weight: Font.Bold
            }

            Rectangle {
                x: queryText.x + queryText.width + 2
                anchors.verticalCenter: parent.verticalCenter
                width: 2
                height: 20
                radius: 1
                color: Theme.pistachio
            }

            Text {
                id: foundCount
                anchors.right: clear.left
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: `${root.matches} window${root.matches === 1 ? "" : "s"}`
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }

            Rectangle {
                id: clear
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32
                radius: 16
                color: clearMouse.containsMouse ? Theme.overlay : "transparent"

                Icon {
                    anchors.centerIn: parent
                    size: 14
                    paths: Icons.close
                    color: Theme.subtext
                }

                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.query = ""
                }
            }
        }

        // this workspace's windows, in rows of up to four, smaller as more come
        Item {
            id: hereArea

            readonly property int n: root.hereCards.length + (root.drag ? 0 : 0)
            readonly property int cols: Math.min(Math.max(1, n), n > 6 ? 4 : 3)
            readonly property int rows: Math.ceil(n / cols)
            readonly property real cardW: Math.min(360, (width - (cols - 1) * 40) / cols, ((height - rows * 56) / Math.max(1, rows)) * 360 / 225)
            readonly property real cardH: cardW * 225 / 360

            visible: !root.searching && root.mode === "here" && n > 0
            x: 60
            y: 244
            width: parent.width - 120
            height: hints.y - 24 - y

            Repeater {
                model: root.hereCards

                Item {
                    id: slot

                    required property var modelData
                    required property int index
                    readonly property int col: index % hereArea.cols
                    readonly property int row: Math.floor(index / hereArea.cols)
                    readonly property int inRow: Math.min(hereArea.cols, hereArea.n - row * hereArea.cols)
                    readonly property bool lifted: root.drag?.card.key === modelData.key

                    // arriving one after another as the Overview opens (a little life, owner's request)
                    property real appear: root.open ? 1 : 0
                    Behavior on appear {
                        SequentialAnimation {
                            PauseAnimation {
                                duration: root.open ? 60 + Math.min(index, 8) * 35 : 0
                            }
                            NumberAnimation {
                                duration: Theme.motionDuration + 60
                                easing.type: Theme.easing
                            }
                        }
                    }
                    opacity: appear
                    transform: Translate {
                        y: (1 - slot.appear) * 22
                    }

                    x: (hereArea.width - inRow * hereArea.cardW - (inRow - 1) * 40) / 2 + col * (hereArea.cardW + 40)
                    y: row * (hereArea.cardH + 56)
                    width: hereArea.cardW
                    height: hereArea.cardH + 12 + 32

                    OverviewThumb {
                        id: thumb
                        visible: !slot.lifted
                        width: hereArea.cardW
                        height: hereArea.cardH
                        w: slot.modelData.w
                        tabs: slot.modelData.tabs
                        live: root.shown
                        selected: !root.drag && slot.index === root.current
                        hovered: cardMouse.containsMouse
                        onCloseClicked: Compositor.close(slot.modelData.w.address)
                    }

                    DashedFrame {
                        visible: slot.lifted
                        width: hereArea.cardW
                        height: hereArea.cardH
                        radius: 16
                        color: Theme.muted
                        lineWidth: 1
                    }

                    OverviewChip {
                        visible: !slot.lifted
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: hereArea.cardH + 12
                        maxWidth: hereArea.cardW
                        active: slot.index === root.current
                        text: slot.modelData.tabs.length > 1 ? "Tabbed group" : root.label(slot.modelData.w)
                        detail: slot.modelData.tabs.length > 1 ? `${slot.modelData.tabs.length} tabs` : ""
                        icon: slot.modelData.tabs.length > 1 ? "" : Apps.iconFor(slot.modelData.w.appId)
                        glyph: slot.modelData.tabs.length > 1 ? Icons.layers : Icons.window
                    }

                    // a click focuses it; a drag takes it to a workspace above
                    MouseArea {
                        id: cardMouse

                        property point from

                        x: thumb.cardRect.x
                        y: thumb.cardRect.y
                        width: thumb.cardRect.width
                        height: thumb.cardRect.height
                        hoverEnabled: true
                        cursorShape: root.drag ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                        onPositionChanged: mouse => {
                            const at = mapToItem(content, mouse.x, mouse.y);
                            if (Math.abs(at.x - root.pointer.x) > 0.5 || Math.abs(at.y - root.pointer.y) > 0.5) {
                                if (root.pointer.x >= 0 && !root.drag)
                                    root.current = slot.index;
                                root.pointer = at;
                            }
                            if (pressed && !root.drag && Math.hypot(mouse.x - from.x, mouse.y - from.y) > 8)
                                root.drag = { card: slot.modelData, x: at.x, y: at.y };
                            if (root.drag) {
                                root.drag = Object.assign({}, root.drag, { x: at.x, y: at.y });
                                const s = strip.childAt(at.x - strip.x, at.y - strip.y);
                                root.dropTarget = s && s.modelData !== undefined && at.y - strip.y < strip.cardH ? s.modelData : 0;
                            }
                        }
                        onPressed: mouse => from = Qt.point(mouse.x, mouse.y)
                        onReleased: root.finishDrag()
                        onClicked: if (!root.drag) root.activate(slot.modelData)
                    }
                }
            }
        }

        // nothing on this workspace
        Item {
            id: emptyCard

            // rising in after the workspaces, like the window cards
            property real appear: root.open ? 1 : 0
            Behavior on appear {
                SequentialAnimation {
                    PauseAnimation {
                        duration: root.open ? 140 : 0
                    }
                    NumberAnimation {
                        duration: Theme.motionDuration + 60
                        easing.type: Theme.easing
                    }
                }
            }
            opacity: appear
            transform: Translate {
                y: (1 - emptyCard.appear) * 22
            }

            visible: !root.searching && root.mode === "here" && root.hereCards.length === 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: 240
            width: 520
            height: 270

            DashedFrame {
                anchors.fill: parent
                radius: 28
                color: Theme.muted
                lineWidth: 1
            }

            Column {
                anchors.centerIn: parent
                spacing: 0

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 56
                    height: 56
                    radius: 28
                    color: Theme.overlay

                    Icon {
                        anchors.centerIn: parent
                        size: 24
                        paths: Icons.layers
                        color: Theme.subtext
                    }
                }

                Item {
                    width: 1
                    height: 18
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: `Nothing open on ${Compositor.nameOf(root.active) || "workspace " + root.active}`
                    color: Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: 18
                    font.weight: Font.ExtraBold
                }

                Item {
                    width: 1
                    height: 8
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 340
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Open an app from the launcher, or bring a saved setup back to this workspace."
                    color: Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    lineHeight: 1.3
                }

                Item {
                    width: 1
                    height: 24
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8

                    Repeater {
                        model: [["all", "Open launcher", Icons.search, true], ["workspaces", "Load a preset", Icons.layers, false]]

                        Rectangle {
                            required property var modelData

                            width: buttonRow.implicitWidth + 40
                            height: 44
                            radius: 22
                            color: modelData[3] ? (buttonMouse.containsMouse ? Qt.lighter(Theme.pistachio, 1.06) : Theme.pistachio) : buttonMouse.containsMouse ? Theme.overlay2 : Theme.overlay

                            Row {
                                id: buttonRow
                                anchors.centerIn: parent
                                spacing: 8

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: 16
                                    paths: parent.parent.modelData[2]
                                    color: parent.parent.modelData[3] ? Theme.bg : Theme.text
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.parent.modelData[1]
                                    color: parent.parent.modelData[3] ? Theme.bg : Theme.text
                                    font.family: Theme.fontUi
                                    font.pixelSize: 13
                                    font.weight: Font.ExtraBold
                                }
                            }

                            MouseArea {
                                id: buttonMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.hide();
                                    root.launcherRequested(parent.modelData[0]);
                                }
                            }
                        }
                    }
                }
            }
        }

        // All windows: a column per workspace
        Row {
            id: columnsRow

            readonly property real colW: Math.min(240, (parent.width - 120 - (root.columns.length - 1) * 56) / Math.max(1, root.columns.length))
            readonly property real cardH: colW * 150 / 240

            visible: !root.searching && root.mode === "all"
            anchors.horizontalCenter: parent.horizontalCenter
            y: 96
            spacing: 56

            Repeater {
                model: root.columns

                Column {
                    id: column

                    required property var modelData

                    width: columnsRow.colW
                    spacing: 14

                    OverviewChip {
                        anchors.horizontalCenter: parent.horizontalCenter
                        small: true
                        maxWidth: columnsRow.colW
                        active: column.modelData.id === root.active
                        text: root.title(column.modelData.id)
                        detail: String(root.count(column.modelData.id))
                    }

                    Item {
                        width: 1
                        height: 8
                    }

                    Repeater {
                        model: column.modelData.cards

                        Item {
                            id: allCard

                            required property var modelData
                            readonly property int index: root.allCards.findIndex(c => c.key === modelData.key)

                    // arriving one after another as the Overview opens (a little life, owner's request)
                    property real appear: root.open ? 1 : 0
                    Behavior on appear {
                        SequentialAnimation {
                            PauseAnimation {
                                duration: root.open ? 60 + Math.min(index, 8) * 35 : 0
                            }
                            NumberAnimation {
                                duration: Theme.motionDuration + 60
                                easing.type: Theme.easing
                            }
                        }
                    }
                    opacity: appear
                    transform: Translate {
                        y: (1 - allCard.appear) * 18
                    }

                            width: columnsRow.colW
                            height: allThumb.cardRect.height + (modelData.tabs.length > 1 ? 12 + 28 : 0)

                            OverviewThumb {
                                id: allThumb
                                width: columnsRow.colW
                                height: columnsRow.cardH
                                atTop: true
                                radius: 14
                                w: allCard.modelData.w
                                tabs: allCard.modelData.tabs
                                live: root.shown && root.mode === "all"
                                selected: allCard.index === root.current
                                hovered: allMouse.containsMouse
                                onCloseClicked: Compositor.close(allCard.modelData.w.address)
                            }

                            // its name inside, bottom left
                            OverviewChip {
                                visible: allCard.modelData.tabs.length <= 1
                                x: allThumb.cardRect.x + 8
                                y: allThumb.cardRect.y + allThumb.cardRect.height - height - 8
                                implicitHeight: 26
                                maxWidth: columnsRow.colW - 16
                                active: allCard.index === root.current
                                text: root.label(allCard.modelData.w)
                                icon: Apps.iconFor(allCard.modelData.w.appId)
                                glyph: Icons.window
                            }

                            OverviewChip {
                                visible: allCard.modelData.tabs.length > 1
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: allThumb.cardRect.height + 12
                                small: true
                                active: allCard.index === root.current
                                text: "Tabbed group"
                                detail: `${allCard.modelData.tabs.length} tabs`
                            }

                            MouseArea {
                                id: allMouse
                                x: allThumb.cardRect.x
                                width: allThumb.cardRect.width
                                height: allThumb.cardRect.height
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onPositionChanged: mouse => {
                                    const at = mapToItem(content, mouse.x, mouse.y);
                                    if (root.pointer.x >= 0 && (Math.abs(at.x - root.pointer.x) > 0.5 || Math.abs(at.y - root.pointer.y) > 0.5))
                                        root.current = allCard.index;
                                    root.pointer = at;
                                }
                                onClicked: root.activate(allCard.modelData)
                            }
                        }
                    }
                }
            }
        }

        // a search: matches first, the rest dimmed, three to a row
        Item {
            id: foundArea

            visible: root.searching
            anchors.horizontalCenter: parent.horizontalCenter
            y: 108
            width: 3 * 280 + 2 * 40
            height: hints.y - 24 - y
            clip: true

            Repeater {
                model: root.found

                Item {
                    id: hit

                    required property var modelData
                    required property int index

                    readonly property int inRow: Math.min(3, root.found.length - Math.floor(index / 3) * 3)

                    x: (foundArea.width - inRow * 280 - (inRow - 1) * 40) / 2 + index % 3 * (280 + 40)
                    y: Math.floor(index / 3) * 234
                    width: 280
                    height: 175 + 12 + 32

                    OverviewThumb {
                        id: hitThumb
                        width: 280
                        height: 175
                        w: hit.modelData.w
                        tabs: hit.modelData.tabs
                        live: root.shown && root.searching
                        dimmed: !hit.modelData.match
                        selected: hit.modelData.match && hit.index === root.current
                        hovered: hit.modelData.match && hitMouse.containsMouse
                        badge: root.title(hit.modelData.w.workspace)
                        onCloseClicked: Compositor.close(hit.modelData.w.address)
                    }

                    OverviewChip {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 175 + 12
                        opacity: hit.modelData.match ? 1 : 0.35
                        maxWidth: 280
                        active: hit.modelData.match && hit.index === root.current
                        text: hit.modelData.tabs.length > 1 ? "Tabbed group" : root.label(hit.modelData.w)
                        detail: hit.modelData.tabs.length > 1 ? `${hit.modelData.tabs.length} tabs` : ""
                        icon: hit.modelData.tabs.length > 1 ? "" : Apps.iconFor(hit.modelData.w.appId)
                        glyph: hit.modelData.tabs.length > 1 ? Icons.layers : Icons.window
                    }

                    MouseArea {
                        id: hitMouse
                        x: hitThumb.cardRect.x
                        y: hitThumb.cardRect.y
                        width: hitThumb.cardRect.width
                        height: hitThumb.cardRect.height
                        enabled: hit.modelData.match
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: mouse => {
                            const at = mapToItem(content, mouse.x, mouse.y);
                            if (root.pointer.x >= 0 && (Math.abs(at.x - root.pointer.x) > 0.5 || Math.abs(at.y - root.pointer.y) > 0.5))
                                root.current = hit.index;
                            root.pointer = at;
                        }
                        onClicked: root.activate(hit.modelData)
                    }
                }
            }
        }

        // the window being dragged, small and tilted, under the pointer
        OverviewThumb {
            visible: root.drag !== null
            x: (root.drag?.x ?? 0) - width / 2
            y: (root.drag?.y ?? 0) - height / 2
            width: 150
            height: 94
            radius: 12
            rotation: -4
            w: root.drag?.card.w ?? null
            live: false
            closable: false
            z: 10
        }

        // the keys
        Row {
            id: hints

            readonly property var keys: root.drag ? [["Drop", "on a workspace to send the window there"], ["Esc", "cancel"]]
                : root.searching ? [["↑ ↓ ← →", "move"], ["Enter", "focus"], ["Backspace", "clear"], ["Esc", "leave"]]
                : root.mode === "here" && root.hereCards.length === 0 ? [["Click", "a workspace to go there"], ["Esc", "leave"]]
                : [["Click", "focus"], ["Tab", root.mode === "all" ? "this workspace" : "all windows"], ["Ctrl+W", "close"], ["Ctrl+F", "float"], ["Ctrl+1…0", "go to workspace"], ["Ctrl+Shift+1…0", "send there"], ["Type", "to search"], ["Esc", "leave"]]

            anchors.horizontalCenter: parent.horizontalCenter
            y: root.height - Theme.barMargin - Theme.barHeight - 58 - 16
            spacing: 14

            Repeater {
                model: hints.keys

                Row {
                    required property var modelData

                    spacing: 4

                    Text {
                        text: parent.modelData[0]
                        color: Theme.textBright
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        font.weight: Font.ExtraBold
                    }

                    Text {
                        text: parent.modelData[1]
                        color: Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }        }
    }
}
