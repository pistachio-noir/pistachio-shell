.pragma library

// Fuzzy matching for the launcher. Tested by tests/fuzzy.test.js (node).

// Letters that keep no accent mark to drop (NFD leaves them whole), as their plain letter.
const plain = { "ł": "l", "ø": "o", "đ": "d", "ħ": "h", "ı": "i", "ŧ": "t" };

// `s` in lower case without accents, for matching (owner's request, after phase 8): "Żółty" reads
// "zolty", so either finds the other. One character for one, so indices into it are indices into `s`.
function fold(s) {
    if (/^[\x00-\x7f]*$/.test(s))
        return s.toLowerCase();
    let out = "";
    for (let i = 0; i < s.length; i++) {
        const base = s[i].normalize("NFD")[0].toLowerCase(); // "Ż" is "Z" and a dot
        out += plain[base] ?? (base.length === 1 ? base : s[i]);
    }
    return out;
}

// Match `query` against `text`, ignoring case and accents. Returns { score, indices } (higher is
// better; indices are the matched characters) or null. A contiguous match beats a scattered one, and
// an earlier match, one at a word start, or one at the very start scores higher. Scattered (in-order)
// matches score by how tightly the letters cluster, and count only if they span at most three
// characters per query letter, so a short query does not match half of every long name.
function match(query, text) {
    if (text === undefined || text === null)
        return null; // e.g. a device with no name yet, or for a moment as it goes (PipeWire)
    const q = fold(query), t = fold(text);
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
