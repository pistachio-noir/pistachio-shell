import qs
import qs.components
import qs.popups
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland // layer-shell keyboard focus and screen capture (Wayland protocols, not a compositor module)
import QtQuick

// Frozen-screen capture with the owner's compact toolbar (design/NewScreenshotMenu.html).
// Crop/save and the existing modes are shared by menu selection, shortcuts and IPC.
PanelWindow {
    id: root

    // "" (closed), "taking" while the still comes, then "menu", "region", "window" or "text"
    property string mode
    property string wanted // what "taking" turns into
    property rect selection // the area being dragged out, in screen coordinates
    property point anchor // where the drag began
    property var hovered: null // the window under the pointer, in window mode
    property int current // the menu's highlighted choice
    property rect cut // what's being saved
    readonly property var choices: [
        { name: "Region", key: Qt.Key_R, icon: Icons.crop, description: "Drag out an area of the screen to save.", command: "psc screenshot region" },
        { name: "Window", key: Qt.Key_W, icon: Icons.monitor, description: "Click a window to capture it.", command: "" },
        { name: "Screen", key: Qt.Key_S, icon: Icons.grid, description: "Save the whole screen.", command: "" },
        { name: "Text", key: Qt.Key_T, icon: Icons.textScan, description: "Snip text to read and copy it to the clipboard.", command: "psc screenshot text" },
        { name: "Lens", key: Qt.Key_L, icon: Icons.scanSearch, description: "Snip anything on screen and ask " + (ShellSettings.lensProvider === "codex" ? "ChatGPT" : "Claude") + " about it.", command: "psc screenshot lens" }
    ].concat(Screenshots.hasPicker ? [{ name: "Colour", key: Qt.Key_C, icon: Icons.pipette, description: "Pick a colour from the screen and copy its hex value.", command: "psc screenshot colour" }] : [],
        Screenshots.hasRecorder && !Screenshots.recording ? [{ name: "Record", key: Qt.Key_V, icon: Icons.recordCircle, description: "Drag out an area to record, or click for the whole screen.", command: "psc screenshot record" }] : [])
    onChoicesChanged: if (current >= choices.length) current = Math.max(0, choices.length - 1)
    // dragging out an area: for a picture, or for its text
    readonly property bool dragging: mode === "region" || mode === "text" || mode === "record" || mode === "lens"
    readonly property bool picking: mode === "menu" || mode === "window" || dragging
    // what stays bright: the area dragged out or the window under the pointer
    readonly property rect hole: dragging ? selection : mode === "window" && hovered ? hovered.bounds : Qt.rect(0, 0, 0, 0)

    function start(next: string) {
        if (mode !== "")
            return;
        if (Lens.open) {
            Lens.close();
            queuedMode = next;
            afterLens.restart();
            return;
        }
        Screenshots.prepare();
        wanted = next;
        cut = Qt.rect(0, 0, 0, 0);
        selection = Qt.rect(0, 0, 0, 0);
        hovered = null;
        current = 0;
        mode = "taking";
        shot.captureSource = screen;
        giveUp.restart();
    }

    // Colour and Record (owner's picks, 8 November 2026) start a moment after the picker has gone, so
    // neither picks up or records it
    property rect recordArea
    property bool recordWhole
    property string queuedMode
    Timer {
        id: afterLens
        interval: Theme.motionDuration + 80
        onTriggered: root.start(root.queuedMode)
    }

    Timer {
        id: colourAfter
        interval: 250
        onTriggered: Screenshots.pickColour()
    }

    Timer {
        id: recordAfter
        interval: 250
        onTriggered: Screenshots.record(root.recordArea, root.recordWhole, root.screen.name)
    }

    function close() {
        mode = "";
    }

    function choose(i: int) {
        const name = choices[i].name;
        if (name === "Screen")
            save(Qt.rect(0, 0, width, height));
        else if (name === "Colour") { // hyprpicker takes over the screen once the menu is gone
            close();
            colourAfter.restart();
        }
        else
            mode = name.toLowerCase();
    }

    // The windows on the active workspace, topmost first: the most recently focused one is on top of
    // the others where they overlap.
    function windowAt(x: real, y: real): var {
        const active = Compositor.workspaces.find(w => w.active)?.id;
        return Compositor.windows.filter(w => w.workspace === active && w.bounds.width > 0)
            .sort((a, b) => a.recency - b.recency)
            .find(w => x >= w.bounds.x && x < w.bounds.x + w.bounds.width && y >= w.bounds.y && y < w.bounds.y + w.bounds.height) ?? null;
    }

    // cut `r` (whole pixels, kept on the screen) out of the still and save it; for its text, at twice
    // the size, which tesseract reads better
    function save(r: rect) {
        const x = Math.max(0, Math.round(r.x)), y = Math.max(0, Math.round(r.y));
        const w = Math.min(width, Math.round(r.x + r.width)) - x, h = Math.min(height, Math.round(r.y + r.height)) - y;
        if (w < 2 || h < 2)
            return;
        cut = Qt.rect(x, y, w, h);
        Screenshots.shutter();
        const forText = mode === "text";
        const forLens = mode === "lens";
        const path = forLens ? Screenshots.nextLensPath() : forText ? Screenshots.nextTextPath() : Screenshots.nextPath();
        const grabbing = crop.grabToImage(result => {
            if (!result.saveToFile(path))
                console.warn("screenshot: can't save", path);
            else if (forLens) {
                const area = root.cut;
                if (!shot.grabToImage(still => {
                    Lens.begin(path, area, still);
                    root.close();
                })) {
                    Lens.begin(path, area, null);
                    root.close();
                }
                return;
            }
            else if (forText)
                Screenshots.readText(path);
            else
                Screenshots.saved(path);
            root.close();
        }, forText ? Qt.size(w * 2, h * 2) : Qt.size(w, h));
        if (!grabbing)
            close();
    }

    function key(event) {
        if (event.key === Qt.Key_Escape) {
            close();
        } else if (mode === "menu") {
            const i = choices.findIndex(c => c.key === event.key);
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Right)
                current = (current + (event.key === Qt.Key_Right ? 1 : -1) + choices.length) % choices.length;
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                choose(current);
            else if (i >= 0)
                choose(i);
        }
    }

    onVisibleChanged: if (!visible) shot.captureSource = null // the next one waits for a fresh still

    // up (transparent) while the still is taken, then until the fade-out ends
    visible: mode !== "" || reveal.shown
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay // above fullscreen windows
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // For keybinds: qs -c pistachio ipc call screenshot region (or menu)
    IpcHandler {
        target: "screenshot"

        function region(): void {
            root.start("region");
        }
        function menu(): void {
            root.start("menu");
        }
        function text(): void {
            root.start("text");
        }
        function lens(): void {
            root.start("lens");
        }
        // starts recording the whole screen, or stops the recording that runs (for a keybind)
        function record(): void {
            if (Screenshots.recording)
                Screenshots.stopRecording();
            else
                Screenshots.record(Qt.rect(0, 0, root.width, root.height), true, root.screen.name);
        }
        function colour(): void {
            Screenshots.pickColour();
        }
    }

    Timer {
        id: giveUp
        interval: 1000
        onTriggered: {
            if (root.mode !== "taking")
                return;
            console.warn("screenshot: no still of the screen came");
            root.close();
        }
    }

    Reveal {
        id: reveal
        open: root.picking
    }

    // the screen as it was; it looks the same as the screen until the dim fades in
    ScreencopyView {
        id: shot
        anchors.fill: parent
        visible: root.mode !== "taking"
        onHasContentChanged: {
            if (!hasContent || root.mode !== "taking")
                return;
            giveUp.stop();
            root.mode = root.wanted;
        }
    }

    // the part being saved, at its place over the still (so it looks no different), grabbed from there
    ShaderEffectSource {
        id: crop
        x: root.cut.x
        y: root.cut.y
        width: root.cut.width
        height: root.cut.height
        sourceItem: shot
        sourceRect: root.cut
        visible: root.cut.width > 0 && root.mode !== ""
    }

    // the dim around what stays bright, in four pieces
    Item {
        anchors.fill: parent
        opacity: reveal.progress
        visible: root.cut.width === 0

        Repeater {
            model: [
                Qt.rect(0, 0, root.width, root.hole.y),
                Qt.rect(0, root.hole.y + root.hole.height, root.width, root.height - root.hole.y - root.hole.height),
                Qt.rect(0, root.hole.y, root.hole.x, root.hole.height),
                Qt.rect(root.hole.x + root.hole.width, root.hole.y, root.width - root.hole.x - root.hole.width, root.hole.height)
            ]

            Rectangle {
                required property rect modelData
                x: modelData.x
                y: modelData.y
                width: modelData.width
                height: modelData.height
                color: Theme.bg
                opacity: root.mode === "menu" ? 0.64 : 0.5
                Behavior on opacity { NumberAnimation { duration: Theme.motionDuration; easing.type: Theme.easing } }
            }
        }

        // the edge of what stays bright
        Rectangle {
            visible: root.hole.width > 0
            x: root.hole.x - 1
            y: root.hole.y - 1
            width: root.hole.width + 2
            height: root.hole.height + 2
            color: "transparent"
            border.width: 1
            border.color: Theme.textBright
        }

        // its size, or the window's title, under it; above it if there's no room, clear of the hint;
        // else inside it, along its bottom edge
        Rectangle {
            readonly property bool below: root.hole.y + root.hole.height + 12 + height <= root.height - 16
            readonly property bool above: root.hole.y - 12 - height >= 72

            visible: root.hole.width > 0
            x: Math.max(16, Math.min(root.width - width - 16, root.hole.x + (root.hole.width - width) / 2))
            y: below ? root.hole.y + root.hole.height + 12 : above ? root.hole.y - 12 - height : root.hole.y + root.hole.height - height - 16
            width: label.implicitWidth + 24
            height: 30
            radius: 15
            color: Theme.bgAlt
            border.width: 1
            border.color: Theme.overlay2

            Text {
                id: label
                anchors.centerIn: parent
                text: (root.mode === "window" && root.hovered ? `${root.hovered.title} · ` : "") + `${Math.round(root.hole.width)} × ${Math.round(root.hole.height)}`
                textFormat: Text.PlainText
                color: Theme.textBright
                font.family: Theme.fontUi
                font.pixelSize: 12
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
            }
        }

        // what to do, at the top
        Rectangle {
            visible: root.dragging || root.mode === "window"
            anchors.horizontalCenter: parent.horizontalCenter
            y: 24
            width: hint.implicitWidth + 32
            height: 36
            radius: 18
            color: Theme.bgAlt
            border.width: 1
            border.color: Theme.overlay2

            Text {
                id: hint
                anchors.centerIn: parent
                text: root.mode === "lens" ? "Drag out an area to ask about · Esc cancel" : root.mode === "record" ? "Drag out an area to record, or click for the whole screen · Esc cancel" : root.mode === "region" ? "Drag out an area · Esc cancel" : root.mode === "text" ? "Drag over some text to copy it · Esc cancel" : "Click a window · Esc cancel"
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
        }
    }

    // region and window: drag out an area, or click a window
    MouseArea {
        anchors.fill: parent
        enabled: root.dragging || root.mode === "window"
        hoverEnabled: true
        cursorShape: root.dragging ? Qt.CrossCursor : Qt.PointingHandCursor
        onPressed: mouse => {
            if (!root.dragging)
                return;
            root.anchor = Qt.point(mouse.x, mouse.y);
            root.selection = Qt.rect(mouse.x, mouse.y, 0, 0);
        }
        onPositionChanged: mouse => {
            if (root.mode === "window")
                root.hovered = root.windowAt(mouse.x, mouse.y);
            else if (pressed)
                root.selection = Qt.rect(Math.min(root.anchor.x, mouse.x), Math.min(root.anchor.y, mouse.y), Math.abs(mouse.x - root.anchor.x), Math.abs(mouse.y - root.anchor.y));
        }
        onReleased: {
            if (root.mode === "record") { // an area, or a click for the whole screen; once the picker is gone
                const whole = root.selection.width < 8 || root.selection.height < 8;
                root.recordArea = whole ? Qt.rect(0, 0, root.width, root.height) : root.selection;
                root.recordWhole = whole;
                root.close();
                recordAfter.restart();
            } else if (root.dragging)
                root.save(root.selection);
        }
        onClicked: {
            if (root.mode === "window" && root.hovered)
                root.save(root.hovered.bounds);
        }
    }

    ScreenshotMenu {
        anchors.fill: parent
        open: root.mode === "menu"
        choices: root.choices
        current: root.current
        onHighlighted: index => root.current = index
        onChosen: index => root.choose(index)
    }

    // a click beside the menu closes it, as with the power menu
    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: root.mode === "menu"
        onClicked: root.close()
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => root.key(event)
    }
}
