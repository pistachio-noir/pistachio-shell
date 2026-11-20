// Desktop widgets' grid (src/panels/desktopGrid.js): sizes, fits, free spots, the default and fitted
// layouts, and the icons' layout around widgets.
const fs = require("fs"), path = require("path"), assert = require("assert");
const G = new Function(fs.readFileSync(path.join(__dirname, "../src/panels/desktopGrid.js"), "utf8") +
    "\nreturn {SIZES, KINDS, DEFAULT, cellsOf, fits, firstFree, defaultLayout, fitLayout, iconLayout, upgrade, iconCellsOf};")();

// sizes in 52 px half-cells (finer snapping, owner's pick 20 November 2026)
assert.deepStrictEqual(G.SIZES, { clock: [6, 4], weather: [4, 4], stats: [4, 4], media: [6, 3], timers: [4, 4], system: [4, 4] });
assert.deepStrictEqual(G.KINDS, ["clock", "weather", "stats", "media", "timers", "system"]);
assert.deepStrictEqual(G.DEFAULT, ["clock", "weather", "stats"]);
assert.deepStrictEqual(G.cellsOf({ kind: "stats", col: 1, row: 2 }).length, 16);
assert.deepStrictEqual(G.cellsOf({ kind: "media", col: 0, row: 0 }).slice(0, 7), ["0,0", "1,0", "2,0", "3,0", "4,0", "5,0", "0,1"]);

// fits: inside the grid, not over another widget (the moved one itself ignored)
const two = [{ kind: "clock", col: 0, row: 0 }, { kind: "stats", col: 10, row: 0 }];
assert.strictEqual(G.fits(two, -1, "weather", 6, 0, 16, 8), true);
assert.strictEqual(G.fits(two, -1, "weather", 5, 0, 16, 8), false, "over the clock");
assert.strictEqual(G.fits(two, -1, "weather", 13, 0, 16, 8), false, "off the right edge");
assert.strictEqual(G.fits(two, -1, "weather", 0, 5, 16, 8), false, "off the bottom");
assert.strictEqual(G.fits(two, -1, "weather", -1, 0, 16, 8), false, "negative");
assert.strictEqual(G.fits(two, 0, "clock", 1, 1, 16, 8), true, "the clock moving over its own cells");
assert.strictEqual(G.fits(two, 0, "clock", 5, 0, 16, 8), false, "the clock onto the stats");

// firstFree: right to left, top down
assert.deepStrictEqual(G.firstFree([], "clock", 16, 8), [10, 0]);
assert.deepStrictEqual(G.firstFree([{ kind: "clock", col: 10, row: 0 }], "weather", 16, 8), [12, 4]);
const full = [{ kind: "weather", col: 0, row: 0 }, { kind: "stats", col: 4, row: 0 }, { kind: "timers", col: 0, row: 4 }, { kind: "system", col: 4, row: 4 }];
assert.strictEqual(G.firstFree(full, "media", 8, 8), null, "no room");

// defaultLayout: clock, weather, stats down the right edge
assert.deepStrictEqual(G.defaultLayout(36, 18), [{ kind: "clock", col: 30, row: 0 }, { kind: "weather", col: 32, row: 4 }, { kind: "stats", col: 32, row: 8 }]);

// fitLayout: unknown kinds and duplicates dropped, misfits moved, what can't fit dropped
assert.deepStrictEqual(G.fitLayout([{ kind: "clock", col: 30, row: 0 }, { kind: "bogus", col: 0, row: 0 }, { kind: "clock", col: 0, row: 0 }], 36, 18), [{ kind: "clock", col: 30, row: 0 }]);
assert.deepStrictEqual(G.fitLayout([{ kind: "clock", col: 30, row: 0 }, { kind: "stats", col: 32, row: 12 }], 20, 12), [{ kind: "clock", col: 14, row: 0 }, { kind: "stats", col: 16, row: 4 }]);
assert.deepStrictEqual(G.fitLayout([{ kind: "clock", col: 0, row: 0 }, { kind: "weather", col: 0, row: 0 }], 6, 4), [{ kind: "clock", col: 0, row: 0 }]);
assert.deepStrictEqual(G.fitLayout(null, 8, 4), []);

// upgrade: a layout saved on the first 104 px grid (no `u`) doubles; one in half-cells stays
assert.deepStrictEqual(G.upgrade([{ kind: "clock", col: 15, row: 1 }]), [{ kind: "clock", col: 30, row: 2 }]);
assert.deepStrictEqual(G.upgrade([{ kind: "clock", col: 15, row: 1, u: 52 }]), [{ kind: "clock", col: 15, row: 1 }]);
assert.deepStrictEqual(G.upgrade(null), null);

// iconCellsOf: the 104 px icon cells a widget touches (half-cells / 2, rounded out)
assert.deepStrictEqual(G.iconCellsOf([{ kind: "weather", col: 1, row: 0 }]), ["0,0", "1,0", "2,0", "0,1", "1,1", "2,1"]);
assert.deepStrictEqual(G.iconCellsOf([{ kind: "weather", col: 2, row: 2 }]), ["1,1", "2,1", "1,2", "2,2"]);

// iconLayout: without widgets, as DesktopIcons always placed them
assert.deepStrictEqual(G.iconLayout(["a", "b", "c"], { b: [0, 0] }, 4, 2, []), { b: [0, 0], a: [0, 1], c: [1, 0] });
// an icon saved under a widget flows to the next free cell; the others go around the widget
assert.deepStrictEqual(G.iconLayout(["a", "b"], { a: [0, 0] }, 4, 2, ["0,0", "0,1"]), { a: [1, 0], b: [1, 1] });
// a saved place outside the grid is ignored
assert.deepStrictEqual(G.iconLayout(["a"], { a: [9, 9] }, 2, 2, []), { a: [0, 0] });

console.log("desktop widgets grid: all passed");
