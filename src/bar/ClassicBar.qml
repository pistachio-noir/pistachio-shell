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
    objectName: "classic-bar"

    // The bar's area on screen (the pill, the tray and media pills if shown, and the gap under them),
    // grown by a small margin.
    readonly property int trayGap: 12
    readonly property real mediaSpace: media.visible ? trayGap + media.width : 0
    readonly property real rightSpace: (tray.visible ? trayGap + tray.width : 0) + (minimizedPill.visible ? trayGap + minimizedPill.width : 0)
    readonly property rect zone: Qt.rect((screen.width - width) / 2 - 8 - mediaSpace, screen.height - height - 8, width + 16 + mediaSpace + rightSpace, height + 8)
    readonly property bool overlapped: Compositor.windowBounds.some(r => r.x < zone.x + zone.width && r.x + r.width > zone.x && r.y + r.height > zone.y)
    // the pointer is on the bar or a pill beside it, or a tray menu or the media card is open
    readonly property bool pointed: hover.hovered || tray.hovered || tray.menuOpen || media.hovered || media.cardOpen || minimizedPill.hovered
    // A fullscreen window (a game, a video; not a maximized one) has the screen to itself: no reveal
    // strip, so a stray pointer at the bottom edge doesn't bring the bar up over it (owner's request,
    // after phase 8). A panel opened by keybind still shows it.
    // Zen mode (FocusMode) hides it the same way: no strip, no handle; a panel opened by key still shows it.
    // So does the Overview while it's open (owner's call, 12 November, superseding the boards' bar under it).
    readonly property bool fullscreen: Compositor.fullscreen || FocusMode.zen || overviewOpen
    // Stays up while pointed (even if a window moves under it), for a moment after, long enough to
    // cross the gap to the tray pill, and while a panel or a tray menu is open.
    property bool overviewOpen // the Overview hides the bar, and the workspace OSD stays quiet
    property real sessionPillWidth // Zen's session pill, while it shows: the minimised pill sits beside it
    readonly property bool shown: !held && (!fullscreen && (!overlapped || pointed || linger.running || peekTimer.running) || tray.menuOpen || media.cardOpen || (quickSettings?.open ?? false) || (centre?.open ?? false) || Showoff.active)

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
    readonly property var tipTarget: !shown || (quickSettings?.open ?? false) || (centre?.open ?? false) || tray.menuOpen || media.cardOpen || Showoff.active ? null
        : clock.hovered ? { lines: clock.tooltip, x: centreOf(clock) }
        : status.hovered ? { lines: status.tooltip, x: centreOf(status) }
        : workspaces.hoveredSlot ? { lines: workspaces.tooltip, x: centreOf(workspaces.hoveredSlot) }
        : tray.tipIcon ? { lines: tray.tipLines, x: tray.tipCentre }
        : minimizedPill.tipIcon ? { lines: minimizedPill.tipLines, x: minimizedPill.tipCentre }
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

    function peek() { peekTimer.restart(); }
    required property var controller
    readonly property var quickSettings: controller.controls
    readonly property var centre: controller.centre
    function toggle(panel) { controller.toggle(panel); }

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

            visible: Clocks.timers.length > 0 || Clocks.stopwatch !== null || FocusMode.session !== null
            anchors.right: recordingChip.visible ? recordingChip.left : clock.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Repeater {
                // a Focus or Zen session first (FocusMode, owner's request, 11 November 2026): its phase and time left
                model: (FocusMode.session ? [{ kind: "session" }] : []).concat(Clocks.timers.slice(0, 2).map(t => ({ kind: "timer", t: t })), Clocks.stopwatch ? [{ kind: "stopwatch" }] : []).slice(0, 2)

                Rectangle {
                    id: pill

                    required property var modelData
                    readonly property bool timer: modelData.kind === "timer"
                    readonly property bool session: modelData.kind === "session"
                    readonly property bool running: session ? !FocusMode.paused : timer ? !!modelData.t.endsAt : !!Clocks.stopwatch?.since
                    readonly property string time: session ? FocusMode.clock(FocusMode.left()) : timer ? Clocks.clock(Clocks.left(modelData.t)) : Clocks.clock(Clocks.elapsed())
                    readonly property string label: session ? FocusMode.phaseName() : timer ? modelData.t.label : ""

                    width: pillRow.implicitWidth + 28
                    height: Theme.chipHeight
                    radius: Theme.chipRadius
                    color: pillMouse.containsMouse ? Theme.overlay2 : Theme.overlay
                    Accessible.role: Accessible.Button
                    Accessible.name: `${session ? "Session" : timer ? "Timer" : "Stopwatch"} ${time}${label ? ", " + label : ""}. ${running ? "Pause" : "Resume"}`

                    Row {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: 8

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            size: 16
                            paths: pill.session ? (FocusMode.working ? Icons.lightbulb : Icons.moon) : pill.timer ? Icons.clock : Icons.stopwatch
                            // a break is calmer: teal, not the active pistachio
                            color: !pill.running ? Theme.subtext : pill.session && !FocusMode.working ? Theme.teal : Theme.pistachio
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
                        onClicked: pill.session ? FocusMode.pause() : pill.timer ? Clocks.pauseTimer(pill.modelData.t.id) : Clocks.pauseStopwatch()
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
            highlighted: (centre?.open ?? false)
            onClicked: root.toggle(centre)
        }

        StatusChip {
            id: status
            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            highlighted: (quickSettings?.open ?? false)
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

    // the minimised windows, right of the tray pill (or of the bar, without one) while there are any
    MinimizedPill {
        id: minimizedPill
        anchors.bottom: true
        anchors.left: true
        // in Zen, which hides the bar, it stays: right of the session pill, or centred without one
        // (not over a fullscreen game or video, nor the Overview: the bar's own reasons to stay away)
        compact: FocusMode.zen && !root.shown && !Compositor.fullscreen && !root.overviewOpen
        margins.left: compact ? (root.sessionPillWidth > 0 ? (screen.width + root.sessionPillWidth) / 2 + root.trayGap : (screen.width - width) / 2)
            : (screen.width + root.width) / 2 + root.trayGap + (tray.visible ? tray.width + root.trayGap : 0)
        shown: root.shown || compact
        instant: root.instant
    }

    BarMenu {
        id: barMenu
        lift: root.height
        onRenameRequested: ws => root.renameWorkspaceRequested(ws)
        onTimerRequested: root.timerRequested()
        onAlarmRequested: root.alarmRequested()
    }

}
