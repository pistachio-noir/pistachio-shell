// Unit test for src/launcher/fuzzy.js. Run: node tests/fuzzy.test.js
const fs = require("fs");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../src/launcher/fuzzy.js"), "utf8").replace(".pragma library", "");
const { match, highlight, fold } = new Function(src + "\nreturn { match, highlight, fold };")();

// the board's example: prefix matches (which tie; the launcher then puts shorter names first)
// beat a match inside a word, and a non-match is dropped
assert.strictEqual(match("ne", "Neovim").score, match("ne", "Network Manager TUI").score);
assert.ok(match("ne", "Neovim").score > match("ne", "General Notes").score);
assert.strictEqual(match("ne", "Firefox"), null);
assert.deepStrictEqual(match("ne", "General Notes").indices, [2, 3]);

// case-insensitive, word starts beat mid-word, scattered letters still match but rank lower
assert.ok(match("FIRE", "Firefox"));
assert.ok(match("term", "GNOME Terminal").score > match("term", "Determined").score);
assert.deepStrictEqual(match("ffx", "Firefox").indices, [0, 4, 6]);
assert.ok(match("fox", "Firefox").score > match("ffx", "Firefox").score);
assert.strictEqual(match("zz", "Firefox"), null);
// letters scattered across a long text do not count (seen: "fire" matched a file manager's keywords)
assert.strictEqual(match("fire", "file manager file explorer"), null);
assert.strictEqual(match("", "Firefox").score, 0);

// accents don't matter either way, and the indices still point into the text as written
assert.deepStrictEqual(match("zolty", "Żółty").indices, [0, 1, 2, 3, 4]);
assert.ok(match("łódź", "Lodz"));
assert.ok(match("gesla", "Gęśla"));
assert.ok(match("zolw", "Żółw").score > match("zolw", "Mój żółw").score);
assert.deepStrictEqual(match("cafe", "Le Café").indices, [3, 4, 5, 6]);
assert.strictEqual(fold("Żółć ĄĘ"), "zolc ae");
assert.strictEqual(fold("Ærø ß"), "æro ß"); // ligatures stay whole: one character for one
// characters outside the BMP (emoji) keep their two code units, so later indices stay right
assert.deepStrictEqual(match("é", "😀 e").indices, [3]);
assert.strictEqual(fold("😀ą").length, "😀ą".length);
assert.strictEqual(highlight("Żółty", match("zo", "Żółty").indices, "c"), '<font color="c">Żó</font>łty');

// highlighting wraps runs and escapes markup in names
assert.strictEqual(highlight("Neovim", [0, 1], "#9fd88a"), '<font color="#9fd88a">Ne</font>ovim');
assert.strictEqual(highlight("a<b>", [1], "c"), 'a<font color="c">&lt;</font>b&gt;');
assert.strictEqual(highlight("ab", [], "c"), "ab");

console.log("fuzzy: all passed");
