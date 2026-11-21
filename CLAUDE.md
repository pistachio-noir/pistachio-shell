# Pistachio Noir Shell

@AGENTS.md

Everything in `AGENTS.md` (imported above) applies to Claude Code: the project, how to run and test it, the owner's workflow and preferences, the decisions, style rules, working rules and gotchas. It is the one copy shared with Codex and other agents, so **put shared rules and new decisions there, not here**. This file holds only what is specific to Claude Code. (Since 21 November 2026; before that, this file held everything and imported `CLAUDE-HANDOFF.md`.)

## Claude Code extras

- **`style-reviewer`** (`.claude/agents/style-reviewer.md`): reviews a diff against the style and working rules. Use it after a feature is built and before reporting; it reads only and never edits.
- **`quickshell-docs`** (`.claude/agents/quickshell-docs.md`): checks Quickshell 0.3.2 types, properties, signals and functions against the official docs (AGENTS.md, "Verify before coding"). Give it a list of names.
- **`/wrap-up`** (`.claude/commands/wrap-up.md`): runs both agents on the work since the last commit and summarises it. Report only: it fixes nothing and never commits.
- Spawn other subagents only when the owner asks; do the work inline otherwise.
