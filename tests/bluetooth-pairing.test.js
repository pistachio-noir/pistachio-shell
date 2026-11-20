// Connect after pairing (src/services/bluetooth.js): a device the shell paired gets connected once
// BlueZ reports it paired, so headphones play without a second click.
const fs = require("fs"), path = require("path"), assert = require("assert");
const { afterPairing } = new Function(fs.readFileSync(path.join(__dirname, "../src/services/bluetooth.js"), "utf8") + "\nreturn {afterPairing};")();

const dev = (address, paired, connected) => ({ address, paired, connected });

// still pairing: nothing to do, keep waiting
assert.deepStrictEqual(afterPairing(["A"], [dev("A", false, false)]), { connect: [], waiting: ["A"] });
// paired, not connected: connect it, stop waiting
assert.deepStrictEqual(afterPairing(["A"], [dev("A", true, false)]), { connect: ["A"], waiting: [] });
// paired and already connected (the device connected on its own): only stop waiting
assert.deepStrictEqual(afterPairing(["A"], [dev("A", true, true)]), { connect: [], waiting: [] });
// gone from the adapter (forgotten, out of range): stop waiting
assert.deepStrictEqual(afterPairing(["A"], []), { connect: [], waiting: [] });
// devices nobody paired from the shell are left alone, even paired and disconnected ones
assert.deepStrictEqual(afterPairing(["A"], [dev("B", true, false), dev("A", false, false)]), { connect: [], waiting: ["A"] });
// several at once, addresses compared without case
assert.deepStrictEqual(afterPairing(["aa:bb", "C"], [dev("AA:BB", true, false), dev("C", false, false)]), { connect: ["AA:BB"], waiting: ["C"] });
assert.deepStrictEqual(afterPairing([], [dev("A", true, false)]), { connect: [], waiting: [] });

console.log("bluetooth connect after pairing: all passed");
