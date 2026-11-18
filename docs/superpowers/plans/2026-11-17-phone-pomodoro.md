# Phone Pomodoro Preview Implementation Plan

> Use superpowers:executing-plans. The owner commits; do not stage or commit.

**Goal:** Show the active Focus/Pomodoro countdown on a phone over the local network.

**Architecture:** FocusMode remains authoritative. A shell service owns a Python HTTP helper for the lifetime of the session and passes only the current countdown state. A shell popup presents a QR and the local URL, opened by the start toast or a persistent timer action. The page has no control endpoints.

**Tech stack:** Quickshell 0.3.2, Qt Quick, Python standard library HTTP, local QR generator if installed. Spec: `docs/superpowers/specs/2026-11-17-phone-pomodoro-design.md`.

## Constraints and review focus

- Run only while a session is active, including pause; recover after shell reload and terminate on session end.
- Bind to an actual local address; no router, firewall, or system network changes. Do not expose other state or mutation endpoints.
- Address/QR unavailable, port collision, reconnect, sleep/wake, paused countdown, phase rollover, and helper crash must have explicit behavior and checks.
- Preserve the existing timer controls and Classic/TUI styling, and all previous unstaged work. No second production shell.
- Owner hand checks stay unchecked. No staging or commits.

## Task 1: Isolated server and state boundary

**Files:** create `src/services/phone-timer.py` and `tests/phone-timer.test.py`; modify a service owned from `src/services/FocusMode.qml` or an adjacent singleton.

- [ ] Complete tests for phase rollover, missing session, occupied port and process shutdown. Initial read-only page/state, paused snapshot and HTTP method checks went red then green.
- [ ] Implement the minimal Python server, using a private local IPC boundary for authoritative updates; reject control requests, show reconnect state if updates stop, and bind the chosen local address.
- [ ] Run the tests and verify helper termination on session end and reload. Verify each new Quickshell type/property against 0.3.2 documentation.

## Task 2: Link, toast, and phone view

**Files:** `src/popups/SessionPill.qml`, `src/bar/ClassicBar.qml`, `src/bar/TuiBar.qml`, `src/popups/Toasts.qml`, shared components and service as needed; relevant tests.

- [ ] Test start notification/action, persistent access in all three timer locations, QR/text URL and failure states without changing timer actions.
- [ ] Implement the desktop controls and compact phone page with phase, live countdown, round and paused state. Preserve accessibility and both styles. Use a locally available QR tool when present, clearly provide text URL when absent.
- [ ] Run native fixture tests and a real shell check; compare Classic/TUI screenshots. Test on a phone if available, otherwise record the owner's hand check.

## Task 3: Finish and hand off

- [ ] Run relevant focused tests, check Configuration Loaded and errors, clean temporary hooks/processes/settings and confirm one shell.
- [ ] Update README, CLAUDE.md dated decisions/gotchas, `todos/TODO_17-11-26.md`, and CLAUDE-HANDOFF.md with verification and remaining hand checks. Record Python choice and Rust option.
- [ ] Review the resulting change and provide a commit message as text only.

## Execution result — 17 November 2026

Implemented and checked against local shell and focused tests; see CLAUDE-HANDOFF.md and today's TODO. Physical phone and direct timer-button hand checks remain open. Review findings fixed: subnet-aware interface discovery, QR error message, monotonic phone countdown, asynchronous helper restart and Reveal fades. Python is current; Rust is an option later.
