#!/bin/sh
# Real Wayland Lens windows, fake providers, fixture files only. Never uses owner model allowance.
set -eu
LENS_NATIVE_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
LENS_NATIVE_DIR=$(mktemp -d /tmp/pistachio-lens-native.XXXXXX)
LENS_NATIVE_PID=
cleanup() {
    if [ -n "$LENS_NATIVE_PID" ]; then kill "$LENS_NATIVE_PID" 2>/dev/null || true; wait "$LENS_NATIVE_PID" 2>/dev/null || true; fi
    rm -rf "$LENS_NATIVE_DIR"
}
trap cleanup EXIT HUP INT TERM
for LENS_NATIVE_PART in services components popups settings; do ln -s "$LENS_NATIVE_ROOT/src/$LENS_NATIVE_PART" "$LENS_NATIVE_DIR/$LENS_NATIVE_PART"; done
ln -s "$LENS_NATIVE_ROOT/src/Theme.qml" "$LENS_NATIVE_DIR/Theme.qml"
cp "$LENS_NATIVE_ROOT/tests/lens-native.qml" "$LENS_NATIVE_DIR/shell.qml"
python3 -B - "$LENS_NATIVE_ROOT" "$LENS_NATIVE_DIR" <<'PY'
import json, pathlib, runpy, struct, sys, zlib
root, base = map(pathlib.Path, sys.argv[1:])
(base / 'bin').mkdir()
fake = runpy.run_path(str(root / 'tests/lens.test.py'))['FAKE']
for name in ('claude', 'codex'):
    script = base / 'bin' / name
    script.write_text(fake); script.chmod(0o755)
script = base / 'bin/zenity'
script.write_text('#!/bin/sh\nprintf "%s\\n" "$LENS_TEST_IMAGE"\n'); script.chmod(0o755)
script = base / 'bin/python3'
script.write_text('''#!/usr/bin/python3
import os, pathlib, runpy, sys
from unittest.mock import patch
with patch('pathlib.Path.home', return_value=pathlib.Path(os.environ['LENS_TEST_HOME'])):
    runpy.run_path(sys.argv[-1], run_name='__main__')
'''); script.chmod(0o755)
chunk=lambda tag,data: struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data))
w,h=520,220
pixels=b''.join(b'\0'+bytes((42,47,31))*w for _ in range(h))
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(pixels))+chunk(b'IEND',b'')
(base / 'snip.png').write_bytes(png)
(base / 'control.json').write_text(json.dumps({'answers':{'claude':'The first image shows the original state.','codex':'The second view confirms the change.'}}))
PY
export LENS_TEST_CONTROL="$LENS_NATIVE_DIR/control.json"
export LENS_TEST_RECORD="$LENS_NATIVE_DIR/calls.jsonl"
export LENS_TEST_HOME="$LENS_NATIVE_DIR"
export LENS_TEST_IMAGE="$LENS_NATIVE_DIR/snip.png"
export PATH="$LENS_NATIVE_DIR/bin:$PATH"
export XDG_STATE_HOME="$LENS_NATIVE_DIR/state"
export XDG_CACHE_HOME="$LENS_NATIVE_DIR/cache"
pgrep -ax qs || true
qs -p "$LENS_NATIVE_DIR" >"$LENS_NATIVE_DIR/log" 2>&1 &
LENS_NATIVE_PID=$!
/usr/bin/python3 - "$LENS_NATIVE_DIR" <<'PY'
import json, pathlib, subprocess, sys, time
base=pathlib.Path(sys.argv[1])
def call(method,*args):
    return subprocess.check_output(['qs','-p',str(base),'ipc','call','lensNative',method,*args],text=True,stderr=subprocess.DEVNULL)
def wait(check):
    deadline=time.monotonic()+8
    while time.monotonic()<deadline:
        try:
            state=json.loads(call('state'))
            if check(state): return state
        except (subprocess.CalledProcessError, ValueError): pass
        time.sleep(.04)
    raise AssertionError((base/'log').read_text())
wait(lambda s:True)
call('beginFixture',str(base/'snip.png'))
wait(lambda s:s['ready'] and s['open'] and s['count']==1)
call('questionFixture')
time.sleep(.2)
subprocess.run(['grim','/tmp/pistachio-lens-one-prompt.png'],check=True)
buttons=json.loads(call('toolbarFixture'))
assert len({round(buttons[label]['y'],1) for label in ['Add snip','Add image','Attach file','Ask both']})==1,buttons
for count in (2,3):
    call('imageFixture'); wait(lambda s:s['count']==count and not s['picking']);time.sleep(.1)
    buttons=json.loads(call('toolbarFixture'))
    assert len({round(buttons[label]['y'],1) for label in ['Add snip','Add image','Attach file','Ask both']})==1,buttons
time.sleep(.4)
subprocess.run(['grim','/tmp/pistachio-lens-prompt.png'],check=True)
call('bothFixture'); wait(lambda s:s['state']=='answer' and s['combined'])
time.sleep(.4)
subprocess.run(['grim','/tmp/pistachio-lens-combined.png'],check=True)
geometry=json.loads(call('geometryFixture'))
assert geometry['closeRight']<=geometry['headerWidth']+.5,geometry
call('oneImageFixture');wait(lambda s:s['count']==1);time.sleep(.2)
buttons=json.loads(call('toolbarFixture'))
assert len({round(buttons[label]['y'],1) for label in ['Add snip','Add image','Attach file']})==1,buttons
assert abs(buttons['Ask ChatGPT instead']['y']-buttons['Ask both']['y'])<.5,buttons
assert buttons['Ask both']['y']>buttons['Attach file']['y'],buttons
subprocess.run(['grim','/tmp/pistachio-lens-one-answer.png'],check=True)
call('crowdedFixture');time.sleep(.2)
geometry=json.loads(call('geometryFixture'))
assert geometry['cardHeight']<=geometry['limit']+.5,geometry
assert all(a['x']+a['width']<=geometry['actionsWidth']+.5 for a in geometry['actions']),geometry
subprocess.run(['grim','/tmp/pistachio-lens-crowded.png'],check=True)
calls=[json.loads(line) for line in (base/'calls.jsonl').read_text().splitlines()]
assert [c['name'] for c in calls]==['claude','codex','claude'],calls
assert calls[1]['args'].count('--image')==3
call('closeFixture'); wait(lambda s:not s['open']); time.sleep(.5)
log=(base/'log').read_text()
assert 'Configuration Loaded' in log,log
unexpected = [line for line in log.splitlines() if any(word in line for word in (' ERROR',' WARN','TypeError','ReferenceError')) and 'qt.qpa.wayland.textinput:' not in line]
assert not unexpected,log
warnings = sum('qt.qpa.wayland.textinput:' in line for line in log.splitlines())
print('lens: aligned attachment/agent rows for one/two/three images, prompt/answer/crowded bounds and close passed; no QML errors or warnings')
if warnings: print('lens: %d transient Qt Wayland text-input focus warnings during chooser transitions' % warnings)
print('Screenshots: /tmp/pistachio-lens-prompt.png /tmp/pistachio-lens-combined.png')
PY
