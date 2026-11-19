//! `psc files`: the launcher's "/" search through the home folder (services/Files.qml). Python's
//! files.py until 19 November 2026; same protocol and the same ranking.
//!
//! As it starts it lists the home folder, skipping hidden entries, node_modules, __pycache__ and the
//! contents of cache folders (those holding a CACHEDIR.TAG, such as Cargo's target). Then it answers
//! queries, a JSON line each way:
//!   out  {"event": "ready", "count": 22343}
//!   in   {"query": "shell qml"}
//!   out  {"query": "shell qml", "results": [["f", "Projects/x/shell.qml"], ...]}   best first, at most 60
//! Matching mirrors launcher/fuzzy.js: case and accents don't matter ("zolty" finds "Żółty"), a run of
//! the query's letters beats scattered ones, and scattered ones count only within three characters per
//! letter. A query with a "/" is matched against the path from the home folder, others the name. It
//! exits when stdin closes, so it never outlives the shell.
use serde_json::{json, Value};
use std::io::{BufRead, Write};
use std::path::Path;
use unicode_normalization::UnicodeNormalization;

const LIMIT: usize = 300_000;
const RESULTS: usize = 60;

/// Lower case without accents, one character for one (as fold() in fuzzy.js).
pub fn fold(s: &str) -> String {
    if s.is_ascii() {
        return s.to_ascii_lowercase();
    }
    s.chars().map(|c| {
        let first = c.to_string().nfd().next().unwrap_or(c);
        let lower: String = first.to_lowercase().collect();
        let mut it = lower.chars();
        match (it.next(), it.next()) {
            (Some(one), None) => match one { 'ł' => 'l', 'ø' => 'o', 'đ' => 'd', 'ħ' => 'h', 'ı' => 'i', 'ŧ' => 't', o => o },
            _ => c,
        }
    }).collect()
}

pub struct Entry { kind: char, path: String, name: String, folded: String }

pub fn scan(home: &Path) -> Vec<Entry> {
    let mut entries = vec![];
    let mut stack = vec![String::new()];
    while let Some(rel) = stack.pop() {
        if entries.len() >= LIMIT { break; }
        let Ok(dir) = std::fs::read_dir(if rel.is_empty() { home.to_path_buf() } else { home.join(&rel) }) else { continue };
        let children: Vec<_> = dir.flatten().filter(|e| !e.file_name().to_string_lossy().starts_with('.')).collect();
        if children.iter().any(|e| e.file_name() == "CACHEDIR.TAG") {
            continue; // a cache: the folder itself is listed, not what's in it
        }
        for e in children {
            let name = e.file_name().to_string_lossy().into_owned();
            let path = if rel.is_empty() { name.clone() } else { format!("{rel}/{name}") };
            let Ok(kind) = e.file_type() else { continue };
            let folder = kind.is_dir();
            if folder && (name == "node_modules" || name == "__pycache__") { continue; }
            entries.push(Entry { kind: if folder { 'd' } else { 'f' }, folded: fold(&path), name: fold(&name), path: path.clone() });
            if folder { stack.push(path); }
        }
    }
    entries
}

/// match() in fuzzy.js, without the indices: a score, or None.
pub fn score(q: &str, t: &str) -> Option<i64> {
    if let Some(byte) = t.find(q) {
        let at = t[..byte].chars().count() as i64;
        let word = at == 0 || t[..byte].chars().last().is_some_and(|c| c.is_whitespace() || "-_./".contains(c));
        return Some(1000 + if at == 0 { 300 } else { 0 } + if word { 200 } else { 0 } - at);
    }
    let q: Vec<char> = q.chars().collect();
    let (mut k, mut first, mut last) = (0usize, 0i64, 0i64);
    for (i, c) in t.chars().enumerate() {
        if c == q[k] {
            if k == 0 { first = i as i64; }
            last = i as i64;
            k += 1;
            if k == q.len() { break; }
        }
    }
    if k < q.len() || last - first > 3 * q.len() as i64 { return None; }
    Some(500 - (last - first) - first)
}

pub fn search(entries: &[Entry], query: &str) -> Vec<Value> {
    let q = fold(query);
    if q.is_empty() { return vec![]; }
    let by_path = q.contains('/');
    let mut hits: Vec<(i64, usize, usize, char, &str)> = entries.iter().filter_map(|e| {
        let text = if by_path { &e.folded } else { &e.name };
        score(&q, text).map(|s| (-s, text.chars().count(), e.path.chars().count(), e.kind, e.path.as_str()))
    }).collect();
    hits.sort();
    hits.into_iter().take(RESULTS).map(|h| json!([h.3.to_string(), h.4])).collect()
}

pub fn main(_args: &[String]) -> i32 {
    let home = std::path::PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
    let entries = scan(&home);
    let send = |v: Value| { let mut o = std::io::stdout().lock(); let _ = writeln!(o, "{v}"); let _ = o.flush(); };
    send(json!({"event": "ready", "count": entries.len()}));
    for line in std::io::stdin().lock().lines().map_while(Result::ok) {
        let Some(query) = serde_json::from_str::<Value>(&line).ok().and_then(|v| v.get("query").cloned()).filter(Value::is_string) else { continue };
        send(json!({"query": query, "results": search(&entries, query.as_str().unwrap())}));
    }
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn folding_and_scores_match_fuzzy_js() {
        assert_eq!(fold("Żółty Ł"), "zolty l");
        assert_eq!(fold("README.md"), "readme.md");
        assert_eq!(score("shell", "shell.qml"), Some(1500));
        assert_eq!(score("qml", "shell.qml"), Some(1000 + 200 - 6), "a word start after a dot");
        assert_eq!(score("sq", "shell.qml"), Some(494), "scattered within three per letter");
        assert_eq!(score("sm", "shell.qml"), None, "scattered more than three per letter");
        assert_eq!(score("shq", "sh.q"), Some(500 - 3));
        assert_eq!(score("ż", "żółw"), Some(1500), "a non-ASCII run, indices in characters");
    }
}
