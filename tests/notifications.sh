#!/bin/bash
# Self-check for src/services/Notifs.qml with notify-send: popups, unread, do-not-disturb, clear all.
# The test shell must become the notification daemon, so stop the shell (and any other daemon) first.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)/harness"

ipc() { qs -p "$ROOT" ipc call notifs "$@"; }
# check <python condition over s (notification state)> <label>
check() {
    ipc state | python3 -I -c "import json, sys; s = json.load(sys.stdin); assert $1, s" \
        || { echo "FAIL: $2"; exit 1; }
    echo "ok: $2"
}

if busctl --user list --no-legend | awk '$1 == "org.freedesktop.Notifications" && $2 != "-" { found = 1 } END { exit !found }'; then
    echo "org.freedesktop.Notifications is taken: stop the shell or other notification daemon first"
    exit 1
fi

qs -p "$ROOT" > /dev/null 2>&1 &
SHELL_PID=$!
trap 'kill $SHELL_PID 2>/dev/null || true' EXIT
sleep 3

notify-send -a pistachio-test "First" "one"; sleep 0.5
check "s['summaries'] == ['First'] and s['popups'] == ['First'] and s['unread']" "listed, shown as a popup, unread"

ipc markSeen
check "not s['unread'] and s['popups'] == []" "opening the centre marks it seen and clears popups"

ipc setDnd true
notify-send -a pistachio-test "Second" "two"; sleep 0.5
check "s['summaries'] == ['Second', 'First'] and s['popups'] == [] and s['unread']" "do not disturb: listed, unread, no popup"
ipc setDnd false

ipc clearAll; sleep 0.5
check "s['summaries'] == []" "clear all"

echo "all passed"
