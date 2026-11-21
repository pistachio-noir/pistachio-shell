import os
import pathlib
import shutil
import subprocess
import tempfile
import time
import threading

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
    tmp = pathlib.Path(tmp)
    log = tmp / 'log'
    qs = tmp / 'qs'
    qs.write_text('#!/bin/sh\ncase "$*" in *list) printf "Process ID: %s\\n" "$TEST_SHELL_PID";; *) printf "%s\\n" "$*" >> "$TEST_LOG";; esac\n')
    qs.chmod(0o755)
    helper = tmp / 'pistachio-auth'
    shutil.copy('/usr/bin/sleep', helper)
    shell = subprocess.Popen(['python3', '-c', 'import subprocess,sys,time; p=subprocess.Popen([sys.argv[1],"60"]); print(p.pid,flush=True); time.sleep(60)', str(helper)], stdout=subprocess.PIPE, text=True)
    helper_pid = int(shell.stdout.readline())
    unrelated = subprocess.Popen(['sleep', '60'])
    reaper = threading.Thread(target=shell.wait, daemon=True)
    reaper.start()
    env = dict(os.environ, PATH=str(tmp) + ':' + os.environ['PATH'], TEST_SHELL_PID=str(shell.pid), TEST_LOG=str(log))
    try:
        # the Rust psc (bin/psc, the old script, is gone since 19 November 2026); PSC= for another build
        psc = os.environ.get('PSC') or str(root / 'rust/target/release/psc')
        result = subprocess.run([psc, 'force-restart'], env=env, capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, result.stderr
        reaper.join(timeout=2)
        assert shell.returncode == -9, shell.returncode
        # The helper must be dead even if it has not yet been reaped.
        status = pathlib.Path(f'/proc/{helper_pid}/stat')
        assert not status.exists() or status.read_text().split()[2] == 'Z'
        assert unrelated.poll() is None, 'unrelated process was stopped'
        assert '-c pistachio -n -d' in log.read_text()
    finally:
        unrelated.kill()
        unrelated.wait()
        if shell.poll() is None:
            shell.kill()
            shell.wait()
print('ok: force restart kills the selected shell and starts a replacement')
