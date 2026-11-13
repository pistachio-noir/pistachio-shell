// Unit test for src/components/highlight.js (code colours in the quick chat and Lens). Run: node tests/highlight.test.js
const fs = require("fs");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../src/components/highlight.js"), "utf8").replace(".pragma library", "");
const { tokens, html, languageOf, guess } = new Function(src + "\nreturn { tokens, html, languageOf, guess };")();

const palette = { keyword: "K", string: "S", number: "N", comment: "C", function: "F", type: "T", variable: "V",
    flag: "G", key: "Y", meta: "M", add: "A", remove: "R", plain: "P", font: "Mono" };
// the kinds of the tokens that have one, as "text:kind"
const kinds = (code, language) => tokens(code, language).filter(t => t[1]).map(t => `${t[0].trim()}:${t[1]}`);
const joined = (code, language) => tokens(code, language).map(t => t[0]).join("");

// the tokens are the code again, whatever the language
for (const [code, language] of [["fn main() { let x = 1; }", "clike"], ["$ git reset --soft HEAD~1 # undo", "shell"],
    ['{"a": [1, 2.5, true]}', "json"], ["def f(x):\n    return 'y'  # no", "python"], ["broken \"string", "clike"]])
    assert.strictEqual(joined(code, language), code, `${language} keeps the code`);

// C-like: keywords, functions, types, strings, numbers, comments, a Rust lifetime and attribute
assert.deepStrictEqual(kinds('let name = String::from("pistachio"); // moved', "clike"),
    ["let:keyword", "String:type", "from:function", '"pistachio":string', "// moved:comment"]);
assert.deepStrictEqual(kinds("fn first<'a>(s: &'a str) -> usize { 0x1F }", "clike"),
    ["fn:keyword", "first:function", "'a:meta", "'a:meta", "str:keyword", "usize:keyword", "0x1F:number"]);
assert.deepStrictEqual(kinds("#[derive(Debug)]\nconst X = 'c';", "clike"), ["#[derive(Debug)]:meta", "const:keyword", "'c':string"]);
assert.deepStrictEqual(kinds("/* open comment\nstill", "clike"), ["/* open comment\nstill:comment"]); // being written

// shell: the prompt, flags, variables, strings and comments; a word isn't a function in a shell line
assert.deepStrictEqual(kinds('$ git commit -m "fix" --amend $HOME # note', "shell"),
    ["$:prompt", "-m:flag", '"fix":string', "--amend:flag", "$HOME:variable", "# note:comment"]);
assert.deepStrictEqual(kinds("for f in *.png; do echo ${f%.png}; done", "shell"), ["for:keyword", "in:keyword", "do:keyword", "${f%.png}:variable", "done:keyword"]);
assert.deepStrictEqual(kinds("a#b", "shell"), [], "a # inside a word isn't a comment");

// JSON keys and values; Python strings, decorators and keywords; config sections and keys; diffs
assert.deepStrictEqual(kinds('{"name": "x", "n": -2, "ok": null}', "json"),
    ['"name":key', '"x":string', '"n":key', "-2:number", '"ok":key', "null:keyword"]);
assert.deepStrictEqual(kinds('@cache\ndef go(x):\n    """doc"""\n    return None', "python"),
    ["@cache:meta", "def:keyword", "go:function", '"""doc""":string', "return:keyword", "None:keyword"]);
assert.deepStrictEqual(kinds("[general]\ngaps = 5 # px\nname: \"x\"", "config"),
    ["[general]:section", "gaps:key", "5:number", "# px:comment", "name:key", '"x":string']);
assert.deepStrictEqual(kinds("@@ -1 +1 @@\n-old\n+new\n same", "diff"), ["@@ -1 +1 @@:meta", "-old:remove", "+new:add"]);
assert.deepStrictEqual(kinds("SELECT name FROM users WHERE id = 3", "sql"), ["SELECT:keyword", "FROM:keyword", "WHERE:keyword", "3:number"]);

// the fence's name, or a guess
assert.strictEqual(languageOf("rust", ""), "clike");
assert.strictEqual(languageOf("Bash", ""), "shell");
assert.strictEqual(languageOf("yml", ""), "config");
assert.strictEqual(languageOf("text", "fn x() {}"), "", "text stays plain");
assert.strictEqual(guess("git reset --soft HEAD~1"), "shell");
assert.strictEqual(guess("$ cargo run"), "shell");
assert.strictEqual(guess('{\n  "a": 1\n}'), "json");
assert.strictEqual(guess("def f(x):\n    return x"), "python");
assert.strictEqual(guess("int main() {\n  return 0;\n}"), "clike");
assert.strictEqual(guess("just some words"), "");

// rich text: escaped, coloured spans, spaces kept
const out = html("if (a < b) { x = \"<b>\"; }", "c", palette);
assert.ok(out.startsWith('<pre style="white-space:pre-wrap;margin:0;font-family:\'Mono\';color:P;">'), out);
assert.ok(out.includes('<span style="color:K;">if</span>'), out);
assert.ok(out.includes("a &lt; b"), out);
assert.ok(out.includes('<span style="color:S;">"&lt;b&gt;"</span>'), out);
assert.ok(!/<b>/.test(out), "no markup from the code gets through");
assert.ok(html("# hi", "sh", palette).includes('font-style:italic'), "comments are italic");

console.log("highlight: all passed");
