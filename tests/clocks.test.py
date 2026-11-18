import json
import os
import subprocess
import tempfile
import unittest

from gi.repository import Gio, GLib


class ClocksTest(unittest.TestCase):
    def test_setting_alarm_keeps_gnome_fields(self):
        with tempfile.TemporaryDirectory() as folder:
            env = dict(os.environ, GSETTINGS_BACKEND="keyfile", XDG_CONFIG_HOME=folder)
            # Use the same isolated backend as the subprocess.
            old = os.environ.copy()
            os.environ.update(env)
            try:
                original = {"id": GLib.Variant("s", "test-id"), "name": GLib.Variant("s", "Test"),
                            "hour": GLib.Variant("i", 8), "minute": GLib.Variant("i", 30),
                            "days": GLib.Variant("ai", []), "ring_time": GLib.Variant("s", "2026-11-19T08:30:00+01:00"),
                            "sound_uri": GLib.Variant("s", "file:///tmp/chime.ogg")}
                settings = Gio.Settings.new("org.gnome.clocks")
                settings.set_value("alarms", GLib.Variant("aa{sv}", [original]))
                Gio.Settings.sync()
                listed = subprocess.run(["python3", "-B", "src/services/clocks.py", "list"],
                                        env=env, check=True, capture_output=True, text=True)
                self.assertTrue(json.loads(listed.stdout)[0]["active"])
                subprocess.run(["python3", "-B", "src/services/clocks.py", "set", "test-id", "inactive"],
                               env=env, check=True, capture_output=True, text=True)
                probe = subprocess.run(["python3", "-B", "-c",
                                        "from gi.repository import Gio; print(Gio.Settings.new('org.gnome.clocks').get_value('alarms').print_(True))"],
                                       env=env, check=True, capture_output=True, text=True)
                self.assertIn("sound_uri", probe.stdout)
                self.assertNotIn("ring_time", probe.stdout)
            finally:
                os.environ.clear()
                os.environ.update(old)


if __name__ == "__main__":
    unittest.main()
