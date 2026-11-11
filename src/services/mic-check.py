#!/usr/bin/env python3
"""Explicit microphone check. Raw audio is kept only in a private temporary directory.
No automatic recording or playback. TERM/EOF closes and reaps owned audio processes.
"""
from array import array
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import tempfile

RATE=16000
LIMIT=RATE*2*5

def peak(data):
    values=array('h'); values.frombytes(data[:len(data)//2*2])
    return min(1, max((abs(v)/32768 for v in values), default=0))

class Sample:
    def __init__(self,path): self.path=path; self.file=None; self.written=0; self.ready=False
    def clear(self):
        if self.file: self.file.close()
        self.file=None; self.ready=False; self.written=0
        self.path.unlink(missing_ok=True)
    def start(self):
        self.clear(); self.file=self.path.open('wb')
    def feed(self,data):
        if self.file is None: return
        part=data[:LIMIT-self.written]; self.file.write(part); self.written+=len(part)
        if self.written>=LIMIT:
            self.file.close(); self.file=None; self.ready=True

def emit(**data): print(json.dumps(data),flush=True)

def stop(process):
    if process and process.poll() is None:
        process.terminate()
        try: process.wait(timeout=2)
        except subprocess.TimeoutExpired: process.kill();process.wait()

def main(target):
    child=None; player=None; selector=selectors.DefaultSelector()
    signal.signal(signal.SIGTERM,lambda *_: (_ for _ in ()).throw(SystemExit(0)))
    with tempfile.TemporaryDirectory(prefix='pistachio-mic-') as directory:
        sample=Sample(Path(directory)/'sample.raw')
        def close_mic():
            nonlocal child
            if child:
                try: selector.unregister(child.stdout)
                except KeyError: pass
                stop(child); child.stdout.close();child=None
        def start_mic():
            nonlocal child
            close_mic()
            child=subprocess.Popen(['pw-record','--raw','--format','s16','--rate',str(RATE),'--channels','1','--target',target,'-'],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
            selector.register(child.stdout,selectors.EVENT_READ,'audio')
        try:
            selector.register(sys.stdin,selectors.EVENT_READ,'command')
            emit(event='ready')
            while True:
                for key,_ in selector.select(0.15):
                    if key.data=='command':
                        line=sys.stdin.readline()
                        if not line: return
                        cmd=json.loads(line).get('command')
                        if cmd in ('meter','record'):
                            stop(player);player=None
                            if cmd=='record': sample.start()
                            else: sample.clear()
                            start_mic();emit(event='state',state='recording' if cmd=='record' else 'metering')
                        elif cmd=='play' and sample.ready and child is None:
                            stop(player)
                            player=subprocess.Popen(['pw-play','--raw','--format','s16','--rate',str(RATE),'--channels','1',str(sample.path)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                            emit(event='state',state='playing')
                        elif cmd=='stop': return
                    else:
                        data=os.read(key.fileobj.fileno(),3200)
                        if not data:
                            close_mic();sample.clear();emit(event='error',message='Microphone unavailable or disconnected.');continue
                        sample.feed(data);emit(event='level',value=peak(data),seconds=sample.written/(RATE*2))
                        if sample.ready:
                            close_mic();emit(event='state',state='recorded')
                if player and player.poll() is not None:
                    player=None;emit(event='state',state='recorded')
        except (OSError,ValueError): emit(event='error',message='Audio check could not start. Check PipeWire tools and your input.')
        finally:
            close_mic();stop(player);sample.clear();selector.close()

if __name__=='__main__': main(sys.argv[1])
