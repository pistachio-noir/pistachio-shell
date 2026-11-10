#!/bin/sh
# Fake-CLI integration checks: no network, accounts, or desktop changes.
set -eu
LENS_TEST_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
python3 -B "$LENS_TEST_ROOT/tests/lens.test.py"
if ! command -v qs >/dev/null; then
    echo "skip: QML cancellation state (Quickshell not installed)"
    exit 0
fi
LENS_TEST_DIR=$(mktemp -d)
cleanup() {
    kill "$LENS_TEST_PID" 2>/dev/null || true
    wait "$LENS_TEST_PID" 2>/dev/null || true
    rm -rf "$LENS_TEST_DIR"
}
ln -s "$LENS_TEST_ROOT/src/services" "$LENS_TEST_DIR/services"
ln -s "$LENS_TEST_ROOT/src/Theme.qml" "$LENS_TEST_DIR/Theme.qml"
ln -s "$LENS_TEST_ROOT/src/components" "$LENS_TEST_DIR/components"
cp "$LENS_TEST_ROOT/tests/lens-state.qml" "$LENS_TEST_DIR/shell.qml"
mkdir -m 700 "$LENS_TEST_DIR/runtime"
export XDG_RUNTIME_DIR="$LENS_TEST_DIR/runtime"
export XDG_STATE_HOME="$LENS_TEST_DIR/state"
export XDG_CACHE_HOME="$LENS_TEST_DIR/cache"
export QT_QPA_PLATFORM=offscreen
unset WAYLAND_DISPLAY DISPLAY
qs -p "$LENS_TEST_DIR" >"$LENS_TEST_DIR/log" 2>&1 &
LENS_TEST_PID=$!
trap cleanup EXIT HUP INT TERM
LENS_TEST_TRIES=0
while [ "$LENS_TEST_TRIES" -lt 50 ]; do
    if LENS_TEST_RESULT=$(qs -p "$LENS_TEST_DIR" ipc call lensTest check 2>/dev/null); then
        [ "$LENS_TEST_RESULT" = "all passed" ] || { echo "$LENS_TEST_RESULT"; exit 1; }
        echo "lens: QML cancellation state passed"
        for LENS_TEST_TEXT in "" "A centred question" "First line
Second line"; do
            qs -p "$LENS_TEST_DIR" ipc call lensTest inputText "$LENS_TEST_TEXT"
            qs -p "$LENS_TEST_DIR" ipc call lensTest inputState | python3 -c '
import json,sys
s=json.load(sys.stdin)
assert abs(s["textTop"] + s["contentHeight"] / 2 - s["height"] / 2) < 1, s
assert abs(s["topPadding"] - s["bottomPadding"]) < 0.01, s
print("lens: input centred (%g px text in %g px field)" % (s["contentHeight"], s["height"]))
'
        done
        LENS_TEST_LONG=$(python3 -c 'print("\n".join("Line %d" % i for i in range(20)))')
        qs -p "$LENS_TEST_DIR" ipc call lensTest inputText "$LENS_TEST_LONG"
        qs -p "$LENS_TEST_DIR" ipc call lensTest inputEnd
        qs -p "$LENS_TEST_DIR" ipc call lensTest inputState | python3 -c '
import json,sys
s=json.load(sys.stdin)
assert s["height"] == 136 and s["contentY"] > 0, s
assert s["cursorTop"] >= 10 and s["cursorTop"] + s["cursorHeight"] <= s["height"] - 10, s
print("lens: long input scrolls to the cursor")
'
        exit 0
    fi
    LENS_TEST_TRIES=$((LENS_TEST_TRIES + 1))
    sleep 0.1
done
cat "$LENS_TEST_DIR/log"
echo "FAIL: QML cancellation test did not start"
exit 1
