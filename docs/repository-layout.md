# Repository layout

```
pistachio-shell/
├─ install.sh      links src/ into place, builds rust/ and installs psc and the helpers into ~/.local/bin
├─ README.md       the public front page: what it is, getting started, links to the pages in docs/
├─ src/            the shell: shell.qml, Theme.qml, and bar/ panels/ popups/ launcher/ settings/ setup/ (first-run setup) lock/ components/ services/
├─ rust/           psc (the control command and the shell's on-demand helpers) and the helpers that run beside the shell all day: pistachio-auth (polkit agent), pistachio-devices (pairing agent, USB drives), pistachio-localsend
├─ legacy/psc      the old shell-script psc, a fallback when the Rust one can't be built
├─ integrations/   what the shell sets up in other programs, and a login screen: kitty/ (the two Kitty colour files), neovim/ (colourscheme and shared-theme loader), vscode/ (the Pistachio Noir theme extension psc installs), sddm/ (the login screen theme, see integrations/sddm/README.md) and hypridle.conf (idle locking)
├─ tools/          make-emoji.py (rebuilds the launcher's emoji list) and make-sound.py (rebuilds the notification sound)
├─ agent-skills/   skills for coding agents (Agent Skills format): pistachio-shell-ui, how to design and build the shell's UI
├─ tests/          checks of the shell and its helpers; tests/README.md says what each one covers ("Running and testing it" in AGENTS.md)
├─ docs/           README.LLM.md (the full feature reference, every feature, key and setting; the README until 21 November 2026), images/, this and the other pages (requirements, install, ipc-and-keybinds, frosted-panels, lock-screen, login-screen, troubleshooting, theming), plus plan.md (architecture, components, build phases), decisions.md, gotchas.md, audio-bluetooth.md, compositors.md and superpowers/ (the plans and specs behind the larger changes)
├─ AGENTS.md       the guide for every coding agent (Codex, Claude Code…): project, workflow, decisions, rules, gotchas
└─ CLAUDE.md       imports AGENTS.md; only Claude Code's extras (its agents and /wrap-up)
```

The design boards (one HTML board per screen, the visual source of truth) are not in this repo since 21 November 2026: they live in the separate `pistachio-shell-design` repo (checked out beside it at `~/Desktop/pistachio/pistachio-shell-design/`; open its `index.html`). Paths like `pistachio-shell-design/Overview.html` in comments and docs mean files there.
