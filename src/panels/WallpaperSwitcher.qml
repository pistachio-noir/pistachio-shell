import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland // layer-shell keyboard focus (a Wayland protocol, not a compositor module)
import Quickshell.Widgets // ClippingRectangle, for the rounded thumbnails
import QtQuick
import QtQuick.Effects

// Wallpaper switcher (wallpaper-switcher and wallpaper-switcher-empty boards; owner's design). Opened
// from the launcher's Wallpapers row or `wallpaper toggle`. A live preview: the chosen image fills
// the screen behind the panel, over the windows (which would hide the desktop's own), cross-fading as
// the choice moves. Enter or a click sets it, R picks one at random, Esc leaves the wallpaper as it
// was. Each image keeps its own fit (Fill, Fit, Center, Tile).
PanelWindow {
    id: root

    property bool open
    property int current
    readonly property var images: Wallpapers.images
    // TUI's filter (WallpapersEmpty board: "/ filter"); Classic always lists every image
    property string filter
    readonly property var list: filtered(filter)
    readonly property var chosen: list[current] ?? null
    // The pointer picks a card only once it moves: the switcher appears under it (as Alt+Tab learnt).
    property point pointerStart: Qt.point(-1, -1)
    property bool pointerMoved
    readonly property var fits: [["fill", "Fill"], ["fit", "Fit"], ["center", "Center"], ["tile", "Tile"]]

    function filtered(text: string): var {
        return Theme.tui && text !== "" ? images.filter(i => i.name.toLowerCase().includes(text.toLowerCase())) : images;
    }

    function show() {
        filter = "";
        current = Math.max(0, images.findIndex(i => i.path === Wallpapers.current));
        pointerStart = Qt.point(-1, -1);
        pointerMoved = false;
        open = true;
        grid.positionViewAtIndex(current, GridView.Contain);
        tuiList.positionViewAtIndex(current, ListView.Contain);
        if (Theme.tui)
            tuiFilter.forceActiveFocus();
    }

    function apply() {
        if (chosen)
            Wallpapers.set(chosen.path);
        open = false;
    }

    function step(by: int) {
        const i = current + by;
        if (i >= 0 && i < list.length)
            current = i;
    }

    function pointer(p: point) {
        if (pointerStart.x < 0)
            pointerStart = p;
        else if (Math.abs(p.x - pointerStart.x) + Math.abs(p.y - pointerStart.y) > 4)
            pointerMoved = true;
    }

    function key(event) {
        const k = event.key;
        if (k === Qt.Key_Escape)
            open = false;
        else if (images.length === 0 && (k === Qt.Key_Return || k === Qt.Key_Enter)) {
            Wallpapers.openFolder();
            open = false;
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter)
            apply();
        else if (k === Qt.Key_Left || k === Qt.Key_H)
            step(-1);
        else if (k === Qt.Key_Right || k === Qt.Key_L)
            step(1);
        else if (k === Qt.Key_Up || k === Qt.Key_K)
            step(-3);
        else if (k === Qt.Key_Down || k === Qt.Key_J)
            step(3);
        else if (k === Qt.Key_R && images.length > 1) {
            const others = images.map((_, i) => i).filter(i => i !== current);
            current = others[Math.floor(Math.random() * others.length)];
        } else
            return;
        event.accepted = true;
    }

    // TUI: letters type into the filter, so the vim motions and R take Ctrl, as in the launcher
    function tuiKey(event) {
        const k = event.key;
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (k === Qt.Key_Escape)
            open = false;
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            if (images.length === 0) {
                Wallpapers.openFolder();
                open = false;
            } else if (chosen)
                apply();
        } else if (k === Qt.Key_Up || (ctrl && k === Qt.Key_K))
            step(-1);
        else if (k === Qt.Key_Down || (ctrl && k === Qt.Key_J))
            step(1);
        else if (k === Qt.Key_PageUp)
            current = Math.max(0, current - 10);
        else if (k === Qt.Key_PageDown)
            current = Math.max(0, Math.min(list.length - 1, current + 10));
        else if (k === Qt.Key_Tab && chosen) {
            const i = fits.findIndex(f => f[0] === Wallpapers.fitOf(chosen.path));
            Wallpapers.setFit(chosen.path, fits[(i + 1) % fits.length][0]);
        } else if (ctrl && k === Qt.Key_R && list.length > 1) {
            const others = list.map((_, i) => i).filter(i => i !== current);
            current = others[Math.floor(Math.random() * others.length)];
        } else
            return;
        event.accepted = true;
    }

    // "3840 × 2160 · 1.1 MB"
    function details(size: size, bytes: real): string {
        const mb = bytes / 1048576;
        const amount = mb >= 1 ? `${mb.toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`;
        return size.width > 0 ? `${size.width} × ${size.height} · ${amount}` : amount;
    }

    onCurrentChanged: {
        grid.positionViewAtIndex(current, GridView.Contain);
        tuiList.positionViewAtIndex(current, ListView.Contain);
    }
    // the handler can run before `list` follows the filter, so it filters for itself
    onFilterChanged: current = Math.max(0, filtered(filter).findIndex(i => i.path === Wallpapers.current))

    visible: open || reveal.shown
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    // TUI keeps its top bar in view (board: the switcher sits below the strip, which names it)
    margins.top: Theme.tui ? Theme.tuiBarHeight : 0
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay // above fullscreen windows
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive // while it's up, as the launcher does

    // For a keybind: qs -c pistachio ipc call wallpaper toggle (random, set <path>)
    IpcHandler {
        target: "wallpaper"

        function toggle(): void {
            if (root.open)
                root.open = false;
            else
                root.show();
        }
        function random(): void {
            Wallpapers.random();
        }
        function set(path: string): void {
            Wallpapers.set(path);
        }
    }

    Reveal {
        id: reveal
        open: root.open
    }

    // the live preview, over the windows; a click on it cancels
    WallpaperView {
        id: preview

        anchors.fill: parent
        path: root.chosen?.path ?? Wallpapers.current
        opacity: reveal.progress

        MouseArea {
            anchors.fill: parent
            onClicked: root.open = false
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
        visible: !Theme.tui
        spacing: 16
        focus: !Theme.tui
        Keys.onPressed: event => root.key(event)

        // the images
        Rectangle {
            visible: root.images.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            width: 20 + grid.width - 12 + 20
            height: content.height + 40
            radius: Theme.panelRadius
            color: Theme.bgAlt
            border.width: 1
            border.color: Theme.overlay2
            Accessible.role: Accessible.List
            Accessible.name: "Wallpapers"

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

                Item {
                    width: grid.width - 12
                    height: 44

                    Text {
                        id: heading
                        x: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Wallpapers"
                        color: Theme.textBright
                        font.family: Theme.fontUi
                        font.pixelSize: 17
                        font.weight: Font.ExtraBold
                    }

                    Text {
                        anchors.left: heading.right
                        anchors.leftMargin: 12
                        anchors.right: count.left
                        anchors.rightMargin: 16
                        anchors.baseline: heading.baseline
                        text: Wallpapers.folder.replace(Quickshell.env("HOME"), "~")
                        textFormat: Text.PlainText
                        elide: Text.ElideMiddle
                        color: Theme.subtext
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }

                    Text {
                        id: count
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: `${root.images.length} image${root.images.length === 1 ? "" : "s"}`
                        color: Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                    }
                }

                // three across; past three rows it scrolls
                GridView {
                    id: grid

                    width: 3 * cellWidth
                    height: Math.min(3, Math.ceil(root.images.length / 3)) * cellHeight - 12
                    cellWidth: 232 + 12
                    cellHeight: 176 + 12
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.images

                    delegate: Rectangle {
                        id: card

                        required property var modelData
                        required property int index
                        readonly property bool selected: root.current === index
                        readonly property bool inUse: modelData.path === Wallpapers.current

                        width: 232
                        height: 8 + thumb.height + 6 + 32 + 8
                        radius: Theme.tileRadius
                        color: selected ? Theme.overlay2 : Theme.overlay
                        Accessible.role: Accessible.ListItem
                        Accessible.name: modelData.name + (inUse ? ", in use" : "")
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
                                    root.current = card.index;
                            }
                            onClicked: {
                                root.current = card.index;
                                root.apply();
                            }
                        }

                        ClippingRectangle {
                            id: thumb

                            x: 8
                            y: 8
                            width: 216
                            height: 122
                            radius: 14
                            color: Theme.bg

                            Image {
                                anchors.fill: parent
                                source: `file://${card.modelData.path}`
                                sourceSize: Qt.size(432, 244)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }

                            // the one on the desktop now
                            Rectangle {
                                visible: card.inUse
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 8
                                width: inUse.implicitWidth + 16
                                height: 20
                                radius: 10
                                color: Theme.bgAlt

                                Row {
                                    id: inUse
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Icon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        size: 12
                                        paths: Icons.check
                                        color: Theme.subtext
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "In use"
                                        color: Theme.subtext
                                        font.family: Theme.fontUi
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }
                                }
                            }
                        }

                        // its file name; the chosen card's in a pistachio chip
                        Rectangle {
                            x: 8
                            y: thumb.y + thumb.height + 6
                            width: 216
                            height: 32
                            radius: 16
                            color: card.selected ? Theme.pistachio : "transparent"

                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.hoverDuration
                                    easing.type: Theme.easing
                                }
                            }

                            Icon {
                                id: glyph
                                x: 10
                                anchors.verticalCenter: parent.verticalCenter
                                size: 16
                                paths: Icons.image
                                color: card.selected ? Theme.bg : Theme.subtext
                            }

                            Text {
                                anchors.left: glyph.right
                                anchors.leftMargin: 8
                                anchors.right: parent.right
                                anchors.rightMargin: card.selected ? 12 : 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: card.modelData.name
                                textFormat: Text.PlainText
                                elide: Text.ElideMiddle
                                color: card.selected ? Theme.bg : Theme.text
                                font.family: Theme.fontUi
                                font.pixelSize: 13
                                font.weight: card.selected ? Font.ExtraBold : Font.Bold
                            }
                        }
                    }
                }

                // the chosen image in full, and its fit
                Item {
                    width: grid.width - 12
                    height: 15 + Math.max(names.height, fitSwitch.height)

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.overlay
                    }

                    Column {
                        id: names

                        x: 4
                        y: 15
                        width: parent.width - fitSwitch.width - 24
                        spacing: 2

                        Text {
                            width: parent.width
                            text: root.chosen?.name ?? ""
                            textFormat: Text.PlainText
                            elide: Text.ElideMiddle
                            color: Theme.textBright
                            font.family: Theme.fontUi
                            font.pixelSize: 14
                            font.weight: Font.ExtraBold
                        }

                        Text {
                            width: parent.width
                            text: root.chosen ? root.details(preview.imageSize, root.chosen.size) : ""
                            color: Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                    }

                    // Fill, Fit, Center or Tile for the chosen image; the preview follows
                    Rectangle {
                        id: fitSwitch

                        anchors.right: parent.right
                        y: 15
                        width: fitRow.implicitWidth + 4
                        height: 40
                        radius: 20
                        color: Theme.bg
                        Accessible.role: Accessible.Grouping
                        Accessible.name: "Fit"

                        Row {
                            id: fitRow

                            anchors.centerIn: parent
                            spacing: 2

                            Repeater {
                                model: root.fits

                                Rectangle {
                                    id: segment

                                    required property var modelData
                                    readonly property bool on: root.chosen !== null && Wallpapers.fitOf(root.chosen.path) === modelData[0]

                                    width: label.implicitWidth + 32
                                    height: 36
                                    radius: 18
                                    color: on ? Theme.overlay2 : "transparent"
                                    Accessible.role: Accessible.RadioButton
                                    Accessible.name: modelData[1]
                                    Accessible.checked: on

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Theme.hoverDuration
                                            easing.type: Theme.easing
                                        }
                                    }

                                    Text {
                                        id: label
                                        anchors.centerIn: parent
                                        text: segment.modelData[1]
                                        color: segment.on ? Theme.textBright : Theme.subtext
                                        font.family: Theme.fontUi
                                        font.pixelSize: 13
                                        font.weight: segment.on ? Font.ExtraBold : Font.Bold
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.chosen)
                                                Wallpapers.setFit(root.chosen.path, segment.modelData[0]);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // no images yet: where to put them
        Rectangle {
            visible: root.images.length === 0
            anchors.horizontalCenter: parent.horizontalCenter
            width: 440
            height: empty.height + 56
            radius: Theme.panelRadius
            color: Theme.bgAlt
            border.width: 1
            border.color: Theme.overlay2
            Accessible.role: Accessible.Dialog
            Accessible.name: "No wallpapers found"

            Shadow {
                z: -1
                kind: Theme.shadowModal
                anchors.fill: parent
                radius: parent.radius
            }

            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: empty

                anchors.horizontalCenter: parent.horizontalCenter
                y: 28
                width: parent.width - 56
                spacing: 16

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 56
                    height: 56
                    radius: 28
                    color: Theme.overlay

                    Icon {
                        anchors.centerIn: parent
                        size: 26
                        paths: Icons.folder
                        color: Theme.subtext
                    }
                }

                Column {
                    width: parent.width
                    spacing: 6

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "No wallpapers found"
                        color: Theme.textBright
                        font.family: Theme.fontUi
                        font.pixelSize: 18
                        font.weight: Font.ExtraBold
                    }

                    Column {
                        width: parent.width

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: "Put PNG, JPG or WebP images in"
                            color: Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            lineHeight: 20
                            lineHeightMode: Text.FixedHeight
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: Wallpapers.folder.replace(Quickshell.env("HOME"), "~")
                            textFormat: Text.PlainText
                            elide: Text.ElideMiddle
                            color: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                            lineHeight: 20
                            lineHeightMode: Text.FixedHeight
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: "and they will show up here."
                            color: Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            lineHeight: 20
                            lineHeightMode: Text.FixedHeight
                        }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: 4
                    spacing: 10

                    ActionButton {
                        height: 44
                        text: "Close"
                        onClicked: root.open = false
                    }

                    // Open folder, with the ↵ chip: Enter does it too
                    Rectangle {
                        width: openLabel.implicitWidth + 22 + 10 + 24 + 10
                        height: 44
                        radius: 22
                        color: Theme.pistachio
                        Accessible.role: Accessible.Button
                        Accessible.name: "Open folder"

                        Text {
                            id: openLabel
                            x: 22
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Open folder"
                            color: Theme.bg
                            font.family: Theme.fontUi
                            font.pixelSize: 14
                            font.weight: Font.ExtraBold
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24
                            height: 24
                            radius: 12
                            color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.14)

                            Text {
                                anchors.centerIn: parent
                                text: "↵"
                                color: Theme.bg
                                font.family: Theme.fontUi
                                font.pixelSize: 12
                                font.weight: Font.ExtraBold
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Wallpapers.openFolder();
                                root.open = false;
                            }
                        }
                    }
                }
            }
        }

        // over the wallpaper, so a soft shadow keeps it readable
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.images.length > 0
            text: "Arrows preview · Enter apply · R random · Esc cancel"
            color: Theme.textBright
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Font.DemiBold
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Theme.shadow
                shadowOpacity: 0.8
                shadowBlur: 0.6
                shadowVerticalOffset: 1
            }
        }
    }

    // TUI (WallpapersEmpty board): a framed "wallpapers" box with a "/ filter" line. With no images the
    // screen dims and the box says where to put them; with images (no board, drawn in the same language)
    // it lists them as rows over the live preview, the chosen one's size and fit underneath.
    Rectangle {
        visible: Theme.tui && root.images.length === 0
        anchors.fill: parent
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.74)
        opacity: reveal.progress
    }

    PanelFrame {
        id: tuiCard

        visible: Theme.tui
        anchors.horizontalCenter: parent.horizontalCenter
        y: 99 + 8 * (1 - reveal.progress)
        opacity: reveal.progress
        width: 600
        height: tuiBody.implicitHeight + 28
        title: "wallpapers"
        detail: root.filter !== "" ? `${root.list.length}/${root.images.length} files` : `${root.images.length} file${root.images.length === 1 ? "" : "s"}`
        Accessible.role: root.images.length > 0 ? Accessible.List : Accessible.Dialog
        Accessible.name: root.images.length > 0 ? "Wallpapers" : "No wallpapers found"

        // clicks inside don't cancel
        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: tuiBody

            x: 16
            y: 18
            width: parent.width - 32

            // / filter▌
            Item {
                width: parent.width
                height: Theme.tuiLineHeight

                Text {
                    id: slash
                    text: "/ "
                    color: Theme.subtext
                    font.family: Theme.fontTui
                    font.pixelSize: Theme.tuiTextSize
                }

                TextInput {
                    id: tuiFilter

                    anchors.left: slash.right
                    anchors.right: parent.right
                    height: parent.height
                    verticalAlignment: TextInput.AlignVCenter
                    focus: Theme.tui
                    text: root.filter
                    onTextEdited: root.filter = text
                    color: Theme.textBright
                    selectionColor: Theme.overlay2
                    font.family: Theme.fontTui
                    font.pixelSize: Theme.tuiTextSize
                    Accessible.role: Accessible.EditableText
                    Accessible.name: "Filter wallpapers"
                    Keys.onPressed: event => root.tuiKey(event)
                    cursorDelegate: Rectangle {
                        width: 8
                        height: Theme.tuiLineHeight - 2
                        color: Theme.pistachio
                        visible: tuiFilter.activeFocus
                    }

                    Text {
                        visible: tuiFilter.text === ""
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: "filter"
                        color: Theme.subtext
                        font.family: Theme.fontTui
                        font.pixelSize: Theme.tuiTextSize
                    }
                }
            }

            Item {
                width: parent.width
                height: Theme.tuiLineHeight

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 1
                    color: Theme.tuiBorder
                }
            }

            // no images at all: where to put them
            Column {
                visible: root.images.length === 0
                width: parent.width
                topPadding: 24
                bottomPadding: 24
                spacing: 0

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "no wallpapers found"
                    color: Theme.textBright
                    font.family: Theme.fontTui
                    font.pixelSize: Theme.tuiTextSize
                    font.weight: Font.ExtraBold
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Wallpapers.folder.replace(Quickshell.env("HOME"), "~") + " has no png, jpg or webp files."
                    textFormat: Text.PlainText
                    elide: Text.ElideMiddle
                    color: Theme.subtext
                    font.family: Theme.fontTui
                    font.pixelSize: Theme.tuiTextSize
                }

                Item {
                    width: 1
                    height: 14
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8

                    ActionButton {
                        height: 44
                        primary: true
                        text: "Open folder"
                        onClicked: {
                            Wallpapers.openFolder();
                            root.open = false;
                        }
                    }
                    ActionButton {
                        height: 44
                        base: Theme.overlay
                        text: "Close"
                        onClicked: root.open = false
                    }
                }
            }

            // images, but none match the filter
            Text {
                visible: root.images.length > 0 && root.list.length === 0
                width: parent.width
                topPadding: 10
                bottomPadding: 10
                text: "no matches"
                color: Theme.subtext
                font.family: Theme.fontTui
                font.pixelSize: Theme.tuiTextSize
            }

            ListView {
                id: tuiList

                visible: root.list.length > 0
                width: parent.width
                height: Math.min(10, root.list.length) * Theme.tuiLauncherRowHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: Theme.tui ? root.list : []
                currentIndex: root.current

                delegate: Rectangle {
                    id: row

                    required property var modelData
                    required property int index
                    readonly property bool selected: root.current === index
                    readonly property bool inUse: modelData.path === Wallpapers.current

                    width: tuiList.width
                    height: Theme.tuiLauncherRowHeight
                    color: selected ? Theme.pistachio : rowMouse.containsMouse ? Theme.tuiHover : "transparent"
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.name + (inUse ? ", in use" : "")
                    Accessible.selected: selected

                    Text {
                        x: 12
                        width: 32
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.inUse ? "[*]" : "[ ]"
                        color: row.selected ? Theme.bg : row.inUse ? Theme.pistachio : Theme.subtext
                        font.family: Theme.fontTui
                        font.pixelSize: Theme.tuiTextSize
                        font.weight: Font.Bold
                    }

                    Text {
                        x: 52
                        width: Math.max(0, parent.width - x - size.width - 24)
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.name
                        textFormat: Text.PlainText
                        elide: Text.ElideMiddle
                        color: row.selected ? Theme.bg : Theme.text
                        font.family: Theme.fontTui
                        font.pixelSize: Theme.tuiTextSize
                        font.weight: row.selected ? Font.Bold : Font.Medium
                    }

                    Text {
                        id: size
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: (row.inUse ? "in use · " : "") + root.details(Qt.size(0, 0), row.modelData.size)
                        color: row.selected ? Theme.bg : Theme.subtext
                        font.family: Theme.fontTui
                        font.pixelSize: Theme.tuiTextSize
                        font.features: { "tnum": 1 }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: mouse => {
                            root.pointer(mapToItem(null, mouse.x, mouse.y));
                            if (root.pointerMoved && !row.selected)
                                root.current = row.index;
                        }
                        onClicked: {
                            root.current = row.index;
                            root.apply();
                        }
                    }
                }
            }

            // the chosen image: size, and its fit as bracket choices
            Column {
                visible: root.chosen !== null
                width: parent.width
                topPadding: 4

                Item {
                    width: parent.width
                    height: Theme.tuiLineHeight

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 1
                        color: Theme.tuiBorder
                    }
                }

                Item {
                    width: parent.width
                    height: Theme.tuiButtonHeight

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - tuiFits.width - 16
                        text: root.chosen ? root.details(preview.imageSize, root.chosen.size) : ""
                        elide: Text.ElideRight
                        color: Theme.subtext
                        font.family: Theme.fontTui
                        font.pixelSize: Theme.tuiTextSize
                        font.features: { "tnum": 1 }
                    }

                    Row {
                        id: tuiFits

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Accessible.role: Accessible.Grouping
                        Accessible.name: "Fit"

                        Repeater {
                            model: root.fits

                            Rectangle {
                                id: fit

                                required property var modelData
                                readonly property bool on: root.chosen !== null && Wallpapers.fitOf(root.chosen.path) === modelData[0]

                                width: fitLabel.implicitWidth + 16
                                height: Theme.tuiLineHeight + 4
                                color: on ? Theme.pistachio : fitMouse.containsMouse ? Theme.tuiHover : "transparent"
                                Accessible.role: Accessible.RadioButton
                                Accessible.name: modelData[1]
                                Accessible.checked: on

                                Text {
                                    id: fitLabel
                                    anchors.centerIn: parent
                                    text: fit.modelData[0]
                                    color: fit.on ? Theme.bg : Theme.text
                                    font.family: Theme.fontTui
                                    font.pixelSize: Theme.tuiTextSize
                                    font.weight: fit.on ? Font.Bold : Font.Medium
                                }

                                MouseArea {
                                    id: fitMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.chosen)
                                            Wallpapers.setFit(root.chosen.path, fit.modelData[0]);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Enter choose · Esc close (board's hint line)
            Flow {
                width: parent.width
                topPadding: 10
                spacing: 16

                Repeater {
                    model: root.images.length === 0 ? [["Enter", "open folder"], ["Esc", "close"]]
                        : [["↑↓", "preview"], ["Enter", "apply"], ["Tab", "fit"], ["Ctrl+R", "random"], ["Esc", "cancel"]]

                    Row {
                        required property var modelData
                        spacing: 8

                        Text {
                            text: modelData[0]
                            color: Theme.textBright
                            font.family: Theme.fontTui
                            font.pixelSize: Theme.tuiTextSize
                            font.weight: Font.Bold
                        }
                        Text {
                            text: modelData[1]
                            color: Theme.subtext
                            font.family: Theme.fontTui
                            font.pixelSize: Theme.tuiTextSize
                        }
                    }
                }
            }
        }
    }
}
