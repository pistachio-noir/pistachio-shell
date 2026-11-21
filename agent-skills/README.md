# Agent skills

Skills for coding agents working on this repo (Codex, Claude Code and others that read the Agent Skills format: a folder with a `SKILL.md` whose front matter has a `name` and a `description`). They add how-to knowledge on top of `AGENTS.md`, which every agent reads first.

| Skill | Use it for |
|:--|:--|
| [`pistachio-shell-ui`](pistachio-shell-ui/SKILL.md) | Designing and building anything the user sees in the shell, in Classic and TUI |

To use one, point your agent at the folder, or link it where your agent looks for skills, for example `ln -s "$PWD/agent-skills/pistachio-shell-ui" .claude/skills/` for Claude Code, or your Codex skills folder for Codex.
