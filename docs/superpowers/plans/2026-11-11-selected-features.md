# Selected Shell Features Implementation Plan

> For agentic workers: use executing-plans; independent domains may use dispatching-parallel-agents. No agent commits.

**Goal:** Implement the approved selected features while preserving existing shell behaviour.
**Architecture:** Extend current service singletons and existing UI, with small focused helpers. Services own files/processes; UI binds state. Capture, Lens, system/settings and launcher/files have separate ownership.
**Tech Stack:** Quickshell 0.3.2, QtQuick, Python standard library, installed system CLIs.
**Spec:** ../specs/2026-11-11-selected-features-design.md

## Global constraints
- Theme-only colours, Manrope/JetBrains Mono, current radii and Reveal motion.
- Check Quickshell 0.3.2 docs and CLI help before coding against them.
- No Hyprland config changes, no commits, no owner-device disruption in tests.
- New requests supersede stale async results; cancellation must reap owned processes.

## Review focus
- Copy-only must not leave saved images; failed/cancelled capture creates no archive.
- Combined Lens proposals must use the original snapshot and coding routing must exclude non-code.
- Alias/pin persistence rejects malformed values; actions require explicit activation.
- Preview and MIME handling must accept spaces/Unicode without shell interpolation.
- Reset/diagnostics must exclude credentials and system device state.

## Tasks
- [x] Capture domain: service first, then setup/countdown/pause controls, trim UI, output choice. Owned: Screenshots.qml, ScreenshotPicker/Menu, RecordingRegion, new capture helpers/components/tests. Store additions coordinated through root.
- [x] Lens domain: multi-image session protocol and helpers, combined synthesis, thumbnails and Ask both; extend fake-CLI and QML tests before production changes. Owned: Lens.qml, lens.py/schema, LensCard/components and tests/lens*.
- [x] System domain: health/reset, mic test, read-only Bluetooth/network, session media chooser and blocked eject. Owned: relevant service singletons and settings UI/tests. Store additions coordinated through root.
- [x] Launcher domain: validated pin/alias model, jobs helper, preview/Open-with service and UI, launch feedback, floating presets and magnifier. Owned: Apps/Files/Desktop/Compositor, launcher, new helpers/UI and shell mounting; root coordinates Store.
- [x] Integration: read each domain diff, run relevant suites, test via isolated fixtures and IPC, inspect grim screenshots and main qs logs, remove hooks, update README/CLAUDE/daily TODO, provide commit text only.

For each domain: write boundary tests, observe expected failure, implement services then UI, pass tests, document evidence and limitations. Avoid tests that just grep source. CLI/device operations mocked only at external boundary; use real UI for geometry/input.

## Execution ledger
- Scope approved in chat and implemented in place; no git mutations by agents.
- Capture: native fixtures, three FFmpeg helper boundaries and a real GPU calibration pause test passed; actual audio sources remain hand checks.
- Lens: 35 fake-CLI checks, real QML interaction tests and native visual checks passed; no paid requests. Source responses remain distinct from the one Apply-eligible synthesis.
- System: nine helper boundaries, two microphone helper/sample cleanup checks and actual Settings controls passed. Live Network read-only facts verified; actual mic/BT/eject hand checks documented.
- Launcher: nine helper boundaries, two real PDF cancellation/reload checks and native panel/service checks passed. Main launcher pins/aliases, preview, Settings pages and magnifier inspected live. Both floating sizes/centre verified on disposable window. Actual helper launch mapped/confirmed a disposable Qt window; its later exit did not show startup failure. Manual health probe returned27 allowlisted statuses without sign-in checks.
- Root reviewed domain diffs and received independent launcher/process boundary review. Fixed stale requests, UTF-8 boundaries, alias removal, reserved IPC name, startup queuing, process cleanup, and startup-vs-later-app-failure distinction.
- JS/system/settings/Lens/screenshots/recording/launcher targeted suites pass. Latest live shell reload63 has no QML errors; only original qs PID735. Historical fixed/debugging reload failures remain counted by the health page; no logs were cleared. Native Qt platform focus warnings remain explicitly recorded. Broad device-mutating services suite was not run to avoid altering owner audio/BT/display state.
- README/CLAUDE/architecture and daily TODO updated. Owner hand tests are in todos/TODO_11-11-26.md. Temporary hooks/test settings restored; no commit performed. Existing staging was left untouched, including deletions of generated artifacts in the working tree.

- Final review follow-up: fixed actual empty-alias save, Terminal=true window correlation and partial-eject retry; red→green coverage and live alias editor confirmed. Deterministic FileView stale-save regression exposed and fixed Store write ordering while retaining debounce (200 fixture notifications:12ms). Native restart exposed and fixed QVariant pin-list normalisation; pin/alias order and runtime jobs now survive restart. Optional dependency action visibility checked. Focused System/Settings, Launcher and JS suites passed after fixes; independent reviewer accepted the alias/terminal/eject and Store ordering fixes.

- Final post-review shell reload 68: no later QML errors, original qs735 only; all temporary hooks/aliases absent.
