// Unit test for src/launcher/calc.js. Run: node tests/calc.test.js
const fs = require("fs");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../src/launcher/calc.js"), "utf8").replace(".pragma library", "");
const { evaluate, format } = new Function(src + "\nreturn { evaluate, format };")();

// precedence, brackets, unary minus, powers
assert.strictEqual(evaluate("2+3*4"), 14);
assert.strictEqual(evaluate("(2+3)*4"), 20);
assert.strictEqual(evaluate("10-4-3"), 3);
assert.strictEqual(evaluate("2^10"), 1024);
assert.strictEqual(evaluate("-2^2"), -4);
assert.strictEqual(evaluate("2^-1"), 0.5);
assert.strictEqual(evaluate("2^3^2"), 512);
assert.strictEqual(evaluate("-(3+2)*-2"), 10);
assert.strictEqual(evaluate("8/2/2"), 2);

// how people type it: spaces, x and ×, ÷, a decimal comma
assert.strictEqual(evaluate(" 12 x 3 "), 36);
assert.strictEqual(evaluate("12×3"), 36);
assert.strictEqual(evaluate("9÷3"), 3);
assert.strictEqual(evaluate("2,5*2"), 5);
assert.strictEqual(evaluate(".5+.5"), 1);

// not math, or not worth a calculator row: words, a bare number, a lone negative, errors
for (const t of ["firefox", "2", "-2", "", "2+", "(2+3", "2+3)", "1/0", "2**3", "1.2.3+1", "x", "rm -rf"])
    assert.strictEqual(evaluate(t), null, t);

// display rounding hides float noise
assert.strictEqual(format(evaluate("0.1+0.2")), "0.3");
assert.strictEqual(format(evaluate("1/3")), "0.333333333333");
assert.strictEqual(format(evaluate("7*6")), "42");

console.log("calc: all passed");
