import os,re,shutil,subprocess,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
scope={'__file__':str(ROOT/'tests/tui-launcher.test.py')}
exec((ROOT/'tests/tui-launcher.test.py').read_text().split('with tempfile.TemporaryDirectory')[0],scope)
mocks=scope['MOCKS']
mocks['Clocks']+='property var ringing:null;property var timers:[];'
mocks['FocusMode']+='signal phaseFinished(string message);'
mocks['Desktop']='property bool enabled:true;property var items:[];property var positions:({fixture:[2,0]});function kindOf(x){return "folder";}function open(x){}function placeAll(x){}function setEnabled(x){enabled=x;}function showFolder(){}function trash(x){}function copyIn(a,b){}'
mocks['Compositor']+='function windowBounds(){return [];}'
mocks['Compositor']+='property bool fullscreen:false;'
mocks['Compositor']+='property var focusedWindow:null;'
mocks['Apps']+='property var terminals:({kitty:{appId:"kitty"}});'
mocks['Media']='property var players:[];'
mocks['ShellSettings']+='property bool desktopCat:true;property string catSkin:"cream";'
with tempfile.TemporaryDirectory(prefix='pistachio-cat-input-') as d:
 base=Path(d);shutil.copytree(ROOT/'src/components',base/'components');(base/'panels').mkdir();(base/'services').mkdir();(base/'runtime').mkdir(mode=0o700)
 for n in ['DesktopCat.qml','DesktopIcons.qml','desktopGrid.js']:shutil.copy(ROOT/'src/panels'/n,base/'panels'/n)
 shutil.copy(ROOT/'src/Theme.qml',base/'Theme.qml')
 wallpaper=(ROOT/'src/panels/Wallpaper.qml').read_text()
 active=re.search(r'^\s+active: (.+)',wallpaper[wallpaper.index('id: desktopCat'):],re.M).group(1)
 target=re.search(r'anchors.fill: desktopCat\n\s+enabled: (.+)',wallpaper).group(1).replace('desktopCat.visible','cat.visible')
 skin=re.search(r'^\s+skin: (.+)',wallpaper[wallpaper.index('id: desktopCat'):],re.M).group(1)
 (base/'shell.qml').write_text((ROOT/'tests/cat-interaction.qml').read_text().replace('active:true; interactive:true; skin:ShellSettings.catSkin',f'active:{active}; interactive:true; skin:{skin}').replace('enabled:FocusMode.zen && !Showoff.active && cat.visible',f'enabled:{target}'))
 for name,body in mocks.items():(base/f'services/{name}.qml').write_text('pragma Singleton\nimport Quickshell\nimport QtQuick\nSingleton {\n'+body+'\n}\n')
 env=dict(os.environ,QT_QPA_PLATFORM='offscreen',XDG_RUNTIME_DIR=str(base/'runtime'),XDG_STATE_HOME=str(base/'state'),XDG_CACHE_HOME=str(base/'cache'));env.pop('DISPLAY',None)
 if os.environ.get('PISTACHIO_CAT_NATIVE')=='1':
  env['QT_QPA_PLATFORM']='wayland';env['WAYLAND_DISPLAY']=os.path.join(os.environ['XDG_RUNTIME_DIR'],os.environ.get('WAYLAND_DISPLAY','wayland-1'))
 else:env.pop('WAYLAND_DISPLAY',None)
 with (base/'log').open('w+') as log:
  proc=subprocess.Popen(['qs','-p',d],env=env,stdout=log,stderr=log)
  try:
   for _ in range(50):
    r=subprocess.run(['qs','-p',d,'ipc','call','catTest','ready'],env=env,capture_output=True,text=True)
    if r.stdout.strip()=='true':break
    if proc.poll() is not None:break
    time.sleep(.1)
   r=subprocess.run(['qs','-p',d,'ipc','call','catTest','run'],env=env,capture_output=True,text=True,timeout=10)
   log.flush();out=(base/'log').read_text();assert r.stdout.startswith('PASS'),r.stdout+'\n'+out
   assert 'ERROR' not in out and 'WARN scene:' not in out,out
   print(r.stdout.strip())
  finally:proc.terminate();proc.wait(timeout=5)
