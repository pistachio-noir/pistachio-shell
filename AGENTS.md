# Handoff for coding agents (Codex and others)

Written by Claude Code on 10 November 2026; current task and handoff updated by Codex on 18 November 2026.

## 1. Read first, in this order

1. `CLAUDE.md` — the project's rules. **Everything in it applies to you too**: the decisions that must not be reopened, the style rules (colours only from `Theme.qml`, pistachio only for active state, Manrope/JetBrains Mono, radii 28/20/round), the working rules (verify every Quickshell type against https://quickshell.org/docs/v0.3.2/, live-reload quirks, run `qs -c pistachio` and read its log), and the long "Gotchas" list. Skim the gotchas before writing QML; most were learnt the hard way.
2. `CLAUDE-HANDOFF.md` — read the current-state section for recent work, checks and remaining hand tests; historical sections are context.
3. `README.md` — install, IPC commands (`psc <target> <function>`), keybinds. Keep it in step with anything you add.
4. `docs/plan.md` — architecture, folder layout, theme tokens, motion.

## 2. What the project is

Pistachio Noir Shell: a Quickshell 0.3.2 (QML) desktop shell for Hyprland, single monitor, Arch desktop PC. Everything in `src/` (linked to `~/.config/quickshell/pistachio`):

- `services/` — singletons; the **only** places that touch system data (processes, files, D-Bus). UI files only read from them.
- `bar/`, `panels/`, `popups/`, `launcher/`, `lock/` — UI.
- `components/` — shared pieces (`Reveal.qml` for open/close fades: set a window's `open`, never `visible`; `Shadow.qml`; `Chip.qml`; `Icons.qml`).
- `Theme.qml` — all colours, sizes, shadows, motion durations (ease-out, 120 ms hover, ~200 ms fades).
- `tests/` — `js.sh`, `services.sh`, etc. (see CLAUDE.md rule 9).

Running: `pgrep -ax qs` first (the owner may already run it; never start a second copy). `psc restart`, `qs log -c pistachio`. Live reload sometimes misses edits; check the "Configuration Loaded" count went up.

## 3. Owner's working preferences

- "Generate a commit message" means **text in chat only**: never `git add`/`git commit` unless told to commit.
- Never edit `~/.config/hypr/*` without explicit permission.
- Don't build features the owner hasn't approved. Ask when a choice is genuinely theirs.
- Daily checklists live in `todos/TODO_DD-MM-YY.md` (marks `+ x - ?`); add a section for things the owner must test by hand.
- Mockup sample text in the boards is fake; wire real data.

## 3b. How the owner and Claude worked together

**You MUST work exactly this way.** This is not a suggestion: the owner requires any agent on this repo to follow the workflow below, the same way Claude and the owner worked together. If something here conflicts with your own defaults, this wins.

**The loop for a feature**
1. **Idea → talk first.** The owner brings an idea, a feature list (`todos/FEATURES_DD-MM-YY.md`, items marked build / discuss / later / ditched) or a board. For anything new, propose how it would work in a few short points (where it lives, keys/IPC, settings, what's out of scope) and ask only the questions that are genuinely the owner's call. Give a recommendation, not a survey of options. Wait for "build" / "go".
2. **Design comes from boards.** If the owner made boards (`design/*.html`), they are the truth: match them. If there are none, lay it out yourself under the Pistachio Noir rules and say so.
3. **Verify before coding.** Check every Quickshell type/property you use against the 0.3.2 docs. Check CLI flags with `--help` and system facts on the live machine (`pw-dump`, `hyprctl`, `busctl`…), never from memory or a binary's strings.
4. **Build in small steps**, services first, then UI. Follow existing patterns in neighbouring files; reuse components.
5. **Test it yourself, for real.** Run the shell, read `qs log -c pistachio` for errors, drive it through IPC (`psc …` / `qs ipc call …`), take screenshots with `grim` and compare them with the boards. Run the relevant `tests/*.sh`. Clean up any test windows, test hooks or changed settings afterwards, and confirm the reload that removes them actually happened.
6. **Write things down** in the same session: README (commands, keys, requirements), CLAUDE.md (new services in rule 4, new decisions under "Decisions" with the date and "owner's call", anything surprising under "Gotchas" with what was checked), and the day's `todos/TODO_DD-MM-YY.md`: what's built, and a list of things the owner must test by hand.
7. **Report honestly.** Short summary: what was built, what you tested and how, what is *not* tested yet, anything that failed. Never say "works" without having run it.
8. **Commit message as text.** When asked for one, write it in chat (style of the log: `new: …`, `fix: …`, lowercase, one line plus a short body if needed). The owner commits and pushes themself.

**Bugs the owner reports** (often from a TODO file as `[ BUGn ]`, explained under `# NOTES FOR BUGS → ### Bug n`): reproduce first, find the actual cause, fix it, test it, then note the cause in CLAUDE.md's gotchas if it could bite again.

**Style of talking:** plain, short, no fluff. Dates written out (e.g. 9 November 2026). The owner decides; you advise. Don't reopen decisions in CLAUDE.md. Don't expand scope; if you notice something worth doing, mention it in one line and let the owner pick.

**Safety habits:** check `pgrep -ax qs` before starting a shell; never toggle Ethernet; don't disconnect Bluetooth devices the owner is using; at most one wrong password in a row for polkit/lock tests (pam_faillock); keep a TTY in mind when testing the lock; ask before stopping plasmashell or other system services.

## 4. Current task and state

There is no further approved implementation task as of 18 November 2026. Respond to the owner's current request; otherwise wait for their next direction. Pistachio Lens was built; its original 9 November plan is historical and later decisions in `CLAUDE.md` supersede it. Do not rebuild it from that plan.

Recent work includes the phone Pomodoro preview, fun About page, interactive desktop cat and project Git status. Read the current-state section of `CLAUDE-HANDOFF.md` and `todos/TODO_17-11-26.md` for details and outstanding hand checks. Check the branch and working tree yourself: on 18 November the branch was `experimental`, HEAD `6acd2f6`, with substantial intentional uncommitted work. Preserve it; never stage or commit unless the owner explicitly asks. Never work on main.

## 5. Other open threads (don't start without asking)

- Restyling the headphones toast.
- GNOME search providers in the launcher (offered, undecided).
- Some items in `todos/TODO_09-11-26.md` still need the owner's hand test (clock right-click menu, alarm ringing at the minute).
