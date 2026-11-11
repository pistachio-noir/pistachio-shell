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
model=sys.argv[sys.argv.index('--model')+1] if '--model' in sys.argv else ''
if name in control.get('fail', []) or model in control.get('fail_models', []):
    message=control.get('message','Usage limit reached (429)')
    print(json.dumps({'is_error':True,'result':message} if name=='claude' else {'type':'error','message':message}))
    sys.exit(1)
if control.get('malformed'):
    print('not json'); sys.exit(0)
answer={'answer':'**Read the snip.**\n\n```rust\nlet owned = &name;\n```','actions':[{'label':'Explain','kind':'followup','prompt':'Why borrow?','query':''}]}
answer['replacement']=control.get('replacement')
answer['task']=control.get('task','other')
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
                        "claude": {"model": "claude-haiku-5-5", "effort": "medium", "fallback": False,
                                   "coding": {"model": "sonnet", "effort": "high"}},
                        "codex": {"model": "gpt-6-luna", "effort": "low", "fallback": False,
                                  "coding": {"model": "gpt-6.1-sol", "effort": "high"}}}

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

    def attach(self, text="old\n"):
        path = self.root / "example.rs"
        path.write_bytes(text.encode())
        path.chmod(0o751)
        self.lens.attach(str(path))
        return path

    def test_proposal_apply_is_explicit_and_preserves_permissions(self):
        path = self.attach()
        self.control.write_text(json.dumps({"replacement": "new\n"}))
        result = self.ask()
        self.assertIn("-old\n+new", result["diff"])
        self.assertEqual(path.read_text(), "old\n")
        self.lens.review(True)
        self.assertEqual(path.read_text(), "new\n")
        self.assertEqual(path.stat().st_mode & 0o777, 0o751)
        self.assertIn("Proposed changes · Applied", (self.lens.folder / "chat.md").read_text())
        self.assertFalse(list(self.root.glob(".pistachio-lens-*")))

    def test_discard_and_missing_attachment_never_write(self):
        path = self.attach()
        self.control.write_text(json.dumps({"replacement": "new\n"}))
        self.ask()
        self.lens.review(False)
        self.assertEqual(path.read_text(), "old\n")
        self.assertIsNone(self.lens.proposal)
        self.lens.attach("")
        self.assertEqual(self.ask()["diff"], "")

    def test_changed_or_replaced_file_rejects_apply(self):
        path = self.attach()
        self.control.write_text(json.dumps({"replacement": "new\n"}))
        self.ask()
        path.write_text("owner's edit\n")
        with self.assertRaisesRegex(ValueError, "changed"):
            self.lens.review(True)
        self.assertEqual(path.read_text(), "owner's edit\n")
        path.unlink()
        target = self.root / "other.rs"
        target.write_text("old\n")
        path.symlink_to(target)
        with self.assertRaisesRegex(ValueError, "changed"):
            self.lens.review(True)
        self.assertEqual(target.read_text(), "old\n")

    def test_transfer_reuses_snapshot_and_context_without_auto_fallback(self):
        path = self.attach()
        self.control.write_text(json.dumps({"replacement": "first proposal\n"}))
        self.ask()
        path.write_text("changed on disk\n")
        self.request.update(provider="codex", transfer=True)
        self.control.write_text(json.dumps({"replacement": "second proposal\n"}))
        self.assertEqual(self.ask()["provider"], "codex")
        prompt = self.calls()[-1]["args"][-1]
        self.assertIn('"content": "old\\n"', prompt)
        self.assertNotIn("changed on disk", prompt)
        self.assertIn("Read the snip", prompt)
        self.assertEqual(self.lens.proposal["replacement"], "second proposal\n")
        self.assertEqual((self.lens.folder / "chat.md").read_text().count("## You"), 2)
        self.control.write_text(json.dumps({"fail": ["codex"]}))
        self.request["codex"]["fallback"] = True
        before = len(self.calls())
        self.assertEqual(self.ask()["event"], "error")
        self.assertEqual(len(self.calls()), before + 1)

    def test_attachments_validate_and_fresh_questions_refresh_snapshot(self):
        path = self.attach()
        self.ask()
        path.write_text("current\n")
        self.request["question"] = "Fix the current file"
        self.ask()
        self.assertIn('"content": "current\\n"', self.calls()[-1]["args"][1])
        for content in (b"\xff", b"a\0b", b"x" * 32769):
            path.write_bytes(content)
            with self.assertRaises(ValueError):
                self.lens.attach(str(path))

    def test_empty_replacement_and_final_newline_are_reviewable(self):
        path = self.attach("old\n")
        self.control.write_text(json.dumps({"replacement": "old"}))
        self.assertIn("No newline at end of file", self.ask()["diff"])
        self.control.write_text(json.dumps({"replacement": ""}))
        self.assertIn("-old", self.ask()["diff"])
        self.lens.review(True)
        self.assertEqual(path.read_bytes(), b"")

    def test_coding_offer_needs_consent_then_retries_same_snapshot(self):
        path = self.attach()
        self.control.write_text(json.dumps({"task": "coding", "replacement": "normal proposal\n"}))
        first = self.ask()
        self.assertTrue(first["offer_coding"])
        self.assertEqual(len(self.calls()), 1)
        path.write_text("changed on disk\n")
        self.request.update(upgrade=True, coding_enabled=True)
        self.control.write_text(json.dumps({"task": "coding", "replacement": "coding proposal\n"}))
        result = self.ask()
        self.assertEqual((result["model"], result["effort"]), ("sonnet", "high"))
        self.assertFalse(result["offer_coding"])
        self.assertIn('"content": "old\\n"', self.calls()[-1]["args"][1])
        with self.assertRaisesRegex(ValueError, "changed"):
            self.lens.review(True)
        saved = (self.lens.folder / "chat.md").read_text()
        self.assertIn("sonnet · high", saved)
        self.assertIn("claude-haiku-5-5 · medium", saved)

    def test_accepted_coding_turns_use_each_providers_own_preset(self):
        self.control.write_text(json.dumps({"task": "coding"}))
        self.request["coding_enabled"] = True
        for provider, model in (("claude", "sonnet"), ("codex", "gpt-6.1-sol")):
            self.request["provider"] = provider
            before = len(self.calls()) if self.record.exists() else 0
            result = self.ask()
            self.assertEqual(len(self.calls()), before + 2)
            self.assertEqual((result["model"], result["effort"]), (model, "high"))

    def test_non_coding_turns_never_inherit_coding_preset(self):
        self.request["coding_enabled"] = True
        for purpose in ("translation", "summary", "extraction"):
            # Even an erroneous agent classification cannot override an explicit chip.
            self.control.write_text(json.dumps({"task": "coding"}))
            self.request.update(purpose=purpose, question=purpose + " this code")
            before = len(self.calls()) if self.record.exists() else 0
            result = self.ask()
            self.assertEqual(result["task"], purpose)
            self.assertEqual(len(self.calls()), before + 1)
            self.assertEqual(result["model"], "claude-haiku-5-5")
            self.assertFalse(result["offer_coding"])
        self.request.update(purpose="auto", question="Translate this code comment into Polish")
        self.control.write_text(json.dumps({"task": "translation"}))
        before = len(self.calls())
        self.assertEqual(self.ask()["model"], "claude-haiku-5-5")
        self.assertEqual(len(self.calls()), before + 1)

    def test_explicit_upgrade_rejected_for_non_coding_question(self):
        self.ask()
        self.request["upgrade"] = True
        result = self.ask()
        self.assertEqual(result["event"], "upgrade_failed")
        self.assertEqual(len(self.calls()), 1)

    def test_upgrade_failure_keeps_previous_proposal_and_does_not_fallback(self):
        path = self.attach()
        self.control.write_text(json.dumps({"task": "coding", "replacement": "normal proposal\n"}))
        self.ask()
        proposal = self.lens.proposal
        self.control.write_text(json.dumps({"fail_models": ["sonnet"]}))
        self.request.update(upgrade=True, coding_enabled=True)
        self.request["claude"]["fallback"] = True
        self.assertEqual(self.ask()["event"], "upgrade_failed")
        self.assertEqual(len(self.calls()), 2)
        self.assertIs(self.lens.proposal, proposal)
        self.lens.review(True)
        self.assertEqual(path.read_text(), "normal proposal\n")

    def test_automatic_upgrade_failure_keeps_normal_answer(self):
        self.request["coding_enabled"] = True
        self.control.write_text(json.dumps({"task": "coding", "fail_models": ["sonnet"]}))
        result = self.ask()
        self.assertEqual(result["event"], "answer")
        self.assertEqual(result["model"], "claude-haiku-5-5")
        self.assertIn("showing the normal answer", result["warning"])

    def test_identical_preset_does_not_offer_or_repeat(self):
        self.request["claude"]["coding"] = self.request["claude"].copy()
        self.control.write_text(json.dumps({"task": "coding"}))
        self.assertFalse(self.ask()["offer_coding"])
        self.request["coding_enabled"] = True
        self.ask()
        self.assertEqual(len(self.calls()), 2)

    def test_cancel_upgrade_keeps_previous_proposal(self):
        self.attach()
        self.control.write_text(json.dumps({"task": "coding", "replacement": "normal proposal\n"}))
        self.ask()
        proposal, previous_pid = self.lens.proposal, self.lens.process.pid
        self.control.write_text(json.dumps({"delay": 30, "task": "coding"}))
        self.request.update(upgrade=True, coding_enabled=True)
        before = len(self.events)
        self.lens.ask(self.request)
        deadline = time.monotonic() + 3
        while self.lens.process.pid == previous_pid and time.monotonic() < deadline:
            time.sleep(.01)
        self.assertNotEqual(self.lens.process.pid, previous_pid)
        self.lens.stop()
        self.lens.worker.join(3)
        self.assertIs(self.lens.proposal, proposal)
        self.assertFalse(any(e["event"] in ("answer", "upgrade_failed", "fallback") for e in self.events[before:]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
