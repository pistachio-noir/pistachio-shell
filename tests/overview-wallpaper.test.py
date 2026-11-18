# Native Wayland pixel regression; uses only temporary images and isolated services.
import os, shutil, subprocess, tempfile, time, re
from pathlib import Path
from PIL import Image
repo=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='pistachio-wallpaper-noir-') as folder:
 p=Path(folder)
 (p/'components').mkdir();(p/'services').mkdir();(p/'runtime').mkdir(mode=0o700)
 shutil.copy(repo/'src/components/WallpaperView.qml',p/'components/WallpaperView.qml')
 shutil.copy(repo/'src/Theme.qml',p/'Theme.qml')
 (p/'services/ShellSettings.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool monochromeWallpaper:false }')
 (p/'services/Wallpapers.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function fitOf(path) { return "fill"; } }')
 Image.new('RGB',(64,64),(210,70,30)).save(p/'source.png')
 effect=re.search(r'layer.enabled: true\s+layer.effect: MultiEffect \{[^}]+\}',(repo/'src/panels/Overview.qml').read_text())[0]
 (p/'shell.qml').write_text('''import Quickshell
import QtQuick
import qs
import qs.components
import QtQuick.Effects
import qs.services
ShellRoot {
 FloatingWindow { visible:true; implicitWidth:128;implicitHeight:128
  Item { id:wrapper; anchors.fill:parent; WallpaperView { anchors.fill:parent;path:Quickshell.shellPath("source.png");fadeDuration:0; EFFECT } }
 }
 property int step:0
 Timer { interval:700;repeat:true;running:true
  onTriggered: {
   Theme.noir=step<3;
   ShellSettings.monochromeWallpaper=step===1 || step===3;
   capture.restart();
  }
 }
 Timer {id:capture;interval:200;onTriggered:{
  const names=["colour","noir","restored","normal"];
  if(step<4) wrapper.grabToImage(r=>{r.saveToFile(Quickshell.shellPath(names[step]+".png"));step++;if(step===4)r.saveToFile(Quickshell.shellPath("done.png"));});
 }}
}'''.replace('EFFECT',effect))
 env=dict(os.environ,QT_QPA_PLATFORM='wayland',XDG_RUNTIME_DIR=str(p/'runtime'),WAYLAND_DISPLAY=str(Path(os.environ['XDG_RUNTIME_DIR'])/os.environ.get('WAYLAND_DISPLAY','wayland-1')))
 with (p/'log').open('w') as log:
  proc=subprocess.Popen(['qs','-p',folder],env=env,stdout=log,stderr=log)
  try:
   for _ in range(100):
    if (p/'done.png').exists():break
    if proc.poll() is not None:break
    time.sleep(.1)
   assert (p/'normal.png').exists(),(p/'log').read_text()
   rgb=lambda n:Image.open(p/(n+'.png')).convert('RGB').getpixel((64,64))
   a,b,c,d=map(rgb,['colour','noir','restored','normal'])
   assert max(a)-min(a)>100,(a,b,c)
   assert max(b)-min(b)<=1,(a,b,c)
   assert a==c==d,(a,b,c,d)
   print('PASS Overview wallpaper colour -> Noir grayscale -> restored:',a,b,c)
  finally:proc.terminate();proc.wait(timeout=5)
