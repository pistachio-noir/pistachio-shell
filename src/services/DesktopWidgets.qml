pragma Singleton

import qs
import Quickshell
import QtQuick
import "../panels/desktopGrid.js" as Grid

// Desktop widgets (owner's request, 20 November 2026; Experimental, off by default; spec
// docs/superpowers/specs/2026-11-20-desktop-widgets-design.md): Clock, Weather and CPU/RAM blocks on
// the desktop icons' grid, arranged in the widget studio (popups/WidgetStudio.qml). The layout is
// Store.saved.widgetLayout ([{ kind, col, row }]; null until first arranged: the default down the right
// edge), fitted to this screen's grid; it stays local (not in the settings export).
Singleton {
    id: root

    readonly property bool enabled: Store.saved.desktopWidgets === true
    function setEnabled(value: bool) { Store.saved.desktopWidgets = value; }

    // the studio is open (arrange from Settings, the launcher, the desktop's menu, `psc widgets arrange`)
    property bool arranging
    function arrange() { // arranging means wanting them: the switch goes on
        if (!enabled) setEnabled(true);
        arranging = true;
    }
    function done() { arranging = false; }

    // half the desktop icons' cells (panels/DesktopIcons.qml), from the same corner: 52 px, so a widget
    // can sit in the middle of the screen. Classic keeps clear of the bar and the room above it at the
    // bottom; TUI of its 35 px strip at the top (owner's bug report, 20 November 2026: under the strip).
    readonly property int cellWidth: 52
    readonly property int cellHeight: 52
    readonly property int margin: 24
    readonly property int top: Theme.tui ? Theme.tuiBarHeight + margin : margin
    readonly property int bottom: Theme.tui ? margin : margin + Theme.barHeight + Theme.barMargin
    readonly property var screen: Quickshell.screens[0] ?? null
    readonly property int columns: screen ? Math.max(1, Math.floor((screen.width - 2 * margin) / cellWidth)) : 1
    readonly property int rows: screen ? Math.max(1, Math.floor((screen.height - top - bottom) / cellHeight)) : 1
    // the grid's middle, for the studio's centre cross
    readonly property real middleX: margin + columns * cellWidth / 2
    readonly property real middleY: top + rows * cellHeight / 2

    readonly property var sizes: Grid.SIZES
    readonly property var kinds: Grid.KINDS
    readonly property var layout: Store.saved.widgetLayout ? Grid.fitLayout(Grid.upgrade(Store.saved.widgetLayout), columns, rows) : Grid.defaultLayout(columns, rows)
    // the icon cells ("col,row") the widgets touch, which the icons go around while the switch is on
    readonly property var cells: Grid.iconCellsOf(layout)
    function xOf(col: int): real { return margin + col * cellWidth; }
    function yOf(row: int): real { return top + row * cellHeight; }

    // the cat's rule: an active workspace without tiled windows, not under a fullscreen window; not in Zen
    readonly property bool desktopEmpty: !!((Compositor.workspaces ?? []).some(w => w.active) && !Compositor.fullscreen && !(Compositor.windows ?? []).some(w => w.workspace === Compositor.activeWorkspace && !w.floating && !w.hidden && !w.minimized))
    readonly property bool shown: enabled && desktopEmpty && !FocusMode.zen

    function fits(index: int, kind: string, col: int, row: int): bool {
        return Grid.fits(layout, index, kind, col, row, columns, rows);
    }
    function freeSpot(kind: string): var {
        return Grid.firstFree(layout, kind, columns, rows);
    }
    function has(kind: string): bool {
        return layout.some(w => w.kind === kind);
    }

    function save(list) {
        Store.saved.widgetLayout = list.map(w => ({ kind: w.kind, col: w.col, row: w.row, u: 52 }));
    }
    // a widget to another spot; false (and nothing changes) if it can't go there
    function move(index: int, col: int, row: int): bool {
        const w = layout[index];
        if (!w || !fits(index, w.kind, col, row))
            return false;
        const list = layout.map(x => ({ kind: x.kind, col: x.col, row: x.row }));
        list[index].col = col;
        list[index].row = row;
        save(list);
        return true;
    }
    function add(kind: string): bool {
        const spot = has(kind) ? null : freeSpot(kind);
        if (!spot)
            return false;
        save(layout.concat([{ kind: kind, col: spot[0], row: spot[1] }]));
        return true;
    }
    function remove(index: int) {
        save(layout.filter((w, i) => i !== index));
    }
}
