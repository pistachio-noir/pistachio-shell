# Components and tokens

What already exists, so new UI reuses it. Read a file's header comment before using it; this is the short form (21 November 2026).

## Shared components (`src/components/`)

| Component | What it is |
|:--|:--|
| `Reveal` | Open/close motion for a window: set `open`; bind content to `progress` (0→1) and the window's `visible` to `shown` |
| `Shadow` | A board's drop shadow: inside the panel with `z: -1`, `anchors.fill: parent`, `radius: parent.radius` (`kind`: `Theme.shadowPanel`, `shadowSmall`, `shadowModal`; `frostable: true` on panels); hidden in TUI |
| `PanelFrame` | A panel's background; in TUI a square frame with its `title` as a tab across the border |
| `Popover` | A card over its parent panel, which it dims (night light schedule, Bluetooth quick connections) |
| `IconButton` | Round 44 px icon button (square in TUI) |
| `GhostButton` | Round 44 px icon button with no background until hovered |
| `ActionButton` | A pill button; the first/primary one pistachio |
| `Chip` | 40 px rounded chip that lightens on hover and while its panel is open |
| `FileChip` | A file on a 28 px chip, with its tinted icon (LocalSend) |
| `Switch` | On/off switch, 48×28 track in a 52×44 hit area |
| `Slider` | 10 px track, pistachio fill up to a 20 px knob |
| `TimeStepper` | A label and a time of day with − and + (15-minute steps, wheel too) |
| `Icon` / `Icons` | Lucide-style stroke icons from 24×24 path data; `Icons` holds the paths (add new Lucide icons there) |
| `TipHover` / `HoverTip` | Inside a Text that may be cut short: shows it whole on hover |
| `TuiBracket` | TUI's `[c] copy`: key bright in brackets, label quiet; pistachio when `on` |
| `TuiControlRow` | A TUI row with a label and detail, as an action, a switch or a meter (`kind`), with `checked`, `selected` and `value` |
| `MediaCard` / `MediaButton` | What's playing, with controls; round 36 px media buttons |
| `NotificationIcon` / `NotificationPreview` | A notification's icon; a screenshot under its text |
| `ChatButton`, `ChatInclude`, `ChatMarkdown` | Quick chat's buttons, Include pills, Markdown answers |
| `LensImages`, `LensInput`, `LensMarkdown`, `LensUpgrade` | Lens's parts |
| `LocalSendLook`, `WeatherLook` | Icons and tints per file type or weather code |
| `WallpaperView` | A wallpaper in its fit, cross-fading |
| `ShellLogo` | The shell's icon, drawn in QML |

## Theme tokens (`src/Theme.qml`)

- **Colours:** `bg`, `bgAlt`, `overlay`, `overlay2`, `muted`, `subtext`, `text`, `textBright`, `pistachio`, `terracotta`, `gold`, `sageBlue`, `teal`, `lavender`, `clay`, `deep`, `surface`, `shadow`; `noir` switches them all to greys.
- **Sizes:** `barWidth`, `barHeight`, `barRadius`, `barMargin`, `chipHeight`, `chipRadius`, `tileRadius`, `panelRadius`, `settingsWidth`, `settingsHeight`, `setupWidth`, `setupHeight`, `lensPromptWidth`, `lensAnswerWidth`.
- **Shadows:** `shadowPanel`, `shadowSmall`, `shadowModal` (each `{ y, blur, alpha }`).
- **Type:** `fontUi` (Manrope), `fontMono` (JetBrains Mono), `fontTui`, `fontEmoji`, `codeColours`.
- **Motion:** `easing`, `hoverDuration`, `motionDuration`, `growDuration`, `introDuration`, `settleDuration`, `dimDuration`.
- **TUI:** `tui` (on/off), `tuiTextSize`, `tuiLineHeight`, `tuiButtonHeight`, `tuiButtonPadding`, `tuiBarHeight`, `tuiBarCellHeight`, `tuiBarCellWidth`, `tuiRowHeight`, `tuiHeaderHeight`, `tuiPanelWidth`, `tuiPanelGap`, `tuiPanelMargin`, `tuiSidebarWidth`, `tuiLauncherWidth`, `tuiSwitcherWidth`, `tuiSurface`, `tuiBorder`, `tuiRule`, `tuiHover`, `tuiCodeSize`.
- **Other:** `catSkins` (the desktop cat's coats).

## Settings row helpers (`src/settings/SettingsContent.qml`)

`group(title, rows)` · `toggle(id, title, subtitle, get, set)` · `action(id, title, subtitle, button, run)` · `read(id, title, value, subtitle)` · `{ id, kind: "choice", title, subtitle, choices, value, set }` · `impact(row, "low" | "medium" | "high" | "saves")`
