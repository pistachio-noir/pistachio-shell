import importlib.util
from pathlib import Path
import tempfile
import subprocess
import os
import json
import selectors
import time
import unittest
from unittest.mock import patch
# `psc mic-check` (Python's mic-check.py until 19 November 2026; its sample/peak cases are Rust tests in
# rust/psc/src/mic.rs). PSC= another psc build.
PSC=os.environ.get('PSC') or str(Path(__file__).resolve().parents[1]/'rust/target/release/psc')
class MicCheckTests(unittest.TestCase):
    def test_protocol_closes_mic_after_sample_and_deletes_temporary_audio_on_stop(self):
        with tempfile.TemporaryDirectory() as td:
            base=Path(td);bindir=base/'bin';bindir.mkdir();tmp=base/'tmp';tmp.mkdir()
            record=bindir/'pw-record'
            record.write_text("#!/usr/bin/env python3\nimport os,sys,time\nfrom pathlib import Path\nPath(os.environ['MIC_PID']).write_text(str(os.getpid()))\nwhile True:\n sys.stdout.buffer.write(b'\\x00\\x40'*1600);sys.stdout.buffer.flush();time.sleep(0.005)\n")
            record.chmod(0o755)
            play=bindir/'pw-play'
            play.write_text("#!/usr/bin/env python3\nimport os,time\nfrom pathlib import Path\nPath(os.environ['PLAYED']).write_text('yes')\ntime.sleep(0.2)\n")
            play.chmod(0o755)
            env=dict(os.environ,PATH=str(bindir)+':'+os.environ['PATH'],TMPDIR=str(tmp),MIC_PID=str(base/'pid'),PLAYED=str(base/'played'))
            process=subprocess.Popen([PSC,'mic-check','fixture-input'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,text=True,bufsize=1)
            def event(name,state=None):
                deadline=time.monotonic()+5
                while time.monotonic()<deadline:
                    # Every command produces a bounded, immediate state line; avoid buffered select.
                    line=process.stdout.readline()
                    self.assertTrue(line,'helper exited before '+name)
                    obj=json.loads(line)
                    if obj.get('event')==name and (state is None or obj.get('state')==state):return obj
                self.fail('event timeout '+name)
            def send(command):process.stdin.write(json.dumps({'command':command})+'\n');process.stdin.flush()
            try:
                event('ready');self.assertFalse((base/'pid').exists())
                send('record');event('state','recorded')
                pid=int((base/'pid').read_text())
                with self.assertRaises(ProcessLookupError):os.kill(pid,0)
                samples=list(tmp.glob('pistachio-mic-*/sample.raw'))
                self.assertEqual(len(samples),1);self.assertEqual(samples[0].stat().st_size,160000)
                self.assertFalse((base/'played').exists(),'record must not autoplay')
                send('play');event('state','playing');event('state','recorded')
                self.assertTrue((base/'played').exists())
                send('meter');event('state','metering');event('level')
                pid=int((base/'pid').read_text())
                process.terminate();process.wait(timeout=4)
                with self.assertRaises(ProcessLookupError):os.kill(pid,0)
                self.assertEqual(list(tmp.iterdir()),[],'sample removed on TERM')
            finally:
                if process.poll() is None:process.terminate();process.wait(timeout=4)
                process.stdin.close();process.stdout.close();process.stderr.close()
if __name__=='__main__':unittest.main()
