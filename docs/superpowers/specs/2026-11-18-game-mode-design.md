# Game mode — short design

18 November 2026. Owner's call: build it, opt-in in Settings → Experimental for now.

## Intent
While a game is fullscreen, the shell gets out of the way: no toasts or sounds, and Hyprland's animations and blur off so nothing costs frames. Everything goes back when the game stops being in front.

## Behaviour
- Settings → Experimental → **Game mode** switch, off by default; saved, in the page reset, in export/import and the settings search.
- With the switch on, game mode is active while the focused window is fullscreen and is a game. Off again 2 s after that stops (alt-tabbing out briefly doesn't flip it).
- A game is: a window whose class is `steam_app_<digits>` (Steam, including Proton), Sober (`org.vinegarhq.Sober`), or `gamescope`. (Claude's call; to check with a real game running — native Steam games may use their own class, which would then need adding.)
- **Extra game windows** (owner's request): a row under the switch in Experimental, edited through the Settings text dialog like Weather location. A comma-separated list of window classes, matched case-insensitively and exactly against the window's class, added to the built-in ones. Validated before Save: up to 20 entries, each 1–100 characters of letters, digits, `.`, `_` and `-` (Claude's call); an empty field clears the list. Saved, reset, exported (as a list) and searchable. The row shows the current list, or "Steam, Sober and gamescope only".
- While active: notifications stay quiet (like Do not disturb, without changing the saved Do not disturb setting; they still reach the centre), and Hyprland `animations:enabled` and `decoration:blur:enabled` are set to false at runtime. The values before are read first and put back after; a config reload while active re-applies the game values. Config files are never edited.
- Gaps and borders are left alone: a fullscreen window has none anyway, and Zen already owns them.
- No tile, launcher switch or IPC for now (Claude's call, to keep the experiment small); easy to add later.

## Approaches
1. **Inside existing services (picked):** `FocusMode`-style state in a small `GameMode` service; Compositor gets `gameLayout(on)` like `zenLayout`; `Notifs.quiet` gains `|| GameMode.active`. Matches how Zen works, smallest change.
2. A separate helper process watching Hyprland: more moving parts, no gain — Compositor already has the focused window and fullscreen state.
3. Hyprland window rules (`immediate`, per-class): would need editing the owner's config, which is off limits.

## Builder notes
- Saved prior values in Store (like `zenGaps`) so a shell restart mid-game still restores them.
- Tests: isolated QML fixture with a stand-in Compositor (fullscreen game window → active, other fullscreen → not, delay off, switch off ends it at once); prefs round trip; settings fixture finds the switch. Real game is an owner hand check.
