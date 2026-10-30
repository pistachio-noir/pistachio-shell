#!/bin/bash
# Self-check for src/services/Notifs.qml with notify-send: popups, unread, do-not-disturb, clear all,
# floods folding into one toast and the sound playing once for them. The test shell must become the
# notification daemon, so stop the shell (and any other daemon) first. Its pw-play is a stand-in that
# writes to a file, so the test is silent.
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

# the stand-in pw-play: one line per sound, in $STUBS/played
STUBS=$(mktemp -d)
printf '#!/bin/sh\necho "$*" >> "%s/played"\n' "$STUBS" > "$STUBS/pw-play"
chmod +x "$STUBS/pw-play"
touch "$STUBS/played"
played() { wc -l < "$STUBS/played"; }

PATH="$STUBS:$PATH" qs -p "$ROOT" > /dev/null 2>&1 &
SHELL_PID=$!
trap 'kill $SHELL_PID 2>/dev/null || true; rm -rf "$STUBS"' EXIT
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

# a flood: the third toast from one app within 5 s of its last takes the place of the two before it,
# standing for all three; the sound plays once for them (at most once a second)
sleep 1.1
BEFORE=$(played)
for i in 1 2 3; do notify-send -a pistachio-flood "Flood $i" "body $i"; done; sleep 0.5
check "s['popups'] == ['Flood 3'] and s['counts'] == [3] and len(s['summaries']) == 3" "three quick ones from one app fold into one toast, all three kept"
[ "$(($(played) - BEFORE))" = 1 ] || { echo "FAIL: the sound plays once for a flood"; exit 1; }
echo "ok: the sound plays once for a flood"
notify-send -a pistachio-other "Other" "another app"; sleep 0.5
check "s['popups'] == ['Flood 3', 'Other'] and s['counts'] == [3, 1]" "another app's toast doesn't fold in"
ipc clearAll; sleep 0.5

echo "all passed"
