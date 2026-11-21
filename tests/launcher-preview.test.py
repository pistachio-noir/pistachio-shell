"""Cancellation exercises the actual JSONL process and real child ownership."""
import json, os, pathlib, subprocess, tempfile, time, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class PreviewLifecycle(unittest.TestCase):
 def run_case(self, terminate):
  with tempfile.TemporaryDirectory() as d:
   base=pathlib.Path(d); (base/'bin').mkdir(); marker=base/'pid'; fake=base/'bin/pdftoppm'
   fake.write_text('#!/usr/bin/python3\nimport os,pathlib,time\npathlib.Path(os.environ["PREVIEW_TEST_PID"]).write_text(str(os.getpid()))\ntime.sleep(30)\n');fake.chmod(0o755)
   pdf=base/'fake.pdf';pdf.write_text('fixture')
   env=dict(os.environ,XDG_RUNTIME_DIR=d,PREVIEW_TEST_PID=str(marker),PATH=str(base/'bin')+':'+os.environ['PATH'])
   helper=subprocess.Popen([os.environ.get('PSC') or str(ROOT/'rust/target/release/psc'),'launcher-tools'],env=env,stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
   try:
    helper.stdin.write(json.dumps({'action':'preview','id':1,'path':str(pdf)})+'\n');helper.stdin.flush()
    deadline=time.monotonic()+3
    while not marker.exists() and time.monotonic()<deadline: time.sleep(.01)
    self.assertTrue(marker.exists(),'PDF child started');pid=int(marker.read_text())
    if terminate: helper.terminate()
    else: helper.stdin.write('{"action":"cancel-preview"}\n');helper.stdin.flush()
    deadline=time.monotonic()+3
    while time.monotonic()<deadline:
     try: os.kill(pid,0)
     except ProcessLookupError: break
     time.sleep(.01)
    else: self.fail('preview child not reaped')
   finally:
    helper.stdin.close()
    try: helper.wait(timeout=3)
    except subprocess.TimeoutExpired: helper.kill();helper.wait();raise
    error=helper.stderr.read();helper.stderr.close()
    self.assertEqual(helper.returncode,0,error)
 def test_close_reaps_pdf(self): self.run_case(False)
 def test_reload_reaps_pdf(self): self.run_case(True)
 def helper(self, d):
  # notify-send goes to a stand-in, so finished jobs never reach the owner's desktop
  (pathlib.Path(d)/'bin').mkdir(exist_ok=True); fake=pathlib.Path(d)/'bin/notify-send'; fake.write_text('#!/bin/sh\n'); fake.chmod(0o755)
  env=dict(os.environ,XDG_RUNTIME_DIR=d,PATH=str(pathlib.Path(d)/'bin')+':'+os.environ['PATH'])
  helper=subprocess.Popen([os.environ.get('PSC') or str(ROOT/'rust/target/release/psc'),'launcher-tools'],env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
  self.assertEqual(json.loads(helper.stdout.readline())['event'],'ready'); return helper
 def send(self, helper, message): helper.stdin.write(json.dumps(message)+'\n'); helper.stdin.flush()
 def test_finished_jobs_leave_no_zombies(self):
  with tempfile.TemporaryDirectory() as d:
   helper=self.helper(d)
   try:
    for _ in range(3): self.send(helper,{'action':'run','command':'true'})
    time.sleep(2.5)
    # task/*/children needs CONFIG_PROC_CHILDREN (off on the owner's Gentoo kernel): else each process's parent from /proc/*/stat
    listing=pathlib.Path(f'/proc/{helper.pid}/task/{helper.pid}/children')
    if listing.exists(): children=listing.read_text().split()
    else:
     children=[]
     for p in pathlib.Path('/proc').iterdir():
      if not p.name.isdigit(): continue
      try: stat=(p/'stat').read_text()
      except OSError: continue
      if int(stat[stat.rindex(')')+1:].split()[1])==helper.pid: children.append(p.name)
    zombies=[c for c in children if pathlib.Path(f'/proc/{c}/stat').read_text().split(') ')[1].startswith('Z')]
    self.assertEqual(zombies,[],'finished job runners are reaped')
   finally: helper.stdin.close(); helper.wait(timeout=5)
if __name__=='__main__':unittest.main()
