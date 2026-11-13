.pragma library

// Syntax colours for code blocks in the quick chat and Lens (owner's request, 13 November 2026).
// html(code, language, palette) returns rich text for a TextEdit (textFormat RichText): the code
// escaped, in a <pre> that keeps its spaces and wraps, with each token in a span of the palette's
// colours (the Theme's, passed in by the caller: this file can't import it). The language comes from
// the code fence (```rust); without one, guess() picks one from what the code looks like.
// A small scanner, not a parser: it knows comments, strings, numbers, keywords, function calls, types,
// shell variables and flags, JSON and config keys, markup tags and diff lines. Unclosed strings and
// comments run to the end (an answer still being written).

const CLIKE = words(`if else for while do switch case default break continue return function fn let const var mut pub
    struct enum impl trait use mod crate self Self super class interface extends implements new delete this typeof
    instanceof void null nullptr nil true false undefined try catch finally throw throws async await yield import
    export as in of package static final public private protected abstract override virtual inline extern
    unsafe where match loop type typedef namespace template typename auto int long short char float double bool
    boolean string byte unsigned signed sizeof go defer chan select map range func property readonly signal
    required alias pragma dyn move ref elif goto volatile register constexpr noexcept operator friend explicit
    usize isize u8 u16 u32 u64 i8 i16 i32 i64 f32 f64 str val when object companion lateinit internal sealed
    data fun is`);
const PYTHON = words(`and as assert async await break class continue def del elif else except False finally for
    from global if import in is lambda None nonlocal not or pass raise return True try while with yield self match
    case print len range int str float list dict set tuple bool`);
const SHELL = words(`if then else elif fi for while until do done case esac in function select return local export
    readonly unset shift exit set source alias sudo time true false`);
const LUA = words(`and break do else elseif end false for function goto if in local nil not or repeat return then
    true until while self require`);
const SQL = words(`select from where and or not insert into values update set delete create table drop alter add
    index on join left right inner outer full group by order having limit offset as distinct null is in like
    between primary key foreign references default unique case when then else end union all exists count sum
    avg min max integer text varchar boolean`);
const CONFIG = words(`true false yes no on off null none`);

function words(list) {
    const out = {};
    for (const w of list.split(/\s+/))
        if (w)
            out[w] = true;
    return out;
}

const STRING = `"(?:\\\\.|[^"\\\\\\n])*"?|'(?:\\\\.|[^'\\\\\\n])*'?`;
const NUMBER = `\\b(?:0[xX][\\da-fA-F_]+|0[bB][01_]+|\\d[\\d_]*(?:\\.\\d[\\d_]*)?(?:[eE][+-]?\\d+)?)[a-zA-Z]*\\b`;
const IDENT = `[A-Za-z_][\\w]*`;

// each language: [kind, pattern] in order (an earlier one wins where two start at the same place), the
// keywords, and whether a capitalised name is a type
const LANGUAGES = {
    clike: {
        rules: [["comment", `\\/\\/[^\\n]*|\\/\\*[\\s\\S]*?(?:\\*\\/|(?![\\s\\S]))`], ["meta", `^[ \\t]*#[ \\t]*\\w+|#!?\\[[^\\]\\n]*\\]?|@[A-Za-z_][\\w.]*`],
            ["meta", `'[A-Za-z_]\\w*(?![\\w'])`], // a Rust lifetime ('a), not the start of a string
            ["string", STRING + "|`(?:\\\\.|[^`\\\\])*`?"], ["number", NUMBER], ["ident", IDENT]],
        keywords: CLIKE, types: true
    },
    python: {
        rules: [["comment", `#[^\\n]*`], ["string", `[rbfuRBFU]{0,2}(?:"""[\\s\\S]*?(?:"""|(?![\\s\\S]))|'''[\\s\\S]*?(?:'''|(?![\\s\\S])))`],
            ["string", `[rbfuRBFU]{0,2}(?:${STRING})`], ["meta", `@[A-Za-z_][\\w.]*`], ["number", NUMBER], ["ident", IDENT]],
        keywords: PYTHON, types: true
    },
    shell: {
        rules: [["prompt", `^[ \\t]*\\$ (?=\\S)`], ["comment", `(?:^|[ \\t])#[^\\n]*`], ["string", `"(?:\\\\.|[^"\\\\])*"?|'[^']*'?`],
            ["variable", `\\$\\{[^}\\n]*\\}?|\\$\\(|\\$[A-Za-z_]\\w*|\\$[@*#?$!0-9-]`], ["flag", `(?:^|[ \\t])--?[A-Za-z][\\w-]*`],
            ["number", NUMBER], ["ident", `[A-Za-z_][\\w-]*`]],
        keywords: SHELL, types: false
    },
    json: {
        rules: [["key", `"(?:\\\\.|[^"\\\\\\n])*"(?=\\s*:)`], ["string", STRING], ["number", `-?${NUMBER}`], ["ident", IDENT]],
        keywords: CONFIG, types: false
    },
    config: {
        rules: [["comment", `(?:^|[ \\t])[#;][^\\n]*`], ["section", `^[ \\t]*\\[[^\\]\\n]*\\]`], ["key", `^[ \\t-]*[\\w.-]+(?=[ \\t]*[:=])`],
            ["string", STRING], ["number", NUMBER], ["ident", IDENT]],
        keywords: CONFIG, types: false
    },
    lua: {
        rules: [["comment", `--\\[\\[[\\s\\S]*?(?:\\]\\]|(?![\\s\\S]))|--[^\\n]*`], ["string", STRING + `|\\[\\[[\\s\\S]*?(?:\\]\\]|(?![\\s\\S]))`], ["number", NUMBER], ["ident", IDENT]],
        keywords: LUA, types: false
    },
    sql: {
        rules: [["comment", `--[^\\n]*|\\/\\*[\\s\\S]*?(?:\\*\\/|(?![\\s\\S]))`], ["string", STRING], ["number", NUMBER], ["ident", IDENT]],
        keywords: SQL, types: false, caseless: true
    },
    css: {
        rules: [["comment", `\\/\\*[\\s\\S]*?(?:\\*\\/|(?![\\s\\S]))`], ["string", STRING], ["number", `#[\\da-fA-F]{3,8}\\b|-?\\d[\\d.]*(?:px|em|rem|%|s|ms|deg|vh|vw)?\\b`],
            ["key", `[\\w-]+(?=[ \\t]*:[^:])`], ["meta", `@[\\w-]+`]],
        keywords: {}, types: false
    },
    markup: {
        rules: [["comment", `<!--[\\s\\S]*?(?:-->|(?![\\s\\S]))`], ["tag", `<\\/?[\\w:.-]+|\\/?>`], ["function", `[\\w:.-]+(?==)`], ["string", STRING]],
        keywords: {}, types: false
    },
    diff: {
        rules: [["meta", `^@@[^\\n]*`], ["comment", `^(?:diff|index|---|\\+\\+\\+)[^\\n]*`], ["add", `^\\+[^\\n]*`], ["remove", `^-[^\\n]*`]],
        keywords: {}, types: false
    }
};

const ALIASES = {
    c: "clike", h: "clike", cpp: "clike", "c++": "clike", cc: "clike", hpp: "clike", cxx: "clike", java: "clike",
    js: "clike", javascript: "clike", mjs: "clike", jsx: "clike", ts: "clike", typescript: "clike", tsx: "clike",
    go: "clike", golang: "clike", rust: "clike", rs: "clike", qml: "clike", kotlin: "clike", kt: "clike",
    swift: "clike", cs: "clike", csharp: "clike", "c#": "clike", php: "clike", dart: "clike", zig: "clike",
    scala: "clike", glsl: "clike", frag: "clike", vert: "clike",
    py: "python", python: "python", python3: "python",
    sh: "shell", bash: "shell", zsh: "shell", fish: "shell", shell: "shell", console: "shell", terminal: "shell",
    shellsession: "shell", ksh: "shell",
    json: "json", jsonc: "json", json5: "json", jsonl: "json",
    yaml: "config", yml: "config", toml: "config", ini: "config", conf: "config", cfg: "config", properties: "config",
    env: "config", dotenv: "config", desktop: "config", systemd: "config", service: "config",
    lua: "lua", sql: "sql", psql: "sql", sqlite: "sql", mysql: "sql",
    css: "css", scss: "css", less: "css", qss: "css",
    html: "markup", xml: "markup", svg: "markup", vue: "markup", xhtml: "markup",
    diff: "diff", patch: "diff", udiff: "diff"
};

// the language a fence names, or a guess from the code
function languageOf(name, code) {
    const fence = String(name || "").trim().toLowerCase().split(/\s+/)[0];
    if (ALIASES[fence])
        return ALIASES[fence];
    if (fence === "text" || fence === "txt" || fence === "plain" || fence === "plaintext" || fence === "output" || fence === "log")
        return "";
    return guess(code);
}

function guess(code) {
    const text = String(code || "");
    const first = text.trim().split("\n")[0] || "";
    if (/^(?:diff --git|--- a\/|@@ )/.test(text.trim()))
        return "diff";
    if (/^\s*[{[]/.test(text) && /"\s*:/.test(text))
        return "json";
    if (/^\s*[$#] \S/.test(first) || /^\s*(?:sudo|git|cd|ls|cargo|npm|pnpm|yarn|pacman|yay|paru|systemctl|journalctl|hyprctl|qs|psc|echo|cat|grep|rg|find|curl|wget|chmod|chown|mkdir|rm|cp|mv|export|ssh|tar|make|cmake|docker|podman|flatpak|python3?|pip|node|kill|pkill|ln|touch|nvim|code|uv|wl-copy|wl-paste|ffmpeg)\b/.test(first))
        return "shell";
    if (/^\s*(?:def|class|import|from)\s[^;{]*:?\s*$/m.test(text) && !/[;{]\s*$/m.test(text))
        return "python";
    if (/^\s*(?:<\?xml|<!DOCTYPE|<[a-zA-Z][\w-]*[\s>])/.test(text))
        return "markup";
    if (/^\s*\[[^\]]+\]\s*$/m.test(text) && /^\s*[\w.-]+\s*=/m.test(text))
        return "config";
    if (/[;{}]\s*$/m.test(text) || /\b(?:fn|let|const|function|return|struct|class|import)\b/.test(text))
        return "clike";
    return "";
}

function escape(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// the span for a token of this kind, in the palette's colours
function wrap(text, kind, palette) {
    const colour = {
        keyword: palette.keyword, string: palette.string, number: palette.number, comment: palette.comment,
        function: palette.function, type: palette.type, variable: palette.variable, flag: palette.flag,
        key: palette.key, section: palette.keyword, meta: palette.meta, tag: palette.keyword,
        add: palette.add, remove: palette.remove, prompt: palette.comment
    }[kind];
    if (!colour)
        return escape(text);
    const italic = kind === "comment" ? "font-style:italic;" : "";
    return `<span style="color:${colour};${italic}">${escape(text)}</span>`;
}

// the code's tokens: [text, kind], kind "" for the rest; joined, they're the code again
function tokens(code, language) {
    const spec = LANGUAGES[language];
    const text = String(code || "");
    if (!spec)
        return [[text, ""]];
    const pattern = new RegExp(spec.rules.map(r => `(${r[1]})`).join("|"), "gm");
    const out = [];
    let at = 0, m;
    while ((m = pattern.exec(text)) !== null) {
        if (m[0] === "") {
            pattern.lastIndex++;
            continue;
        }
        if (m.index > at)
            out.push([text.slice(at, m.index), ""]);
        const rule = spec.rules[m.slice(1).findIndex(g => g !== undefined)];
        let kind = rule[0];
        if (kind === "ident") {
            const word = spec.caseless ? m[0].toLowerCase() : m[0];
            const after = text.slice(pattern.lastIndex, pattern.lastIndex + 80).match(/^[ \t]*(?:<[^<>()\n]{0,60}>)?[ \t]*!?\(/); // a call, generics and macros too
            kind = spec.keywords[word] ? "keyword" : after && language !== "shell" ? "function" : spec.types && /^[A-Z][a-z0-9]/.test(m[0]) ? "type" : "";
        }
        out.push([m[0], kind]);
        at = pattern.lastIndex;
    }
    if (at < text.length)
        out.push([text.slice(at), ""]);
    return out;
}

function html(code, name, palette) {
    const language = languageOf(name, code);
    const body = tokens(code, language).map(t => wrap(t[0], t[1], palette)).join("");
    return `<pre style="white-space:pre-wrap;margin:0;font-family:'${palette.font}';color:${palette.plain};">${body}</pre>`;
}
