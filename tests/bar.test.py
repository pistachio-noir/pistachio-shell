"""Actual bar/control QML with service stand-ins; never touches devices or saved user state."""
import ast,json,os,shutil,subprocess,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
# Share existing device fixtures without executing their test driver.
module=ast.parse((ROOT/'tests/settings.test.py').read_text())
MOCKS=ast.literal_eval(next(n.value for n in module.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='MOCKS' for t in n.targets)))
MOCKS.update({
 'Compositor':'''property var workspaces:[{id:1,active:true,occupied:true},{id:2,active:false,occupied:true}];property int activeWorkspace:1;property var focusedWindow:({title:"Fixture window",appId:"fixture"});property bool fullscreen:false;property var windowBounds:[];property var windows:[];property var minimized:[];function isTabbed(w){return false;}function nameOf(w){return "";}function goto(w){activeWorkspace=w;}function restore(a){}''',
 'Showoff':'property bool active:false;function stop(){active=false;}function toggle(){active=!active;}function openTerminal(r){}',
 'Screenshots':'property bool recording:false;property bool paused:false;function elapsedMs(t){return 0;}function stopRecording(){}function togglePause(){}',
 'Tray':'property var items:[];function activate(i){}function secondaryActivate(i){}function scroll(i,d,h){}',
 'Media':'property var player:null;function togglePlaying(){}function next(){}function previous(){}',
 'Cider':'property bool usable:false;property var queue:[];function refreshQueue(){}function refreshSoon(){}',
 'Chat':'property string providerName:"Claude";function show(s){}',
 'Uptime':'property int seconds:3600',
 'SettingsHub':'function openPage(p,c){}',
 'ShellSettings':'property bool quickChatTile:true;property bool shadows:true;property bool frosted:false;property bool tuiTrayOpen:false;function setTuiTrayOpen(v){tuiTrayOpen=v}',
 'FocusMode':'property bool zen:false;property var session:null;function phaseName(){return "Focus";}function clock(s){return "25:00";}function left(){return 1500;}function pause(){}',
 'Clocks':'property var timers:[];property var stopwatch:null;property var alarms:[];property bool enabled:false;property bool clocksInstalled:false;function clock(t){return "00:00";}function left(t){return 0;}function elapsed(){return 0;}function pauseTimer(i){}function pauseStopwatch(){}',
})
MOCKS['Notifs']+='property var popups:[];property int unreadCount:2;property bool unread:true;property real seenAt:0;function received(n){return 0;}'
MOCKS['Audio']+='property var recorders:[];'
MOCKS['ScreenShare']='property bool sharing:false;property var apps:[];'
MOCKS['Bluetooth']+='property int battery:-1;property string connectedName:"";property var levels:[];property var batteryDevice:({name:"Fixture headphones"});'
MOCKS['LocalSend']+='property var addedPaths:[];function add(paths){addedPaths=paths;}'
MOCKS['LocalSend']+='property var devices:[];property var items:[];property real itemsSize:0;property var send:null;property bool sendRunning:false;property bool receiving:false;property bool busy:false;property bool scanning:false;property bool toastShown:false;function scan(){}function size(s){return "0 B";}function pickFiles(f){}function paste(){}function clear(){}function sendTo(d){}function closeSend(v){}'
MOCKS['Brightness']+='function refresh(){}'
with tempfile.TemporaryDirectory(prefix='pistachio-bar-test-') as directory:
 base=Path(directory)
 for folder in ['bar','components','settings']:
  shutil.copytree(ROOT/'src'/folder,base/folder)
 (base/'services').mkdir();(base/'panels').mkdir();(base/'popups').mkdir();(base/'runtime').mkdir(mode=0o700)
 shutil.copy(ROOT/'src/Theme.qml',base/'Theme.qml');shutil.copy(ROOT/'src/panels/TuiQuickSettings.qml',base/'panels/TuiQuickSettings.qml');shutil.copy(ROOT/'src/panels/TuiLocalSendSending.qml',base/'panels/TuiLocalSendSending.qml')
 shutil.copy(ROOT/'src/services/FocusGrab.qml',base/'services/FocusGrab.qml')
 for name,body in MOCKS.items():(base/f'services/{name}.qml').write_text('pragma Singleton\nimport Quickshell\nimport QtQuick\nSingleton {\n'+body+'\n}\n')
 panel='''import Quickshell
import QtQuick
PanelWindow {
 property bool calendarShown:true; property bool open; property string page;property real slide
 readonly property int side:0;readonly property int below:0
 readonly property int panelWidth:380;readonly property int panelHeight:300
 visible:open;exclusiveZone:0
 signal powerRequested;signal launcherRequested(string mode)
 function show(n){open=true;}
}
'''
 for name in ['QuickSettings','NotificationCentre','PowerMenu']:(base/f'panels/{name}.qml').write_text(panel)
 (base/'panels/LocalSendPage.qml').write_text('import QtQuick\nItem {implicitHeight:100;signal back;signal settingsRequested}\n')
 (base/'popups/Toasts.qml').write_text('import Quickshell\nPanelWindow {property bool suppressNotifications:false;property bool phoneShown:false;property int side:0;property int above:0;property int below:0;implicitWidth:400;implicitHeight:180;visible:false;exclusiveZone:0}\n')
 (base/'popups/Osd.qml').write_text('import Quickshell\nPanelWindow {property int lift;property bool suppressed;property bool overviewOpen;visible:false;exclusiveZone:0}\n')
 shutil.copy(ROOT/'tests/bar-ui.qml',base/'shell.qml')
 env=dict(os.environ,XDG_RUNTIME_DIR=str(base/'runtime'),XDG_STATE_HOME=str(base/'state'),XDG_CACHE_HOME=str(base/'cache'))
 env['WAYLAND_DISPLAY']=os.path.join(os.environ['XDG_RUNTIME_DIR'],os.environ.get('WAYLAND_DISPLAY','wayland-1'))
 if not env.get('HYPRLAND_INSTANCE_SIGNATURE'):
  env['HYPRLAND_INSTANCE_SIGNATURE']=json.loads(subprocess.check_output(['hyprctl','instances','-j']))[0]['instance']
 with (base/'log').open('w+') as log:
  proc=subprocess.Popen(['qs','-p',directory],env=env,stdout=log,stderr=log)
  try:
   for _ in range(80):
    ready=subprocess.run(['qs','-p',directory,'ipc','call','barTest','ready'],env=env,capture_output=True,text=True)
    if ready.stdout.strip()=='true':break
    time.sleep(.1)
   result=subprocess.run(['qs','-p',directory,'ipc','call','barTest','run'],env=env,capture_output=True,text=True,timeout=20)
   log.flush();output=(base/'log').read_text()
   assert result.stdout.startswith('PASS'),result.stdout+'\n'+output
   assert 'WARN scene:' not in output and 'ERROR' not in output,output
   def call(*args):subprocess.run(['qs','-p',directory,'ipc','call','barTest',*args],env=env,check=True,capture_output=True)
   def reserved():return json.loads(subprocess.check_output(['hyprctl','--instance','0','monitors','-j']))[0]['reserved']
   call('classic');time.sleep(.2);baseline=reserved();changes=[]
   for kind in ['toast','centre']:
    call('popup',kind,'true');time.sleep(.2);during=reserved()
    call('popup',kind,'false');time.sleep(.3);after=reserved()
    changes.append((kind,during,after))
   assert all(during==baseline and after==baseline for _,during,after in changes),(baseline,changes)
   print(result.stdout.strip())
   print('PASS Classic toast/centre reserve no space on the real compositor')
  finally:
   proc.terminate();proc.wait(timeout=5)
