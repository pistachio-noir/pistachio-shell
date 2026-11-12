import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland // layer-shell keyboard focus and window capture (Wayland protocols, not a compositor module)
import Quickshell.Widgets // ClippingRectangle, for the rounded thumbnails
import QtQuick

// Alt+Tab window switcher (window-switcher and window-switcher-many boards; owner's design). Hyprland
// binds Alt+Tab and Alt+Shift+Tab to `switcher next` and `switcher prev`: the first opens it on the
// window before the focused one, the next ones step. Releasing Alt switches to the chosen window, its
// workspace too; should the release go unseen, a release bind on Alt can call `switcher commit`. The
// windows of every workspace, most recently used first, five to a row, each with a still taken as it
// opens; a badge names another workspace, a terracotta dot one that wants attention.
PanelWindow {
    id: root

    property bool open
    property var order: [] // the windows' addresses as it opened, most recently used first
    property int current
    // the ones still open, in that order (Q closes the chosen one)
    readonly property var windows: order.map(a => Compositor.windows.find(w => w.address === a)).filter(w => w)
    readonly property var chosen: windows[current] ?? null
    readonly property int activeWorkspace: Compositor.workspaces.find(w => w.active)?.id ?? 0
    // The pointer picks a card only once it has moved: the switcher appears under it, and the card
    // that happened to be there took the choice from Tab, so letting go of Alt "didn't switch" (checked).
    property point pointerStart: Qt.point(-1, -1)
    property bool pointerMoved

    // `tabs`: only the tabs of the focused window's group (Alt+`, owner's request, 9 November 2026), in
    // a tabbed workspace or any Hyprland group; nothing to show outside one
    property bool tabsOnly // shown by Alt+`: the hint says so

    function show(by: int, tabs: bool) {
        if (open) {
            step(by);
            return;
        }
        tabsOnly = tabs;
        // minimised windows wait in the bar's pill, not here
        let list = Compositor.windows.filter(w => !w.minimized).sort((a, b) => a.recency - b.recency);
        if (tabs) {
            const group = list[0]?.group ?? [];
            list = list.filter(w => group.includes(w.address));
            if (list.length < 2)
                return;
        }
        if (list.length === 0)
            return;
        order = list.map(w => w.address);
        current = list.length > 1 ? (by > 0 ? 1 : list.length - 1) : 0;
        pointerStart = Qt.point(-1, -1);
        pointerMoved = false;
        open = true;
    }

    // a pointer position on screen; it counts as moved once 4 px from where it first showed up
    function pointer(p: point) {
        if (pointerStart.x < 0)
            pointerStart = p;
        else if (Math.abs(p.x - pointerStart.x) + Math.abs(p.y - pointerStart.y) > 4)
            pointerMoved = true;
    }

    function step(by: int) {
        if (windows.length > 0)
            current = (current + by + windows.length) % windows.length;
    }

    // up and down a row, staying on the grid
    function row(by: int) {
        const i = current + by * 5;
        if (i >= 0 && i < windows.length)
            current = i;
    }

    // Focus first, keeping the keyboard until the switcher has gone: Hyprland gives it back to the
    // window that had it before a layer took it, so letting go first undid the switch (checked).
    function commit() {
        if (!open)
            return;
        if (chosen) {
            Compositor.focus(chosen.address);
            // a tab: once the switcher has let go of the keyboard, Hyprland hands it back to the tab
            // that had it, which brings that one to the front again (owner, 9 November): focus the
            // chosen one once more after
            if (chosen.group.length > 1)
                refocus = chosen.address;
        }
        open = false;
    }

    property string refocus

    Connections {
        target: reveal
        function onShownChanged() {
            if (!reveal.shown && root.refocus)
                refocusLater.restart(); // a beat after the window is gone, when Hyprland has handed the keyboard back
        }
    }

    Timer {
        id: refocusLater
        interval: 150
        onTriggered: {
            Compositor.focus(root.refocus);
            root.refocus = "";
        }
    }

    function cancel() {
        open = false;
    }

    function key(event) {
        const k = event.key;
        if (k === Qt.Key_Escape)
            cancel();
        else if (k === Qt.Key_Return || k === Qt.Key_Enter)
            commit();
        else if (k === Qt.Key_QuoteLeft && event.modifiers & Qt.ShiftModifier || k === Qt.Key_AsciiTilde) // Shift+`
            step(-1);
        else if (k === Qt.Key_QuoteLeft)
            step(1);
        else if (k === Qt.Key_Backtab || k === Qt.Key_Left || k === Qt.Key_H)
            step(-1);
        else if (k === Qt.Key_Tab || k === Qt.Key_Right || k === Qt.Key_L)
            step(1);
        else if (k === Qt.Key_Up || k === Qt.Key_K)
            row(-1);
        else if (k === Qt.Key_Down || k === Qt.Key_J)
            row(1);
        else if (k === Qt.Key_Q && chosen)
            Compositor.close(chosen.address);
        else
            return;
        event.accepted = true;
    }

    onWindowsChanged: {
        if (open && windows.length === 0)
            open = false;
        else if (current >= windows.length)
            current = Math.max(0, windows.length - 1);
    }
    onVisibleChanged: if (!visible) order = [] // the stills go with their cards

    visible: open || reveal.shown
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay // above fullscreen windows
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive // while it's up, as the launcher does

    // For keybinds: qs -c pistachio ipc call switcher next (prev, commit, cancel)
    IpcHandler {
        target: "switcher"

        function next(): void {
            root.show(1);
        }
        function prev(): void {
            root.show(-1);
        }
        // the tabs of the group you're in only
        function tabs(): void {
            root.show(1, true);
        }
        function tabsPrev(): void {
            root.show(-1, true);
        }
        function commit(): void {
            root.commit();
        }
        function cancel(): void {
            root.cancel();
        }
    }

    Reveal {
        id: reveal
        open: root.open
    }

    // the dimmed screen; a click on it cancels
    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        opacity: 0.66 * reveal.progress

        MouseArea {
            anchors.fill: parent
            onClicked: root.cancel()
        }

        HoverHandler {
            onPointChanged: root.pointer(point.position)
        }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        // centred in the room above the bar, rising 12 px as it fades in
        anchors.verticalCenterOffset: -(Theme.barHeight + Theme.barMargin) / 2 + 12 * (1 - reveal.progress)
        opacity: reveal.progress
        spacing: 16
        focus: true
        Keys.onPressed: event => root.key(event)
        Keys.onReleased: event => {
            if (event.key === Qt.Key_Alt)
                root.commit();
        }

        Rectangle {
            id: panel

            anchors.horizontalCenter: parent.horizontalCenter
            width: content.width + 40
            height: content.height + 40
            radius: Theme.panelRadius
            color: Theme.bgAlt
            border.width: 1
            border.color: Theme.overlay2
            Accessible.role: Accessible.List
            Accessible.name: "Open windows"

            Shadow {
                z: -1 // beneath the panel, fading with it
                kind: Theme.shadowModal
                anchors.fill: parent
                radius: parent.radius
            }

            // clicks between the cards don't cancel
            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: content

                x: 20
                y: 20
                spacing: 14

                Grid {
                    id: grid
                    columns: Math.max(1, Math.min(5, root.windows.length))
                    spacing: 12

                    Repeater {
                        model: root.order

                        Rectangle {
                            id: card

                            required property string modelData
                            // looked up live, so a title change doesn't remake the card (and its still)
                            readonly property var w: Compositor.windows.find(x => x.address === modelData) ?? null
                            readonly property bool selected: root.chosen?.address === modelData

                            visible: w !== null
                            width: 184
                            height: 8 + thumb.height + 6 + 32 + 8
                            radius: Theme.tileRadius
                            color: selected ? Theme.overlay2 : Theme.overlay
                            Accessible.role: Accessible.ListItem
                            Accessible.name: `${w?.title ?? ""}, ${Apps.nameFor(w?.appId ?? "")}, workspace ${w?.workspace ?? 0}` + (w?.urgent ? ", needs attention" : "")
                            Accessible.selected: selected

                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.hoverDuration
                                    easing.type: Theme.easing
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onPositionChanged: mouse => {
                                    root.pointer(mapToItem(null, mouse.x, mouse.y));
                                    if (root.pointerMoved && !card.selected)
                                        root.current = root.windows.findIndex(x => x.address === card.modelData);
                                }
                                onClicked: {
                                    root.current = root.windows.findIndex(x => x.address === card.modelData);
                                    root.commit();
                                }
                            }

                            ClippingRectangle {
                                id: thumb

                                x: 8
                                y: 8
                                width: 168
                                height: 104
                                radius: 14
                                color: Theme.bg

                                // a still of the window, covering the box (the longer side spills over)
                                ScreencopyView {
                                    id: shot

                                    readonly property real aspect: hasContent && sourceSize.height > 0 ? sourceSize.width / sourceSize.height : thumb.width / thumb.height

                                    anchors.centerIn: parent
                                    width: Math.max(thumb.width, thumb.height * aspect)
                                    height: Math.max(thumb.height, thumb.width / aspect)
                                    captureSource: card.w?.toplevel ?? null
                                    opacity: hasContent ? 1 : 0

                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: Theme.motionDuration
                                            easing.type: Theme.easing
                                        }
                                    }
                                }

                                // on another workspace: which
                                Rectangle {
                                    visible: card.w !== null && card.w.workspace !== root.activeWorkspace
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 8
                                    width: badge.implicitWidth + 16
                                    height: 20
                                    radius: 10
                                    color: Theme.bgAlt

                                    Text {
                                        id: badge
                                        anchors.centerIn: parent
                                        text: `WS ${card.w?.workspace ?? 0}`
                                        color: Theme.subtext
                                        font.family: Theme.fontUi
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        font.features: { "tnum": 1 }
                                    }
                                }

                                // wants attention: a terracotta dot ringed in the thumbnail's colour
                                Rectangle {
                                    visible: card.w?.urgent ?? false
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 5
                                    width: 16
                                    height: 16
                                    radius: 8
                                    color: Theme.bg

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 10
                                        height: 10
                                        radius: 5
                                        color: Theme.terracotta
                                    }
                                }
                            }

                            // the app's icon and the title; the chosen card's in a pistachio chip
                            Rectangle {
                                x: 8
                                y: thumb.y + thumb.height + 6
                                width: 168
                                height: 32
                                radius: 16
                                color: card.selected ? Theme.pistachio : "transparent"

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.hoverDuration
                                        easing.type: Theme.easing
                                    }
                                }

                                Image {
                                    id: appIcon
                                    x: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16
                                    height: 16
                                    sourceSize: Qt.size(32, 32)
                                    source: Apps.iconFor(card.w?.appId ?? "")
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    visible: status === Image.Ready
                                }

                                Icon {
                                    anchors.centerIn: appIcon
                                    visible: !appIcon.visible
                                    size: 16
                                    paths: Icons.window
                                    color: card.selected ? Theme.bg : Theme.subtext
                                }

                                Text {
                                    anchors.left: appIcon.right
                                    anchors.leftMargin: 8
                                    anchors.right: parent.right
                                    anchors.rightMargin: card.selected ? 12 : 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: card.w?.title ?? ""
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: card.selected ? Theme.bg : Theme.text
                                    font.family: Theme.fontUi
                                    font.pixelSize: 13
                                    font.weight: card.selected ? Font.ExtraBold : Font.Bold
                                }
                            }
                        }
                    }
                }

                // the chosen window in full, and where it is in the list
                Item {
                    width: grid.width
                    height: 15 + Math.max(names.height, count.height)

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.overlay
                    }

                    Column {
                        id: names

                        x: 4
                        y: 15
                        width: parent.width - count.width - 24
                        spacing: 2

                        Text {
                            width: parent.width
                            text: root.chosen?.title ?? ""
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: Theme.textBright
                            font.family: Theme.fontUi
                            font.pixelSize: 14
                            font.weight: Font.ExtraBold
                        }

                        Text {
                            width: parent.width
                            text: root.chosen ? `${Apps.nameFor(root.chosen.appId)} · Workspace ${root.chosen.workspace}` : ""
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }

                    Text {
                        id: count
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: names.verticalCenter
                        text: `${root.current + 1} of ${root.windows.length}`
                        color: Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.tabsOnly ? "` next tab · Shift+` previous · Q close window · Esc cancel" : "Tab next · Shift+Tab previous · Q close window · Esc cancel"
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
    }
}
