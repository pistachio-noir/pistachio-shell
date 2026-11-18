import importlib.util
import json
import threading
import subprocess
import sys
import tempfile
import os
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

spec = importlib.util.spec_from_file_location('phone_timer', Path(__file__).resolve().parents[1] / 'src/services/phone-timer.py')
phone = importlib.util.module_from_spec(spec)
spec.loader.exec_module(phone)

class PhoneTimerTest(unittest.TestCase):
    def setUp(self):
        self.server = phone.Server(('127.0.0.1', 0), phone.Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = 'http://127.0.0.1:%s' % self.server.server_port

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def test_state_and_read_only(self):
        self.server.update({'phase': 'Break', 'endsAt': 10000, 'left': 0, 'paused': False})
        with urllib.request.urlopen(self.url + '/state') as response:
            state = json.load(response)
            self.assertEqual(state['phase'], 'Break')
            self.assertLess(abs(state['serverNow'] - time.time()*1000), 1000)
        self.server.update({'phase': 'Work 2/4', 'endsAt': 0, 'left': 43000, 'paused': True})
        with urllib.request.urlopen(self.url + '/state') as response:
            self.assertEqual(json.load(response)['left'], 43000)
        with urllib.request.urlopen(self.url + '/') as response:
            self.assertIn(b'countdown', response.read())
        self.server.updated = time.monotonic() - 10
        with self.assertRaises(urllib.error.HTTPError) as stale:
            urllib.request.urlopen(self.url + '/state')
        self.assertEqual(stale.exception.code, 503)
        stale.exception.close()
        with self.assertRaises(urllib.error.HTTPError) as error:
            urllib.request.urlopen(urllib.request.Request(self.url + '/state', data=b'{}', method='POST'))
        self.assertEqual(error.exception.code, 405)
        error.exception.close()
        with self.assertRaises(urllib.error.HTTPError) as missing:
            urllib.request.urlopen(self.url + '/other')
        missing.exception.close()

    def test_address_without_default_route(self):
        from unittest.mock import patch
        result = [{'ifname':'tailscale0','addr_info':[{'local':'100.64.0.5','prefixlen':32}]}, {'ifname':'eno1','addr_info':[{'local':'192.168.4.7','prefixlen':24}]}]
        with patch.object(phone.subprocess, 'check_output', return_value=json.dumps(result)):
            self.assertEqual(phone.local_address(), ('192.168.4.7', 24))

    def test_helper_lifecycle(self):
        with tempfile.TemporaryDirectory() as runtime:
            source = str(Path(__file__).resolve().parents[1] / 'src/services/phone-timer.py')
            script = "import importlib.util,sys;s=importlib.util.spec_from_file_location('p',sys.argv[1]);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);m.local_address=lambda:('127.0.0.1',8);m.main()"
            proc = subprocess.Popen([sys.executable, '-B', '-u', '-c', script, source], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=dict(os.environ, XDG_RUNTIME_DIR=runtime))
            try:
                ready = json.loads(proc.stdout.readline())
                self.assertTrue(Path(ready['qr']).is_file())
                proc.stdin.write(json.dumps({'phase':'Break','endsAt':123456,'left':0,'paused':False})+'\n');proc.stdin.flush()
                for _ in range(30):
                    try:
                        with urllib.request.urlopen(ready['url']+'state', timeout=1) as response:
                            self.assertEqual(json.load(response)['phase'], 'Break')
                            break
                    except urllib.error.HTTPError:
                        time.sleep(.05)
                else:
                    self.fail('server never received state')
                proc.stdin.close()
                self.assertEqual(proc.wait(timeout=5), 0)
                self.assertFalse(Path(ready['qr']).exists())
                with self.assertRaises(urllib.error.URLError):
                    urllib.request.urlopen(ready['url']+'state', timeout=1)
            finally:
                if proc.poll() is None:
                    proc.kill();proc.wait()
                proc.stdout.close()

if __name__ == '__main__':
    unittest.main()
