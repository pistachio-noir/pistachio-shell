#!/usr/bin/env python3
"""Exercise the real bridge against fake CLIs; no network or account usage."""
import importlib.util
import json
import os
import select
import subprocess
import sys
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("lens", Path(__file__).resolve().parents[1] / "src/services/lens.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

FAKE = r'''#!/usr/bin/python3
import json, os, pathlib, sys, time
name=pathlib.Path(sys.argv[0]).name
control=json.loads(pathlib.Path(os.environ['LENS_TEST_CONTROL']).read_text())
record=pathlib.Path(os.environ['LENS_TEST_RECORD'])
with record.open('a') as out: out.write(json.dumps({'name':name,'args':sys.argv[1:],'cwd':os.getcwd()})+'\n')
if control.get('read_stdin'): sys.stdin.read()
if control.get('delay'): time.sleep(control['delay'])
if name in control.get('fail', []):
    message=control.get('message','Usage limit reached (429)')
    print(json.dumps({'is_error':True,'result':message} if name=='claude' else {'type':'error','message':message}))
    sys.exit(1)
if control.get('malformed'):
    print('not json'); sys.exit(0)
answer={'answer':'**Read the snip.**\n\n```rust\nlet owned = &name;\n```','actions':[{'label':'Explain','kind':'followup','prompt':'Why borrow?','query':''}]}
session=name+'-session'
if name=='claude': print(json.dumps({'is_error':False,'session_id':session,'structured_output':answer}))
else:
    print(json.dumps({'type':'thread.started','thread_id':session}))
    print(json.dumps({'type':'item.completed','item':{'type':'agent_message','text':json.dumps(answer)}}))
'''


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="pistachio-lens-test-")
        self.root = Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("claude", "codex"):
            script = self.bin / name
            script.write_text(FAKE)
            script.chmod(0o755)
        self.control = self.root / "control.json"
        self.control.write_text("{}")
        self.record = self.root / "calls.jsonl"
        self.environ = patch.dict(os.environ, {"PATH": str(self.bin), "LENS_TEST_CONTROL": str(self.control), "LENS_TEST_RECORD": str(self.record)})
        self.environ.start()
        self.events = []
        self.lens = module.Lens(self.events.append, self.root)
        image = self.root / "source.png"
        image.write_bytes(b"test-image-content")
        self.lens.begin(image)
        self.request = {"question": "Why doesn't this compile?", "provider": "claude",
                        "claude": {"model": "claude-haiku-5-5", "effort": "medium", "fallback": False},
                        "codex": {"model": "gpt-6-luna", "effort": "low", "fallback": False}}

    def tearDown(self):
        self.lens.stop()
        if self.lens.worker:
            self.lens.worker.join(3)
        self.environ.stop()
        self.tmp.cleanup()

    def ask(self):
        self.lens.ask(self.request)
        self.lens.worker.join(5)
        self.assertFalse(self.lens.worker.is_alive())
        return self.events[-1]

    def calls(self):
        return [json.loads(line) for line in self.record.read_text().splitlines()]

    def test_claude_image_answer_resume_and_save(self):
        self.assertEqual(self.ask()["event"], "answer")
        self.request["question"] = "And why borrow it?"
        self.assertEqual(self.ask()["event"], "answer")
        first, second = self.calls()
        self.assertEqual(first["args"][first["args"].index("--tools") + 1], "Read")
        self.assertEqual(second["args"][second["args"].index("--resume") + 1], "claude-session")
        saved = (self.lens.folder / "chat.md").read_text()
        self.assertIn("![Screen snip](snip.png)", saved)
        self.assertEqual(saved.count("## You"), 2)
        self.assertIn("claude-haiku-5-5", saved)
        self.assertEqual((self.lens.folder / "snip.png").read_bytes(), b"test-image-content")

    def test_codex_image_separator_model_effort_and_resume(self):
        self.request["provider"] = "codex"
        self.assertEqual(self.ask()["event"], "answer")
        self.request["question"] = "Follow up"
        self.ask()
        first, second = self.calls()
        self.assertIn("gpt-6-luna", first["args"])
        self.assertIn('model_reasoning_effort="low"', first["args"])
        self.assertIn("features.shell_tool=false", first["args"])
        self.assertIn("features.hooks=false", first["args"])
        self.assertIn("apps._default.enabled=false", first["args"])
        self.assertEqual(first["args"][first["args"].index("--image") + 2], "--")
        self.assertEqual(second["args"][:3], ["-a", "never", "-s"])
        self.assertIn("resume", second["args"])
        self.assertIn("codex-session", second["args"])

    def test_open_control_pipe_does_not_hold_agent_stdin(self):
        # The real CLI reads piped stdin even with a positional prompt. Keep the
        # bridge's control pipe open for a follow-up, exactly as QML's Process does.
        self.control.write_text(json.dumps({"read_stdin": True}))
        wrapper = "import pathlib,runpy,sys; from unittest.mock import patch; " \
                  "p=patch('pathlib.Path.home', return_value=pathlib.Path(sys.argv[2])); " \
                  "p.start(); runpy.run_path(sys.argv[1], run_name='__main__')"
        process = subprocess.Popen([sys.executable, "-B", "-c", wrapper, str(spec.origin), str(self.root)],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        buffer = b""

        def receive():
            nonlocal buffer
            deadline = time.monotonic() + 3
            while b"\n" not in buffer:
                remaining = deadline - time.monotonic()
                self.assertGreater(remaining, 0, "agent waited for EOF on the bridge's open control pipe")
                readable, _, _ = select.select([process.stdout], [], [], remaining)
                self.assertTrue(readable, "agent waited for EOF on the bridge's open control pipe")
                buffer += os.read(process.stdout.fileno(), 65536)
            line, buffer = buffer.split(b"\n", 1)
            return json.loads(line)

        try:
            self.assertEqual(receive()["event"], "ready")
            process.stdin.write((json.dumps({"event": "begin", "path": str(self.root / "source.png")}) + "\n").encode())
            self.request.update(event="ask", provider="codex")
            for question in ("Read this snip", "A follow-up while stdin stays open"):
                self.request["question"] = question
                process.stdin.write((json.dumps(self.request) + "\n").encode())
                process.stdin.flush()
                self.assertEqual(receive()["event"], "reading")
                self.assertEqual(receive()["event"], "answer")
        finally:
            process.terminate()
            process.communicate(timeout=5)

    def test_fallback_in_both_directions(self):
        for primary, backup in (("claude", "codex"), ("codex", "claude")):
            self.control.write_text(json.dumps({"fail": [primary]}))
            self.request["provider"] = primary
            self.request[primary]["fallback"] = True
            result = self.ask()
            self.assertEqual(result["provider"], backup)
            self.assertTrue(any(e["event"] == "fallback" for e in self.events))

    def test_two_unavailable_providers_do_not_loop(self):
        self.control.write_text(json.dumps({"fail": ["claude", "codex"]}))
        self.request["claude"]["fallback"] = self.request["codex"]["fallback"] = True
        self.assertEqual(self.ask()["event"], "error")
        self.assertEqual(len(self.calls()), 2)
        self.assertEqual(self.lens.messages, [])

    def test_fallback_off_and_invalid_response_do_not_switch(self):
        self.control.write_text(json.dumps({"fail": ["claude"]}))
        self.assertEqual(self.ask()["event"], "error")
        self.assertEqual(len(self.calls()), 1)
        self.control.write_text(json.dumps({"malformed": True}))
        self.request["claude"]["fallback"] = True
        self.assertEqual(self.ask()["event"], "error")
        self.assertEqual(len(self.calls()), 2)

    def test_retry_does_not_duplicate_question(self):
        self.control.write_text(json.dumps({"fail": ["claude"]}))
        self.ask()
        folder = self.lens.folder
        self.control.write_text("{}")
        self.assertEqual(self.ask()["event"], "answer")
        self.assertEqual(self.lens.folder, folder)
        self.assertEqual((folder / "chat.md").read_text().count("## You"), 1)

    def test_switch_replays_completed_conversation(self):
        self.ask()
        self.request["provider"] = "codex"
        self.request["question"] = "Now explain ownership."
        self.ask()
        prompt = self.calls()[-1]["args"][-1]
        self.assertIn("Why doesn't this compile?", prompt)
        self.assertIn("Read the snip", prompt)
        self.assertIn("Now explain ownership", prompt)
        self.assertNotIn("resume", self.calls()[-1]["args"])

    def test_cancel_reaps_process_and_does_not_fallback_or_save_answer(self):
        self.control.write_text(json.dumps({"delay": 30}))
        self.request["claude"]["fallback"] = True
        self.lens.ask(self.request)
        deadline = time.monotonic() + 3
        while self.lens.process is None and time.monotonic() < deadline:
            time.sleep(0.01)
        self.lens.stop()
        self.lens.worker.join(3)
        self.assertIsNotNone(self.lens.process.poll())
        self.assertFalse(any(e["event"] in ("answer", "fallback", "error") for e in self.events))
        self.assertEqual(self.lens.messages, [])

    def test_paths_are_safe_and_collision_does_not_overwrite(self):
        self.request["question"] = "../../ Unicode żółty: $(touch nope)"
        self.ask()
        folder = self.lens.folder
        self.assertEqual(folder.parent, self.root / "lens-chats")
        self.lens.begin(self.root / "source.png")
        self.ask()
        self.assertNotEqual(folder, self.lens.folder)
        self.assertTrue((folder / "chat.md").exists())

    def test_action_filter_ignores_unexpected_operations(self):
        text, actions = module.decode_answer(json.dumps({"answer": "Hi", "actions": [
            {"kind": "execute", "label": "Run", "prompt": "rm -rf"},
            {"kind": "search", "label": "Find", "query": "Rust ownership"}]}))
        self.assertEqual(text, "Hi")
        self.assertEqual([a["kind"] for a in actions], ["search"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
