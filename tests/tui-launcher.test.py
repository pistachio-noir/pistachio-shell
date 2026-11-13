"""Native launcher/switcher drawing and input, with isolated state and device/action boundaries."""
import ast,json,os,shutil,subprocess,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
module=ast.parse((ROOT/'tests/settings.test.py').read_text())
MOCKS=ast.literal_eval(next(n.value for n in module.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='MOCKS' for t in n.targets)))
MOCKS.update({
 'Store':'property var saved:({zenPomodoro:false,pomodoroWork:25,pomodoroBreak:5,focusPomodoro:false,focusMinutes:25})',
 'Apps':'''property var list:Array.from({length:70},(_,i)=>({id:"fixture"+i,name:i?"Application "+i:"Helium",genericName:"Web browser",comment:"Fixture",keywords:[],actions:[],icon:""}));property string launched;property var claudeApp:null;property string terminal:"kitty";property var terminalChoices:["kitty"];property var recentCommands:[];function icon(s){return "";}function iconFor(s){return "";}function nameFor(s){return s;}function frecency(a){return a.id==="fixture0"?1:0;}function programOf(a){return a.id;}function launch(a){launched=a.id;}function launchAction(a,b){}function terminalName(s){return s;}function terminalIcon(s){return "";}function setTerminal(s){}function inTerminal(s){}function run(s,t){}function askClaude(s){}function searchWeb(s){}''',
 'Compositor':'''property var windows:Array.from({length:15},(_,i)=>({address:String(i),title:"Window "+i,appId:i?"kitty":"helium",workspace:1+i%5,recency:i,group:[],minimized:false,urgent:false,floating:false,toplevel:null,bounds:Qt.rect(0,0,640,480)}));property var workspaces:[{id:1,active:true},{id:2,active:false}];property int activeWorkspace:1;property var names:({});property var presets:[{name:"Study",names:{},apps:{}}];property var binds:[];property var focused:[];property string closed;property int went;function nameOf(i){return i===1?"code":"";}function isTabbed(i){return i===1;}function focus(a){focused=focused.concat([a]);}function close(a){closed=a;}function goto(i){went=i;}function moveWindow(a,i){}function sendWindow(a,i){}function restore(a){focus(a);}function setName(i,n){}function setTabbed(i,b){}function toggleFloating(a){}function togglePin(a){}function floatingPreset(a,x,y){}function loadBinds(){}function savePreset(n){}function loadPreset(p){}function deletePreset(p){}''',
 'ShellSettings':'property bool shadows:false;function integration(s){return s==="tldr";}function lensChoices(s){return [];}function lensLabel(s){return "";}function setLensChoice(k,v){}',
 'LauncherTools':'property var pins:[];property var aliases:({});property var pending:({});property var actions:[];function resolve(d){return d?.kind==="app"?{kind:"app",key:"pin:"+d.target,title:"Pinned fixture",subtitle:"Alias fixture",app:Apps.list[0],descriptor:d}:null;}function aliasFor(r){return "";}function pinned(d){return false;}function checkAlias(s,d){return "";}function togglePin(d){}function movePin(d,n){}function setAlias(s,d){}function activateAction(d){}function showFile(p,m){}',
 'Library':'property bool clion:false;property bool vscode:false;property var projects:[];property var codeProjects:[];property var games:[];function load(){}function openProject(p){}function play(p){}',
 'Files':'property string home:"/tmp";property bool ready:true;property int count:0;property string place:"";property var results:[];function setActive(b){}function search(s){}function reveal(e){}function open(e){}',
 'Processes':'property var groups:[];function load(){}function endAll(g){}',
 'Tldr':'property bool busy:false;property bool missing:false;property string description:"A detailed paragraph explaining this command and its arguments. ".repeat(12);property string page:"tar";property string more:"https://example.invalid/manual";property var examples:[{what:"List an archive",command:"tar tf archive.tar"}];function lookup(s){}',
 'Qalc':'property bool installed:false;property string answer:"";property string expression:"";property bool failed:false;function ask(s){}',
 'Cider':'property bool installed:false;property bool enabled:false;property bool reachable:false;property bool usable:false;property bool searching:false;property var results:[];function search(s){}function play(i,m){}function check(s,f){}function setToken(s){}',
 'Clocks':'function parseDuration(s){return 60;}function startTimer(s,n){}function addAlarm(t,n){}',
 'Chat':'property string providerName:"Claude";function show(p){}',
 'Showoff':'property bool active:false;function toggle(){}',
 'Desktop':'function check(s){return "";}function newFolder(c,n){}function rename(i,n){}',
 'Drives':'function eject(d){}',
})
MOCKS['Notifs']+='property string dndStatus:"Off";function age(n){return "now";}function clearAll(){}function iconSource(n){return "";}function isCritical(n){return false;}function own(n){return false;}function received(n){return 0;}'
MOCKS['Bluetooth']=MOCKS['Bluetooth'].replace('function pair(d){}','function pair(d){ask("confirm");}')
MOCKS['NightLight']+='property string status:"Off";'
MOCKS['FocusMode']='property bool zen:false;property bool pomodoring:false;property bool focusing:false;property var session:null;function toggleZen(){zen=!zen;}function togglePomodoro(){}function toggleFocus(){}function phaseName(){return "Focus";}function clock(t){return "25:00";}function left(){return 1500;}'
with tempfile.TemporaryDirectory(prefix='pistachio-tui-launcher-') as directory:
 base=Path(directory)
 for folder in ['launcher','components']:shutil.copytree(ROOT/'src'/folder,base/folder)
 for folder in ['services','panels','runtime']:(base/folder).mkdir(mode=0o700)
 for name in ['WindowSwitcher.qml','TuiWindowSwitcher.qml']:
  if (ROOT/'src/panels'/name).exists():shutil.copy(ROOT/'src/panels'/name,base/'panels'/name)
 shutil.copy(ROOT/'src/Theme.qml',base/'Theme.qml')
 for name in ['FocusGrab.qml']:shutil.copy(ROOT/'src/services'/name,base/'services'/name)
 for name,body in MOCKS.items():(base/f'services/{name}.qml').write_text('pragma Singleton\nimport Quickshell\nimport QtQuick\nSingleton {\n'+body+'\n}\n')
 shutil.copy(ROOT/'tests/tui-launcher.qml',base/'shell.qml')
 env=dict(os.environ,XDG_RUNTIME_DIR=str(base/'runtime'),XDG_STATE_HOME=str(base/'state'),XDG_CACHE_HOME=str(base/'cache'))
 env['WAYLAND_DISPLAY']=os.path.join(os.environ['XDG_RUNTIME_DIR'],os.environ.get('WAYLAND_DISPLAY','wayland-1'))
 env['HYPRLAND_INSTANCE_SIGNATURE']=os.environ.get('HYPRLAND_INSTANCE_SIGNATURE') or json.loads(subprocess.check_output(['hyprctl','instances','-j']))[0]['instance']
 with (base/'log').open('w+') as log:
  proc=subprocess.Popen(['qs','-p',directory],env=env,stdout=log,stderr=log)
  try:
   for _ in range(60):
    ready=subprocess.run(['qs','-p',directory,'ipc','call','tuiLauncherTest','ready'],env=env,capture_output=True,text=True)
    if ready.stdout.strip()=='true':break
    if proc.poll() is not None:break
    time.sleep(.1)
   results=[]
   if os.environ.get('PISTACHIO_LAUNCHER_REGRESSIONS')!='1':
    result=subprocess.run(['qs','-p',directory,'ipc','call','tuiLauncherTest','run'],env=env,capture_output=True,text=True,timeout=30)
    results.append(result.stdout)
   for case in ['scan','pairing','bounds','note','emoji','pins','switcher','style']:
    result=subprocess.run(['qs','-p',directory,'ipc','call','tuiLauncherTest','regression',case],env=env,capture_output=True,text=True,timeout=10)
    results.append(result.stdout)
   log.flush();output=(base/'log').read_text()
   assert all(r.startswith('PASS') for r in results),'\n'.join(results)+'\n'+output
   assert 'WARN scene:' not in output and 'ERROR' not in output,output
   print('\n'.join(r.strip() for r in results))
  finally:proc.terminate();proc.wait(timeout=5)
