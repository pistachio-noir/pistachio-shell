// Unit test for src/panels/calendar.js. Run: node tests/calendar.test.js
const fs = require("fs");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../src/panels/calendar.js"), "utf8").replace(".pragma library", "");
const { days, shift, sameDay } = new Function(src + "\nreturn { days, shift, sameDay };")();

const ymd = d => [d.getFullYear(), d.getMonth() + 1, d.getDate()].join("-");

// October 2026 starts on a Thursday: three September days first, then into November
let grid = days(2026, 9);
assert.strictEqual(grid.length, 42);
assert.strictEqual(ymd(grid[0]), "2026-9-28");
assert.strictEqual(ymd(grid[3]), "2026-10-1");
assert.strictEqual(ymd(grid[41]), "2026-11-8");

// a month starting on Monday begins the grid with its 1st (February 2027), one starting on
// Sunday gets six days of the month before (November 2026)
assert.strictEqual(ymd(days(2027, 1)[0]), "2027-2-1");
assert.strictEqual(ymd(days(2027, 1)[41]), "2027-3-14");
assert.strictEqual(ymd(days(2026, 10)[0]), "2026-10-26");

// every week starts on Monday and days follow each other, across the switch from summer time
// (25 October 2026 in Europe) and over a year's end
for (const [y, m] of [[2026, 9], [2026, 11], [2027, 1], [2028, 1]]) {
    grid = days(y, m);
    for (let i = 0; i < 42; i++) {
        if (i % 7 === 0)
            assert.strictEqual(grid[i].getDay(), 1, `${y}-${m + 1}: week ${i / 7} starts on Monday`);
        if (i > 0) {
            const next = new Date(grid[i - 1]);
            next.setDate(next.getDate() + 1);
            assert.ok(sameDay(next, grid[i]), `${y}-${m + 1}: ${ymd(grid[i - 1])} then ${ymd(grid[i])}`);
        }
    }
}

// a leap February has 29 days in the grid
assert.strictEqual(days(2028, 1).filter(d => d.getMonth() === 1).length, 29);

// moving between months, over year ends both ways
assert.deepStrictEqual(shift(2026, 11, 1), { year: 2027, month: 0 });
assert.deepStrictEqual(shift(2027, 0, -1), { year: 2026, month: 11 });
assert.deepStrictEqual(shift(2026, 9, 0), { year: 2026, month: 9 });
assert.deepStrictEqual(shift(2026, 9, -22), { year: 2024, month: 11 });

assert.ok(sameDay(new Date(2026, 9, 26, 23, 59), new Date(2026, 9, 26, 0, 0)));
assert.ok(!sameDay(new Date(2026, 9, 26), new Date(2025, 9, 26)));

console.log("calendar: all passed");
