"""Actual Qt layout, no system services or owner state."""
import os,pathlib,shutil,subprocess,tempfile,time
ROOT=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='pistachio-layout-') as d:
 base=pathlib.Path(d);(base/'launcher').mkdir();(base/'components').mkdir();(base/'panels').mkdir();shutil.copy(ROOT/'src/panels/DesktopCat.qml',base/'panels/DesktopCat.qml');
 for name in ['ActionButton.qml','Icon.qml','Switch.qml','Slider.qml','PanelFrame.qml']:shutil.copy(ROOT/'src/components'/name,base/'components'/name)
 (base/'runtime').mkdir(mode=0o700);(base/'services').mkdir()
 for name,body in {'Clocks':'property var ringing: null','FocusMode':'signal phaseFinished(string message)'}.items():(base/f'services/{name}.qml').write_text('pragma Singleton\nimport Quickshell\nimport QtQuick\nSingleton { '+body+' }\n')
 shutil.copy(ROOT/'src/Theme.qml',base/'Theme.qml');shutil.copy(ROOT/'src/launcher/KeyHints.qml',base/'launcher/KeyHints.qml');shutil.copy(ROOT/'tests/layout-ui.qml',base/'shell.qml')
 env=dict(os.environ,QT_QPA_PLATFORM='offscreen',XDG_RUNTIME_DIR=str(base/'runtime'),XDG_CACHE_HOME=str(base/'cache'));env.pop('WAYLAND_DISPLAY',None);env.pop('DISPLAY',None)
 with (base/'log').open('w+') as log:
  proc=subprocess.Popen(['qs','-p',d],env=env,stdout=log,stderr=log)
  try:
   for _ in range(50):
    p=subprocess.run(['qs','-p',d,'ipc','call','layoutTest','ready'],env=env,capture_output=True,text=True)
    if p.stdout.strip()=='true':break
    time.sleep(.05)
   p=subprocess.run(['qs','-p',d,'ipc','call','layoutTest','run'],env=env,capture_output=True,text=True,timeout=10)
   assert p.returncode==0 and p.stdout.startswith('PASS'),p.stdout+p.stderr
   print(p.stdout.strip())
  finally:
   proc.terminate();proc.wait(timeout=5);log.seek(0);out=log.read()
   assert 'ERROR' not in out,out
