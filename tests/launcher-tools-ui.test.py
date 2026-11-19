"""Real native panel/service/protocol checks, isolated settings/runtime and no owner launches."""
import json, os, pathlib, shutil, subprocess, tempfile, time
ROOT=pathlib.Path(__file__).resolve().parents[1]
if not os.environ.get('WAYLAND_DISPLAY'):
 print('skip: native launcher tools panel requires Wayland');raise SystemExit(0)
with tempfile.TemporaryDirectory(prefix='pistachio-tools-test-') as d:
 base=pathlib.Path(d); (base/'services').mkdir(); (base/'popups').mkdir(); (base/'runtime').mkdir(mode=0o700); (base/'bin').mkdir()
 for folder in ['components','settings']: shutil.copytree(ROOT/'src'/folder,base/folder)
 shutil.copy(ROOT/'src/Theme.qml',base/'Theme.qml')
 for name in ['LauncherTools.qml','Store.qml']: shutil.copy(ROOT/'src/services'/name,base/'services'/name)
 # LauncherTools runs the installed `$HOME/.local/bin/psc launcher-tools`: test this build instead (PSC= another)
 service=(base/'services/LauncherTools.qml').read_text(); real='Quickshell.env("HOME") + "/.local/bin/psc"'; assert service.count(real)==1, 'update this fixture'
 (base/'services/LauncherTools.qml').write_text(service.replace(real, json.dumps(os.environ.get('PSC') or str(ROOT/'rust/target/release/psc'))))
 for name in ['LauncherExtras.qml','JobCard.qml']: shutil.copy(ROOT/'src/popups'/name,base/'popups'/name)
 mocks={'Apps':'property var list:[{id:"fixture",name:"Fixture",icon:""}]; function icon(s){return "";} function nameFor(s){return s;}', 'Compositor':'property var windows:[]; function entryOf(s){return s;} property var presets:[{name:"Work"}];', 'ShellSettings':'property bool shadows:true;', 'SettingsHub':'signal present;', 'Session':'property bool locked:false;', 'LocalSend':'property bool available:true;', 'Screenshots':'property bool hasRecorder:true;'}
 for name,body in mocks.items(): (base/'services'/f'{name}.qml').write_text('pragma Singleton\nimport Quickshell\nSingleton { '+body+' }\n')
 (base/'bin/notify-send').write_text('#!/bin/sh\nexit 0\n'); (base/'bin/notify-send').chmod(0o755)
 text=base/'żółć $() text.txt'; text.write_text('fixture text\n')
 shutil.copy(ROOT/'tests/launcher-tools-ui.qml',base/'shell.qml')
 env=dict(os.environ,QT_QPA_PLATFORM='wayland',XDG_RUNTIME_DIR=str(base/'runtime'),XDG_STATE_HOME=str(base/'state'),PATH=str(base/'bin')+':'+os.environ['PATH'],TOOL_TEST_TEXT=str(text))
 env['WAYLAND_DISPLAY']=os.path.join(os.environ.get('XDG_RUNTIME_DIR','/run/user/'+str(os.getuid())),os.environ['WAYLAND_DISPLAY'])
 env.pop('DISPLAY',None)
 with (base/'log').open('w+') as log:
  proc=subprocess.Popen(['qs','-p',d],env=env,stdout=log,stderr=log)
  try:
   for _ in range(50):
    p=subprocess.run(['qs','-p',d,'ipc','call','toolsTest','ready'],env=env,capture_output=True,text=True)
    if p.returncode==0 and p.stdout.strip()=="true": break
    if proc.poll() is not None: break
    time.sleep(.1)
   p=subprocess.run(['qs','-p',d,'ipc','call','toolsTest','run'],env=env,capture_output=True,text=True,timeout=20)
   assert p.returncode==0 and 'PASS' in p.stdout,p.stdout+p.stderr
   print(p.stdout.strip())
   proc.terminate();proc.wait(timeout=5)
   proc=subprocess.Popen(['qs','-p',d],env=env,stdout=log,stderr=log)
   deadline=time.monotonic()+5
   while time.monotonic()<deadline:
    ready=subprocess.run(['qs','-p',d,'ipc','call','toolsTest','ready'],env=env,capture_output=True,text=True)
    if ready.stdout.strip()=='true':
     saved=subprocess.run(['qs','-p',d,'ipc','call','toolsTest','persisted'],env=env,capture_output=True,text=True)
     data=json.loads(saved.stdout)
     if data['jobs']>=2:break
    time.sleep(.05)
   else:raise AssertionError('restarted launcher tools not ready')
   assert [p['target'] for p in data['pins']]==['jobs','fixture'],data
   assert data['aliases']['editor']=={'kind':'app','target':'fixture'},data
   subprocess.run(['qs','-p',d,'ipc','call','toolsTest','dismiss'],env=env,check=True,capture_output=True)
   print('PASS launcher pins/aliases and temporary jobs survive shell restart')
  finally:
   for state in (base/'runtime').glob('pistachio-jobs-*/*/state.json'):
    try:
     if json.loads(state.read_text()).get('state')=='running': state.with_name('cancel').touch()
    except (OSError,ValueError): pass
   deadline=time.monotonic()+3
   while time.monotonic()<deadline:
    states=list((base/'runtime').glob('pistachio-jobs-*/*/state.json'))
    if all(json.loads(state.read_text()).get('state')!='running' for state in states): break
    time.sleep(.05)
   proc.terminate(); proc.wait(timeout=5); log.seek(0); output=log.read()
   if "ERROR" in output or "WARN" in output: print(output)
   assert "ERROR" not in output and "WARN qml" not in output, output
