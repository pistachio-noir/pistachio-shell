# Theming integration — design

19 November 2026. Owner's call: the shell sets apps up itself to follow Colours (Pistachio Noir / Noir), behind one switch, on by default; a user's own app themes are never overwritten without asking. Python now (`services/shared-theme.py`), moved into the Rust CLI when that is built.

## Intent
The owner's desktop should keep following Colours everywhere, as now, and a fresh install (or someone else's machine) should get the same without hand setup. Someone with their own Kitty or Neovim theme must be able to keep it.

## Behaviour
- Settings → Appearance → Colours group: **Theming integration** switch, **on by default** (`Store.saved.themingIntegration`, missing = on), plus one row per app with its state: *following*, *your own theme* (with Use Pistachio), *not installed*, *couldn't set up* (with the reason). Saved, in the page reset, export/import and search.
- While on, for each app (Kitty, Neovim for now):
  - already wired up: nothing to do (the owner's machine today);
  - not wired up and no theme of its own: the shell wires it up quietly;
  - its own theme found and no answer stored: the Settings dialog asks — "**Kitty has its own theme.** Use Pistachio Noir and Noir? Your config is backed up first." [Keep mine] [Use Pistachio]. The answer is stored per app (`Store.saved.themingKeep`, a list of app ids); "Keep mine" means never touched until the owner presses Use Pistachio on its row. The dialog opens when Settings is opened, not as a popup over the desktop (Claude's call: no interruption at login).
- Off: the shell removes its own lines from each wired app, so the app's own settings (or its default) apply again; apps the user kept were never touched. Text, FM and Notes keep following Colours either way: they are the suite's own apps, with no user theme to protect (Claude's call).
- Colours still switch live, as now (shared-theme file, Kitty include + SIGUSR1, Neovim's watcher).

## How each app is wired (Claude's calls)
- **Kitty** (`~/.config/kitty/kitty.conf`): wired = a line `include pistachio-shared.conf`. Own theme = an `include` of another file, or `foreground`/`background`/`color0–15` lines. Setup: copy the two theme files (`pistachio-noir.conf`, `noir.conf`, from `extras/`) only where missing, append the marked line `include pistachio-shared.conf  # pistachio-shell theming` at the end (so it wins over earlier lines), write `pistachio-shared.conf`, reload Kitty. Undo: remove that one line and `pistachio-shared.conf`; the user's own lines are untouched and apply again.
- **Neovim** (`~/.config/nvim/init.lua`): wired = `require("pistachio-shared").setup()` in it. Own theme = a `colorscheme` other than `pistachio-noir`. Setup: copy `colors/pistachio-noir.lua` and `lua/pistachio-shared.lua` (back up any different existing copy), append the marked line `pcall(function() require("pistachio-shared").setup() end) -- pistachio-shell theming`. Undo: remove the marked line; a line put in by the earlier hand install becomes `vim.cmd("colorscheme pistachio-noir")` again. No `init.lua` (e.g. `init.vim` only) → *couldn't set up*.
- Before any change the file is copied to `<file>.pistachio-bak-<date>`; writes are atomic; a file that changed between reading and writing is left alone and reported.

## Approaches
1. **Extend `shared-theme.py` (picked):** one table of app entries (`check`, `setup`, `undo`), JSON lines back to a new `services/AppTheming.qml` that owns the switch, states and conflicts. Runs only on start, on a Colours change and on the switch. Testable in a temporary config folder.
2. Rust, inside the future CLI: delayed until that project is designed; this moves there later.
3. One shell script per app: hard to report state and conflicts to Settings, hard to test.

## Out of scope now
GTK, Qt, browser and other apps (each needs its own theme files; to be talked through separately). Undo of the files copied in (theme files stay; harmless and tiny).

## Tests
Helper in a temporary `XDG_CONFIG_HOME`: fresh Kitty/Neovim → set up; already wired → unchanged; own theme → reported, untouched; Use Pistachio → set up with backup; off → own lines restored byte for byte; legacy Neovim line restored; init.vim-only → couldn't set up; Colours switch still writes the include. Settings fixture: switch default on, rows' states, conflict dialog Keep/Use. Live: the owner's machine must stay "following" for both, unchanged.
