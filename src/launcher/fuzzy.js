.pragma library

// Fuzzy matching for the launcher. Tested by tests/fuzzy.test.js (node).

// Match `query` against `text`, ignoring case. Returns { score, indices } (higher is better;
// indices are the matched characters) or null. A contiguous match beats a scattered one, and an
// earlier match, one at a word start, or one at the very start scores higher. Scattered (in-order)
// matches score by how tightly the letters cluster, and count only if they span at most three
// characters per query letter, so a short query does not match half of every long name.
function match(query, text) {
    const q = query.toLowerCase(), t = text.toLowerCase();
    if (q === "")
        return { score: 0, indices: [] };

    const at = t.indexOf(q);
    if (at >= 0) {
        const wordStart = at === 0 || /[\s\-_.\/]/.test(t[at - 1]);
        return { score: 1000 + (at === 0 ? 300 : 0) + (wordStart ? 200 : 0) - at, indices: range(at, at + q.length) };
    }

    const indices = [];
    for (let i = 0; i < t.length && indices.length < q.length; i++) {
        if (t[i] === q[indices.length])
            indices.push(i);
    }
    const spread = indices[indices.length - 1] - indices[0];
    if (indices.length < q.length || spread > 3 * q.length)
        return null;
    return { score: 500 - spread - indices[0], indices: indices };
}

// `text` as StyledText with the characters at `indices` in `color`, everything escaped.
function highlight(text, indices, color) {
    const marked = new Set(indices);
    let out = "", open = false;
    for (let i = 0; i < text.length; i++) {
        if (marked.has(i) !== open) {
            out += open ? "</font>" : `<font color="${color}">`;
            open = !open;
        }
        out += escape(text[i]);
    }
    return open ? out + "</font>" : out;
}

function escape(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function range(from, to) {
    const r = [];
    for (let i = from; i < to; i++)
        r.push(i);
    return r;
}
