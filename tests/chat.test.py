#!/usr/bin/env python3
"""The quick chat's helper (src/services/chat.py) against stand-in `claude` and `codex` programs that
answer in the CLIs' own event formats (captured from Claude Code and codex-cli 0.167 on 13 November
2026). No real request is made; chats are saved under a temporary home."""

import json
import os
import queue
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

HELPER = Path(__file__).resolve().parent.parent / "src" / "services" / "chat.py"

FAKE = r'''#!/usr/bin/env python3
import json, os, sys, time
name = os.path.basename(sys.argv[0])
log = os.environ["FAKE_LOG"]
with open(log, "a") as f:
    f.write(json.dumps({"cli": name, "argv": sys.argv[1:]}) + "\n")
mode = open(os.environ["FAKE_MODE"]).read().strip()
def out(e):
    print(json.dumps(e), flush=True)
if mode == "fail":
    print("Error: connection refused (ECONNREFUSED)", file=sys.stderr)
    sys.exit(1)
if name == "claude":
    session = sys.argv[sys.argv.index("--resume") + 1] if "--resume" in sys.argv else "claude-session-1"
    out({"type": "system", "subtype": "init", "session_id": session})
    words = ["Use ", "a soft ", "reset."]
    for i, w in enumerate(words):
        out({"type": "stream_event", "event": {"type": "content_block_delta", "delta": {"type": "text_delta", "text": w}}})
        time.sleep(0.08)
        if mode == "slow" and i == 1:
            time.sleep(30)
    out({"type": "result", "subtype": "success", "is_error": False, "session_id": session, "result": "".join(words)})
else:
    session = sys.argv[sys.argv.index("resume") + 1] if "resume" in sys.argv else "codex-thread-1"
    out({"type": "thread.started", "thread_id": session})
    out({"type": "turn.started"})
    out({"type": "item.completed", "item": {"type": "agent_message", "text": "git reset --soft HEAD~1"}})
    out({"type": "turn.completed"})
'''


class Helper:
    def __init__(self, test):
        self.test = test
        self.events = queue.Queue()
        env = dict(os.environ, PATH=f"{test.bin}:{os.environ['PATH']}", QUICK_CHAT_HOME=str(test.home),
                   FAKE_LOG=str(test.log), FAKE_MODE=str(test.mode))
        self.p = subprocess.Popen([sys.executable, "-I", str(HELPER)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True, env=env)
        threading.Thread(target=self.read, daemon=True).start()
        self.wait("ready")

    def read(self):
        for line in self.p.stdout:
            self.events.put(json.loads(line))

    def send(self, **message):
        self.p.stdin.write(json.dumps(message) + "\n")
        self.p.stdin.flush()

    def wait(self, event, seconds=8):
        seen = []
        end = time.time() + seconds
        while time.time() < end:
            try:
                m = self.events.get(timeout=max(0.05, end - time.time()))
            except queue.Empty:
                break
            seen.append(m)
            if m["event"] == event:
                m["_seen"] = seen
                return m
        self.test.fail(f"no {event} event; saw {seen}")

    def ask(self, question, provider="claude", context=None):
        self.send(cmd="ask", question=question, provider=provider, model="m-" + provider, effort="low", context=context or {})

    def close(self):
        self.p.stdin.close()
        self.p.wait(5)


class ChatHelperTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.bin, self.home = self.tmp / "bin", self.tmp / "home"
        self.bin.mkdir()
        self.home.mkdir()
        for name in ("claude", "codex"):
            (self.bin / name).write_text(FAKE)
            (self.bin / name).chmod(0o755)
        self.log, self.mode = self.tmp / "calls.jsonl", self.tmp / "mode"
        self.mode.write_text("ok")
        self.helper = Helper(self)

    def tearDown(self):
        if self.helper.p.poll() is None:
            self.helper.close()
        subprocess.run(["rm", "-rf", str(self.tmp)])

    def calls(self):
        return [json.loads(l) for l in self.log.read_text().splitlines()] if self.log.exists() else []

    def chats(self):
        return sorted((self.home / "quick-chats").iterdir())

    def test_claude_streams_and_a_follow_up_resumes_its_session(self):
        self.helper.ask("how do I undo my last commit?")
        answer = self.helper.wait("answer")
        deltas = [m["text"] for m in answer["_seen"] if m["event"] == "delta"]
        self.assertTrue(deltas and deltas[0].startswith("Use") and len(deltas[-1]) >= len(deltas[0]), deltas)
        self.assertEqual((answer["text"], answer["provider"], answer["stopped"]), ("Use a soft reset.", "claude", False))
        first = self.calls()[0]["argv"]
        self.assertIn("stream-json", first)
        self.assertIn("--include-partial-messages", first)
        self.assertEqual(first[first.index("--tools") + 1], "")  # no tool without a picture
        self.assertNotIn("--resume", first)
        self.helper.ask("and keep the changes?")
        self.helper.wait("answer")
        second = self.calls()[1]["argv"]
        self.assertEqual(second[second.index("--resume") + 1], "claude-session-1")
        self.assertNotIn("Conversation so far", second[second.index("-p") + 1])
        [folder] = self.chats()
        state = json.loads((folder / "chat.json").read_text())
        self.assertEqual([m["role"] for m in state["messages"]], ["user", "assistant", "user", "assistant"])
        self.assertIn("## You", (folder / "chat.md").read_text())

    def test_codex_answers_whole_and_resumes_its_thread(self):
        self.helper.ask("undo commit", provider="codex")
        answer = self.helper.wait("answer")
        self.assertFalse([m for m in answer["_seen"] if m["event"] == "delta"])
        self.assertEqual(answer["text"], "git reset --soft HEAD~1")
        argv = self.calls()[0]["argv"]
        self.assertEqual(argv[:5], ["-a", "never", "-s", "read-only", "exec"])
        self.assertEqual(argv[-2], "--")
        self.assertIn("quick chat", argv[-1])  # the instructions travel with Codex's first prompt
        self.helper.ask("again", provider="codex")
        self.helper.wait("answer")
        argv = self.calls()[1]["argv"]
        self.assertEqual(argv[argv.index("resume") + 1], "codex-thread-1")

    def test_switching_provider_replays_the_conversation(self):
        self.helper.ask("first question")
        self.helper.wait("answer")
        self.helper.ask("second question", provider="codex")
        self.helper.wait("answer")
        prompt = self.calls()[1]["argv"][-1]
        self.assertIn("Conversation so far", prompt)
        self.assertIn("User: first question", prompt)
        self.assertIn("Assistant: Use a soft reset.", prompt)
        self.assertNotIn("resume", self.calls()[1]["argv"])

    def test_context_text_and_pictures_reach_each_provider_read_only(self):
        picture = self.tmp / "window.png"
        picture.write_bytes(b"\x89PNG fake")
        context = {"label": "Selected text from kitty", "text": "error[E0382]", "images": [str(picture)]}
        self.helper.ask("why?", context=context)
        self.helper.wait("answer")
        argv = self.calls()[0]["argv"]
        self.assertEqual((argv[argv.index("--tools") + 1], argv[argv.index("--allowedTools") + 1]), ("Read", "Read"))
        prompt = argv[argv.index("-p") + 1]
        self.assertIn("Selected text from kitty:\n```\nerror[E0382]\n```", prompt)
        [folder] = self.chats()
        self.assertIn(str(folder / "picture-1.png"), prompt)  # a copy kept with the chat, not the original
        self.helper.ask("and this?", provider="codex", context={"label": "Clipboard", "images": [str(picture)]})
        self.helper.wait("answer")
        argv = self.calls()[1]["argv"]
        self.assertEqual(argv[argv.index("--image") + 1], str(folder / "picture-2.png"))

    def test_an_unreachable_provider_is_told_and_the_question_kept(self):
        self.mode.write_text("fail")
        self.helper.ask("hello?")
        error = self.helper.wait("error")
        self.assertTrue(error["unavailable"])
        self.assertEqual(error["question"], "hello?")
        self.assertEqual(self.chats(), [])  # nothing was said: no empty chat left behind
        self.mode.write_text("ok")
        self.helper.ask("hello?")
        self.assertEqual(self.helper.wait("answer")["text"], "Use a soft reset.")

    def test_stop_keeps_what_was_written_and_ends_the_process(self):
        self.mode.write_text("slow")
        self.helper.ask("long one")
        self.helper.wait("delta")
        time.sleep(0.2)
        started = time.time()
        self.helper.send(cmd="stop")
        answer = self.helper.wait("answer", seconds=5)
        self.assertTrue(answer["stopped"])
        self.assertTrue(answer["text"].startswith("Use"))
        self.assertLess(time.time() - started, 3)
        state = json.loads((self.chats()[0] / "chat.json").read_text())
        self.assertTrue(state["messages"][-1]["stopped"])
        self.assertEqual(state["sessions"], {})  # a stopped session isn't resumed
        self.mode.write_text("ok")
        self.helper.ask("next")
        self.helper.wait("answer")
        self.assertNotIn("--resume", self.calls()[1]["argv"])

    def test_history_lists_chats_and_open_continues_one(self):
        self.helper.ask("first chat")
        self.helper.wait("answer")
        self.helper.send(cmd="new")
        time.sleep(1.1)
        self.helper.ask("second chat", provider="codex")
        self.helper.wait("answer")
        self.helper.send(cmd="history")
        chats = self.helper.wait("history")["chats"]
        self.assertEqual([c["title"] for c in chats], ["second chat", "first chat"])
        self.helper.send(cmd="open", id=chats[1]["id"])
        loaded = self.helper.wait("loaded")
        self.assertEqual([m["text"] for m in loaded["messages"]], ["first chat", "Use a soft reset."])
        self.helper.ask("more")
        self.helper.wait("answer")
        argv = self.calls()[-1]["argv"]
        self.assertEqual(argv[argv.index("--resume") + 1], "claude-session-1")
        self.helper.send(cmd="open", id="../../etc")
        self.assertIn("isn't there", self.helper.wait("error")["message"])

    def test_retry_replaces_the_last_answer_without_resuming(self):
        picture = self.tmp / "region.png"
        picture.write_bytes(b"\x89PNG fake")
        self.helper.ask("what is this?", context={"label": "A snip", "images": [str(picture)]})
        self.assertEqual(self.helper.wait("started")["chat"], self.chats()[0].name)
        self.helper.wait("answer")
        self.helper.send(cmd="retry", provider="codex", model="m-codex", effort="low")
        self.helper.wait("answer")
        argv = self.calls()[1]["argv"]
        self.assertNotIn("resume", argv)
        self.assertEqual(argv[argv.index("--image") + 1], str(self.chats()[0] / "picture-1.png"))  # the same copy, not a new one
        self.assertEqual(sorted(p.name for p in self.chats()[0].glob("picture-*")), ["picture-1.png"])
        state = json.loads((self.chats()[0] / "chat.json").read_text())
        self.assertEqual([(m["role"], m.get("provider")) for m in state["messages"]], [("user", None), ("assistant", "codex")])

    def test_ask_both_asks_each_then_combines_with_the_preferred(self):
        self.helper.ask("first")
        self.helper.wait("answer")
        self.helper.send(cmd="ask", question="which is right?", provider="claude", model="m-claude", effort="low",
                         context={}, both={"model": "m-codex", "effort": "low"})
        self.helper.wait("combining")
        answer = self.helper.wait("answer")
        self.assertTrue(answer["both"])
        calls = self.calls()[1:]
        self.assertEqual(sorted(c["cli"] for c in calls), ["claude", "claude", "codex"])
        sources, synthesis = calls[:2], calls[2]
        for call in sources:
            self.assertNotIn("--resume", call["argv"])  # sources don't share a session
            self.assertNotIn("resume", call["argv"])
        prompt = synthesis["argv"][synthesis["argv"].index("-p") + 1]
        self.assertIn("Answer from Claude:", prompt)
        self.assertIn("Answer from ChatGPT:\ngit reset --soft HEAD~1", prompt)
        state = json.loads((self.chats()[0] / "chat.json").read_text())
        self.assertEqual(sorted(s["provider"] for s in state["messages"][-1]["sources"]), ["claude", "codex"])
        self.assertEqual(state["sessions"], {})
        self.assertIn("ChatGPT alone", (self.chats()[0] / "chat.md").read_text())
        self.helper.ask("then?")
        self.helper.wait("answer")
        self.assertIn("Conversation so far", self.calls()[-1]["argv"][self.calls()[-1]["argv"].index("-p") + 1])

    def test_it_exits_when_the_shell_goes(self):
        self.helper.close()
        self.assertEqual(self.helper.p.returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=1)
