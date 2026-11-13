#!/usr/bin/env python3
"""Quick chat for the shell; services/Chat.qml runs it while the chat is open.

A text chat with Claude Code or Codex (owner's call, 13 November 2026; boards design/QuickChat*.html):
short questions, answers in Markdown. Claude's answer arrives as it's written (stream-json with
partial messages); Codex's `exec --json` sends a message only once it's whole. Follow-ups resume the
provider's own session; switching provider mid-chat replays the conversation so far. Both CLIs run
read-only: Claude may only Read the attached pictures, Codex runs in its read-only sandbox with its
tools off. Each chat is saved in ~/quick-chats/<date time question>/ as chat.md (to read) and
chat.json (to open it again), with its pictures.

  in   {"cmd": "ask", "question": "…", "provider": "claude"|"codex", "model": "…", "effort": "…",
        "context": {"label": "Selected text from kitty", "text": "…", "images": ["/path.png"]},
        "both": {"model": "…", "effort": "…"}}   both: Ask both, with the other provider's model;
                                        each answers on its own, then `provider` writes one answer
                                        from the two (owner's call: three requests, as Lens's Ask both)
  in   {"cmd": "retry", "provider", "model", "effort"}   the last question again, its answer replaced
  in   {"cmd": "stop"}                  ends the answer being written; what came so far is kept
  in   {"cmd": "new"}                   a fresh chat
  in   {"cmd": "history"}               the saved chats, newest first
  in   {"cmd": "open", "id": "…"}       continue a saved chat
  out  {"event": "ready"}
  out  {"event": "started", "chat", "provider", "model", "effort"}   chat: the saved chat's id, for "open"
  out  {"event": "combining"}           Ask both: the two answers are in; the combined one is next
  out  {"event": "delta", "text": "…"}  the answer so far (Claude only)
  out  {"event": "answer", "text", "provider", "model", "effort", "seconds", "stopped": false}
  out  {"event": "error", "message", "unavailable": true}   unavailable: no connection, no login, limits
  out  {"event": "history", "chats": [{"id", "title", "time": "2026-11-13T11:05:00"}]}
  out  {"event": "loaded", "id", "messages": [{"role": "user"|"assistant", "text", "provider"}]}

It exits when stdin closes, so it never outlives the shell. QUICK_CHAT_HOME (tests) replaces the home
folder the chats are saved under.
"""

import datetime as dt
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

INSTRUCTIONS = (
    "You are the quick chat in the user's Linux desktop shell (Hyprland on Arch). Answer briefly and "
    "directly in Markdown: short paragraphs, fenced code blocks for commands and code, and a '> ' "
    "quote for a single important caution. No preamble, no follow-up offers. If the user attached "
    "context (selected text, the clipboard, a picture of a window or a screen region), use it."
)
TIMEOUT = 180  # seconds for one answer
DELTA_EVERY = 0.06  # the answer so far is sent at most this often


def unavailable(message):
    """No connection, no login, a limit or a missing model: told apart from a plain failure."""
    return bool(re.search(r"rate.?limit|usage.?limit|limit reached|quota|overloaded|unavailable|"
                          r"not.?found|does not exist|not supported|unsupported model|"
                          r"not logged|log.?in|authentication|unauthori[sz]ed|expired|"
                          r"connection|network|timed? ?out|timeout|ECONN|ENOTFOUND|"
                          r"service error|server error|\b(?:401|403|429|50[0234])\b", message, re.I))


class AgentError(Exception):
    def __init__(self, message, unavailable=False):
        super().__init__(message)
        self.unavailable = unavailable


class Chat:
    def __init__(self, home):
        self.home = home
        self.out = threading.Lock()
        self.lock = threading.Lock()
        self.processes = set()  # the requests running (two at once for Ask both)
        self.worker = None
        self.stopped = False
        self.reset()

    def reset(self):
        self.messages = []  # {"role", "text", "provider", "model", "effort", "context"}
        self.sessions = {}  # provider -> its session id
        self.active = ""  # the provider whose session holds the whole conversation
        self.folder = None
        self.pictures = 0

    def emit(self, message):
        with self.out:
            try:
                sys.stdout.write(json.dumps(message) + "\n")
                sys.stdout.flush()
            except (BrokenPipeError, ValueError):
                pass  # the shell is gone; stdin's end stops the helper next

    # ---- saving ------------------------------------------------------------------------------

    def base(self):
        folder = self.home / "quick-chats"
        folder.mkdir(mode=0o700, parents=True, exist_ok=True)
        return folder

    def start_folder(self, question):
        slug = re.sub(r"[^\w -]+", "", question, flags=re.U)
        slug = re.sub(r"[\s_]+", "-", slug).strip("- ")[:60] or "chat"
        name = dt.datetime.now().strftime("%Y-%m-%d %H-%M-%S") + " " + slug
        folder = self.base() / name
        suffix = 1
        while folder.exists():
            suffix += 1
            folder = self.base() / f"{name}-{suffix}"
        folder.mkdir(mode=0o700)
        self.folder = folder

    def keep_pictures(self, paths):
        """Copies of the attached pictures in the chat's folder (the originals may be temporary)."""
        kept = []
        for path in paths:
            source = Path(path)
            if not source.is_file():
                continue
            self.pictures += 1
            target = self.folder / f"picture-{self.pictures}{source.suffix.lower() or '.png'}"
            shutil.copyfile(source, target)
            kept.append(target)
        return kept

    def save(self):
        if not self.folder:
            return
        state = {"messages": self.messages, "sessions": self.sessions, "active": self.active}
        tmp = self.folder / ".chat.json.tmp"
        tmp.write_text(json.dumps(state, ensure_ascii=False, indent=1), encoding="utf-8")
        tmp.replace(self.folder / "chat.json")
        lines = ["# " + (self.messages[0]["text"].splitlines() or ["Quick chat"])[0], ""]
        for m in self.messages:
            if m["role"] == "user":
                context = m.get("context") or {}
                lines += ["## You", ""]
                if context.get("label"):
                    lines += [f"*With {context['label'][0].lower() + context['label'][1:]}*", ""]
                for picture in context.get("pictures", []):
                    lines += [f"![{Path(picture).name}]({Path(picture).name})", ""]
                lines += [m["text"], ""]
            else:
                lines += [f"## {'Claude' if m.get('provider') == 'claude' else 'ChatGPT'} · {m.get('model', '')}"
                          + (" · from both" if m.get("both") else "") + (" · stopped" if m.get("stopped") else ""), "", m["text"], ""]
                for source in m.get("sources", []):
                    lines += [f"### {'Claude' if source['provider'] == 'claude' else 'ChatGPT'} alone", "", source["text"], ""]
        tmp = self.folder / ".chat.md.tmp"
        tmp.write_text("\n".join(lines), encoding="utf-8")
        tmp.replace(self.folder / "chat.md")

    def history(self):
        chats = []
        for folder in self.base().iterdir():
            state = folder / "chat.json"
            if not state.is_file():
                continue
            try:
                messages = json.loads(state.read_text(encoding="utf-8")).get("messages", [])
                title = next((m["text"] for m in messages if m.get("role") == "user"), "")
            except (OSError, ValueError, TypeError, KeyError):
                continue
            stamp = dt.datetime.fromtimestamp(state.stat().st_mtime)
            chats.append({"id": folder.name, "title": " ".join(title.split())[:120] or folder.name,
                          "time": stamp.isoformat(timespec="seconds")})
        chats.sort(key=lambda c: c["time"], reverse=True)
        self.emit({"event": "history", "chats": chats[:200]})

    def open(self, chat_id):
        folder = self.base() / chat_id
        if "/" in chat_id or chat_id in ("", ".", "..") or not (folder / "chat.json").is_file():
            self.emit({"event": "error", "message": "That chat isn't there anymore.", "unavailable": False})
            return
        try:
            state = json.loads((folder / "chat.json").read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            self.emit({"event": "error", "message": f"Couldn't read that chat: {error}", "unavailable": False})
            return
        self.reset()
        self.folder = folder
        self.messages = [m for m in state.get("messages", []) if isinstance(m, dict) and m.get("role") in ("user", "assistant")]
        self.sessions = {k: v for k, v in (state.get("sessions") or {}).items() if k in ("claude", "codex") and isinstance(v, str)}
        self.active = state.get("active", "") if state.get("active") in self.sessions else ""
        self.pictures = len(list(folder.glob("picture-*")))
        self.emit({"event": "loaded", "id": chat_id, "messages": [
            {"role": m["role"], "text": m.get("text", ""), "provider": m.get("provider", ""), "both": bool(m.get("both")),
             "context": (m.get("context") or {}).get("label", "")} for m in self.messages]})

    # ---- asking ------------------------------------------------------------------------------

    def command(self, provider, model, effort, prompt, pictures, session):
        if provider == "claude":
            args = ["claude", "-p", prompt, "--safe-mode", "--model", model, "--effort", effort,
                    "--output-format", "stream-json", "--include-partial-messages", "--verbose",
                    "--permission-mode", "dontAsk", "--system-prompt", INSTRUCTIONS]
            # only the pictures to read, and only then (with no picture, no tool at all)
            args += ["--tools", "Read", "--allowedTools", "Read", "--add-dir", str(self.folder)] if pictures else ["--tools", ""]
            return args + (["--resume", session] if session else [])
        args = ["codex", "-a", "never", "-s", "read-only", "exec"]
        if session:
            args += ["resume", session]
        args += ["--ignore-user-config", "--skip-git-repo-check", "--json", "--model", model,
                 "-c", f'model_reasoning_effort="{effort}"',
                 "-c", "features.shell_tool=false", "-c", "features.hooks=false",
                 "-c", "features.plugins=false", "-c", "features.multi_agent=false",
                 "-c", "features.memories=false", "-c", "apps._default.enabled=false",
                 "-c", "web_search=\"disabled\"", "-c", "project_doc_max_bytes=0"]
        for picture in pictures:
            args += ["--image", str(picture)]
        return args + ["--", prompt]

    def prompt_for(self, provider, question, context, pictures, continuing):
        parts = []
        if not continuing:
            if provider == "codex":
                parts.append(INSTRUCTIONS)
            earlier = [m for m in self.messages[:-1]]
            if earlier:
                parts.append("Conversation so far:\n\n" + "\n\n".join(
                    f'{"User" if m["role"] == "user" else "Assistant"}: {m["text"]}' for m in earlier))
        if context.get("text"):
            parts.append(f"{context.get('label') or 'Context'}:\n```\n{context['text']}\n```")
        if pictures:
            if provider == "claude":
                parts.append("Attached pictures (read them):\n" + "\n".join(str(p) for p in pictures))
            else:
                parts.append(f"{len(pictures)} picture(s) attached: {context.get('label') or 'context'}.")
        parts.append(question)
        return "\n\n".join(parts)

    def run(self, provider, command, started, quiet=False):
        """Runs one request; the answer's text and the session it belongs to. quiet: no "delta" events
        (Ask both's sources, which run side by side)."""
        with self.lock:
            if self.stopped:
                return "", None
            try:
                # stdin closed for the agent: Codex also reads piped stdin and would wait for its end
                process = subprocess.Popen(command, cwd=str(self.folder), stdin=subprocess.DEVNULL,
                                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                           start_new_session=True)
            except FileNotFoundError:
                raise AgentError(f"{'Claude Code' if provider == 'claude' else 'Codex'} isn't installed or isn't on the shell's PATH.", True)
            self.processes.add(process)
        timer = threading.Timer(TIMEOUT, lambda: self.kill(process))
        timer.start()
        errors = []
        reading_errors = threading.Thread(target=lambda: errors.append(process.stderr.read()), daemon=True)
        reading_errors.start()
        text, session, problem, last = "", None, "", 0.0
        try:
            for line in process.stdout:
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                kind = event.get("type")
                if provider == "claude":
                    if kind == "system" and event.get("session_id"):
                        session = event["session_id"]
                    elif kind == "stream_event":
                        delta = (event.get("event") or {}).get("delta") or {}
                        if delta.get("type") == "text_delta":
                            text += delta.get("text", "")
                            if not quiet and time.monotonic() - last >= DELTA_EVERY:
                                last = time.monotonic()
                                self.emit({"event": "delta", "text": text})
                    elif kind == "result":
                        session = event.get("session_id") or session
                        if event.get("is_error"):
                            problem = str(event.get("result") or event.get("errors") or "Claude couldn't answer.")
                        elif event.get("result"):
                            text = event["result"]
                else:
                    if kind == "thread.started":
                        session = event.get("thread_id")
                    elif kind == "item.completed" and (event.get("item") or {}).get("type") == "agent_message":
                        text = event["item"].get("text", "")
                    elif kind in ("error", "turn.failed"):
                        problem = str(event.get("message") or (event.get("error") or {}).get("message") or "Codex couldn't answer.")
            process.wait()
        finally:
            timer.cancel()
            reading_errors.join(1)
            with self.lock:
                self.processes.discard(process)
        if self.stopped:
            return text, session
        if time.monotonic() - started >= TIMEOUT:
            raise AgentError(f"No answer within {TIMEOUT} seconds.", True)
        if process.returncode or problem or not text.strip():
            detail = problem or "".join(errors).strip()[-1200:] or "The answer came back empty."
            raise AgentError(detail, unavailable(detail))
        return text, session

    def kill(self, process):
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass

    def answer(self, request):
        provider = request.get("provider") if request.get("provider") in ("claude", "codex") else "claude"
        model, effort = str(request.get("model") or ""), str(request.get("effort") or "")
        question = str(request.get("question") or "").strip()
        context = request.get("context") if isinstance(request.get("context"), dict) else {}
        started = time.monotonic()
        try:
            if not self.folder:
                self.start_folder(question)
            # a retry's pictures are already the chat's own copies
            pictures = [self.folder / name for name in context.get("kept", []) if (self.folder / name).is_file()]
            pictures += self.keep_pictures([p for p in context.get("images") or [] if isinstance(p, str)])
            saved_context = {k: v for k, v in {"label": context.get("label"), "text": context.get("text"),
                                               "pictures": [p.name for p in pictures]}.items() if v}
            self.messages.append({"role": "user", "text": question, "context": saved_context})
            self.save()
            plain = {k: v for k, v in context.items() if k not in ("images", "kept")}
            if isinstance(request.get("both"), dict):
                self.emit({"event": "started", "chat": self.folder.name, "provider": provider, "model": model, "effort": effort})
                self.both(provider, model, effort, request["both"], question, plain, pictures, started)
                return
            continuing = self.active == provider and provider in self.sessions
            prompt = self.prompt_for(provider, question, plain, pictures, continuing)
            self.emit({"event": "started", "chat": self.folder.name, "provider": provider, "model": model, "effort": effort})
            command = self.command(provider, model, effort, prompt, pictures, self.sessions.get(provider) if continuing else None)
            try:
                text, session = self.run(provider, command, started)
            except AgentError:
                if not continuing or self.stopped:
                    raise
                # a session that's gone (cleared, expired): once more, with the conversation replayed
                self.sessions.pop(provider, None)
                prompt = self.prompt_for(provider, question, plain, pictures, False)
                text, session = self.run(provider, self.command(provider, model, effort, prompt, pictures, None), started)
        except AgentError as error:
            if self.stopped:
                self.finish_stopped(provider, model, effort, "", started)
                return
            self.messages.pop()
            if not self.messages and self.folder:
                shutil.rmtree(self.folder, ignore_errors=True)  # nothing was said: no empty chat kept
                self.folder = None
            else:
                self.save()
            self.emit({"event": "error", "message": str(error), "unavailable": error.unavailable, "question": question})
            return
        except OSError as error:
            self.emit({"event": "error", "message": f"Couldn't save the chat: {error}", "unavailable": False, "question": question})
            return
        if self.stopped:
            self.finish_stopped(provider, model, effort, text, started, session)
            return
        if session:
            self.sessions[provider] = session
            self.active = provider
        self.messages.append({"role": "assistant", "text": text, "provider": provider, "model": model, "effort": effort})
        self.save()
        self.emit({"event": "answer", "text": text, "provider": provider, "model": model, "effort": effort,
                   "seconds": round(time.monotonic() - started, 1), "stopped": False})

    def both(self, provider, model, effort, other_config, question, context, pictures, started):
        """Ask both: each provider answers the same question with the same conversation, side by side;
        then the preferred one writes the answer from the two (as it's written, for Claude)."""
        other = "codex" if provider == "claude" else "claude"
        configs = {provider: (model, effort), other: (str(other_config.get("model") or ""), str(other_config.get("effort") or ""))}
        replies, failures = {}, {}

        def source(name):
            prompt = self.prompt_for(name, question, context, pictures, False)
            try:
                # sources run on their own: no session is resumed into, or kept from, them
                replies[name] = self.run(name, self.command(name, *configs[name], prompt, pictures, None), started, quiet=True)[0]
            except AgentError as error:
                failures[name] = error

        threads = [threading.Thread(target=source, args=(name,), daemon=True) for name in (provider, other)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        if self.stopped:
            self.finish_stopped(provider, model, effort, "", started)
            return
        if not replies:
            error = failures[provider]
            self.messages.pop()
            self.save()
            self.emit({"event": "error", "message": str(error), "unavailable": error.unavailable, "question": question})
            return
        self.emit({"event": "combining"})
        name = lambda p: "Claude" if p == "claude" else "ChatGPT"
        sources = "\n\n".join(f"Answer from {name(p)}:\n{replies[p]}" for p in (provider, other) if p in replies)
        missing = "".join(f"\n\n({name(p)} couldn't answer: {failures[p]})" for p in failures)
        prompt = self.prompt_for(provider, question, context, [], False) + (
            "\n\nTwo assistants answered this question independently. Write ONE answer for the user: keep "
            "what is right in either, settle any disagreement, and say plainly if they differ on something "
            "that matters. Don't mention the two answers unless they disagree.\n\n" + sources + missing)
        try:
            text, _ = self.run(provider, self.command(provider, model, effort, prompt, [], None), started)
        except AgentError as error:
            if self.stopped:
                self.finish_stopped(provider, model, effort, "", started)
                return
            self.messages.pop()
            self.save()
            self.emit({"event": "error", "message": str(error), "unavailable": error.unavailable, "question": question})
            return
        if self.stopped:
            self.finish_stopped(provider, model, effort, text, started)
            return
        # no provider's session holds this turn: the next question replays the conversation
        self.sessions.clear()
        self.active = ""
        self.messages.append({"role": "assistant", "text": text, "provider": provider, "model": model, "effort": effort,
                              "both": True, "sources": [{"provider": p, "text": replies[p]} for p in replies]})
        self.save()
        self.emit({"event": "answer", "text": text, "provider": provider, "model": model, "effort": effort, "both": True,
                   "seconds": round(time.monotonic() - started, 1), "stopped": False})

    def finish_stopped(self, provider, model, effort, text, started, session=None):
        """Stopped by the owner: what was written so far stays, marked; the session isn't trusted."""
        self.sessions.pop(provider, None)
        if self.active == provider:
            self.active = ""
        if text.strip():
            self.messages.append({"role": "assistant", "text": text, "provider": provider, "model": model,
                                  "effort": effort, "stopped": True})
        self.save()
        self.emit({"event": "answer", "text": text, "provider": provider, "model": model, "effort": effort,
                   "seconds": round(time.monotonic() - started, 1), "stopped": True})

    def retry(self, request):
        """The last question once more: its answer (if any) goes, and no session remembers it."""
        last = max((i for i, m in enumerate(self.messages) if m["role"] == "user"), default=-1)
        if last < 0:
            return
        asked = self.messages[last]
        del self.messages[last:]
        self.sessions.clear()
        self.active = ""
        context = dict(asked.get("context") or {})
        context["kept"] = context.pop("pictures", [])
        self.ask(dict(request, question=asked["text"], context=context))

    def ask(self, request):
        if self.worker and self.worker.is_alive():
            return
        self.stopped = False
        self.worker = threading.Thread(target=self.answer, args=(request,), daemon=True)
        self.worker.start()

    def stop(self):
        with self.lock:
            self.stopped = True
            for process in self.processes:
                self.kill(process)

    def wait(self):
        if self.worker:
            self.worker.join()

    def handle(self, message):
        cmd = message.get("cmd")
        if cmd == "ask":
            self.ask(message)
        elif cmd == "retry":
            if not (self.worker and self.worker.is_alive()):
                self.retry(message)
        elif cmd == "stop":
            self.stop()
        elif cmd in ("new", "open"):
            self.stop()
            self.wait()
            if cmd == "new":
                self.reset()
            else:
                self.open(str(message.get("id") or ""))
        elif cmd == "history":
            self.history()


def main():
    home = Path(os.environ.get("QUICK_CHAT_HOME") or Path.home())
    chat = Chat(home)
    chat.emit({"event": "ready"})
    for line in sys.stdin:
        try:
            message = json.loads(line)
        except ValueError:
            print("bad command", file=sys.stderr, flush=True)
            continue
        if isinstance(message, dict):
            chat.handle(message)
    chat.stop()
    os._exit(0)


if __name__ == "__main__":
    main()
