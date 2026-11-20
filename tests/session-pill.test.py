"""The Zen Pomodoro pill's Hide (popups/SessionPill.qml): the real QML on the real compositor with a
stand-in FocusMode; never touches saved state. Hide, Keep shown, the handle's 4 px strip, and Hide
forgotten when Zen ends. The pill shows briefly at the bottom of the screen."""
import json, os, shutil, subprocess, tempfile, time
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
MOCKS = {
    'FocusMode': 'property bool zen:true;property var session:({owner:"zen",pomodoro:true,phase:"work",round:1,endsAt:Date.now()+600000});'
                 'property bool paused:false;property bool working:true;function phaseName(){return "Work 1/4";}'
                 'function clock(s){return "10:00";}function left(){return 600000;}function pause(){}function skip(){}function endSession(){}function showPhone(){}',
    'ShellSettings': 'property bool phonePreview:true;property bool frosted:false;property bool shadows:true',
}
with tempfile.TemporaryDirectory(prefix='pistachio-pill-test-') as directory:
    base = Path(directory)
    shutil.copytree(ROOT / 'src/components', base / 'components')
    (base / 'services').mkdir(); (base / 'popups').mkdir(); (base / 'runtime').mkdir(mode=0o700)
    shutil.copy(ROOT / 'src/Theme.qml', base / 'Theme.qml')
    shutil.copy(ROOT / 'src/popups/SessionPill.qml', base / 'popups/SessionPill.qml')
    for name, body in MOCKS.items():
        (base / f'services/{name}.qml').write_text('pragma Singleton\nimport Quickshell\nimport QtQuick\nSingleton {\n' + body + '\n}\n')
    shutil.copy(ROOT / 'tests/session-pill-ui.qml', base / 'shell.qml')
    env = dict(os.environ, XDG_RUNTIME_DIR=str(base / 'runtime'), XDG_STATE_HOME=str(base / 'state'), XDG_CACHE_HOME=str(base / 'cache'))
    env['WAYLAND_DISPLAY'] = os.path.join(os.environ['XDG_RUNTIME_DIR'], os.environ.get('WAYLAND_DISPLAY', 'wayland-1'))
    with (base / 'log').open('w+') as log:
        proc = subprocess.Popen(['qs', '-p', directory], env=env, stdout=log, stderr=log)
        call = lambda *a: subprocess.run(['qs', '-p', directory, 'ipc', 'call', 'pillTest', *a], env=env, capture_output=True, text=True, timeout=20).stdout.strip()
        try:
            for _ in range(80):
                if call('ready') == 'true': break
                time.sleep(.1)
            result = call('run')
            log.flush(); output = (base / 'log').read_text()
            assert result.startswith('PASS'), result + '\n' + output
            # tucked with no pointer on it: the handle, and only a 4 px strip at the edge takes the pointer
            call('tuck'); time.sleep(.6)
            state = json.loads(call('state'))
            assert state['hidden'] and state['grown'] == 0 and state['maskH'] == 4 and state['maskY'] == state['height'] - 4, state
            output = (base / 'log').read_text()
            assert 'ERROR' not in output and 'WARN scene:' not in output, output
            print(result); print('PASS tucked into the handle with a 4 px strip')
        finally:
            proc.terminate(); proc.wait(timeout=5)
