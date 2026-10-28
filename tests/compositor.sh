#!/bin/bash
# Self-check for src/services/Compositor.qml against the running Hyprland session.
# It opens a throwaway kitty window, moves it to workspace 9, floats and tiles it, sends it to 8 without
# following, focuses and closes it, and ends on workspace 1.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)/harness"

ipc() { qs -p "$ROOT" ipc call compositor "$@"; }
# check <python condition over s (state) and w (test windows)> <label>
check() {
    ipc state | python3 -I -c "import json, sys; s = json.load(sys.stdin); w = [x for x in s['windows'] if x['appId'] == 'pistachio-test']; assert $1, s" \
        || { echo "FAIL: $2"; exit 1; }
    echo "ok: $2"
}

qs -p "$ROOT" > /dev/null 2>&1 &
SHELL_PID=$!
kitty --class pistachio-test sleep 300 &
KITTY_PID=$!
trap 'kill $SHELL_PID $KITTY_PID 2>/dev/null || true' EXIT
sleep 3

check "len(w) == 1 and s['bounds']" "test window listed, bounds present"
ADDR=$(ipc state | python3 -I -c "import json, sys; print(next(x['address'] for x in json.load(sys.stdin)['windows'] if x['appId'] == 'pistachio-test'))")

ipc moveWindow "$ADDR" 9; sleep 1
check "w[0]['workspace'] == 9 and 9 in [x['id'] for x in s['workspaces']]" "moveWindow to workspace 9"

ipc toggleFloating "$ADDR"; sleep 1
check "w[0]['floating']" "toggleFloating floats it"
ipc toggleFloating "$ADDR"; sleep 1
check "not w[0]['floating']" "toggleFloating tiles it again"

ipc sendWindow "$ADDR" 8; sleep 1
check "w[0]['workspace'] == 8 and s['active'] == [9]" "sendWindow to workspace 8 stays on 9"

ipc goto 1; sleep 1
check "s['active'] == [1]" "goto 1"

ipc focus "$ADDR"; sleep 1
check "s['active'] == [8] and s['focused'] == 'pistachio-test'" "focus switches to the window's workspace"

ipc close "$ADDR"; sleep 1
check "not w" "close"

ipc goto 1
echo "all passed"
