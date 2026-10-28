import Quickshell
import QtQuick

// Runs one node-style unit test (tests/*.test.js) in Quickshell's own JS engine, for machines without
// node: tests/js.sh starts it with TEST=<file> and QML_XHR_ALLOW_FILE_READ=1. It knows only what the
// tests use: require("fs").readFileSync, require("path").join and assert's ok, strictEqual and
// deepStrictEqual. Prints "PASS <output>" or "FAIL <message>" and quits.
Scope {
    function read(path) {
        const x = new XMLHttpRequest();
        x.open("GET", "file://" + path, false);
        x.send();
        return x.responseText;
    }

    Component.onCompleted: {
        const file = Quickshell.env("TEST");
        const fail = message => {
            throw new Error(message);
        };
        const shown = v => JSON.stringify(v);
        const assert = {
            ok: (v, m) => v || fail(m || `not ok: ${shown(v)}`),
            strictEqual: (a, b, m) => a === b || fail(m || `expected ${shown(b)}, got ${shown(a)}`),
            deepStrictEqual: (a, b, m) => shown(a) === shown(b) || fail(m || `expected ${shown(b)}, got ${shown(a)}`)
        };
        const modules = {
            fs: { readFileSync: p => read(p) },
            path: { join: (...parts) => parts.join("/").replace(/\/[^\/]+\/\.\.\//g, "/") },
            assert: assert
        };
        try {
            const out = [];
            new Function("require", "__dirname", "console", read(file))(m => modules[m], file.slice(0, file.lastIndexOf("/")), { log: m => out.push(m) });
            console.log("PASS", out.join(" "));
        } catch (e) {
            console.log("FAIL", e.message);
        }
        Qt.quit();
    }
}
