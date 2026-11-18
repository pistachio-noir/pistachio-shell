#!/usr/bin/env python3
"""Settings export/import helper (src/services/prefs.py), in a temporary folder. Run: python3 -B tests/prefs.test.py"""
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import tomllib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
HELPER = ROOT / "src/services/prefs.py"
CTX = {"actions": ["settings", "lens"], "claudeModels": ["claude-haiku-5-5", "sonnet", "opus"], "codexModels": ["gpt-6-luna", "gpt-6.1-sol"]}
VALUES = {
    "frosted": True, "frostStyle": "glassy", "appearanceStyle": "tui", "colourScheme": "noir", "tuiTrayOpen": False, "phonePreview": True, "desktopCat": True, "clipboardHistory": True, "monochromeWallpaper": True, "gameMode": True, "gameClasses": ["minecraft"],
    "nightLight": True, "temperature": 3750.0, "nightSchedule": True, "nightFrom": 1320, "nightTo": 420,
    "dnd": False, "dndFrom": 1320, "notificationRules": {"Vesktop": {"noToasts": True}, "Spotify": {"until": 9999999999999}},
    "focusMinutes": 60, "focusAllowed": ["Vesktop"], "pomodoroRounds": 4,
    "lensProvider": "codex", "lensClaudeModel": "sonnet", "lensCodexEffort": "high",
    "screenshotOutput": "both", "recordingCountdown": 3, "terminal": "kitty", "weatherCity": "Kłobuck \"centre\" \\ west",
    "integrationsOff": ["steam", "tldr"], "localsendName": "", "localsendFolder": "",
    "launcherPins": [{"kind": "app", "target": "helium"}, {"kind": "action", "target": "lens"}],
    "launcherAliases": {"hl": {"kind": "app", "target": "helium"}, "dc": {"kind": "app", "target": "vesktop"}},
    "workspacePresets": [{"name": "work", "names": {"2": "code"}, "apps": {"2": ["code.desktop"], "3": []}}],
}


def run(*args):
    out = subprocess.run([sys.executable, "-B", str(HELPER), *args], capture_output=True, text=True, timeout=20)
    return out.returncode, json.loads(out.stdout)


class Prefs(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = pathlib.Path(self.dir.name) / "pistachio" / "pistachio-shell" / "settings.toml"

    def tearDown(self):
        self.dir.cleanup()

    def export(self, values):
        return run("export", str(self.path), json.dumps({"values": values}))

    def read(self):
        return run("read", str(self.path), json.dumps(CTX))

    def test_round_trip(self):
        code, reply = self.export(VALUES)
        self.assertEqual((code, reply["ok"]), (0, True))
        code, reply = self.read()
        self.assertEqual(reply["skipped"], [])
        got = reply["values"]
        self.assertEqual(got["temperature"], 3750)  # QML's float comes back whole
        self.assertEqual(got["nightFrom"], 1320)
        self.assertEqual(got["weatherCity"], VALUES["weatherCity"])
        self.assertEqual(got["notificationRules"], {"Vesktop": {"noToasts": True}})  # a timed silence doesn't travel
        for key in VALUES:
            if key not in ("temperature", "notificationRules"):
                self.assertEqual(got[key], VALUES[key], key)
        text = self.path.read_text()
        self.assertIn('night_from = "22:00"', text)
        self.assertIn("[[launcher.presets]]", text)

    def test_secrets_and_history_never_written(self):
        values = dict(VALUES, ciderToken="secret-token", localsendKnown=["private-device-identifier"], notifications=[{"summary": "hi"}],
                      launches={"helium": 3}, recentCommands=["ls"], focusState={"x": 1}, wallpaper="/w.png", desktopPositions={"a": 1})
        self.export(values)
        text = self.path.read_text()
        for leaked in ("secret-token", "private-device-identifier", "summary", "recentCommands", "/w.png", "focusState"):
            self.assertNotIn(leaked, text)

    def test_bad_and_unknown_values_are_skipped(self):
        self.path.parent.mkdir(parents=True)
        self.path.write_text('''
[experimental]
style = "fancy"
colours = "noir"
[display]
night_from = "25:00"
night_warmth = 9000
[focus]
focus_minutes = 61
[lens]
claude_model = "gpt-6-luna"
[launcher]
pins = [{ kind = "action", target = "rm -rf" }]
[launcher.aliases]
"bad alias!" = { kind = "app", target = "x" }
[integrations]
off = ["steam", "nope"]
[localsend]
folder = "/definitely/not/here"
[nonsense]
x = 1
[appearance]
glitter = true
''')
        code, reply = self.read()
        self.assertTrue(reply["ok"])
        self.assertEqual(reply["values"], {"colourScheme": "noir"})
        skipped = {s["key"] for s in reply["skipped"]}
        self.assertTrue({"experimental.style", "display.night_from", "display.night_warmth", "focus.focus_minutes", "lens.claude_model",
                         "launcher.pins", "launcher.aliases", "integrations.off", "localsend.folder", "nonsense", "appearance.glitter"} <= skipped, skipped)

    def test_backup_and_valid_file(self):
        self.export({"frosted": True})
        first = self.path.read_text()
        self.export({"frosted": False})
        self.assertEqual((self.path.parent / "settings.toml.bak").read_text(), first)
        tomllib.loads(self.path.read_text())
        self.assertIn("frosted = false", self.path.read_text())

    def test_missing_and_broken_files(self):
        code, reply = self.read()
        self.assertEqual((code, reply["ok"]), (1, False))
        self.assertIn("export first", reply["error"])
        self.path.parent.mkdir(parents=True)
        self.path.write_text("[appearance\nfrosted = ")
        code, reply = self.read()
        self.assertFalse(reply["ok"])
        self.assertIn("isn't valid TOML", reply["error"])

    def test_service_keys_match_schema(self):
        schema = set(re.findall(r'\("[a-z]+", "[a-z_]+", "([A-Za-z]+)", [a-z_]', HELPER.read_text()))
        qml = (ROOT / "src/services/Preferences.qml").read_text()
        block = qml[qml.index("readonly property var titles"):qml.index("readonly property var times")]
        titles = set(re.findall(r"\b([a-zA-Z]+): \"", block))
        self.assertEqual(schema, titles)


if __name__ == "__main__":
    unittest.main(verbosity=1)
