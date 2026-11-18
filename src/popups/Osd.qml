import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland // layer-shell layer for this window (a Wayland protocol, not a compositor module)
import QtQuick

// Volume, brightness, output device, microphone, screen sharing and desktop icons OSD (Osd board; the
// last four aren't on it). Volume shows on any PipeWire change, whoever made it, and so does a new default output,
// e.g. headphones connecting; brightness only through IPC, because the monitor reports nothing. The
// microphone and screen sharing ones name the apps that start recording or sharing, and say when all
// have stopped (owner's request: privacy cues, so they show even in Do not disturb, fullscreen or with
// quick settings open). The bar positions it.
PanelWindow {
    id: root

    property string kind: "volume" // or "brightness", "output", "mic", "screen" or "desktop"
    property bool suppressed // set by the bar while quick settings (which has the same sliders) is open
    property bool overviewOpen // no workspace OSD while the Overview shows the workspaces itself
    property int lift // the pill's distance from the screen's bottom edge; the bar sets it
    // room around the pill for its shadow; below, at most what's left down to the screen edge
    readonly property int side: Theme.shadowSmall.blur
    readonly property int above: Theme.shadowSmall.blur - Theme.shadowSmall.y
    readonly property int below: Math.min(lift, Theme.shadowSmall.blur + Theme.shadowSmall.y)
    property bool settling: true // after startup and output switches, when volume "changes" on its own
    readonly property bool output: kind === "output"
    readonly property bool cue: kind === "mic" || kind === "screen" // a privacy cue
    // Desktop icons shown or hidden (owner's request, 29 October: by IPC `desktop toggle` or in Shell
    // settings), told with words in place of the bar, as a cue is
    readonly property bool desktop: kind === "desktop"
    // the workspace you switched to, with its name and the bar's dots (owner's request, 3 November
    // 2026, in place of peeking at the hidden bar; a Shell setting)
    readonly property bool workspace: kind === "workspace"
    // a workspace's tabs on or off (owner's request, 9 November 2026; a Shell setting)
    readonly property bool tabs: kind === "tabs"
    property bool tabsOn
    property int tabsWorkspace
    // Zen, Focus and their Pomodoro phases (FocusMode, owner's request, 11 November 2026)
    readonly property bool mode: kind === "mode"
    property string modeTitle
    property string modeDetail
    property bool modeOn
    readonly property bool notice: cue || desktop || workspace || tabs || mode
    readonly property bool muted: (kind === "volume" || output) && Audio.muted
    readonly property real value: kind === "brightness" ? Brightness.value : Audio.volume
    // The bar and number ease to a new value; they start at it while hidden and on a switch between
    // volume and brightness, rather than sweep from the other one.
    property real level: value
    property bool snap
    // the default output's node name, to tell a real switch from the moment between two devices
    property string outputNode
    property string outputName
    Component.onCompleted: outputNode = Audio.sink?.name ?? ""
    // the apps recording as last announced; null until the first look after startup, which isn't news
    property bool cueOn // false: the apps in cueNames have stopped
    property string cueNames
    readonly property string cueTitle: kind === "screen" ? (cueOn ? "Sharing your screen" : "Screen sharing stopped")
        : !cueOn ? "Microphone not in use" : Audio.micMuted ? "Microphone in use, muted" : "Microphone in use"

    function show(k: string) {
        snap = k !== kind;
        kind = k;
        snap = false;
        hide.restart();
    }

    Behavior on level {
        enabled: reveal.shown && !root.snap
        NumberAnimation {
            duration: Theme.motionDuration
            easing.type: Theme.easing
        }
    }

    visible: reveal.shown
    exclusiveZone: 0
    margins.bottom: lift - below
    implicitWidth: side + 320 + side
    implicitHeight: above + 56 + below
    color: "transparent"
    WlrLayershell.namespace: "pistachio-panel" // frosted panels: Hyprland blurs the shell's layers by name
    mask: Region {} // clicks go through
    WlrLayershell.layer: WlrLayer.Overlay // above fullscreen windows

    Reveal {
        id: reveal
        open: hide.running && (!root.suppressed || root.notice)
    }

    Timer {
        id: hide
        interval: root.workspace ? 1200 : root.output || root.notice ? 2500 : 1500 // a name takes longer to read than a bar
    }

    Timer {
        id: settle
        running: true
        interval: 1000
        onTriggered: root.settling = false
    }

    // a device switch reports the new volume before the new device, so look a tick later
    function volumeMoved() {
        if (!settling)
            show("volume");
    }

    // outputNode is "" until the first output after startup, which isn't a switch
    function outputMoved() {
        const node = Audio.sink?.name ?? "";
        if (!node || node === outputNode)
            return;
        const first = outputNode === "";
        outputNode = node;
        outputName = Audio.deviceName(Audio.sink);
        if (!first)
            show("output");
    }

    function showCue(k: string, on: bool, names: string) {
        cueOn = on;
        cueNames = names;
        show(k);
    }

    // A new app shows the cue again; one stopping while others go on doesn't.
    PrivacyWatch {
        apps: Audio.recorders.map(n => Audio.appName(n))
        onStarted: names => root.showCue("mic", true, names)
        onStopped: names => root.showCue("mic", false, names)
    }

    PrivacyWatch {
        apps: ScreenShare.apps
        onStarted: names => root.showCue("screen", true, names)
        onStopped: names => root.showCue("screen", false, names)
    }

    Connections {
        target: FocusMode

        function onAnnounce(title, detail, on) {
            root.modeTitle = title;
            root.modeDetail = detail;
            root.modeOn = on;
            root.show("mode");
        }
    }

    // Game mode (owner's request, 18 November 2026): the same card as Zen's as it starts and ends
    Connections {
        target: GameMode

        function onActiveChanged() {
            root.modeTitle = GameMode.active ? "Game mode on" : "Game mode off";
            root.modeDetail = GameMode.active ? "Toasts wait · no animations or blur" : "Animations and blur are back";
            root.modeOn = GameMode.active;
            root.show("mode");
        }
    }

    // (not as the setting is read at startup: settling covers that)
    Connections {
        target: Compositor

        function onTabbedToggled(workspace, on) {
            if (!ShellSettings.tabbedOsd)
                return;
            root.tabsOn = on;
            root.tabsWorkspace = workspace;
            root.show("tabs");
        }

        function onActiveWorkspaceChanged() {
            if (!root.settling && ShellSettings.workspaceOsd && Compositor.activeWorkspace > 0 && !Compositor.fullscreen && !root.overviewOpen)
                root.show("workspace");
        }
    }

    Connections {
        target: Desktop

        function onEnabledChanged() {
            if (!root.settling)
                root.show("desktop");
        }
    }

    Connections {
        target: Audio

        function onVolumeChanged() {
            Qt.callLater(root.volumeMoved);
        }
        function onMutedChanged() {
            Qt.callLater(root.volumeMoved);
        }
        function onSinkChanged() {
            root.settling = true;
            settle.restart();
            Qt.callLater(root.outputMoved);
        }
    }

    // For the brightness keys: qs -c pistachio ipc call brightness up (or down)
    IpcHandler {
        target: "brightness"

        function up(): void {
            root.step(0.05);
        }
        function down(): void {
            root.step(-0.05);
        }
    }

    function step(d: real) {
        if (!Brightness.available)
            return;
        Brightness.set(Brightness.value + d);
        show("brightness");
    }

    Rectangle {
        id: pill

        x: root.side
        width: 320
        height: 56
        radius: Theme.tui ? 0 : height / 2
        color: Theme.surface
        border.width: 1
        border.color: Theme.overlay2
        // fades in rising 12 px, and back
        opacity: reveal.progress
        y: root.above + 12 * (1 - reveal.progress)
        Accessible.role: Accessible.StatusBar

        // beneath the pill (z -1), so it fades and rises with it
        Shadow {
            frostable: true
            z: -1
            kind: Theme.shadowSmall
            anchors.fill: parent
            radius: parent.radius
        }
        Accessible.name: root.tabs ? `${tabsTitle.text}, ${tabsDetail.text}`
            : root.workspace ? workspaceTitle.text
            : root.desktop ? `${desktopTitle.text}, ${desktopDetail.text}`
            : root.cue ? `${root.cueTitle}, ${root.cueNames}`
            : root.output ? `Output ${root.outputName}`
            : root.muted ? "Volume muted" : `${root.kind === "volume" ? "Volume" : "Brightness"} ${label.text} percent`

        // TUI: a short word, as the strip labels its readings, in place of the glyph
        Item {
            id: icon
            x: Theme.tui ? 18 : 22
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.tui ? tag.implicitWidth : 20
            height: 20

            Text {
                id: tag
                visible: Theme.tui
                anchors.verticalCenter: parent.verticalCenter
                text: root.mode ? "mode" : root.tabs ? "tabs" : root.workspace ? "ws" : root.desktop ? "desk"
                    : root.kind === "brightness" ? "bri" : root.output ? "out" : root.kind === "mic" ? "mic"
                    : root.kind === "screen" ? "scr" : "vol"
                color: glyph.color
                font.family: Theme.fontTui
                font.pixelSize: Theme.tuiTextSize
                font.weight: Font.Bold
            }
        }

        Icon {
            id: glyph
            visible: !Theme.tui
            anchors.centerIn: icon
            size: 20
            paths: root.mode ? (root.modeOn ? Icons.lightbulb : Icons.moon)
                : root.tabs ? Icons.layers
                : root.workspace ? Icons.layers
                : root.desktop ? (Desktop.enabled ? Icons.folder : Icons.folder.concat(Icons.slash))
                : root.kind === "brightness" ? Icons.sun
                : root.output ? (Audio.isHeadphones(Audio.sink) ? Icons.headphones : Icons.speaker)
                : root.kind === "mic" ? (root.cueOn && Audio.micMuted ? Icons.micOff : Icons.mic)
                : root.kind === "screen" ? Icons.screenShare
                : root.muted ? Icons.volumeMuted : Icons.volume
            // as the bar shows them: clay while in use, subtext when muted or let go
            color: root.mode ? (root.modeOn ? Theme.pistachio : Theme.teal)
                : root.tabs ? (root.tabsOn ? Theme.pistachio : Theme.subtext)
                : root.workspace ? Theme.textBright
                : root.desktop ? (Desktop.enabled ? Theme.textBright : Theme.subtext)
                : root.cue ? (root.cueOn && !(root.kind === "mic" && Audio.micMuted) ? Theme.clay : Theme.subtext)
                : root.muted ? Theme.subtext : Theme.textBright
        }

        // the new output's name in place of the bar
        Text {
            visible: root.output
            anchors.left: icon.right
            anchors.leftMargin: 14
            anchors.right: label.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: root.outputName
            elide: Text.ElideRight
            color: Theme.textBright
            font.family: Theme.fontUi
            font.pixelSize: Theme.tui ? Theme.tuiTextSize : 14
            font.weight: Font.Bold
        }

        // a privacy cue's news in place of the bar: what happened, and to which apps
        Column {
            visible: root.cue
            anchors.left: icon.right
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: root.cueTitle
                elide: Text.ElideRight
                color: Theme.textBright
                font.family: Theme.fontUi
                font.pixelSize: Theme.tui ? Theme.tuiTextSize : 14
                font.weight: Font.Bold
            }

            Text {
                width: parent.width
                text: root.cueNames
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: Theme.tui ? Theme.tuiTextSize : 12
                font.weight: Font.Medium
            }
        }

        // Zen or Focus on or off, a Pomodoro phase
        Column {
            visible: root.mode
            anchors.left: icon.right
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: root.modeTitle
                elide: Text.ElideRight
                color: Theme.textBright
                font.family: Theme.fontUi
                font.pixelSize: Theme.tui ? Theme.tuiTextSize : 14
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
            }

            Text {
                width: parent.width
                text: root.modeDetail
                elide: Text.ElideRight
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: Theme.tui ? Theme.tuiTextSize : 12
                font.weight: Font.Medium
                font.features: { "tnum": 1 }
            }
        }

        // tabs on or off, and for which workspace
        Column {
            visible: root.tabs
            anchors.left: icon.right
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                id: tabsTitle
                width: parent.width
                text: root.tabsOn ? "Tabbed" : "Tabs off"
                elide: Text.ElideRight
                color: Theme.textBright
                font.family: Theme.fontUi
                font.pixelSize: Theme.tui ? Theme.tuiTextSize : 14
                font.weight: Font.Bold
            }

            Text {
                id: tabsDetail
                width: parent.width
                text: {
                    const name = Compositor.nameOf(root.tabsWorkspace);
                    const ws = `Workspace ${root.tabsWorkspace}${name ? ` · ${name}` : ""}`;
                    return root.tabsOn ? `${ws}: its windows as tabs` : `${ws}: tiled again`;
                }
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: Theme.tui ? Theme.tuiTextSize : 12
                font.weight: Font.Medium
            }
        }

        // the workspace: its name (or number) and what's on it, then the bar's dots
        Column {
            visible: root.workspace
            anchors.left: icon.right
            anchors.leftMargin: 14
            anchors.right: dots.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                id: workspaceTitle
                width: parent.width
                text: Compositor.nameOf(Compositor.activeWorkspace) || `Workspace ${Compositor.activeWorkspace}`
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.textBright
                font.family: Theme.fontUi
                font.pixelSize: Theme.tui ? Theme.tuiTextSize : 14
                font.weight: Font.Bold
            }

            Text {
                width: parent.width
                text: {
                    const id = Compositor.activeWorkspace;
                    const apps = [...new Set(Compositor.windows.filter(w => w.workspace === id).map(w => Apps.nameFor(w.appId)))];
                    const what = apps.length ? apps.join(", ") : "Empty";
                    return Compositor.nameOf(id) ? `Workspace ${id} · ${what}` : what;
                }
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: Theme.tui ? Theme.tuiTextSize : 12
                font.weight: Font.Medium
            }
        }

        Row {
            id: dots
            visible: root.workspace
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Repeater {
                model: Math.max(5, ...Compositor.workspaces.map(w => w.id))

                Rectangle {
                    required property int index
                    readonly property var ws: Compositor.workspaces.find(w => w.id === index + 1)
                    readonly property bool current: index + 1 === Compositor.activeWorkspace

                    anchors.verticalCenter: parent.verticalCenter
                    width: current ? 20 : 6
                    height: 6
                    radius: Theme.tui ? 0 : 3
                    color: current ? Theme.pistachio : ws?.occupied ? Theme.subtext : "transparent"
                    border.width: current || ws?.occupied ? 0 : 1.5
                    border.color: Theme.muted

                    Behavior on width {
                        NumberAnimation {
                            duration: Theme.motionDuration
                            easing.type: Theme.easing
                        }
                    }
                }
            }
        }

        // the desktop icons' news in place of the bar
        Column {
            visible: root.desktop
            anchors.left: icon.right
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                id: desktopTitle
                width: parent.width
                text: Desktop.enabled ? "Desktop icons shown" : "Desktop icons hidden"
                elide: Text.ElideRight
                color: Theme.textBright
                font.family: Theme.fontUi
                font.pixelSize: Theme.tui ? Theme.tuiTextSize : 14
                font.weight: Font.Bold
            }

            Text {
                id: desktopDetail
                width: parent.width
                text: Desktop.enabled ? `${Desktop.items.length} ${Desktop.items.length === 1 ? "item" : "items"} from ${Desktop.folder.split("/").pop()}` : "Your files stay where they are"
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: Theme.tui ? Theme.tuiTextSize : 12
                font.weight: Font.Medium
                font.features: { "tnum": 1 }
            }
        }

        Rectangle {
            visible: !root.output && !root.notice
            anchors.left: icon.right
            anchors.leftMargin: 14
            anchors.right: label.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            height: Theme.tui ? 10 : 8
            radius: Theme.tui ? 0 : 4
            color: Theme.overlay

            Rectangle {
                width: parent.width * Math.min(1, root.level)
                height: parent.height
                radius: Theme.tui ? 0 : 4
                color: root.muted ? Theme.overlay2 : Theme.pistachio
            }
        }

        Text {
            id: label
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            width: root.muted ? (Theme.tui ? 56 : 50) : (Theme.tui ? 40 : 30)
            // a new output's volume reads 0 until PipeWire has bound it
            visible: !root.notice && (!root.output || (Audio.sink?.ready ?? false))
            horizontalAlignment: Text.AlignRight
            text: Theme.tui ? (root.muted ? "muted" : Math.round(root.level * 100) + "%") : root.muted ? "Muted" : Math.round(root.level * 100)
            color: root.muted ? Theme.subtext : Theme.textBright
            font.family: Theme.fontUi
            font.pixelSize: Theme.tui ? Theme.tuiTextSize : 13
            font.weight: Font.ExtraBold
            font.features: { "tnum": 1 }
        }
    }
}
