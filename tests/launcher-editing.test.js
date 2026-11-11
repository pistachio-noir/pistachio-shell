const fs = require("fs"), path = require("path"), assert = require("assert");
const source = fs.readFileSync(path.join(__dirname, "../src/launcher/Launcher.qml"), "utf8");
// Exercise the real editor functions against their field/service boundary, in the shell's JS engine too.
function bind(name, scope) {
    const declaration = "function " + name + "(", begin = source.indexOf(declaration);
    assert(begin >= 0, name);
    const body = source.indexOf("{", begin);
    let depth = 1, end = body + 1;
    while (depth && end < source.length) {
        if (source[end] === "{") depth++;
        if (source[end] === "}") depth--;
        end++;
    }
    return new Function("scope", "with (scope) { return (" + source.slice(begin, end) + "); }")(scope);
}
const scope = {
    editing: null, editBusy: false, editError: "", open: true, rows: [],
    field: { text: "", select() {} }, resetSelection() {}
};
Object.defineProperty(scope, "query", { get() { return scope.field.text; } });
for (const name of ["startEditing", "stopEditing", "saveEditing"]) scope[name] = bind(name, scope);
let applied = null;
const alias = { key: "alias", allowEmpty: true, check(text, then) { then(text, ""); }, apply(value) { applied = value; } };
scope.startEditing(alias, "editor");
scope.field.text = "";
scope.saveEditing();
assert.strictEqual(applied, "", "clearing an alias must apply the empty string");
assert.strictEqual(scope.editing, null, "successful empty alias closes editor");
applied = null;
scope.startEditing({ key: "other", check(text, then) { then(null, "Required"); }, apply(value) { applied = value; } }, "");
scope.saveEditing();
assert.strictEqual(applied, null);
assert.strictEqual(scope.editError, "Required");
assert(scope.editing, "invalid editor remains open");
console.log("launcher editing: empty alias removal and invalid-result handling passed");
