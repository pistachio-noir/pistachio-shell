---
description: Wrap up the work since the last commit - runs the style-reviewer and quickshell-docs agents, then summarises everything done
---

Wrap up the work since the last commit (or the part the owner names here: $ARGUMENTS). Report only: fix nothing and never commit as part of this.

1. **Gather what changed.** `git status --short`, `git diff --stat HEAD`, the diff of tracked files, and the untracked files under `src/`, `tests/`, `docs/`, `.claude/`, `README.md`, `AGENTS.md` and `CLAUDE.md` (the day's TODO is `todos/TODO_<DD-MM-YY>.md`, local and ignored by git). If a `refs/snapshots/*` ref exists, note which changes came after it.

2. **Run both agents at once**, in one message:
   - `style-reviewer`: give it the list of changed and new files, and tell it to read the diff itself.
   - `quickshell-docs`: give it every Quickshell type, property, signal and function the changed QML starts using (new imports, new types, properties of Quickshell types not used in the code before). If there are none, don't start it, and say so in the summary.

3. **Summarise for the owner**, in plain English, as in AGENTS.md and the todo files:
   - **Built or changed:** grouped by feature, not by file, a line or two each, and whether the owner has tested it (their marks in `todos/TODO_<today as DD-MM-YY>.md`).
   - **Style review:** its findings, most serious first, with `file:line`. Say which ones you agree with and why you'd leave any.
   - **Docs check:** anything that doesn't exist, or behaves differently from how the code uses it.
   - **Tests:** which ran in this session and passed (`tests/js.sh`, `compositor.sh`, `services.sh`, `notifications.sh`, the agent tests), and which didn't run. Only count a test whose passing output you saw.
   - **Left to do:** open checklist items, loose ends, and what's uncommitted.

4. End by asking whether to fix the findings.
