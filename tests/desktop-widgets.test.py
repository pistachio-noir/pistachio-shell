"""Desktop widgets (Experimental): the real widget layer, studio and DesktopWidgets service on the real
compositor, with stand-in Store, Compositor, FocusMode, SystemStats, Weather and Desktop; never touches
saved state. The studio shows full screen for a moment. The grid rules are tests/desktop-grid.test.js."""
import os, shutil, subprocess, tempfile, time
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
MOCKS = {
    'Store': 'property QtObject saved: QtObject { property bool desktopWidgets: true; property var widgetLayout: null }',
    'Compositor': 'property var workspaces: [{ id: 1, active: true }]; property int activeWorkspace: 1; property bool fullscreen: false; property var windows: []',
    'FocusMode': 'property bool zen: false; property var session: null; property bool paused: false; function phaseName() { return "Work 1/4"; } function clock(ms) { return "25:00"; } function left() { return 0; }',
    'Media': 'property var player: null',
    'Clocks': 'property var timers: []; property var stopwatch: null; function clock(ms) { return "0:00"; } function left(t) { return 0; } function elapsed() { return 0; }',
    'SystemStats': 'property int widgetWatchers; function watchWidget(on) { widgetWatchers = Math.max(0, widgetWatchers + (on ? 1 : -1)); } property real cpu: 0.42; property real memUsed: 7.5; property real memTotal: 16; property var disks: [{ mount: "/", size: 500, free: 120, low: false }]; property bool gpuFound: true; property real gpu: 0.3; property real gpuTemp: 51',
    'Weather': 'property bool enabled: true; property bool available: true; property var now: ({ temp: 4, code: 3, day: true }); property var place: ({ name: "Fixture town" }); property string city: "Fixture"; function describe(c) { return { text: "Overcast", kind: "cloud" }; }',
    'Showoff': 'property bool active: false',
    'Desktop': 'property bool enabled: true; property var items: [{ name: "a" }, { name: "b" }]; property var positions: ({})',
    'Wallpapers': 'property string current: ""; function fitOf(path) { return "fill"; }',
    'ShellSettings': 'property bool monochromeWallpaper: false; property bool frosted: false; property bool shadows: true',
}
with tempfile.TemporaryDirectory(prefix='pistachio-widgets-test-') as directory:
    base = Path(directory)
    shutil.copytree(ROOT / 'src/components', base / 'components')
    for d in ['services', 'panels', 'popups', 'runtime']: (base / d).mkdir()
    os.chmod(base / 'runtime', 0o700)
    shutil.copy(ROOT / 'src/Theme.qml', base / 'Theme.qml')
    for f in ['DesktopWidget.qml', 'DesktopWidgetLayer.qml', 'desktopGrid.js', 'DashedFrame.qml']:
        shutil.copy(ROOT / 'src/panels' / f, base / 'panels' / f)
    shutil.copy(ROOT / 'src/popups/WidgetStudio.qml', base / 'popups/WidgetStudio.qml')
    shutil.copy(ROOT / 'src/services/DesktopWidgets.qml', base / 'services/DesktopWidgets.qml')
    for name, body in MOCKS.items():
        (base / f'services/{name}.qml').write_text('pragma Singleton\nimport Quickshell\nimport QtQuick\nSingleton {\n' + body + '\n}\n')
    shutil.copy(ROOT / 'tests/desktop-widgets-ui.qml', base / 'shell.qml')
    env = dict(os.environ, XDG_RUNTIME_DIR=str(base / 'runtime'), XDG_STATE_HOME=str(base / 'state'), XDG_CACHE_HOME=str(base / 'cache'))
    env['WAYLAND_DISPLAY'] = os.path.join(os.environ['XDG_RUNTIME_DIR'], os.environ.get('WAYLAND_DISPLAY', 'wayland-1'))
    with (base / 'log').open('w+') as log:
        proc = subprocess.Popen(['qs', '-p', directory], env=env, stdout=log, stderr=log)
        call = lambda *a: subprocess.run(['qs', '-p', directory, 'ipc', 'call', *a], env=env, capture_output=True, text=True, timeout=30).stdout.strip()
        try:
            for _ in range(80):
                if call('widgetsTest', 'ready') == 'true': break
                time.sleep(.1)
            result = call('widgetsTest', 'run')
            status = call('widgets', 'status')
            log.flush(); output = (base / 'log').read_text()
            assert result.startswith('PASS'), result + '\n' + output
            assert '"arranging":false' in status, status
            assert 'ERROR' not in output and 'WARN scene' not in output, output
            print(result); print('PASS IPC widgets status')
        finally:
            proc.terminate(); proc.wait(timeout=5)
