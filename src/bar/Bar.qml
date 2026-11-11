import qs
import qs.components
import qs.panels
import qs.popups
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland // the layer's name, which a Hyprland blur rule matches (a Wayland protocol, not a compositor module)
import QtQuick

// The floating bar. Only the bottom edge is anchored, so the compositor centres it horizontally.
// It hides while a window on the active workspace overlaps it; pointing at the bottom edge brings it back.
PanelWindow {
    id: root

    // The bar's area on screen (the pill, the tray and media pills if shown, and the gap under them),
    // grown by a small margin.
    readonly property int trayGap: 12
    readonly property real mediaSpace: media.visible ? trayGap + media.width : 0
    readonly property rect zone: Qt.rect((screen.width - width) / 2 - 8 - mediaSpace, screen.height - height - 8, width + 16 + mediaSpace + (tray.visible ? trayGap + tray.width : 0), height + 8)
    readonly property bool overlapped: Compositor.windowBounds.some(r => r.x < zone.x + zone.width && r.x + r.width > zone.x && r.y + r.height > zone.y)
    // the pointer is on the bar or a pill beside it, or a tray menu or the media card is open
    readonly property bool pointed: hover.hovered || tray.hovered || tray.menuOpen || media.hovered || media.cardOpen
    // A fullscreen window (a game, a video; not a maximized one) has the screen to itself: no reveal
    // strip, so a stray pointer at the bottom edge doesn't bring the bar up over it (owner's request,
    // after phase 8). A panel opened by keybind still shows it.
    readonly property bool fullscreen: Compositor.fullscreen
    // Stays up while pointed (even if a window moves under it), for a moment after, long enough to
    // cross the gap to the tray pill, and while a panel or a tray menu is open.
    readonly property bool shown: !held && (!fullscreen && (!overlapped || pointed || linger.running || peekTimer.running) || tray.menuOpen || media.cardOpen || quickSettings.open || centre.open || Showoff.active)

    // The startup animation (owner's request, after phase 8; shell.qml): as the shell starts, the bar
    // and its pills wait as the handle while the wallpaper fades in, then grow out of it. Not on a
    // live reload. `instant` makes the drop to the handle at the start jump instead of ease.
    property bool held
    property bool instant

    function startIntro() {
        instant = true;
        held = true;
        instant = false;
    }

    function endIntro() {
        held = false;
    }

    onPointedChanged: if (!pointed) linger.restart()

    // Tooltips (owner's request; not on a board): what the pointer rests on, as lines and the x to
    // centre on, or null. It shows after half a second; moving on to the next item swaps it at once,
    // across the gaps between them too, and the bar hiding, a panel or a tray menu drops it.
    readonly property var tipTarget: !shown || quickSettings.open || centre.open || tray.menuOpen || media.cardOpen || Showoff.active ? null
        : clock.hovered ? { lines: clock.tooltip, x: centreOf(clock) }
        : status.hovered ? { lines: status.tooltip, x: centreOf(status) }
        : workspaces.hoveredSlot ? { lines: workspaces.tooltip, x: centreOf(workspaces.hoveredSlot) }
        : tray.tipIcon ? { lines: tray.tipLines, x: tray.tipCentre }
        : null

    function centreOf(item: Item): real {
        return (screen.width - width) / 2 + item.mapToItem(null, item.width / 2, 0).x;
    }

    onTipTargetChanged: {
        if (tipTarget) {
            tipClose.stop();
            tip.lines = tipTarget.lines;
            tip.centre = tipTarget.x;
            if (!tip.open)
                tipDelay.restart();
        } else {
            tipDelay.stop();
            tipClose.restart();
        }
    }

    Timer {
        id: tipDelay
        interval: 500
        onTriggered: tip.open = true
    }

    Timer {
        id: tipClose
        interval: 150 // long enough to cross to the next item
        onTriggered: tip.open = false
    }

    BarTooltip {
        id: tip
        lift: Theme.barHeight + Theme.barMargin + 8
    }

    Timer {
        id: linger
        interval: 400
    }

    // `bar peek` (owner's request, 3 November 2026): out for 2 s, for a keybind; not over fullscreen
    Timer {
        id: peekTimer
        interval: 2000
    }

    // quick settings asks for a launcher mode; shell.qml owns the launcher
    signal launcherRequested(string mode)
    signal renameWorkspaceRequested(int workspace) // the right-click menu: shell.qml asks in the launcher
    signal timerRequested
    signal alarmRequested

    // the notification centre at one notification (the launcher's "!")
    function showNotification(n) {
        quickSettings.open = false;
        centre.show(n);
    }

    // Showoff mode (Showoff): the notification centre, with the calendar and the weather, 48 px from the
    // left edge, quick settings 48 px from the right, both sliding in from their side, one after the
    // other, then the terminal in the room between them. `staged` keeps them there until they've faded
    // out. A click outside doesn't close them meanwhile.
    readonly property int stageMargin: 48
    property bool staged

    // the desktop's "Send with LocalSend" and `psc localsend add|open`: its page, in quick settings
    Connections {
        target: LocalSend

        function onOpenRequested() {
            quickSettings.page = "localsend";
            quickSettings.open = true;
        }
    }

    Connections {
        target: Showoff

        function onActiveChanged() {
            grab.active = false;
            quickSettings.open = false;
            centre.open = false;
            stageSteps.stop();
            if (Showoff.active) {
                unstage.stop();
                root.staged = true;
                stageSteps.start();
            } else {
                unstage.restart();
            }
        }
    }

    SequentialAnimation {
        id: stageSteps

        PauseAnimation {
            duration: 150
        }
        ScriptAction {
            script: centre.open = true
        }
        PauseAnimation {
            duration: 150
        }
        ScriptAction {
            script: quickSettings.open = true
        }
        PauseAnimation {
            duration: 150
        }
        ScriptAction {
            script: {
                const bottom = root.screen.height - root.height - 16;
                const left = root.stageMargin + centre.panelWidth + 40;
                const right = root.screen.width - root.stageMargin - quickSettings.panelWidth - 40;
                const top = bottom - Math.max(centre.panelHeight, quickSettings.panelHeight);
                Showoff.openTerminal(Qt.rect(left, top, right - left, bottom - top));
            }
        }
    }

    Timer {
        id: unstage
        interval: Theme.motionDuration + 50 // the panels have faded out
        onTriggered: root.staged = false
    }

    // One panel at a time.
    function toggle(panel) {
        const open = !panel.open;
        quickSettings.open = false;
        centre.open = false;
        panel.open = open;
    }

    anchors.bottom: true
    exclusiveZone: 0 // reserve no space, so windows can sit under the bar
    implicitWidth: Theme.barWidth
    implicitHeight: Theme.barHeight + Theme.barMargin // reaches the screen edge, where the reveal strip is
    color: "transparent"
    WlrLayershell.namespace: "pistachio-bar" // frosted panels: Hyprland blurs the shell's layers by name

    // Hidden, only a 4 px strip at the screen edge takes the pointer (none over a fullscreen window);
    // clicks elsewhere reach the windows below.
    mask: Region {
        y: root.shown ? 0 : root.height - 4
        width: root.width
        height: root.shown ? root.height : root.fullscreen ? 0 : 4
    }

    HoverHandler {
        id: hover
    }

    // From the handle left behind while hidden (AutoHide board: 72 x 4, 2 px above the screen edge,
    // in subtext) to the pill and back: 0 is the handle, 1 the bar (owner's request).
    property real grown: shown ? 1 : 0

    Behavior on grown {
        enabled: !root.instant

        NumberAnimation {
            duration: Theme.growDuration
            easing.type: Theme.easing
        }
    }

    // The pill, grown out of the handle: it widens and rises as the handle's colour gives way to the
    // bar's within the first third.
    Rectangle {
        width: 72 + (parent.width - 72) * root.grown
        height: 4 + (Theme.barHeight - 4) * root.grown
        x: (parent.width - width) / 2
        y: (root.height - 2 - 4) * (1 - root.grown)
        radius: height / 2 // 2 for the handle, Theme.barRadius for the bar
        color: Theme.glass(Qt.tint(Theme.bgAlt, Qt.rgba(Theme.subtext.r, Theme.subtext.g, Theme.subtext.b, Math.max(0, 1 - 3 * root.grown))))
        border.width: 1
        border.color: Qt.rgba(Theme.overlay2.r, Theme.overlay2.g, Theme.overlay2.b, root.grown)
        // no handle over a fullscreen window, as there's no strip to point at
        opacity: root.fullscreen && !root.shown ? 0 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.growDuration
                easing.type: Theme.easing
            }
        }
    }

    // The bar's content, at its full size: it fades in rising 6 px once the pill is half grown, and
    // goes first when it shrinks.
    Item {
        id: content

        readonly property real shownPart: Math.max(0, 2 * root.grown - 1)

        width: parent.width
        height: Theme.barHeight
        opacity: shownPart
        visible: opacity > 0
        transform: Translate {
            y: 6 * (1 - content.shownPart)
        }

        // a right click anywhere on the bar: its menu (tabbed, the workspace's name)
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: mouse => {
                barMenu.at = (root.screen.width - root.width) / 2 + mapToItem(null, mouse.x, 0).x; // the bar is centred
                const p = mapToItem(clock, mouse.x, mouse.y), q = mapToItem(clockPills, mouse.x, mouse.y);
                barMenu.kind = clock.contains(p) || clockPills.visible && clockPills.contains(q) ? "clock" : "workspace";
                barMenu.open = true;
            }
        }

        // Edges sit 9 px in (1 px border + 8 px padding) with 8 px gaps, as on the board.
        Workspaces {
            id: workspaces
            anchors.left: parent.left
            anchors.leftMargin: 9
            anchors.verticalCenter: parent.verticalCenter
        }

        WindowTitle {
            anchors.left: workspaces.right
            anchors.right: clockPills.visible ? clockPills.left : recordingChip.visible ? recordingChip.left : clock.left
            anchors.leftMargin: 12 // gap + the title's own 4 px padding
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
        }

        // a running timer or stopwatch (owner's request, 9 November 2026): the time counting, its label;
        // a click pauses or resumes it, a right click opens the clock's menu (stop, lap)
        Row {
            id: clockPills

            visible: Clocks.timers.length > 0 || Clocks.stopwatch !== null
            anchors.right: recordingChip.visible ? recordingChip.left : clock.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Repeater {
                model: Clocks.timers.slice(0, 2).map(t => ({ kind: "timer", t: t })).concat(Clocks.stopwatch ? [{ kind: "stopwatch" }] : []).slice(0, 2)

                Rectangle {
                    id: pill

                    required property var modelData
                    readonly property bool timer: modelData.kind === "timer"
                    readonly property bool running: timer ? !!modelData.t.endsAt : !!Clocks.stopwatch?.since
                    readonly property string time: timer ? Clocks.clock(Clocks.left(modelData.t)) : Clocks.clock(Clocks.elapsed())
                    readonly property string label: timer ? modelData.t.label : ""

                    width: pillRow.implicitWidth + 28
                    height: Theme.chipHeight
                    radius: Theme.chipRadius
                    color: pillMouse.containsMouse ? Theme.overlay2 : Theme.overlay
                    Accessible.role: Accessible.Button
                    Accessible.name: `${timer ? "Timer" : "Stopwatch"} ${time}${label ? ", " + label : ""}. ${running ? "Pause" : "Resume"}`

                    Row {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: 8

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            size: 16
                            paths: pill.timer ? Icons.clock : Icons.stopwatch
                            color: pill.running ? Theme.pistachio : Theme.subtext
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: pill.time
                            color: pill.running ? Theme.textBright : Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.ExtraBold
                            font.features: { "tnum": 1 }
                        }

                        Text {
                            visible: pill.label !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, 70)
                            elide: Text.ElideRight
                            text: pill.label
                            textFormat: Text.PlainText
                            color: Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }

                    MouseArea {
                        id: pillMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pill.timer ? Clocks.pauseTimer(pill.modelData.t.id) : Clocks.pauseStopwatch()
                    }
                }
            }
        }

        // while the screen is recorded (owner's pick, 8 November 2026): a red dot and the time; a click
        // stops it and saves the video
        Rectangle {
            id: recordingChip

            property real now: Date.now()
            readonly property int seconds: Math.floor(Screenshots.elapsedMs(now) / 1000)

            visible: Screenshots.recording
            anchors.right: clock.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: recordingRow.implicitWidth + 28
            height: Theme.chipHeight
            radius: Theme.chipRadius
            color: recordingMouse.containsMouse ? Theme.overlay2 : Theme.overlay
            Accessible.role: Accessible.Button
            Accessible.name: `Recording, ${recordingTime.text}. Left click stops; right click ${Screenshots.paused ? "resumes" : "pauses"}`

            Timer {
                running: recordingChip.visible
                interval: 500
                repeat: true
                onTriggered: recordingChip.now = Date.now()
            }

            Row {
                id: recordingRow
                anchors.centerIn: parent
                spacing: 8

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10
                    height: 10
                    radius: 5
                    color: Theme.terracotta

                    SequentialAnimation on opacity {
                        running: recordingChip.visible
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 800; easing.type: Theme.easing }
                        NumberAnimation { to: 1; duration: 800; easing.type: Theme.easing }
                    }
                }

                Text {
                    id: recordingTime
                    anchors.verticalCenter: parent.verticalCenter
                    text: `${Screenshots.paused ? "Ⅱ " : ""}${Math.floor(recordingChip.seconds / 60)}:${String(recordingChip.seconds % 60).padStart(2, "0")}`
                    color: Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.ExtraBold
                    font.features: { "tnum": 1 }
                }
            }

            MouseArea {
                id: recordingMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: event => event.button===Qt.RightButton ? Screenshots.togglePause() : Screenshots.stopRecording()
            }
        }

        ClockChip {
            id: clock
            anchors.right: status.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            highlighted: centre.open
            onClicked: root.toggle(centre)
        }

        StatusChip {
            id: status
            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            highlighted: quickSettings.open
            onClicked: root.toggle(quickSettings)
        }
    }

    // what's playing, left of the bar while a player has a track
    MediaPill {
        id: media
        anchors.bottom: true
        anchors.left: true
        margins.left: (screen.width - root.width) / 2 - root.trayGap - media.width
        shown: root.shown
        instant: root.instant
    }

    // the tray pill, right of the bar while any app has a tray icon
    TrayPill {
        id: tray
        anchors.bottom: true
        anchors.left: true
        margins.left: (screen.width + root.width) / 2 + root.trayGap
        shown: root.shown
        instant: root.instant
    }

    // Quick settings is right-aligned with the bar, 12 px above it. The notification centre, wider
    // with the calendar beside it, and the toasts are centred over the bar, 16 px above it (as on
    // their boards).
    QuickSettings {
        id: quickSettings
        anchors.bottom: true
        anchors.left: true
        margins.left: root.staged ? screen.width - root.stageMargin - quickSettings.panelWidth - quickSettings.side : (screen.width + root.width) / 2 - width + quickSettings.side
        margins.bottom: root.height + 12 - quickSettings.below
        slide: root.staged ? 36 : 0
        onOpenChanged: grab.active = (open || centre.open) && !Showoff.active
        onPowerRequested: {
            open = false;
            powerMenu.open = true;
        }
        onLauncherRequested: mode => {
            open = false;
            root.launcherRequested(mode);
        }
    }

    BarMenu {
        id: barMenu
        lift: root.height
        onRenameRequested: ws => root.renameWorkspaceRequested(ws)
        onTimerRequested: root.timerRequested()
        onAlarmRequested: root.alarmRequested()
    }

    PowerMenu {
        id: powerMenu
    }

    NotificationCentre {
        id: centre
        anchors.bottom: true
        anchors.left: true // centred over the bar, as the compositor would
        margins.left: root.staged ? root.stageMargin - centre.side : (screen.width - centre.implicitWidth) / 2
        margins.bottom: root.height + 16 - centre.below
        slide: root.staged ? -36 : 0
        onOpenChanged: grab.active = (open || quickSettings.open) && !Showoff.active
    }

    // only the bottom edge is anchored, so the compositor centres it, like the bar
    Toasts {
        id: toasts
        visible: Notifs.popups.length > 0 && !centre.open || LocalSend.toastShown
        anchors.bottom: true
        margins.bottom: root.height + 16 - toasts.below
    }

    // where the pill is while the bar is hidden, else above it like the toasts
    Osd {
        anchors.bottom: true
        lift: root.shown ? root.height + 16 : Theme.barMargin
        suppressed: quickSettings.open
    }

    // A click outside the panels and the bar closes the panels; the bar stays clickable.
    FocusGrab {
        id: grab
        windows: [quickSettings, centre, root]
        onCleared: {
            quickSettings.open = false;
            centre.open = false;
        }
    }

    // For keybinds: qs -c pistachio ipc call quicksettings toggle (or notifications toggle)
    IpcHandler {
        target: "quicksettings"

        function toggle(): void {
            root.toggle(quickSettings);
        }

        // straight to the sound mixer
        function mixer(): void {
            quickSettings.page = "mixer";
            quickSettings.open = true;
        }
    }

    // For a keybind: qs -c pistachio ipc call bar peek
    IpcHandler {
        target: "bar"

        function peek(): void {
            peekTimer.restart();
        }
    }

    // For a keybind: qs -c pistachio ipc call showoff toggle
    IpcHandler {
        target: "showoff"

        function toggle(): void {
            Showoff.toggle();
        }
    }

    IpcHandler {
        target: "notifications"

        function toggle(): void {
            root.toggle(centre);
        }

        function toggleDnd(): void {
            Notifs.setDnd(!Notifs.dnd);
        }
    }
}
