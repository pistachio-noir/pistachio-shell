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
# Test the real service-to-helper JSON pipe as well as the bridge in isolation.
python3 -B - "$LENS_TEST_ROOT" "$LENS_TEST_DIR" <<'PY'
import json, pathlib, runpy, sys
root, base = map(pathlib.Path, sys.argv[1:])
fake = runpy.run_path(str(root / 'tests/lens.test.py'))['FAKE']
(base / 'bin').mkdir()
for name in ('claude', 'codex'):
    script = base / 'bin' / name
    script.write_text(fake)
    script.chmod(0o755)
script = base / 'bin/zenity'
script.write_text('#!/bin/sh\ncase "$*" in *image*) printf "%s\\n" "$LENS_TEST_IMAGE" ;; *) printf "%s\\n" "$LENS_TEST_ATTACHMENT" ;; esac\n')
script.chmod(0o755)
script = base / 'bin/python3'
script.write_text('''#!/usr/bin/python3
import os, pathlib, runpy, sys
from unittest.mock import patch
if len(sys.argv) == 3 and sys.argv[1] == '-I' and sys.argv[2].endswith('/lens.py'):
    with patch('pathlib.Path.home', return_value=pathlib.Path(os.environ['LENS_TEST_HOME'])):
        runpy.run_path(sys.argv[2], run_name='__main__')
else:
    os.execv('/usr/bin/python3', ['python3', *sys.argv[1:]])
''')
script.chmod(0o755)
(base / 'control.json').write_text(json.dumps({'replacement': 'fixed\\n', 'task': 'coding'}))
(base / 'example.rs').write_text('broken\\n')
import base64
import struct, zlib
chunk = lambda tag, data: struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data))
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b'\x00\x50\x60\x40')) + chunk(b'IEND', b'')
for name in ('image.png', 'snip.png'): (base / name).write_bytes(png)
PY
export LENS_TEST_CONTROL="$LENS_TEST_DIR/control.json"
export LENS_TEST_RECORD="$LENS_TEST_DIR/calls.jsonl"
export LENS_TEST_ATTACHMENT="$LENS_TEST_DIR/example.rs"
export LENS_TEST_IMAGE="$LENS_TEST_DIR/image.png"
export LENS_TEST_HOME="$LENS_TEST_DIR"
export PATH="$LENS_TEST_DIR/bin:$PATH"
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
        python3 - "$LENS_TEST_DIR" <<'PY'
import json, pathlib, subprocess, sys, time
base = pathlib.Path(sys.argv[1])
def call(method, *args):
    return subprocess.check_output(['qs', '-p', str(base), 'ipc', 'call', 'lensTest', method, *args], text=True)
def wait(predicate):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        state = json.loads(call('fixtureState'))
        if predicate(state): return state
        time.sleep(.02)
    raise AssertionError(state)
call('beginFixture', str(base / 'snip.png'))
wait(lambda s: s['ready'])
call('chooseFixture')
wait(lambda s: s['attachment'] == 'example.rs' and not s['picking'])
call('askFixture')
first = wait(lambda s: s['state'] == 'answer')
assert first['provider'] == first['preferred'] == 'claude' and first['diff'] and first['upgrade'], first
(base / 'control.json').write_text(json.dumps({'replacement': 'fixed\\n', 'task': 'coding', 'fail_models': ['sonnet']}))
call('acceptFixture')
failed_upgrade = wait(lambda s: s['state'] == 'answer' and 'previous answer is kept' in s['notice'])
assert failed_upgrade['diff'] and failed_upgrade['model'] == 'claude-haiku-5-5', failed_upgrade
(base / 'control.json').write_text(json.dumps({'replacement': 'fixed\\n', 'task': 'coding'}))
call('beginFixture', str(base / 'snip.png'))
call('chooseFixture')
wait(lambda s: s['attachment'] == 'example.rs' and not s['picking'])
call('askFixture')
wait(lambda s: s['state'] == 'answer' and s['upgrade'])
call('keepFixture')
declined = wait(lambda s: not s['upgrade'])
assert declined['asked'] and not declined['enabled'] and declined['state'] == 'answer', declined
call('askFixture')
assert not wait(lambda s: s['state'] == 'answer')['upgrade'], 'must ask only once per snip'
# A new snip resets the choice; keyboard Right/Enter explicitly accepts it.
call('beginFixture', str(base / 'snip.png'))
call('chooseFixture')
wait(lambda s: s['attachment'] == 'example.rs' and not s['picking'])
call('askFixture')
wait(lambda s: s['state'] == 'answer' and s['upgrade'])
call('acceptFixture')
accepted = wait(lambda s: s['state'] == 'answer' and s['model'] == 'sonnet')
assert accepted['enabled'] and accepted['effort'] == 'high' and accepted['normalClaude'] == 'claude-haiku-5-5', accepted
before = len((base / 'calls.jsonl').read_text().splitlines())
call('taskFixture', 'translation')
translated = wait(lambda s: s['state'] == 'answer' and s['model'] == 'claude-haiku-5-5')
assert not translated['upgrade'] and translated['effort'] == 'medium', translated
assert len((base / 'calls.jsonl').read_text().splitlines()) == before + 1, 'translation must not invoke a coding model'
before = len((base / 'calls.jsonl').read_text().splitlines())
call('repeatBothFixture')
translated_both = wait(lambda s: s['state'] == 'answer' and s['combined'])
assert translated_both['model'] == 'claude-haiku-5-5' and not translated_both['upgrade'], translated_both
repeated_calls = [json.loads(line) for line in (base / 'calls.jsonl').read_text().splitlines()][before:]
assert len(repeated_calls) == 3, repeated_calls
assert all(call['args'][call['args'].index('--model') + 1] in ('claude-haiku-5-5', 'gpt-6-luna') for call in repeated_calls)
call('suggestFixture', 'false')
call('askFixture')
disabled = wait(lambda s: s['state'] == 'answer')
assert disabled['model'] == 'claude-haiku-5-5' and not disabled['upgrade'], disabled
call('suggestFixture', 'true')
call('askFixture')
wait(lambda s: s['state'] == 'answer' and s['model'] == 'sonnet')
call('transferFixture')
second = wait(lambda s: s['state'] == 'answer' and s['provider'] == 'codex')
assert second['preferred'] == 'claude' and second['diff'] and second['model'] == 'gpt-6.1-sol' and second['normalCodex'] == 'gpt-6-luna', second
call('applyFixture')
wait(lambda s: not s['diff'] and 'Applied' in s['notice'])
assert (base / 'example.rs').read_text() == 'fixed\\n'
print('lens: QML chooser, confirmation keyboard, once-per-snip choice, coding-only routing, setting off, transfer and Apply passed')
call('beginFixture', str(base / 'snip.png'))
wait(lambda s: len(s['images']) == 1)
for total in (2, 3):
    call('chooseImageFixture')
    wait(lambda s: len(s['images']) == total and not s['picking'])
ui = json.loads(call('imageUiState'))
assert ui['first'] and ui['second'] and ui['third'] and ui['height'] > 0, ui
before = len((base / 'calls.jsonl').read_text().splitlines())
# Turn coding suggestions off here: Ask both has exactly two sources + synthesis.
call('suggestFixture', 'false')
call('bothFixture')
combined = wait(lambda s: s['state'] == 'answer' and s['combined'])
assert combined['provider'] == combined['preferred'] == 'claude', combined
calls = [json.loads(line) for line in (base / 'calls.jsonl').read_text().splitlines()][before:]
assert [c['name'] for c in calls] == ['claude', 'codex', 'claude'], calls
assert calls[1]['args'].count('--image') == 3
call('clickRemoveSecondImageFixture')
reduced = wait(lambda s: len(s['images']) == 2)
ui = json.loads(call('imageUiState'))
assert ui['first'] and ui['second'] and not ui['third'], ui
call('snipFixture')
suspended = wait(lambda s: s['capturing'] and not s['open'])
call('resumeSnipsFixture')
resumed = wait(lambda s: not s['capturing'] and s['open'])
assert len(resumed['images']) == 2 and resumed['state'] == 'answer'
print('lens: QML image chooser, numbered thumbnails, removal, snip cancellation and Ask both protocol passed')
PY
        exit 0
    fi
    LENS_TEST_TRIES=$((LENS_TEST_TRIES + 1))
    sleep 0.1
done
cat "$LENS_TEST_DIR/log"
echo "FAIL: QML cancellation test did not start"
exit 1
