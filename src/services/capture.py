#!/usr/bin/env python3
"""Recording inspection and precise trim; writes a new sibling, never the input."""
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile

child = None


def cancel(signum, _frame):
    if child is not None and child.poll() is None:
        child.terminate()
        try:
            child.wait(timeout=3)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()
    raise SystemExit(128 + signum)


def run(command):
    global child
    child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    out, err = child.communicate()
    if child.returncode:
        raise ValueError(err.strip()[-600:] or 'Video tool failed')
    return out


def probe(source):
    source = Path(source)
    if not source.is_file():
        raise ValueError('Recording no longer exists')
    result = json.loads(run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'json', str(source)]))
    duration = float(result['format']['duration'])
    if not math.isfinite(duration) or duration <= 0:
        raise ValueError('Recording has no usable duration')
    return duration


def trim(source, start, end):
    source = Path(source).absolute()
    duration = probe(source)
    start, end = float(start), float(end)
    if not math.isfinite(start) or not math.isfinite(end) or start < 0 or end <= start or end > duration + .01:
        raise ValueError('Choose a start before the end, within the recording')
    # Reserve the target exclusively, even for simultaneous trims or Unicode/spaced paths.
    target = source.with_name(source.stem + '_trimmed.mp4')
    serial = 2
    while True:
        try:
            descriptor = os.open(target, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            os.close(descriptor)
            break
        except FileExistsError:
            target = source.with_name(source.stem + f'_trimmed_{serial}.mp4')
            serial += 1
    temporary = None
    try:
        descriptor, temporary = tempfile.mkstemp(prefix='.pistachio-trim-', suffix='.part.mp4', dir=source.parent)
        os.close(descriptor)
        # Re-encode to avoid keyframe snapping; optional audio preserves silent recordings too.
        run(['ffmpeg', '-v', 'error', '-nostdin', '-y', '-ss', str(start), '-i', str(source), '-t', str(end-start),
             '-map', '0:v:0', '-map', '0:a?', '-c:v', 'libx264', '-preset', 'fast', '-crf', '20', '-c:a', 'aac',
             '-movflags', '+faststart', temporary])
        os.replace(temporary, target)
        temporary = None
        return str(target)
    except BaseException:
        target.unlink(missing_ok=True)
        raise
    finally:
        if temporary:
            Path(temporary).unlink(missing_ok=True)


def main():
    signal.signal(signal.SIGTERM, cancel)
    signal.signal(signal.SIGINT, cancel)
    try:
        if len(sys.argv) == 3 and sys.argv[1] == 'probe':
            result = {'duration': probe(sys.argv[2])}
        elif len(sys.argv) == 5 and sys.argv[1] == 'trim':
            result = {'path': trim(sys.argv[2], sys.argv[3], sys.argv[4])}
        else:
            raise ValueError('Invalid capture command')
        print(json.dumps(result), flush=True)
        return 0
    except (ValueError, OSError, KeyError) as error:
        print(json.dumps({'error': str(error)}), flush=True)
        return 1


if __name__ == '__main__':
    sys.exit(main())
