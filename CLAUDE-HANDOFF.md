# Handoff for Claude Code

Written by Codex on 10 November 2026. The owner is switching back to Claude Code.

## 1. Read first, in this order

1. `CLAUDE.md` (all project rules apply), then `AGENTS.md` for the owner’s workflow and safety habits.
2. `README.md`, `docs/plan.md`, and `todos/TODO_10-11-26.md` for usage, architecture, validation and hand tests.

## 2. What the project is

Pistachio Noir Shell is a Quickshell 0.3.2/QML Hyprland desktop shell. `src/services/` and `Compositor.qml` own system access; `src/settings/`, `launcher/`, `panels/`, `popups/`, `bar/` and `components/` are UI. `Theme.qml` owns colours, radii and timing. `src/` is linked to `~/.config/quickshell/pistachio`. Before starting a shell check `pgrep -ax qs`; the owner normally has one running. Use `psc` / `qs -c pistachio ipc call …`, then `qs log -c pistachio` and verify a new Configuration Loaded entry. Relevant tests: `sh tests/settings.sh`, `sh tests/js.sh`, `sh tests/lens.sh`, and `bash tests/compositor.sh` for compositor changes.

## 3. Owner's working preferences

The owner commits and pushes. Give commit messages as chat text, lowercase `new: …` / `fix: …`; never add or commit unless explicitly asked. Never edit `~/.config/hypr/*` without permission. Daily checklists and hand tests live in `todos/TODO_DD-MM-YY.md`. Design boards are the source of truth; their sample data is fake.

## 3b. How the owner and Codex worked together

**You MUST work exactly this way.** The owner requires this workflow.

1. Talk through new features first, recommend a direction, ask only the owner’s calls, and wait for build/go. Match approved boards; otherwise say the layout is yours.
2. Before coding verify Quickshell 0.3.2 types/properties, CLI flags using `--help`, and system facts on the actual machine. Build in small steps, services first.
3. Reproduce bugs, identify their cause, fix and test. Test for real: running shell, logs, IPC, grim screenshots against boards, relevant test scripts. Clean test hooks/windows/settings and verify the cleanup reload.
4. In the same session update README, decisions/gotchas in CLAUDE.md, and today’s TODO with hand tests. Report what was tested and what remains; never claim untested behaviour works. Give commit messages as text only.
5. Be brief and plain. Don’t expand scope or reopen owner decisions. Never toggle Ethernet or disconnect Bluetooth devices in use; ask before stopping system services; use at most one wrong password at a time and keep a TTY available for lock tests.

## 4. Your task: wait for the owner

The approved Settings app redesign is implemented; no new feature is approved yet. Start by reviewing the owner’s hand tests in `todos/TODO_10-11-26.md` and ask what they want next. Boards: `design/settings/01–24`. Settings opens via `psc settings open`, launcher System, or quick settings; its detailed pages use existing services. Lens remains available through `psc screenshot lens`, with independent Claude/Codex settings and optional fallback. No new Hyprland config edit was made.

The latest owner request was sidebar spacing and subtle matching animations: 4 px between navigation entries, 120 ms selection icon/text colour, a 200 ms selected-pill scale and a 200 ms page fade using existing Theme easing. `tests/settings.sh` checks both selected-pill and page-fade progress, plus the existing controls. Ask the owner to visually check it. They asked for a commit message, not a commit.

## 5. Other open threads (don't start without asking)

- Owner hand tests in today’s TODO: real Bluetooth pairing, audio device switching, LocalSend transfer, removable-drive eject, settings motion and navigation.
- Headphones toast restyle and GNOME search providers remain undecided/out of scope.
- Previous `tests/services.sh` rerun failed “default output untouched”; cause not established. It was not repeated while headphones were in use. Earlier run had passed.

## 6. State right now

Last commit `51eef08` contains Lens and the settings boards. The Settings app, tests, documentation and current polish are uncommitted; inspect `git status --short` before editing and preserve the owner’s work. `sh tests/settings.sh`, `sh tests/js.sh`, `sh tests/lens.sh`, and `bash tests/compositor.sh` passed during the redesign; latest Settings suite passed after the sidebar change. Live Settings pages, floating border (local border 0 and radius 28), launcher routing and grim screenshots were checked; existing Qt Wayland text-input warnings remain. Only the main shell was left running; no new production test hooks. Real pairing, transfers and ejection were not exercised.
