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
   helper=subprocess.Popen(['python3','-I',str(ROOT/'src/services/launcher-tools.py')],env=env,stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
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
if __name__=='__main__':unittest.main()
