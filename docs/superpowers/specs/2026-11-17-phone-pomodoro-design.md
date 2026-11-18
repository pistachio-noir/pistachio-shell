---
title: Untitled
author: sx
date: 2026-11-17T22:09:27Z
---

# Phone preview for Focus and Pomodoro

## Intent

Let the owner check the current Focus or Pomodoro countdown on a phone while away from the desktop, using their local network.

## Behavior

- Start a local HTTP server when an existing Focus, standalone Pomodoro, or Zen-owned Pomodoro session is active. Stop it when the session ends; a paused session remains active.
- Show the current phase, remaining time, round when relevant, and paused state. Follow work, break, long break, pause, resume, skip, and session end from the existing FocusMode state. A single-stretch Focus session is shown too.
- The phone view is read-only. It cannot pause, skip, end, or change the session.
- At session start show a brief shell toast with a View on phone action. A persistent action beside the desktop timer opens the same QR code and local URL after the toast has gone. Respect the existing timer click-to-pause and its other controls.
- The QR and URL are presented for the active session; report a clear error if the local address, QR generation, or server cannot be made available. No router, firewall, or system network settings are changed.
- Match the current shell style for the desktop popup and use a simple phone-sized page in the Pistachio palette. The phone needs no app or account.

## Approach

Use a small Python HTTP helper owned by a shell service. FocusMode remains the source of truth and supplies only the state needed for the page. Bind to a chosen local-network address, and do not expose the service through port forwarding or any internet service. Work out the address and QR dependency on the installed machine before implementation; the text URL remains available if QR generation is unavailable. Do not publish other shell state.

An alternative is extending the Rust LocalSend server. The owner chose Python for now; Rust remains an option for a later Claude handoff. Integrating with LocalSend would couple the timer to file sharing and its availability.

## Verification

Use isolated sessions and state to check server start/stop, pause and all phase transitions, stale/disconnected phone updates, occupied ports, unavailable LAN address, and read-only endpoints. Test the toast action and persistent timer action in Classic and TUI. Exercise the page from a second device if available; otherwise explicitly leave that as an owner hand check. Check the live shell reload/log, update README, dated CLAUDE decisions/gotchas, today's TODO and CLAUDE-HANDOFF.md. Never stage or commit.
