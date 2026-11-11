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
prompt=sys.argv[sys.argv.index('-p')+1] if name=='claude' else sys.argv[-1]
if 'SYNTHESISE BOTH PROVIDER RESPONSES' in prompt:
    if control.get('delay_synthesis'): time.sleep(control['delay_synthesis'])
    if control.get('fail_synthesis'):
        print('synthesis failed', file=sys.stderr); sys.exit(1)
    answer['answer']='One combined answer'
    answer['replacement']=control.get('synthesis_replacement', answer['replacement'])
else:
    answer['answer']=control.get('answers', {}).get(name, answer['answer'])
    answer['replacement']=control.get('replacements', {}).get(name, answer['replacement'])
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
        self.lens.cleanup()
        self.environ.stop()
        self.tmp.cleanup()

    def ask(self):
        self.lens.ask(self.request)
        self.lens.worker.join(5)
        self.assertFalse(self.lens.worker.is_alive())
        return self.events[-1]

    def calls(self):
        return [json.loads(line) for line in self.record.read_text().splitlines()]

    def image_file(self, name="second image.png"):
        path = self.root / name
        # A tiny valid PNG, recognised by both helper and Qt fixtures.
        import base64
        path.write_bytes(base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1kAAAAASUVORK5CYII="))
        return path

    def test_three_images_are_numbered_removable_and_reused_by_followups(self):
        self.assertTrue(callable(getattr(self.lens, "add_image", None)), "multi-image protocol is missing")
        second = self.image_file()
        self.lens.add_image(second)
        self.lens.add_image(self.image_file("third.png"))
        with self.assertRaisesRegex(ValueError, "three"):
            self.lens.add_image(second)
        self.request["provider"] = "codex"
        self.ask()
        args = self.calls()[-1]["args"]
        self.assertEqual(args.count("--image"), 3)
        self.assertEqual(args[args.index("--image") + 1], str(self.lens.folder / "snip.png"))
        second.write_bytes(b"changed outside Lens")
        self.request["question"] = "Compare these three"
        self.ask()
        self.assertEqual(self.calls()[-1]["args"].count("--image"), 3)
        second_id = self.lens.images[1]["id"]
        self.lens.remove_image(second_id)
        self.request["provider"] = "claude"
        self.ask()
        prompt = self.calls()[-1]["args"][1]
        self.assertIn("Image 1:", prompt)
        self.assertIn("Image 2:", prompt)
        self.assertNotIn("Image 3:", prompt)
        self.assertEqual(len(self.lens.images), 2)
        saved = (self.lens.folder / "chat.md").read_text()
        self.assertIn("snip-2.png", saved)
        self.assertIn("snip-3.png", saved)
        self.assertEqual((self.lens.folder / "snip-2.png").read_bytes()[:8], b"\x89PNG\r\n\x1a\n")

    def test_image_attachment_rejects_text_symlink_and_overlarge_file(self):
        self.assertTrue(callable(getattr(self.lens, "add_image", None)), "multi-image protocol is missing")
        bad = self.root / "not.png"
        bad.write_text("not an image")
        with self.assertRaisesRegex(ValueError, "image"):
            self.lens.add_image(bad)
        link = self.root / "link.png"
        link.symlink_to(self.image_file())
        with self.assertRaisesRegex(ValueError, "symbolic"):
            self.lens.add_image(link)
        with bad.open("wb") as output:
            output.truncate(32 * 1024 * 1024 + 1)
        with self.assertRaisesRegex(ValueError, "32 MiB"):
            self.lens.add_image(bad)
        self.assertEqual(len(self.lens.images), 1)

    def test_ask_both_synthesises_once_and_only_final_replacement_can_apply(self):
        path = self.attach()
        self.request["both"] = True
        self.control.write_text(json.dumps({"answers": {"claude": "Claude source", "codex": "Codex source"},
            "replacements": {"claude": "first source\n", "codex": "second source\n"}, "synthesis_replacement": "combined\n"}))
        answer = self.ask()
        self.assertEqual([call["name"] for call in self.calls()], ["claude", "codex", "claude"])
        self.assertEqual(answer["answer"], "One combined answer")
        self.assertTrue(answer["combined"])
        final_prompt = self.calls()[-1]["args"][1]
        self.assertIn("Claude source", final_prompt)
        self.assertIn("Codex source", final_prompt)
        self.assertIn('"content": "old\\n"', final_prompt)
        self.assertIn("first source", final_prompt)
        self.assertNotIn("--resume", self.calls()[-1]["args"])
        self.assertEqual(path.read_text(), "old\n")
        self.assertEqual(self.lens.proposal["replacement"], "combined\n")
        self.lens.review(True)
        self.assertEqual(path.read_text(), "combined\n")
        saved = (self.lens.folder / "chat.md").read_text()
        for text in ("Claude source", "Codex source", "One combined answer", "combined", "Applied"):
            self.assertIn(text, saved)
        self.assertEqual(saved.count("## You"), 1)

    def test_combination_failure_never_publishes_source_proposal_or_falls_back(self):
        path = self.attach()
        self.request.update(both=True)
        self.request["claude"]["fallback"] = True
        self.control.write_text(json.dumps({"replacement": "source edit\n", "fail_synthesis": True}))
        self.assertEqual(self.ask()["event"], "error")
        self.assertEqual(len(self.calls()), 3)
        self.assertIsNone(self.lens.proposal)
        self.assertEqual(path.read_text(), "old\n")
        self.assertIn("source edit", (self.lens.folder / "chat.md").read_text())
        self.assertFalse(any(event["event"] == "answer" for event in self.events))

    def test_both_translation_uses_normal_presets_even_after_coding_consent(self):
        self.request.update(both=True, coding_enabled=True, purpose="translation", provider="codex")
        self.control.write_text(json.dumps({"task": "coding"}))
        result = self.ask()
        self.assertEqual([call["name"] for call in self.calls()], ["codex", "claude", "codex"])
        self.assertEqual([call["args"][call["args"].index("--model") + 1] for call in self.calls()],
                         ["gpt-6-luna", "claude-haiku-5-5", "gpt-6-luna"])
        self.assertEqual(result["task"], "translation")
        self.assertFalse(result["offer_coding"])

    def test_both_identical_coding_presets_do_not_add_redundant_requests(self):
        self.request.update(both=True, coding_enabled=True)
        self.control.write_text(json.dumps({"task": "coding"}))
        for provider in ("claude", "codex"):
            self.request[provider]["coding"] = {key: self.request[provider][key] for key in ("model", "effort")}
        self.ask()
        self.assertEqual(len(self.calls()), 3)

    def test_cancelling_synthesis_keeps_sources_and_never_offers_their_replacements(self):
        path = self.attach()
        self.request["both"] = True
        self.control.write_text(json.dumps({"replacement": "source edit\n", "delay_synthesis": 30}))
        self.lens.ask(self.request)
        deadline = time.monotonic() + 3
        while (not self.record.exists() or len(self.calls()) < 3) and time.monotonic() < deadline:
            time.sleep(.01)
        self.assertEqual(len(self.calls()), 3)
        self.lens.stop()
        self.lens.worker.join(3)
        self.assertFalse(self.lens.worker.is_alive())
        self.assertIsNotNone(self.lens.process.poll())
        self.assertIsNone(self.lens.proposal)
        self.assertEqual(path.read_text(), "old\n")
        self.assertFalse(any(event["event"] in ("answer", "fallback", "error") for event in self.events))
        self.assertEqual(len(self.lens.sources), 2)
        self.assertIn("source edit", (self.lens.folder / "chat.md").read_text())

    def test_failed_explicit_combined_upgrade_keeps_original_proposal(self):
        path = self.attach()
        self.control.write_text(json.dumps({"task": "coding", "replacement": "normal\n"}))
        self.ask()
        original = self.lens.proposal
        self.request.update(both=True, upgrade=True, coding_enabled=True)
        self.control.write_text(json.dumps({"task": "coding", "replacement": "source\n", "fail_synthesis": True}))
        self.assertEqual(self.ask()["event"], "upgrade_failed")
        self.assertIs(self.lens.proposal, original)
        self.lens.review(True)
        self.assertEqual(path.read_text(), "normal\n")

    def test_automatic_combined_coding_failure_falls_back_to_same_provider_normal_synthesis(self):
        self.request.update(both=True, coding_enabled=True)
        self.control.write_text(json.dumps({"task": "coding", "fail_models": ["sonnet"]}))
        answer = self.ask()
        self.assertEqual(answer["event"], "answer")
        self.assertTrue(answer["combined"])
        self.assertEqual(answer["model"], "claude-haiku-5-5")
        self.assertIn("normal", answer["warning"])
        self.assertEqual([call["name"] for call in self.calls()][-2:], ["claude", "claude"])

    def test_removed_unsent_images_are_not_saved_in_chat(self):
        second = self.image_file()
        self.lens.add_image(second)
        self.lens.remove_image(self.lens.images[-1]["id"])
        self.ask()
        self.assertFalse((self.lens.folder / "snip-2.png").exists())
        third = self.image_file("third.png")
        self.lens.add_image(third)
        self.lens.remove_image(self.lens.images[-1]["id"])
        self.request["question"] = "A follow up"
        self.ask()
        self.assertFalse((self.lens.folder / "snip-3.png").exists())
        self.assertEqual(second.read_bytes(), third.read_bytes())

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
                event = receive()
                while event["event"] == "images":
                    event = receive()
                self.assertEqual(event["event"], "reading")
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
