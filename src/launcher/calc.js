.pragma library

// Basic arithmetic for the launcher: + - * / ^, brackets, unary minus, decimals with "." or ",".
// A small parser, never eval: typed text is not run as code.
// evaluate("2*(3+4)") → 14; anything else (words, a bare number, 1/0) → null.
function evaluate(text) {
    const s = text.replace(/\s+/g, "").replace(/,/g, ".").replace(/[x×]/g, "*").replace(/÷/g, "/");
    if (!/^[0-9.+\-*/^()]+$/.test(s) || !/[0-9]/.test(s) || !/[+\-*/^]/.test(s.replace(/^-/, "")))
        return null;
    let i = 0;

    function number() {
        const m = /^\d*\.?\d+|^\d+\./.exec(s.slice(i));
        if (!m)
            throw "number expected";
        i += m[0].length;
        return parseFloat(m[0]);
    }

    function primary() {
        if (s[i] === "(") {
            i++;
            const v = sum();
            if (s[i++] !== ")")
                throw "unclosed bracket";
            return v;
        }
        return number();
    }

    // -2^2 = -4 (the power binds first), 2^-1 = 0.5, and 2^3^2 = 2^9
    function unary() {
        if (s[i] === "-" || s[i] === "+")
            return s[i++] === "-" ? -unary() : unary();
        return power();
    }

    function power() {
        const base = primary();
        if (s[i] !== "^")
            return base;
        i++;
        return Math.pow(base, unary());
    }

    function product() {
        let v = unary();
        while (s[i] === "*" || s[i] === "/")
            v = s[i++] === "*" ? v * unary() : v / unary();
        return v;
    }

    function sum() {
        let v = product();
        while (s[i] === "+" || s[i] === "-")
            v = s[i++] === "+" ? v + product() : v - product();
        return v;
    }

    try {
        const v = sum();
        return i === s.length && isFinite(v) ? v : null;
    } catch (e) {
        return null;
    }
}

// rounded to 12 significant digits, which hides float noise: 0.1+0.2 → "0.3", 1/3 → "0.333333333333"
function format(v) {
    return String(parseFloat(v.toPrecision(12)));
}
