# Pomodoro pill hide + phone page controls

Owner's request, 20 November 2026. No boards: reuses the pill's buttons and the Classic bar's handle.

## Intent

During a long Pomodoro in Zen the timer pill at the bottom is in the way; the owner wants to tuck it
away like the Classic bar. The phone page should look like the shell and let the owner pause, skip or
end the session from the phone.

## Pill (`popups/SessionPill.qml`)

- A fourth round button, Hide (chevron down).
- Hidden: the pill shrinks into the Classic bar's handle (72 × 4, 2 px above the screen edge, subtext),
  with a 4 px strip at the edge taking the pointer. Pointing at the strip brings the pill out while the
  pointer stays on it (as the bar); clicking the handle brings it back for good.
- Hidden is per session and not saved: a new session, or Zen re-entered, shows it again.
- TUI: square, otherwise the same.

## Phone page (`psc phone-timer`)

- Styled with the shell's colours (sent with the state): phase chip, large tabular countdown, a thin
  progress bar for the phase, "Paused" in subtext; Pause/Resume, Skip (Finish for a single stretch), End
  (tap twice to confirm).
- `POST /pause`, `/skip`, `/end` from the local subnet print `{"action":"…"}` on psc's stdout; FocusMode
  calls `pause()`, `skip()`, `endSession()` and sends the state straight back. Other POSTs 404; requests
  from outside the subnet 403.
- No key or token (owner's call: home network, not exposed). This reverses the 17 November "read-only"
  rule of `2026-11-17-phone-pomodoro-design.md`.

## Approaches

- Phone actions through the helper's stdout to FocusMode (chosen): one source of truth, no new IPC.
- Phone calling `psc`/Quickshell IPC: FocusMode has no IPC by the owner's call.
- A per-session key in the QR link: offered, declined by the owner.
- Pill: auto-hide on window overlap or always-hidden were offered; the owner chose a hide button with the
  bar's handle.
