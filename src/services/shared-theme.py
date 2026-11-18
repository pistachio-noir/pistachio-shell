#!/usr/bin/env python3
"""Publish the shell's colour choice for Pistachio applications."""
import os
from pathlib import Path
import sys
import subprocess
import tempfile


def write_atomic(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.shared-theme-')
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(content)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def publish(path, scheme):
    if scheme not in ('pistachio', 'noir'):
        raise ValueError('invalid colour scheme')
    write_atomic(path, scheme + '\n')
    kitty = path.parent.parent / 'kitty/pistachio-shared.conf'
    if kitty.exists():
        content = 'include ' + ('noir.conf' if scheme == 'noir' else 'pistachio-noir.conf') + '\n'
        if kitty.read_text() != content:
            write_atomic(kitty, content)
            result = subprocess.run(['pkill', '-USR1', '-u', str(os.getuid()), '-x', 'kitty'])
            if result.returncode not in (0, 1):
                print('Could not reload Kitty configuration', file=sys.stderr)


if __name__ == '__main__':
    publish(Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'pistachio/shared-theme', sys.argv[1])
