"""Real FFmpeg boundaries: trimming preserves the source and rejects unsafe ranges. Runs `psc capture`
(Python's capture.py until 19 November 2026) the way the shell does; PSC= another psc build."""
import json
import os
import signal
import sys
import time
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PSC = os.environ.get('PSC') or str(ROOT / 'rust/target/release/psc')


def capture(*args, env=None):
    out = subprocess.run([PSC, 'capture', *map(str, args)], capture_output=True, text=True, env=env, timeout=60)
    reply = json.loads(out.stdout)
    if out.returncode: raise ValueError(reply['error'])
    return reply


class helper:
    probe = staticmethod(lambda source: capture('probe', source)['duration'])
    trim = staticmethod(lambda source, start, end: capture('trim', source, start, end)['path'])

class CaptureTests(unittest.TestCase):
    def test_trim_is_new_file_and_validates_range(self):
        with tempfile.TemporaryDirectory(prefix='pistachio-trim-') as folder:
            source = Path(folder) / 'source with unicode ą.mp4'
            subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','color=c=black:s=64x64:r=10:d=2','-c:v','libx264','-y',str(source)],check=True)
            original = source.read_bytes()
            self.assertAlmostEqual(helper.probe(source), 2, delta=.1)
            for start,end in [(1,1),(-1,1),(0,4),(float('nan'),1),(0,float('inf'))]:
                with self.assertRaises(ValueError): helper.trim(source,start,end)
            first = Path(helper.trim(source,.4,1.4))
            second = Path(helper.trim(source,.4,1.4))
            self.assertNotEqual(first,source)
            self.assertNotEqual(first,second)
            self.assertEqual(source.read_bytes(),original)
            self.assertAlmostEqual(helper.probe(first),1,delta=.2)
            self.assertFalse(list(Path(folder).glob('*.part.mp4')))
    def test_cancel_reaps_encoder_and_removes_partial(self):
        with tempfile.TemporaryDirectory(prefix='pistachio-trim-cancel-') as folder:
            base = Path(folder)
            source = base / 'source.mp4'
            subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','color=c=black:s=64x64:r=10:d=2','-c:v','libx264','-y',str(source)],check=True)
            original = source.read_bytes()
            binary = base / 'bin'; binary.mkdir()
            encoder = binary / 'ffmpeg'
            encoder.write_text('#!/usr/bin/python3\nimport os,pathlib,time\npathlib.Path(os.environ["CAPTURE_TEST_PID"]).write_text(str(os.getpid()))\ntime.sleep(30)\n')
            encoder.chmod(0o755)
            pidfile = base / 'child.pid'
            env = dict(os.environ,PATH=str(binary)+':'+os.environ['PATH'],CAPTURE_TEST_PID=str(pidfile))
            proc = subprocess.Popen([PSC,'capture','trim',str(source),'0','1'],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            try:
                deadline = time.monotonic()+5
                while not pidfile.exists() and time.monotonic()<deadline: time.sleep(.02)
                self.assertTrue(pidfile.exists(),'encoder did not start')
                child_pid = int(pidfile.read_text())
                proc.send_signal(signal.SIGTERM)
                proc.communicate(timeout=5)
                self.assertEqual(proc.returncode,143)
                self.assertFalse(Path('/proc') .joinpath(str(child_pid)).exists(),'encoder must be reaped')
                self.assertEqual(source.read_bytes(),original)
                self.assertFalse(list(base.glob('*_trimmed*.mp4')))
                self.assertFalse(list(base.glob('*.part.mp4')))
            finally:
                if proc.poll() is None: proc.kill();proc.communicate()

    def test_cli_reports_structured_error(self):
        result = subprocess.run([PSC,'capture','probe','/not/a/file'],capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('error',json.loads(result.stdout))

if __name__ == '__main__': unittest.main()
