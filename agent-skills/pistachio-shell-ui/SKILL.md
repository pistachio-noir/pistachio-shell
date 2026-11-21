---
name: pistachio-shell-ui
description: Design and build user interface for the Pistachio Noir shell (Quickshell 0.3.2 QML on Hyprland), in both its Classic and TUI styles. Use whenever you add or change anything the user sees in the shell (a panel, popup, toast, card, settings row, launcher row, bar item) or sketch a new screen for it.
---

# Building UI for the Pistachio Noir shell

The shell's look is settled and consistent; new UI must feel like it was always there. Read `AGENTS.md` first (the owner's workflow, style rules and gotchas apply here too). This skill is the how-to for the visible parts. Component and token lists: [references/components.md](references/components.md).

## 1. Before you draw anything

1. **Talk first.** Describe the screen in a few short points (where it opens, what it shows, how it closes, its keys) and wait for the owner's "go".
2. **Find the board.** The boards are the visual source of truth: the separate repo at `~/Desktop/pistachio/pistachio-shell-design/` (open `index.html`; TUI boards in `TUI/`, Settings in `settings/`). If a board exists, match it: sizes, spacing, wording, states. Its sample content is fake: wire real data.
3. **No board?** Build from the existing components and tokens, look at the nearest existing screen and copy its structure, and say in your report that there was no board. For a large new screen, offer to sketch an HTML board in the design repo first, in the same style, for the owner to approve.
4. **Find the data.** UI never touches the system. If the data isn't in a service (`src/services/`), add it to one (or a new one) first; the UI only binds to it.

## 2. The look

- **Surfaces:** `Theme.bg` (the desktop-dark base), `bgAlt` (panels, cards), `overlay` / `overlay2` (controls, hovered controls), `Theme.surface` for panel backgrounds (it turns see-through when frosted panels are on). Never a hex value outside `Theme.qml`.
- **Text:** `textBright` for titles, `text` for body, `subtext` for secondary lines. `muted` is only ~3.4:1 on `bg`: never for small text.
- **Pistachio means "active", and only that:** the current workspace, a switch that is on, slider fills, the cursor, the selected row's chip (with `bg`-coloured text). No pistachio borders, no large pistachio areas, no pistachio decoration.
- **The other colours have jobs:** terracotta for errors, danger and low battery; gold, clay, teal, sageBlue and lavender as tints for kinds of things (file types, weather, recording in clay). Noir (`Theme.noir`) swaps the palette for greys with one red; it's automatic as long as you only use tokens.
- **Shapes:** panels `Theme.panelRadius` (28), chips and tiles `chipRadius`/`tileRadius` (20), round icon buttons. Everything soft and pill-like in Classic.
- **Type:** Manrope (`Theme.fontUi`, weights 500–800) for UI; JetBrains Mono (`Theme.fontMono`) for code-like text, paths and commands; tabular figures for numbers that change (clocks, percentages).
- **Depth:** panels and popups carry the boards' drop shadows (`components/Shadow.qml`, kinds `Theme.shadowPanel`, `shadowSmall`, `shadowModal`). The bar and tray pill stay flat.
- **Motion:** one curve (`Theme.easing`), `hoverDuration` (120 ms) for hover, `motionDuration` (~200 ms) for fades and slides. Nothing bounces.
- **Words:** short, plain and specific ("Couldn't eject: Firefox is using it", not "An error occurred"). Sentence case. A little warmth is welcome; jokes belong to the cat and the About page.

## 3. Classic and TUI

Every screen exists in both styles; `Theme.tui` says which is on, and switching is live. Check both.

| | Classic | TUI |
|:--|:--|:--|
| Shape | rounded pills and panels | square: radius 0 everywhere |
| Font | Manrope | `Theme.fontTui` (JetBrains Mono Nerd Font) at `tuiTextSize`, rows of `tuiLineHeight` |
| Panel | `bgAlt`/`surface`, shadow | `tuiSurface` with a 1 px `tuiBorder`; title as a tab across the border (`PanelFrame` with `title`) |
| Buttons | round icon buttons, pills | `[k] label` brackets (`TuiBracket`), the key bright, pistachio when on |
| Shadows | yes | none (`Shadow` hides itself) |
| Motion | ~200 ms | ~80 ms |
| Bar | floating pill at the bottom | 35 px strip across the top (`tuiBarHeight`); popups place themselves from it |

Small differences can live in one file (`radius: Theme.tui ? 0 : Theme.panelRadius`). When the layouts really differ, make a `Tui…` sibling file (like `TuiQuickChat.qml` beside `QuickChat.qml`) and pick one with a `Loader`. TUI boards are in the design repo's `TUI/` folder.

## 4. Building it in QML

**Where things go:** `src/bar/`, `src/panels/` (bigger surfaces), `src/popups/` (transient windows), `src/settings/`, `src/launcher/`, `src/lock/`, shared parts in `src/components/`. A new window is added to `src/shell.qml`.

**A popup's skeleton** (from `popups/PhonePreview.qml`):

```qml
import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland
import QtQuick

Scope {
    PanelWindow {
        id: popup
        visible: reveal.shown                        // stays up until the fade-out ends
        Reveal { id: reveal; open: SomeService.open } // open/close through Reveal: set `open`, never `visible`
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay        // Top is below fullscreen windows
        WlrLayershell.namespace: "pistachio-panel"   // the frosted-panel blur rule matches this
        WlrLayershell.keyboardFocus: SomeService.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        MouseArea { anchors.fill: parent; onClicked: SomeService.open = false }   // a click beside it closes it

        PanelFrame {
            id: card
            opacity: reveal.progress
            anchors.centerIn: parent
            width: 360; height: 200
            title: Theme.tui ? "my panel" : ""
            color: Theme.surface
            focus: popup.visible
            Keys.onEscapePressed: SomeService.open = false
            MouseArea { anchors.fill: parent }       // clicks on the card don't close it
            // beneath the card (z -1), so it fades and moves with it; frostable: gone while frosted panels are on
            Shadow { z: -1; anchors.fill: parent; radius: parent.radius; kind: Theme.shadowPanel; frostable: true }
            // content…
        }
    }
}
```

**Rules that keep it working:**
- Colours, sizes and durations come from `Theme`; data from services. No `Process` or file reading in UI files.
- A shadowed window needs room around the panel for the shadow (`Shadow.side/above/below`) and must let clicks through outside the card (a mask or the full-screen MouseArea above).
- Untrusted text (notifications, file names, chat) uses `textFormat: Text.PlainText`. Long text elides and shows whole on hover (`TipHover`).
- Every `image://icon` Image is `asynchronous: true`.
- Lists from a service use `ScriptModel` with keys, not a plain JS array.
- Don't name a property after an `Item` property (`left`, `top`…); qualify with `root.` where an `id` could shadow it.
- Keyboard first: Esc closes, arrows (and Ctrl+H J K L where lists are) move, Enter acts, focus lands somewhere sensible on open. Select on pointer *movement*, not hover-enter.
- Quickshell's JavaScript has no `Object.fromEntries`, `flatMap`, `.at()` or object spread.

## 5. Recipes

**A setting.** Rows are data in `src/settings/SettingsContent.qml`, built with its helpers: `group(title, rows)`, `toggle(id, title, subtitle, get, set)`, `action(id, title, subtitle, button, run)`, `read(id, title, value, subtitle)`, a `{ kind: "choice", … }` object for choices, and `impact(row, "low"|"medium"|"high"|"saves")` for a visual setting's performance note. Wire the value through `Store.saved` and a getter/setter in `ShellSettings` (or its own service). Then, in the same change: a search entry in `src/settings/catalog.js`, its default in `SettingsReset` (if the page has a reset), a row in `rust/psc/src/prefs.rs`'s `SCHEMA` if it belongs in the export, and checks in `tests/settings-ui.qml`. Rows that appear and disappear rebuild the list: tests must find items again afterwards.

**A launcher row.** Rows are objects with a `kind`; the launcher draws each kind through its `sourceComponent` table, so a new kind needs an entry there, for Classic and TUI. Cards in the System view are built with `card(name, q, rows)`; shell actions others can pin go in `LauncherTools.actions`.

**A toast or notification-like message.** The shell is the notification daemon: send it with `notify-send` from a service (through `setpriv --pdeathsig TERM` if it waits for an action) rather than drawing a new toast type.

**IPC for a new window.** An `IpcHandler` with a `target` in the window's service; never name a function `show`. Document it in `docs/ipc-and-keybinds.md`.

## 6. Check it

1. **Live:** the shell reloads on save. Read `qs log -c pistachio --no-color`: the "Configuration Loaded" count went up, no new `ERROR`. Open it through its real entry point (keybind, launcher, IPC).
2. **Both styles and both schemes:** Classic and TUI, Pistachio Noir and Noir. Long names, empty states, errors, and the smallest Settings window (900 × 620).
3. **Tests:** `sh tests/run.sh` (every safe suite); for layout bugs `sh tests/layout.sh`, for Settings `sh tests/settings.sh`. Native checks with screenshots run in a private `qs -p` fixture (`--native`), never against the owner's shell.
4. **Write it down** (AGENTS.md, "Write it down"): the feature reference `docs/README.LLM.md`, a decision, gotchas met, today's TODO with the owner's visual check as an unticked box. Say which board you matched, or that there was none.
