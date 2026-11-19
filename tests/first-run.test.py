"""The first-run view (src/setup) with only fixture values and no system services, offscreen or
on Wayland (PISTACHIO_SETUP_NATIVE=1); PISTACHIO_SETUP_SHOTS=<dir> saves each page."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="pistachio-first-run-") as folder:
    root = Path(folder)
    # the view alone: the window and its controller reach the shell's services, which this fixture leaves out
    shutil.copytree(ROOT / "src/setup", root / "setup", ignore=shutil.ignore_patterns("FirstRunWindow.qml", "SetupController.qml"))
    for subdir, files in {
        "components": ("Icon.qml", "Icons.qml", "ShellLogo.qml"),
    }.items():
        (root / subdir).mkdir()
        for name in files:
            shutil.copyfile(ROOT / "src" / subdir / name, root / subdir / name)
    shutil.copyfile(ROOT / "src/Theme.qml", root / "Theme.qml")
    native = os.environ.get("PISTACHIO_SETUP_NATIVE") == "1"
    (root / "shell.qml").write_text((ROOT / "tests/first-run-ui.qml").read_text())
    for name in ("home", "runtime", "state", "cache", "config", "data"):
        (root / name).mkdir(mode=0o700)
    environment = dict(os.environ, QT_QPA_PLATFORM="offscreen", HOME=str(root / "home"),
                       XDG_RUNTIME_DIR=str(root / "runtime"), XDG_STATE_HOME=str(root / "state"),
                       XDG_CACHE_HOME=str(root / "cache"), XDG_CONFIG_HOME=str(root / "config"),
                       XDG_DATA_HOME=str(root / "data"))
    for name in ("DISPLAY", "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "DBUS_SESSION_BUS_ADDRESS"):
        environment.pop(name, None)
    if native:
        display = Path(os.environ["WAYLAND_DISPLAY"])
        environment["QT_QPA_PLATFORM"] = "wayland"
        environment["WAYLAND_DISPLAY"] = str(Path(os.environ["XDG_RUNTIME_DIR"]) / display)

    with (root / "shell.log").open("w+") as log:
        shell = subprocess.Popen(["qs", "-p", folder], env=environment, stdout=log, stderr=log)

        def call(function):
            return subprocess.run(["qs", "-p", folder, "ipc", "call", "firstRunTest", function],
                                  env=environment, capture_output=True, text=True, timeout=15).stdout.strip()

        try:
            for _ in range(80):
                if call("ready") == "true" or shell.poll() is not None:
                    break
                time.sleep(0.05)
            result = call("run")
            log.seek(0)
            output = log.read()
            assert result.startswith("PASS"), result + "\n" + output
            assert "ERROR" not in output and "WARN scene:" not in output, output
            print(result)
        finally:
            shell.terminate()
            shell.wait(timeout=5)
