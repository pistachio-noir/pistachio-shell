// The desktop's grid, shared by the desktop icons (panels/DesktopIcons.qml), the desktop widgets
// (panels/DesktopWidgetLayer.qml) and the widget studio (popups/WidgetStudio.qml). Icons sit on 104 px
// cells; widgets on 52 px half-cells from the same corner (finer snapping, owner's pick, 20 November
// 2026), so two half-cells make an icon cell. A widget is { kind, col, row } in half-cells and covers
// SIZES[kind] of them (columns, rows).
// Tested by tests/desktop-grid.test.js (node and Quickshell's JS engine: no Object.fromEntries,
// Array.flatMap or Array.at).

var SIZES = { clock: [6, 4], weather: [4, 4], stats: [4, 4], media: [6, 3], timers: [4, 4], system: [4, 4] };
var KINDS = ["clock", "weather", "stats", "media", "timers", "system"];
var DEFAULT = ["clock", "weather", "stats"]; // what a first layout holds; the rest come from the studio's +

// a layout saved on the first 104 px grid (20 November 2026, before half-cells: no `u`) in half-cells
function upgrade(saved) {
    if (!saved) return saved;
    return Array.from(saved).map(function (w) {
        return w && w.u === 52 ? { kind: w.kind, col: w.col, row: w.row } : { kind: w ? w.kind : "", col: (w ? Number(w.col) || 0 : 0) * 2, row: (w ? Number(w.row) || 0 : 0) * 2 };
    });
}

// the 104 px icon cells ("col,row") the widgets touch, which the icons go around
function iconCellsOf(layout) {
    var seen = {}, out = [];
    for (var i = 0; i < layout.length; i++) {
        var w = layout[i], size = SIZES[w.kind];
        if (!size) continue;
        for (var r = Math.floor(w.row / 2); r <= Math.floor((w.row + size[1] - 1) / 2); r++)
            for (var c = Math.floor(w.col / 2); c <= Math.floor((w.col + size[0] - 1) / 2); c++)
                if (!seen[c + "," + r]) { seen[c + "," + r] = true; out.push(c + "," + r); }
    }
    return out;
}

// "col,row" of each cell a widget covers
function cellsOf(w) {
    var size = SIZES[w.kind], out = [];
    for (var r = 0; r < size[1]; r++)
        for (var c = 0; c < size[0]; c++)
            out.push((w.col + c) + "," + (w.row + r));
    return out;
}

// the cells of every widget but layout[skip]
function taken(layout, skip) {
    var set = {};
    for (var i = 0; i < layout.length; i++) {
        if (i === skip) continue;
        var cells = cellsOf(layout[i]);
        for (var j = 0; j < cells.length; j++) set[cells[j]] = true;
    }
    return set;
}

// can a widget of `kind` sit at col, row (layout[index] left out: the one being moved; -1 for a new one)?
function fits(layout, index, kind, col, row, columns, rows) {
    var size = SIZES[kind];
    if (!size || col < 0 || row < 0 || col + size[0] > columns || row + size[1] > rows) return false;
    var busy = taken(layout, index), cells = cellsOf({ kind: kind, col: col, row: row });
    for (var i = 0; i < cells.length; i++)
        if (busy[cells[i]]) return false;
    return true;
}

// the first spot for a new widget, from the top-right corner (the icons start top-left): columns right
// to left, rows top down; null when there's no room
function firstFree(layout, kind, columns, rows) {
    var size = SIZES[kind];
    for (var c = columns - size[0]; c >= 0; c--)
        for (var r = 0; r + size[1] <= rows; r++)
            if (fits(layout, -1, kind, c, r, columns, rows)) return [c, r];
    return null;
}

function defaultLayout(columns, rows) {
    var layout = [];
    for (var i = 0; i < DEFAULT.length; i++) {
        var spot = firstFree(layout, DEFAULT[i], columns, rows);
        if (spot) layout.push({ kind: DEFAULT[i], col: spot[0], row: spot[1] });
    }
    return layout;
}

// a saved layout made to fit this grid: unknown kinds and second copies dropped; widgets that still
// fit keep their place, the others move to the first free spot (or go, with no room); order kept
function fitLayout(saved, columns, rows) {
    var list = [], seen = {};
    var raw = saved ? Array.from(saved) : [];
    for (var i = 0; i < raw.length; i++) {
        var w = raw[i];
        if (!w || !SIZES[w.kind] || seen[w.kind]) continue;
        seen[w.kind] = true;
        list.push({ kind: w.kind, col: Math.floor(Number(w.col) || 0), row: Math.floor(Number(w.row) || 0) });
    }
    var placed = [], keep = [];
    for (var k = 0; k < list.length; k++) {
        keep.push(fits(placed, -1, list[k].kind, list[k].col, list[k].row, columns, rows));
        if (keep[k]) placed.push(list[k]);
    }
    for (var m = 0; m < list.length; m++) {
        if (keep[m]) continue;
        var spot = firstFree(placed, list[m].kind, columns, rows);
        if (spot) { list[m].col = spot[0]; list[m].row = spot[1]; placed.push(list[m]); keep[m] = true; }
    }
    return list.filter(function (w, n) { return keep[n]; });
}

// where each icon sits, name -> [col, row]: saved places first (on the grid, not on `blocked` cells
// ("col,row"), not taken by another), then the rest in the first free cells, down then right
function iconLayout(names, positions, columns, rows, blocked) {
    var at = {}, busy = {}, i;
    for (i = 0; i < blocked.length; i++) busy[blocked[i]] = true;
    var key = function (cell) { return cell[0] + "," + cell[1]; };
    for (i = 0; i < names.length; i++) {
        var p = positions[names[i]];
        if (p && p[0] < columns && p[1] < rows && !busy[key(p)]) {
            at[names[i]] = [p[0], p[1]];
            busy[key(p)] = true;
        }
    }
    var next = 0, cells = columns * rows;
    for (i = 0; i < names.length; i++) {
        if (at[names[i]]) continue;
        while (next < cells && busy[key([Math.floor(next / rows), next % rows])]) next++;
        var cell = next < cells ? [Math.floor(next / rows), next % rows] : [0, 0]; // no room left: stacked
        at[names[i]] = cell;
        busy[key(cell)] = true;
    }
    return at;
}
