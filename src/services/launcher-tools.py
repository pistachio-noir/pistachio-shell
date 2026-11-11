#!/usr/bin/env python3
"""Read-only file tools and volatile, reload-safe launcher background jobs."""
from concurrent.futures import ThreadPoolExecutor
import json, mimetypes, os, pathlib, selectors, signal, subprocess, sys, tempfile, threading, time, uuid
LIMIT=262144
PREVIEW_CHILDREN=set()
PREVIEW_LOCK=threading.Lock()
PREVIEW_CLOSING=threading.Event()
PREVIEW_REQUEST_ID=None

def atomic(path, data):
 tmp=path.with_suffix('.tmp'); tmp.write_text(json.dumps(data), encoding='utf-8'); tmp.replace(path)

def preview(name, cache, request_id=None):
 p=pathlib.Path(name); st=p.stat(); mime=mimetypes.guess_type(p.name)[0] or 'application/octet-stream'
 result={'path':str(p),'name':p.name,'size':st.st_size,'modified':time.strftime('%d %B %Y %H:%M',time.localtime(st.st_mtime)), 'mime':mime,'kind':'metadata'}
 if not p.is_file(): return result
 if mime.startswith('image/') and st.st_size<=67108864:
  result.update(kind='image',image=p.as_uri()); return result
 if mime=='application/pdf':
  dest=pathlib.Path(cache)/('pdf-'+uuid.uuid4().hex)
  try:
   with PREVIEW_LOCK:
    if PREVIEW_CLOSING.is_set() or request_id is not None and request_id != PREVIEW_REQUEST_ID: return result
    child=subprocess.Popen(['pdftoppm','-f','1','-l','1','-singlefile','-scale-to','1600','-png',str(p),str(dest)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    PREVIEW_CHILDREN.add(child)
   try:
    if child.wait(timeout=10)!=0: raise ValueError('PDF conversion failed')
   finally:
    if child.poll() is None: child.kill()
    child.wait()
    with PREVIEW_LOCK: PREVIEW_CHILDREN.discard(child)
   result.update(kind='image',image=dest.with_suffix('.png').as_uri())
  except (OSError, ValueError, subprocess.SubprocessError): result['note']='PDF preview needs pdftoppm and a readable PDF.'
  return result
 with p.open('rb') as f: data=f.read(LIMIT+1)
 if b'\0' not in data:
  try:
   import codecs
   text=codecs.getincrementaldecoder('utf-8')('strict').decode(data[:LIMIT],final=len(data)<=LIMIT)
   result.update(kind='text',text=text,truncated=len(data)>LIMIT)
  except UnicodeDecodeError: pass
 return result

def read_jobs(base):
 rows=[]
 for p in base.glob('*/state.json'):
  try:
   row=json.loads(p.read_text()); log=p.parent/'output'; row['output']=log.read_bytes()[-65536:].decode('utf-8','replace') if log.exists() else ''; rows.append(row)
  except (OSError,ValueError): pass
 return sorted(rows,key=lambda r:r['started'],reverse=True)

def run_job(folder, command):
 folder.mkdir(parents=True, exist_ok=True)
 row={'id':folder.name,'command':command,'started':time.time()*1000,'state':'running','code':None}
 atomic(folder/'state.json',row)
 child=None; sel=None; owned_error=False
 try:
  with (folder/'output').open('w+b') as log:
   child=subprocess.Popen(['sh','-c',command],stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,start_new_session=True)
   sel=selectors.DefaultSelector(); sel.register(child.stdout,selectors.EVENT_READ)
   cancelled=False; killed_at=0
   while True:
    if (folder/'cancel').exists() and not cancelled:
     cancelled=True; killed_at=time.monotonic()
     try: os.killpg(child.pid,signal.SIGTERM)
     except ProcessLookupError: pass
    if cancelled and time.monotonic()-killed_at>2:
     try: os.killpg(child.pid,signal.SIGKILL)
     except ProcessLookupError: pass
    for key,_ in sel.select(.1):
     chunk=os.read(key.fd,8192)
     if chunk:
      log.write(chunk); log.flush()
      if log.tell()>131072:
       log.seek(-65536,2); tail=log.read()
       # The UI tail is bounded; cap disk output without changing the running command.
       log.seek(0); log.truncate(); log.write(tail)
     else: sel.unregister(key.fileobj)
    if child.poll() is not None and not sel.get_map(): break
   child.stdout.close(); sel.close()
   row.update(code=child.returncode,state='cancelled' if cancelled else 'finished' if child.returncode==0 else 'failed',ended=time.time()*1000)
 except OSError as e:
  owned_error=True
  row.update(state='failed',error=str(e),ended=time.time()*1000)
 finally:
  if child is not None:
   if child.poll() is None or owned_error:
    try: os.killpg(child.pid,signal.SIGKILL)
    except ProcessLookupError: pass
   child.wait()
   if child.stdout: child.stdout.close()
  if sel: sel.close()
 atomic(folder/'state.json',row)
 # Volatile session history: retain twenty completed jobs, never remove active jobs.
 finished=[r for r in read_jobs(folder.parent) if r['state']!='running']
 import shutil
 for old in finished[20:]: shutil.rmtree(folder.parent/old['id'],ignore_errors=True)

def handlers(path):
 from gi.repository import Gio
 f=Gio.File.new_for_path(path); info=f.query_info('standard::content-type',Gio.FileQueryInfoFlags.NONE,None); mime=info.get_content_type()
 return mime,[{'id':a.get_id(),'name':a.get_display_name(),'icon':a.get_icon().to_string() if a.get_icon() else ''} for a in Gio.AppInfo.get_all_for_type(mime) if a.get_id()]

def open_with(path, appid, remember):
 from gi.repository import Gio
 mime,apps=handlers(path)
 if appid not in [a['id'] for a in apps]: raise ValueError('That application is no longer available for this file.')
 app=next(a for a in Gio.AppInfo.get_all_for_type(mime) if a.get_id()==appid)
 if not app.launch([Gio.File.new_for_path(path)],None): raise ValueError("Application could not open this file.")
 if remember: app.set_as_default_for_type(mime)

def main():
 global PREVIEW_REQUEST_ID
 if len(sys.argv)>1 and sys.argv[1]=='--job':
  run_job(pathlib.Path(sys.argv[2]),sys.argv[3])
  row=json.loads((pathlib.Path(sys.argv[2])/'state.json').read_text())
  lines=(pathlib.Path(sys.argv[2])/'output').read_bytes()[-65536:].decode('utf-8','replace').splitlines()
  last=next((line for line in reversed(lines) if line.strip()),'No output')[-300:]
  try: subprocess.run(['notify-send','--app-name=Command','--icon=utilities-terminal',row['state'].title()+': '+row['command'],'Exit '+str(row.get('code'))+' · '+last+'\nOpen Background jobs for output.'],timeout=3,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  except (OSError,subprocess.TimeoutExpired): pass
  return
 base=pathlib.Path(os.environ.get('XDG_RUNTIME_DIR',tempfile.gettempdir()))/('pistachio-jobs-'+str(os.getuid())); base.mkdir(mode=0o700,exist_ok=True)
 lock=threading.Lock()
 def emit(value):
  with lock: print(json.dumps(value,ensure_ascii=False),flush=True)
 emit({"event":"ready"})
 def poll():
  previous=None
  while True:
   rows=read_jobs(base)
   if rows!=previous: emit({'event':'jobs','jobs':rows}); previous=rows
   time.sleep(.7)
 threading.Thread(target=poll,daemon=True).start()
 def on_signal(*_): raise SystemExit(0)
 signal.signal(signal.SIGTERM,on_signal)
 def preview_request(m,cache):
  try: emit({'event':'preview','id':m.get('id',0),'data':preview(m['path'],cache,m.get('id',0))})
  except Exception as e: emit({'event':'error','id':m.get('id',0),'error':str(e)})
 def watch_launch(child,app,request):
  code=child.wait()
  if code: emit({'event':'launch-failed','app':app,'request':request,'error':'Application exited with status '+str(code)})
 with tempfile.TemporaryDirectory(prefix='pistachio-preview-') as cache:
  previews=ThreadPoolExecutor(max_workers=2,thread_name_prefix='preview')
  try:
   for line in sys.stdin:
    try:
     m=json.loads(line); action=m.get('action'); ident=m.get('id',0)
     if action in ('preview','cancel-preview'):
      with PREVIEW_LOCK:
       PREVIEW_REQUEST_ID=m.get('id',0) if action=='preview' else None
       for child in PREVIEW_CHILDREN:
        if child.poll() is None: child.kill()
      if action=='preview': previews.submit(preview_request,m,cache)
     elif action=='handlers':
      mime,apps=handlers(m['path']); emit({'event':'handlers','id':ident,'mime':mime,'apps':apps})
     elif action=='open': open_with(m['path'],m['app'],m.get('remember') is True); emit({'event':'opened','id':ident})
     elif action=='run':
      folder=base/uuid.uuid4().hex; subprocess.Popen([sys.executable,'-I',__file__,'--job',str(folder),m['command']],start_new_session=True,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,close_fds=True)
     elif action=='cancel':
      ident=m['job']
      if len(ident)==32 and all(c in '0123456789abcdef' for c in ident): (base/ident/'cancel').touch()
     elif action=='launch':
      try:
       child=subprocess.Popen(m['argv'],cwd=m.get('cwd') or None,start_new_session=True,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,close_fds=True)
       emit({'event':'launched','app':m['app']})
       threading.Thread(target=watch_launch,args=(child,m['app'],m['request']),daemon=True).start()
      except OSError as e: emit({'event':'launch-failed','app':m['app'],'request':m['request'],'error':str(e)})
    except Exception as e: emit({'event':'error','id':locals().get('ident',0),'error':str(e)})
  finally:
   with PREVIEW_LOCK:
    PREVIEW_CLOSING.set()
    for child in PREVIEW_CHILDREN:
     if child.poll() is None: child.kill()
   previews.shutdown(wait=True,cancel_futures=True)

if __name__=='__main__': main()
