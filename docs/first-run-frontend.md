# First-run setup: view, controller and service

The boards in `design/FirstRun/` define the screens. Codex built the first frontend (19 November 2026); Claude finished it and built the backend the same evening (decision "First-run setup, finished" in `docs/decisions.md`).

## Pieces

| File | Job |
| --- | --- |
| `src/services/FirstRun.qml` | When it opens (`Store.fresh`, `setupDone`), the check (`psc doctor --json` + `busctl`), finishing, the file chooser for Restore, IPC `setup open/close/status`, placing the window. |
| `src/setup/FirstRunWindow.qml` | The normal window ("Pistachio Setup", 880 × 600), loaded lazily by `shell.qml` while `FirstRun.loaded`. Closing it from outside counts as Skip. |
| `src/setup/SetupController.qml` | UI glue: binds the view's inputs to the services and sends each request to the setter Settings uses. |
| `src/setup/FirstRunWizard.qml` | The view. Knows nothing about services: inputs in, signals out. |
| `WizardPages`, `WizardCheck`, `WizardWelcome`, `WizardBackdrop`, `WizardRow`, `WizardToggle`, `WizardChoice`, `WizardLevel`, `WizardRecap`, `WizardSegment`, `WizardCaption` | Its parts, one per file (no inline components). |

## Flow

`flow` is a list of page ids. The full flow is welcome, check, look, sound, notifications, connections, lens, places, done. Restore my settings is welcome, restore, check, done. `page` is the index and `pageId` the id. Back moves one page; Back from restore cancels the review and returns to the full flow. Skip asks first. From the attention state the check can be retried or bypassed.

## Inputs on the view

Assign new objects or arrays when data changes. Text is shown as plain text.

| Property | Shape |
| --- | --- |
| `checkState` | `idle`, `checking`, `clear` or `attention` |
| `checks` | `[{title, detail, status, package?, command?}]`, status `pass`, `optional`, `warning` (required), `conflict`. Titles are unique (the grid is keyed by title). Missing tools carry `package` only; a conflict carries `command`. |
| `checkTotal`, `checkNote` | Expected rows; the clear state's footer note. |
| `values` | Keyed by setting; a missing value disables its control. |
| `options` | Keyed by setting: `[{value, title, subtitle?, disabled?, source?}]`. |
| `details` | Strings: `outputDevice`, `inputDevice`, `brightness`, `nightLight`, `bluetooth`, `localSendName`, `ethernet`, `lensFallback`, `lensArchive`, `lensNone`, `terminal`, `weather`, `wallpaperFolder`, `wallpaperEmpty`, `screenshotFolder`, `bindTip`. |
| `available` | `false` disables or hides: `desktopIcons`, `localSend` (hides), `lensProvider` (no assistant: Lens says so), `lensFallback`, `wallpaper`, `restore`, `restoreChoose`, `playNotificationSound`. |
| `devices` | `[{title, detail}]` Bluetooth devices. |
| `summary` | `[{title, detail}]` for "You chose". |
| `shortcuts` | `[{title, note, detail}]` for "Bind keys to psc" (note = keys, detail = the psc command). |
| `commands` | `[{command, detail}]` for "psc in a terminal". |
| `restore` | `{state: idle|busy|reviewing|missing|error, path, message, changes: [{title, from, to}], skipped}`. |
| `errorMessage`, `reducedMotion` | A plain status line; skip decorative motion. |

Setting keys: `colourScheme`, `frostStyle` (`off`, `subtle`, `glassy`), `shadows`, `desktopIcons`, `wallpaper`; `outputLevel`, `inputLevel`, `brightness` in [0, 1], `outputDevice`, `inputDevice`, `nightLight`; `quietFullscreen`, `quietCalls`, `notificationSound`; `bluetooth`, `localSend`; `lensProvider`, `lensModel`, `lensEffort`, `lensFallback` (for the chosen provider); `terminal`, `weatherLocation` (on Enter).

## Signals

| Signal | Controller |
| --- | --- |
| `checkRequested()` | `FirstRun.check()` |
| `valueRequested(key, value)` | the service setter (see `SetupController.setValue`) |
| `actionRequested(action, payload)` | `copyCommand`, `playNotificationSound`, `restoreReview`, `restoreChoose`, `restoreApply`, `restoreCancel` |
| `finished(destination)` | `FirstRun.finish`: `shell`, `settings` (opens Settings) or `skip`; all mark setup done |
| `moveRequested()` | the window's `startSystemMove()` |

## Tests

`python3 -B tests/first-run.test.py` runs the view alone with fixture inputs at 880 × 600 (`PISTACHIO_SETUP_SHOTS=<dir>` saves each page; `PISTACHIO_SETUP_NATIVE=1` on Wayland). `python3 -B tests/first-run-backend.test.py` runs FirstRun, the controller and Preferences with stand-in services, psc and busctl. See `docs/gotchas.md`.
