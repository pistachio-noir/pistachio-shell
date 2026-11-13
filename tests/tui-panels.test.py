"""Actual Overview/notification/calendar/weather UI; all device/data actions are stand-ins."""
import json,os,shutil,subprocess,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
scope={'__file__':str(ROOT/'tests/tui-launcher.test.py')}
header=(ROOT/'tests/tui-launcher.test.py').read_text().split('with tempfile.TemporaryDirectory')[0]
exec(header,scope)
MOCKS=scope['MOCKS']
MOCKS['Compositor']=MOCKS['Compositor'].replace('id:1,active:true','id:1,active:true,occupied:true').replace('id:2,active:false','id:2,active:false,occupied:true').replace('function goto(i){went=i;}','function goto(i){went=i;activeWorkspace=i;}').replace('function sendWindow(a,i){}','property var sent:[];function sendWindow(a,i){sent=sent.concat([{address:a,workspace:i}]);}')
MOCKS['Wallpapers']='property string current:"";function fitOf(p){return "cover";}'
MOCKS['Weather']='''property bool available:true;property bool enabled:true;property string city:"Fixture city";property string placeName:"Fixture city · Country";property var place:({name:"Fixture city",country:"Country"});property var now:({temp:8,feels:5,humidity:71,wind:14,code:3,day:true});property var today:({max:9,min:4,sunset:"15:38"});property var days:Array.from({length:5},(_,i)=>({name:["Fri","Sat","Sun","Mon","Tue"][i],code:3,max:7+i,min:2+i}));property var hours:Array.from({length:8},(_,i)=>({label:i?String(17+i):"Now",code:3,day:true,temp:8-i,rain:i*10}));function describe(c){return {text:"cloudy"};}function refresh(){}function setCity(s){city=s;}'''
MOCKS['Events']='''property bool available:true;property bool enabled:false;property bool watching:false;property var byDay:({});property var events:[];property var loaded:[];property int opened;function key(d){return Qt.formatDate(d,"yyyy-MM-dd");}function on(d){return events;}function load(y,m){loaded=[y,m];}function refresh(){}function open(){opened++;}function colourFor(s){return Theme.sageBlue;}function calendarName(s){return "Fixture";}'''
MOCKS['Notifs']='''property bool dnd:false;property real seenAt:0;property real seenBefore:0;property int invoked:-1;property var notifications:Array.from({length:4},(_,i)=>({id:i+1,appName:i<2?"Mail":"Application "+i,summary:"Fixture notification "+i,body:"A message for the test",time:Date.now()-i*60000,saved:false,resident:false,actions:[],urgency:0,appIcon:"",image:""}));function preview(n){return "";}function age(t,now){return "now";}function received(n){return n?.time??0;}function own(n){return false;}function isCritical(n){return false;}function iconSource(n){return "";}function markSeen(){seenBefore=seenAt;seenAt=Date.now();}function setDnd(v){dnd=v;}function dismiss(n){notifications=notifications.filter(x=>x!==n);}function clearAll(){notifications=[];}function clearApp(a){notifications=notifications.filter(n=>n.appName!==a);}function invokeDefault(n){if(n)invoked=n.id;}function ruleChoices(a){return [];}'''
with tempfile.TemporaryDirectory(prefix='pistachio-tui-panels-') as directory:
 base=Path(directory)
 shutil.copytree(ROOT/'src/components',base/'components');shutil.copytree(ROOT/'src/shaders',base/'shaders')
 for folder in ['services','panels','launcher','runtime']:(base/folder).mkdir(mode=0o700)
 for name in ['Overview.qml','OverviewThumb.qml','OverviewChip.qml','DashedFrame.qml','NotificationCentre.qml','Calendar.qml','MonthPage.qml','WeatherPanel.qml','calendar.js','TuiOverview.qml','TuiOverviewWindow.qml','TuiNotificationList.qml','TuiCalendar.qml','TuiWeather.qml']:
  if (ROOT/'src/panels'/name).exists():shutil.copy(ROOT/'src/panels'/name,base/'panels'/name)
 for name in ['Overview','NotificationCentre']:
  p=base/'panels'/str(name+'.qml');s=p.read_text();s=s.replace('id: content','id: content; objectName: "overview-capture"').replace('id: panels','id: panels; objectName: "centre-capture"');p.write_text(s)
 for name in ['fuzzy.js','KeyHints.qml']:shutil.copy(ROOT/'src/launcher'/name,base/'launcher'/name)
 for name in ['Theme.qml']:shutil.copy(ROOT/'src'/name,base/name)
 shutil.copy(ROOT/'src/services/FocusGrab.qml',base/'services/FocusGrab.qml')
 for name,body in MOCKS.items():(base/f'services/{name}.qml').write_text('pragma Singleton\nimport qs\nimport Quickshell\nimport QtQuick\nSingleton {id:service\n'+body+'\n}\n')
 shutil.copy(ROOT/'tests/tui-panels.qml',base/'shell.qml')
 env=dict(os.environ,XDG_RUNTIME_DIR=str(base/'runtime'),XDG_STATE_HOME=str(base/'state'),XDG_CACHE_HOME=str(base/'cache'))
 env['WAYLAND_DISPLAY']=os.path.join(os.environ['XDG_RUNTIME_DIR'],os.environ.get('WAYLAND_DISPLAY','wayland-1'))
 env['HYPRLAND_INSTANCE_SIGNATURE']=os.environ.get('HYPRLAND_INSTANCE_SIGNATURE') or json.loads(subprocess.check_output(['hyprctl','instances','-j']))[0]['instance']
 with (base/'log').open('w+') as log:
  proc=subprocess.Popen(['qs','-p',directory],env=env,stdout=log,stderr=log)
  try:
   for _ in range(60):
    p=subprocess.run(['qs','-p',directory,'ipc','call','panelsTest','ready'],env=env,capture_output=True,text=True)
    if p.stdout.strip()=='true':break
    if proc.poll() is not None:break
    time.sleep(.1)
   p=subprocess.run(['qs','-p',directory,'ipc','call','panelsTest','classic' if os.environ.get('PISTACHIO_PANELS_CLASSIC_ONLY')=='1' else 'run'],env=env,capture_output=True,text=True,timeout=30)
   log.flush();output=(base/'log').read_text()
   assert p.stdout.startswith('PASS'),p.stdout+'\n'+output
   assert 'WARN scene:' not in output and 'ERROR' not in output,output
   print(p.stdout.strip())
  finally:proc.terminate();proc.wait(timeout=5)
