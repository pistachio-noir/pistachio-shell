# Desktop widgets and the widget studio

Owner's request, 20 November 2026 (feature 14 of `todos/FEATURES_15-11-26.md`). No boards: laid out by
Claude from existing components (desktop icons' grid and tiles, DashedFrame, the cat's visibility rule).
Feature 18 (ambient clock) follows as its own design and reuses the clock and media parts.

## Intent

Make the empty desktop worth looking at: a clock, the weather and CPU/RAM on the wallpaper, arranged by
the owner on the real desktop. Experimental for now.

## Goals

- Three blocks: **Clock** (time large, weekday and date), **Weather** (temperature, condition glyph,
  place; from `Weather`), **CPU/RAM** (two meters with percentages; from `SystemStats`).
- A widget studio: arrange on the real desktop, snapped to a grid; add/remove blocks; remembered.
- Classic and TUI looks (Classic: rounded tiles, `Theme.glass(bgAlt)`, radius 20; TUI: square boxes with
  `tuiBorder`, JetBrains Mono).
- Settings → Experimental → Desktop widgets: a switch (off by default) and an Arrange… button.

## Non-goals / anti-goals

- No free (unsnapped) placement, resizing, per-widget settings or third-party widgets.
- Must not steal clicks or keyboard from windows, cost CPU while nobody sees the blocks, or cover icons.

## Behaviour

- **Grid:** the desktop icons' grid (104 px cells from a 24 px margin, clear of the bar). Sizes in cells:
  Clock 3×2, Weather 2×2, CPU/RAM 2×2. Defaults: top-right corner, stacked down (icons start top-left).
- **Icons flow around widgets:** cells under a shown widget are taken before icons are placed; an icon
  saved under a widget moves to the next free cell (its saved place is kept for when the widget goes); an
  icon can't be dropped onto a widget's cells.
- **When shown:** switch on, and the cat's rule: an active workspace without tiled windows, not
  fullscreen. Hidden in Zen (Zen hides desktop furniture). Shown in Showoff (no private data). Classic and
  TUI. Stats are read every 1.5 s only while the CPU/RAM block is on screen (SystemStats gets a second
  watcher flag; today one bool is shared with Settings).
- **Studio (Arrange widgets):** a full-screen Overlay layer, so it works over windows and in TUI: the
  current wallpaper dimmed, the grid as faint dots, the icons' cells as faint outlines (Classic, icons
  on), the widgets live with a dashed frame and a round ✕. Drag a widget: it follows the pointer, a
  dashed outline shows the snapped target (subtext; terracotta if it can't go there: off the grid or
  over another widget; dropped there, it goes back). A toolbar pill at the bottom: `+ Clock`,
  `+ Weather`, `+ CPU/RAM` (only those not placed; added at the first free spot), and Done. Esc or Done
  closes; every change saves at once (Store). Opened from Experimental → Arrange…, the launcher (System →
  Experimental "Arrange widgets"), the desktop right-click menu (Classic), and `psc widgets arrange`
  (IPC target `widgets`, functions `arrange`, `done`).
- **Saved:** `Store.saved.desktopWidgets` (bool) and `Store.saved.widgetLayout`
  (`[{ kind: "clock"|"weather"|"stats", col, row }]`). Export/import (`psc prefs`) carries the switch as
  `[experimental] desktop_widgets`; the layout stays local, like icon positions. Experimental's page reset
  turns the switch off and leaves the layout.

## Approaches

- **Edit on the desktop (chosen by the owner)** vs a Settings page with a thumbnail of the screen.
- Edit layer: an Overlay copy of the desktop (chosen, Claude's call) vs editing the Background layer in
  place (needs the workspace empty and the TUI input mask widened; windows would cover it).
- Grid: the icons' grid with icons flowing around (Claude's call) vs a finer separate grid that may
  overlap icons.

## Left to the builder

- Exact typography and inner layout of each block within its cells; the studio toolbar's look (reuse the
  screenshot/recording pill style); motion within the Theme durations.
- Sharing the icon layout code between DesktopIcons and the studio (a small JS helper).
