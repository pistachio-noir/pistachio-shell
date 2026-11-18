#!/usr/bin/env python3
"""Read-only phone view. Timer updates arrive as JSON lines on stdin."""
import json
import sys
import threading
import time
import ipaddress
import tempfile
import subprocess
import os
import signal
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PAGE = b'''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Focus timer</title><style>body{background:Canvas;color:CanvasText;font:18px sans-serif;text-align:center;margin:20vh 1rem}h1{font-size:1.5rem}#countdown{font-size:5rem}</style></head><body><h1 id="phase">Connecting...</h1><div id="countdown">--:--</div><p id="status"></p><script>let state=null,last=0;async function refresh(){try{let r=await fetch('/state',{cache:'no-store'});if(!r.ok)throw 0;state=await r.json();last=performance.now();document.body.style.background=state.bg;document.body.style.color=state.text;document.getElementById("countdown").style.color=state.accent}catch(e){}}function draw(){if(!state||performance.now()-last>5000){document.getElementById('status').textContent='Connection lost';return}let ms=state.paused?state.left:Math.max(0,state.endsAt-state.serverNow-(performance.now()-last));let s=Math.ceil(ms/1000),h=Math.floor(s/3600),m=Math.floor(s%3600/60),sec=s%60;document.getElementById('phase').textContent=state.phase;document.getElementById('countdown').textContent=(h?h+':'+String(m).padStart(2,'0'):m)+':'+String(sec).padStart(2,'0');document.getElementById('status').textContent=state.paused?'Paused':''}refresh();setInterval(refresh,1500);setInterval(draw,250)</script></body></html>'''

class Server(ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, address, handler):
        super().__init__(address, handler)
        self.state = None
        self.updated = 0
        self.lock = threading.Lock()
    def update(self, value):
        with self.lock:
            self.state = {k: value[k] for k in ('phase', 'endsAt', 'left', 'paused')}
            self.state.update({k: value.get(k, '') for k in ('bg', 'text', 'accent')})
            self.updated = time.monotonic()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if getattr(self.server, "network", None) and ipaddress.ip_address(self.client_address[0]) not in self.server.network:
            self.send_error(403)
            return
        if self.path == '/':
            body, kind, status = PAGE, 'text/html; charset=utf-8', 200
        elif self.path == '/state':
            with self.server.lock:
                state = self.server.state if time.monotonic() - self.server.updated < 5 else None
            if state:
                state = dict(state, serverNow=int(time.time()*1000))
            body, kind, status = json.dumps(state).encode(), 'application/json', 200 if state else 503
        else:
            self.send_error(404)
            return
        self.send_response(status)
        self.send_header('Content-Type', kind)
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_POST(self):
        self.send_error(405)
    def log_message(self, *args):
        pass

def local_address():
    """Prefer a connected physical LAN interface, including networks with no default route."""
    try:
        entries = json.loads(subprocess.check_output(['ip', '-j', '-4', 'address', 'show', 'up', 'scope', 'global'], text=True, timeout=3))
        networks = [ipaddress.ip_network(n) for n in ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')]
        for entry in entries:
            if not entry.get('ifname', '').startswith(('en', 'eth', 'wl')):
                continue
            for info in entry.get('addr_info', []):
                ip = ipaddress.ip_address(info['local'])
                if any(ip in net for net in networks):
                    return str(ip), int(info['prefixlen'])
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        raise OSError('Cannot discover a local network address') from error
    raise OSError('No private wired or wireless network address is available')

def main():
    def stop(_signum, _frame):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, stop)
    path = None
    try:
        address, prefix = local_address()
        server = Server((address, 0), Handler)
        server.network = ipaddress.ip_network(f"{address}/{prefix}", strict=False)
        url = f'http://{address}:{server.server_port}/'
        try:
            fd, path = tempfile.mkstemp(prefix='pistachio-phone-', suffix='.png', dir=os.environ.get('XDG_RUNTIME_DIR'))
            os.close(fd)
            subprocess.run(['qrencode', '-o', path, '-s', '6', url], check=True, timeout=5, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.SubprocessError):
            if path:
                os.unlink(path)
            path = None
        print(json.dumps({'url': url, 'qr': path or '', 'qrError': '' if path else 'QR code unavailable; use the address below.'}), flush=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            for line in sys.stdin:
                try:
                    server.update(json.loads(line))
                except (ValueError, KeyError, TypeError):
                    continue
        finally:
            server.shutdown()
            server.server_close()
    except OSError as error:
        print(json.dumps({'error': str(error)}), flush=True)
    finally:
        if path:
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

if __name__ == '__main__':
    main()
