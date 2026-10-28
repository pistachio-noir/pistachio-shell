#!/usr/bin/env python3
"""Finds files and folders in the home folder for the launcher's "/" search; services/Files.qml runs it.

As it starts it lists the home folder, skipping hidden entries, node_modules, __pycache__ and the
contents of cache folders (those holding a CACHEDIR.TAG, such as Cargo's target). Then it answers
queries, a JSON line each way:

  out  {"event": "ready", "count": 22343}            the folder is listed
  in   {"query": "shell qml"}
  out  {"query": "shell qml", "results": [["f", "Projects/x/shell.qml"], ...]}    best first, at most 60

Matching mirrors launcher/fuzzy.js, which the launcher then runs on these few for the highlights:
case and accents don't matter ("zolty" finds "Żółty"), a run of the query's letters beats scattered
ones, and scattered ones count only if they span at most three characters per letter. A query with
a "/" is matched against the path from the home folder, others against the name.

It exits when stdin closes, so it never outlives the shell.
"""

import json
import os
import re
import sys
import unicodedata

LIMIT = 300000  # entries listed at most
RESULTS = 60
SKIP = {"node_modules", "__pycache__"}
PLAIN = {"ł": "l", "ø": "o", "đ": "d", "ħ": "h", "ı": "i", "ŧ": "t"}


def fold(s):
    """Lower case without accents, one character for one (as fold() in fuzzy.js)."""
    if s.isascii():
        return s.lower()
    out = []
    for c in s:
        base = unicodedata.normalize("NFD", c)[0].lower()
        out.append(PLAIN.get(base, base if len(base) == 1 else c))
    return "".join(out)


def scan(home):
    """[(kind, path from home, folded name, folded path)], folders first in each folder."""
    entries = []
    stack = [""]
    while stack and len(entries) < LIMIT:
        rel = stack.pop()
        try:
            with os.scandir(os.path.join(home, rel)) as it:
                children = [e for e in it if not e.name.startswith(".")]
        except OSError:
            continue
        if any(e.name == "CACHEDIR.TAG" for e in children):
            continue  # a cache: the folder itself is listed, not what's in it
        for e in children:
            path = rel + "/" + e.name if rel else e.name
            try:
                folder = e.is_dir(follow_symlinks=False)
            except OSError:
                continue
            if folder and e.name in SKIP:
                continue
            entries.append(("d" if folder else "f", path, fold(e.name), fold(path)))
            if folder:
                stack.append(path)
    return entries


def score(q, t):
    """match() in fuzzy.js, without the indices: a score, or None."""
    at = t.find(q)
    if at >= 0:
        word = at == 0 or t[at - 1].isspace() or t[at - 1] in "-_./"
        return 1000 + (300 if at == 0 else 0) + (200 if word else 0) - at
    k = first = last = 0
    for i, c in enumerate(t):
        if c == q[k]:
            if k == 0:
                first = i
            last = i
            k += 1
            if k == len(q):
                break
    if k < len(q) or last - first > 3 * len(q):
        return None
    return 500 - (last - first) - first


def search(entries, query):
    q = fold(query)
    if not q:
        return []
    by_path = "/" in q
    letters = re.compile(".*?".join(map(re.escape, q)))  # the letters in order, quickly
    hits = []
    for kind, path, name, folded in entries:
        text = folded if by_path else name
        if letters.search(text):
            s = score(q, text)
            if s is not None:
                hits.append((-s, len(text), len(path), kind, path))
    hits.sort()
    return [[h[3], h[4]] for h in hits[:RESULTS]]


def send(message):
    print(json.dumps(message, ensure_ascii=False), flush=True)


def main():
    entries = scan(os.path.expanduser("~"))
    send({"event": "ready", "count": len(entries)})
    for line in iter(sys.stdin.readline, ""):
        try:
            query = json.loads(line)["query"]
        except (ValueError, KeyError, TypeError):
            continue
        send({"query": query, "results": search(entries, query)})


if __name__ == "__main__":
    main()
