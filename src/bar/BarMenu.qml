import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland // the layer's name, level and keyboard (a Wayland protocol, not a compositor module)
import QtQuick

// The bar's right-click menu (owner's request, 9 November 2026): for the workspace on screen, tabbed
// (i3-style) on or off, and naming it. Over the whole screen while open, so a click beside it (or
// Esc) closes it, as with the power menu.
PanelWindow {
    id: root

    property bool open
    property real at // the click's x on the screen
    property bool topEdge
    property int lift // the bar's top, from the screen's bottom edge

    signal renameRequested(int workspace)
    signal timerRequested
    signal alarmRequested

    // which menu: the workspace's (anywhere on the bar) or the clock's (on the clock pill: timers, the
    // stopwatch and alarms, owner's request, 9 November 2026)
    property string kind: "workspace"

    readonly property int ws: Compositor.activeWorkspace
    readonly property var entries: kind === "clock" ? clockEntries : workspaceEntries
    readonly property var clockEntries: {
        const out = [];
        // a Focus or Zen session (FocusMode)
        if (FocusMode.session) {
            if (ShellSettings.phonePreview) out.push({ text: "View on phone", glyph: Icons.smartphone, run: () => FocusMode.showPhone() });
            out.push({ text: FocusMode.paused ? "Resume the session" : "Pause the session", glyph: FocusMode.working ? Icons.lightbulb : Icons.moon, run: () => FocusMode.pause() });
            if (FocusMode.session.pomodoro)
                out.push({ text: FocusMode.working ? "Skip to the break" : "Skip to work", glyph: Icons.skipForward, run: () => FocusMode.skip() });
            out.push({ text: FocusMode.session.owner === "focus" ? "End the session" : "End the Pomodoro", glyph: Icons.close, danger: true, run: () => FocusMode.endSession() });
        }
        out.push({ text: "Timer…", glyph: Icons.clock, run: () => root.timerRequested() });
        for (const t of Clocks.timers) {
            const name = t.label || `Timer ${Clocks.clock(t.duration)}`;
            out.push({ text: `${t.endsAt ? "Pause" : "Resume"} ${name}`, glyph: Icons.clock, run: () => Clocks.pauseTimer(t.id) });
            out.push({ text: `Stop ${name}`, glyph: Icons.close, danger: true, run: () => Clocks.stopTimer(t.id) });
        }
        if (!Clocks.stopwatch)
            out.push({ text: "Start a stopwatch", glyph: Icons.stopwatch, run: () => Clocks.startStopwatch() });
        else
            out.push({ text: Clocks.stopwatch.since ? "Pause the stopwatch" : "Resume the stopwatch", glyph: Icons.stopwatch, run: () => Clocks.pauseStopwatch() },
                { text: `Lap (${Clocks.stopwatch.laps.length} so far)`, glyph: Icons.plus, run: () => Clocks.lap() },
                { text: "Stop the stopwatch", glyph: Icons.close, danger: true, run: () => Clocks.stopStopwatch() });
        if (Clocks.enabled)
            out.push({ text: "Alarm…", glyph: Icons.bell, run: () => root.alarmRequested() });
        for (const a of Clocks.alarms)
            out.push({ text: `${a.active ? "On" : "Off"} · ${a.hour}:${String(a.minute).padStart(2, "0")} ${a.name}`, glyph: a.active ? Icons.check : Icons.bellOff, run: () => Clocks.setAlarm(a.id, !a.active) });
        if (Clocks.clocksInstalled)
            out.push({ text: "Open Clocks", glyph: Icons.folderOpen, run: () => Clocks.openClocks() });
        return out;
    }
    readonly property var workspaceEntries: [
        { text: Compositor.isTabbed(ws) ? "Tabs off: tile again" : "Tabbed, i3-style", glyph: Icons.layers, run: () => Compositor.setTabbed(ws, !Compositor.isTabbed(ws)) },
        { text: Compositor.nameOf(ws) ? `Rename “${Compositor.nameOf(ws)}”…` : `Name workspace ${ws}…`, glyph: Icons.pencil, run: () => root.renameRequested(ws) }
    ].concat(Compositor.nameOf(ws) ? [{ text: "Clear its name", glyph: Icons.close, run: () => Compositor.setName(ws, "") }] : [])

    visible: open
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "pistachio-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: root.open = false
    }

    Item {
        id: card

        x: Math.max(8, Math.min(root.at - width / 2, root.width - width - 8))
        y: root.topEdge ? root.lift+15 : root.height - root.lift - height - 8
        width: 240
        height: column.implicitHeight + (Theme.tui ? 20 : 12)
        focus: root.open
        Keys.onEscapePressed: root.open = false

        Shadow {
            kind: Theme.shadowSmall
            anchors.fill: panel
            radius: panel.radius
        }

        // TUI: a frame whose title tab carries the heading
        PanelFrame {
            id: panel
            anchors.fill: parent
            title: Theme.tui ? heading.text.toLowerCase() : ""
            active: false
            radius: Theme.tileRadius
            color: Theme.tui ? Theme.tuiSurface : Theme.bgAlt
            border.width: 1
            border.color: Theme.overlay2
            Accessible.role: Accessible.PopupMenu
        }

        Column {
            id: column
            x: 6
            y: Theme.tui ? 14 : 6
            width: parent.width - 12

            Text {
                id: heading
                visible: !Theme.tui
                x: 10
                height: visible ? 28 : 0
                verticalAlignment: Text.AlignVCenter
                text: root.kind === "clock" ? "TIMERS AND ALARMS" : `WORKSPACE ${root.ws}`
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 0.66
            }

            Repeater {
                model: root.entries

                Rectangle {
                    id: entry

                    required property var modelData

                    width: column.width
                    height: Theme.tui ? Theme.tuiButtonHeight : 36
                    radius: Theme.tui ? 0 : 14
                    color: entryMouse.containsMouse ? (Theme.tui ? Theme.tuiHover : Theme.overlay) : "transparent"
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: modelData.text

                    Icon {
                        visible: !Theme.tui
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        size: 16
                        paths: entry.modelData.glyph
                        color: entry.modelData.danger ? Theme.terracotta : Theme.subtext
                    }

                    Text {
                        x: Theme.tui ? 12 : 40
                        width: parent.width - x - 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData.text
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.tui && entry.modelData.danger ? Theme.terracotta : Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.tui ? Theme.tuiTextSize : 13
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: entryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const run = entry.modelData.run;
                            root.open = false;
                            run();
                        }
                    }
                }
            }
        }
    }
}
