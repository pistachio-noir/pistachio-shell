"""`psc phone-timer` (Python's phone-timer.py until 19 November 2026), run the way FocusMode runs it: the
read-only state page, 403/404/405, stale state after 5 s, the QR file removed on exit. Its address choice
is a Rust test (rust/psc/src/phone.rs). PSC= another psc build."""
import json
import os
import subprocess
import tempfile
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

PSC = os.environ.get('PSC') or str(Path(__file__).resolve().parents[1] / 'rust/target/release/psc')


class PhoneTimerTest(unittest.TestCase):
    def test_lifecycle_state_and_read_only(self):
        with tempfile.TemporaryDirectory() as runtime:
            env = dict(os.environ, XDG_RUNTIME_DIR=runtime, PSC_PHONE_TEST_ADDRESS='127.0.0.1/8')
            proc = subprocess.Popen([PSC, 'phone-timer'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=env)
            try:
                ready = json.loads(proc.stdout.readline())
                url = ready['url']
                self.assertTrue(url.startswith('http://127.0.0.1:'), url)
                if ready['qr']:
                    self.assertTrue(Path(ready['qr']).is_file())
                with self.assertRaises(urllib.error.HTTPError) as early:
                    urllib.request.urlopen(url + 'state', timeout=2)
                self.assertEqual(early.exception.code, 503, 'no state yet')
                early.exception.close()
                def send(state):
                    proc.stdin.write(json.dumps(state) + '\n'); proc.stdin.flush(); time.sleep(0.15)
                send({'phase': 'Break', 'endsAt': 10000, 'left': 0, 'paused': False, 'bg': '#111111'})
                with urllib.request.urlopen(url + 'state', timeout=2) as response:
                    state = json.load(response)
                self.assertEqual(state['phase'], 'Break')
                self.assertEqual(state['bg'], '#111111')
                self.assertLess(abs(state['serverNow'] - time.time() * 1000), 1000)
                send({'phase': 'Work 2/4', 'endsAt': 0, 'left': 43000, 'paused': True})
                with urllib.request.urlopen(url + 'state', timeout=2) as response:
                    self.assertEqual(json.load(response)['left'], 43000)
                send({'not': 'a state'})  # ignored
                with urllib.request.urlopen(url, timeout=2) as response:
                    self.assertIn(b'countdown', response.read())
                with self.assertRaises(urllib.error.HTTPError) as error:
                    urllib.request.urlopen(urllib.request.Request(url + 'state', data=b'{}', method='POST'), timeout=2)
                self.assertEqual(error.exception.code, 405)
                error.exception.close()
                with self.assertRaises(urllib.error.HTTPError) as missing:
                    urllib.request.urlopen(url + 'other', timeout=2)
                self.assertEqual(missing.exception.code, 404)
                missing.exception.close()
                time.sleep(5.3)
                with self.assertRaises(urllib.error.HTTPError) as stale:
                    urllib.request.urlopen(url + 'state', timeout=2)
                self.assertEqual(stale.exception.code, 503, 'no heartbeat for 5 s')
                stale.exception.close()
                proc.stdin.close()
                self.assertEqual(proc.wait(timeout=5), 0)
                if ready['qr']:
                    self.assertFalse(Path(ready['qr']).exists(), 'QR removed on exit')
                with self.assertRaises(urllib.error.URLError):
                    urllib.request.urlopen(url + 'state', timeout=1)
            finally:
                if proc.poll() is None:
                    proc.kill(); proc.wait()
                proc.stdout.close()


if __name__ == '__main__':
    unittest.main()
