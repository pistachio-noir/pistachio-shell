"""The ambient clock (Experimental): the real Ambient service and AmbientClock layer on the real
compositor, with stand-in Store, Compositor, FocusMode, Clocks and Media; idle set by hand. Never
touches saved state. It shows full screen for a moment."""
import os, shutil, subprocess, tempfile, time
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
MOCKS = {
    'Store': 'property QtObject saved: QtObject { property bool ambientClock: false; property int ambientDelay: 3 }',
    'Compositor': 'property var workspaces: [{ id: 1, active: true }]; property int activeWorkspace: 1; property bool fullscreen: false; property var windows: []',
    'FocusMode': 'property var session: ({ phase: "work" }); property bool paused: false; function phaseName() { return "Work 2/4"; } function clock(ms) { return "12:30"; } function left() { return 750000; }',
    'Clocks': 'property var timers: []; property var stopwatch: null; function clock(ms) { return "0:00"; } function left(t) { return 0; } function elapsed() { return 0; }',
    'Media': 'property var player: ({ trackTitle: "Fixture song", trackArtist: "Fixture band", trackArtUrl: "", isPlaying: true })',
}
with tempfile.TemporaryDirectory(prefix='pistachio-ambient-test-') as directory:
    base = Path(directory)
    shutil.copytree(ROOT / 'src/components', base / 'components')
    for d in ['services', 'popups', 'runtime']: (base / d).mkdir()
    os.chmod(base / 'runtime', 0o700)
    shutil.copy(ROOT / 'src/Theme.qml', base / 'Theme.qml')
    shutil.copy(ROOT / 'src/popups/AmbientClock.qml', base / 'popups/AmbientClock.qml')
    shutil.copy(ROOT / 'src/services/Ambient.qml', base / 'services/Ambient.qml')
    for name, body in MOCKS.items():
        (base / f'services/{name}.qml').write_text('pragma Singleton\nimport Quickshell\nimport QtQuick\nSingleton {\n' + body + '\n}\n')
    shutil.copy(ROOT / 'tests/ambient-clock-ui.qml', base / 'shell.qml')
    env = dict(os.environ, XDG_RUNTIME_DIR=str(base / 'runtime'), XDG_STATE_HOME=str(base / 'state'), XDG_CACHE_HOME=str(base / 'cache'))
    env['WAYLAND_DISPLAY'] = os.path.join(os.environ['XDG_RUNTIME_DIR'], os.environ.get('WAYLAND_DISPLAY', 'wayland-1'))
    with (base / 'log').open('w+') as log:
        proc = subprocess.Popen(['qs', '-p', directory], env=env, stdout=log, stderr=log)
        call = lambda *a: subprocess.run(['qs', '-p', directory, 'ipc', 'call', *a], env=env, capture_output=True, text=True, timeout=30).stdout.strip()
        try:
            for _ in range(80):
                if call('ambientTest', 'ready') == 'true': break
                time.sleep(.1)
            result = call('ambientTest', 'run')
            status = call('ambient', 'status')
            log.flush(); output = (base / 'log').read_text()
            assert result.startswith('PASS'), result + '\n' + output
            assert '"enabled":true' in status and '"delay":5' in status, status
            assert 'ERROR' not in output and 'WARN scene' not in output, output
            print(result); print('PASS IPC ambient status')
        finally:
            proc.terminate(); proc.wait(timeout=5)
