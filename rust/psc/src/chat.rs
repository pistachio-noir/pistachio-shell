//! Quick chat's JSON-lines helper, used by Chat.qml.
use crate::agent::{self, emit, list, string, AgentError, Worker};
use serde_json::{json, Map, Value};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    mpsc,
};
use std::time::{Duration, Instant};

const INSTRUCTIONS: &str = concat!(
    "You are the quick chat in the user's Linux desktop shell (Hyprland on Arch). Answer briefly and ",
    "directly in Markdown: short paragraphs, fenced code blocks for commands and code, and a '> ' ",
    "quote for a single important caution. No preamble, no follow-up offers. If the user attached ",
    "context (selected text, the clipboard, a picture of a window or a screen region), use it."
);

#[derive(Default)]
struct Chat {
    messages: Vec<Value>,
    sessions: Map<String, Value>,
    active: String,
    folder: Option<PathBuf>,
    pictures: usize,
}

fn name(provider: &str) -> &'static str {
    if provider == "claude" {
        "Claude"
    } else {
        "ChatGPT"
    }
}

fn first_text<'a>(values: impl IntoIterator<Item = &'a Value>) -> Option<&'a str> {
    values
        .into_iter()
        .find_map(|value| value.as_str().filter(|text| !text.is_empty()))
}

fn error(message: impl Into<String>, unavailable: bool) -> Value {
    json!({"event": "error", "message": message.into(), "unavailable": unavailable})
}

fn failed(error: AgentError, question: &str) -> Value {
    json!({"event": "error", "message": error.message, "unavailable": error.unavailable, "question": question})
}

struct Question<'a> {
    text: &'a str,
    context: &'a Value,
    pictures: Vec<PathBuf>,
}

struct Provider<'a> {
    id: &'a str,
    model: &'a str,
    effort: &'a str,
}

impl<'a> Provider<'a> {
    fn new(id: &'a str, config: &'a Value) -> Self {
        Self {
            id,
            model: string(&config["model"]),
            effort: string(&config["effort"]),
        }
    }

    fn message(&self, text: &str) -> Value {
        json!({"role": "assistant", "text": text, "provider": self.id, "model": self.model, "effort": self.effort})
    }

    fn answer(&self, text: &str, started: Instant, stopped: bool) -> Value {
        json!({"event": "answer", "text": text, "provider": self.id, "model": self.model, "effort": self.effort,
            "seconds": (started.elapsed().as_secs_f64() * 10.0).round() / 10.0, "stopped": stopped})
    }
}

impl Chat {
    fn attach(&mut self, context: &Value) -> io::Result<Vec<PathBuf>> {
        let folder = self.folder.as_ref().unwrap();
        let mut pictures: Vec<_> = list(&context["kept"])
            .iter()
            .filter_map(Value::as_str)
            .filter(|name| {
                Path::new(name)
                    .file_name()
                    .is_some_and(|file| file == *name)
            })
            .map(|name| folder.join(name))
            .filter(|path| path.is_file())
            .collect();
        for source in list(&context["images"])
            .iter()
            .filter_map(Value::as_str)
            .map(Path::new)
        {
            if !source.is_file() {
                continue;
            }
            self.pictures += 1;
            let extension = source
                .extension()
                .and_then(|ext| ext.to_str())
                .filter(|ext| !ext.is_empty())
                .unwrap_or("png");
            let target = folder.join(format!(
                "picture-{}.{}",
                self.pictures,
                extension.to_lowercase()
            ));
            fs::copy(source, &target)?;
            pictures.push(target);
        }
        Ok(pictures)
    }

    fn save(&self) -> io::Result<()> {
        let Some(folder) = &self.folder else {
            return Ok(());
        };
        let state =
            json!({"messages": self.messages, "sessions": self.sessions, "active": self.active});
        let pretty = serde_json::to_string_pretty(&state)?;
        let text = pretty
            .lines()
            .map(|line| {
                let indent = line.len() - line.trim_start_matches(' ').len();
                &line[indent / 2..]
            })
            .collect::<Vec<_>>()
            .join("\n");
        agent::replace(&folder.join("chat.json"), ".chat.json.tmp", &text)?;

        let title = self
            .messages
            .first()
            .and_then(|message| agent::split_lines(string(&message["text"]), false).next())
            .unwrap_or("Quick chat");
        let mut lines = vec![format!("# {title}"), String::new()];
        for message in &self.messages {
            if message["role"] == "user" {
                lines.extend(["## You".into(), String::new()]);
                let context = &message["context"];
                if let Some(label) = context["label"].as_str().filter(|text| !text.is_empty()) {
                    let mut chars = label.chars();
                    lines.extend([
                        format!(
                            "*With {}{}*",
                            chars.next().unwrap().to_lowercase(),
                            chars.as_str()
                        ),
                        String::new(),
                    ]);
                }
                for picture in list(&context["pictures"]).iter().filter_map(Value::as_str) {
                    let picture = Path::new(picture)
                        .file_name()
                        .unwrap_or_default()
                        .to_string_lossy();
                    lines.extend([format!("![{picture}]({picture})"), String::new()]);
                }
            } else {
                let both = if message["both"] == true {
                    " · from both"
                } else {
                    ""
                };
                let stopped = if message["stopped"] == true {
                    " · stopped"
                } else {
                    ""
                };
                lines.extend([
                    format!(
                        "## {} · {}{both}{stopped}",
                        name(string(&message["provider"])),
                        string(&message["model"])
                    ),
                    String::new(),
                ]);
            }
            lines.extend([string(&message["text"]).into(), String::new()]);
            for source in list(&message["sources"]) {
                lines.extend([
                    format!("### {} alone", name(string(&source["provider"]))),
                    String::new(),
                    string(&source["text"]).into(),
                    String::new(),
                ]);
            }
        }
        agent::replace(&folder.join("chat.md"), ".chat.md.tmp", &lines.join("\n"))
    }

    fn history(base: &Path) -> io::Result<Value> {
        agent::private_dir(base, true)?;
        let mut chats: Vec<_> = fs::read_dir(base)?.flatten().filter_map(|folder| {
            let path = folder.path().join("chat.json");
            let state: Value = serde_json::from_str(&fs::read_to_string(&path).ok()?).ok()?;
            let title = list(&state["messages"]).iter().find(|message| message["role"] == "user")
                .map(|message| string(&message["text"])).unwrap_or_default();
            let title: String = title.split_whitespace().collect::<Vec<_>>().join(" ").chars().take(120).collect();
            let id = folder.file_name();
            let id = id.to_string_lossy();
            let time = agent::local_stamp(fs::metadata(path).ok()?.modified().ok()?, "%Y-%m-%dT%H:%M:%S");
            Some(json!({"id": id, "title": if title.is_empty() { &*id } else { &title }, "time": time}))
        }).collect();
        chats.sort_by(|a, b| string(&b["time"]).cmp(string(&a["time"])));
        chats.truncate(200);
        Ok(json!({"event": "history", "chats": chats}))
    }

    fn open(&mut self, base: &Path, id: &str) -> Value {
        let folder = base.join(id);
        let path = folder.join("chat.json");
        if id.contains('/') || matches!(id, "" | "." | "..") || !path.is_file() {
            return error("That chat isn't there anymore.", false);
        }
        let state: Value =
            match fs::read_to_string(&path).and_then(|data| Ok(serde_json::from_str(&data)?)) {
                Ok(state) => state,
                Err(err) => return error(format!("Couldn't read that chat: {err}"), false),
            };
        let messages = list(&state["messages"])
            .iter()
            .filter(|m| matches!(m["role"].as_str(), Some("user" | "assistant")))
            .cloned()
            .collect();
        let sessions: Map<_, _> = state["sessions"]
            .as_object()
            .into_iter()
            .flatten()
            .filter(|(key, value)| matches!(key.as_str(), "claude" | "codex") && value.is_string())
            .map(|(key, value)| (key.clone(), value.clone()))
            .collect();
        let active = string(&state["active"]);
        let active = if sessions.contains_key(active) {
            active.into()
        } else {
            String::new()
        };
        let pictures = fs::read_dir(&folder)
            .into_iter()
            .flatten()
            .flatten()
            .filter_map(|entry| {
                let name = entry.file_name();
                let suffix = name.to_str()?.strip_prefix("picture-")?;
                suffix.split('.').next()?.parse::<usize>().ok()
            })
            .max()
            .unwrap_or(0);
        *self = Self {
            messages,
            sessions,
            active,
            folder: Some(folder),
            pictures,
        };
        let messages: Vec<_> = self.messages.iter().map(|message| json!({
            "role": message["role"], "text": string(&message["text"]), "provider": string(&message["provider"]),
            "both": message["both"] == true, "context": string(&message["context"]["label"]),
        })).collect();
        json!({"event": "loaded", "id": id, "messages": messages})
    }

    fn prompt(
        &self,
        provider: &str,
        question: &Question<'_>,
        continuing: bool,
        pictures: &[PathBuf],
    ) -> String {
        let mut parts = Vec::new();
        if !continuing {
            if provider == "codex" {
                parts.push(INSTRUCTIONS.to_owned());
            }
            let earlier = &self.messages[..self.messages.len() - 1];
            if !earlier.is_empty() {
                let transcript = earlier
                    .iter()
                    .map(|message| {
                        format!(
                            "{}: {}",
                            if message["role"] == "user" {
                                "User"
                            } else {
                                "Assistant"
                            },
                            string(&message["text"])
                        )
                    })
                    .collect::<Vec<_>>()
                    .join("\n\n");
                parts.push(format!("Conversation so far:\n\n{transcript}"));
            }
        }
        let label = question.context["label"]
            .as_str()
            .filter(|label| !label.is_empty());
        let context = string(&question.context["text"]);
        if !context.is_empty() {
            parts.push(format!(
                "{}:\n```\n{context}\n```",
                label.unwrap_or("Context")
            ));
        }
        if !pictures.is_empty() {
            if provider == "claude" {
                let paths = pictures
                    .iter()
                    .map(|path| path.to_string_lossy())
                    .collect::<Vec<_>>()
                    .join("\n");
                parts.push(format!("Attached pictures (read them):\n{paths}"));
            } else {
                parts.push(format!(
                    "{} picture(s) attached: {}.",
                    pictures.len(),
                    label.unwrap_or("context")
                ));
            }
        }
        parts.push(question.text.to_owned());
        parts.join("\n\n")
    }

    fn invoke(
        &self,
        provider: &Provider<'_>,
        prompt: &str,
        pictures: &[PathBuf],
        session: Option<&str>,
        started: Instant,
        stop: &AtomicBool,
        quiet: bool,
    ) -> Result<(String, Option<String>), AgentError> {
        let folder = self.folder.as_ref().unwrap();
        let claude = provider.id == "claude";
        let command = if claude {
            let mut command = Command::new("claude");
            command.args([
                "-p",
                prompt,
                "--safe-mode",
                "--model",
                provider.model,
                "--effort",
                provider.effort,
                "--output-format",
                "stream-json",
                "--include-partial-messages",
                "--verbose",
                "--permission-mode",
                "dontAsk",
                "--system-prompt",
                INSTRUCTIONS,
            ]);
            if pictures.is_empty() {
                command.args(["--tools", ""]);
            } else {
                command
                    .args(["--tools", "Read", "--allowedTools", "Read", "--add-dir"])
                    .arg(folder);
            }
            if let Some(session) = session {
                command.args(["--resume", session]);
            }
            command
        } else {
            let mut command = agent::codex(provider.model, provider.effort, session, None);
            for picture in pictures {
                command.arg("--image").arg(picture);
            }
            command.args(["--", prompt]);
            command
        };
        let mut text = String::new();
        let mut session = None;
        let mut problem = String::new();
        let mut last = None::<Instant>;
        let output = agent::run(command, folder, stop, false, |line| {
            let Ok(event) = serde_json::from_str::<Value>(line) else {
                return;
            };
            match (claude, string(&event["type"])) {
                (true, "system" | "result") => {
                    if let Some(id) = first_text([&event["session_id"]]) {
                        session = Some(id.to_owned());
                    }
                    if event["type"] == "result" {
                        if event["is_error"] == true {
                            problem = first_text([&event["result"], &event["errors"]])
                                .map(str::to_owned)
                                .or_else(|| {
                                    event["errors"]
                                        .as_array()
                                        .filter(|errors| !errors.is_empty())
                                        .map(|errors| format!("{errors:?}"))
                                })
                                .unwrap_or_else(|| "Claude couldn't answer.".into());
                        } else if let Some(answer) = first_text([&event["result"]]) {
                            text = answer.into();
                        }
                    }
                }
                (true, "stream_event") if event["event"]["delta"]["type"] == "text_delta" => {
                    text.push_str(string(&event["event"]["delta"]["text"]));
                    let now = Instant::now();
                    if !quiet && last.is_none_or(|last| now - last >= Duration::from_millis(60)) {
                        last = Some(now);
                        emit(json!({"event": "delta", "text": text}));
                    }
                }
                (false, "thread.started") => {
                    session = event["thread_id"].as_str().map(str::to_owned)
                }
                (false, "item.completed") if event["item"]["type"] == "agent_message" => {
                    text = string(&event["item"]["text"]).into()
                }
                (false, "error" | "turn.failed") => {
                    problem = first_text([&event["message"], &event["error"]["message"]])
                        .unwrap_or("Codex couldn't answer.")
                        .into();
                }
                _ => {}
            }
        })
        .map_err(|err| {
            if err.kind() == io::ErrorKind::NotFound {
                AgentError::new(
                    format!(
                        "{} isn't installed or isn't on the shell's PATH.",
                        if claude { "Claude Code" } else { "Codex" }
                    ),
                    true,
                )
            } else {
                AgentError::new(err.to_string(), false)
            }
        })?;
        if stop.load(Ordering::Relaxed) {
            return Ok((text, session));
        }
        let Some(output) = output else {
            return Ok((text, session));
        };
        if output.timed_out || started.elapsed() >= agent::TIMEOUT {
            return Err(AgentError::new("No answer within 180 seconds.", true));
        }
        if !output.status.success() || !problem.is_empty() || text.trim().is_empty() {
            return Err(AgentError::from_response(
                problem,
                &output.stderr,
                "The answer came back empty.",
            ));
        }
        Ok((text, session))
    }

    fn stop_answer(
        &mut self,
        provider: &Provider<'_>,
        text: &str,
        started: Instant,
    ) -> io::Result<Value> {
        self.sessions.shift_remove(provider.id);
        if self.active == provider.id {
            self.active.clear();
        }
        if !text.trim().is_empty() {
            let mut message = provider.message(text);
            message["stopped"] = json!(true);
            self.messages.push(message);
        }
        self.save()?;
        Ok(provider.answer(text, started, true))
    }

    fn reject(&mut self, question: &Question<'_>, error: AgentError) -> io::Result<Value> {
        self.messages.pop();
        if self.messages.is_empty() {
            if let Some(folder) = self.folder.take() {
                let _ = fs::remove_dir_all(folder);
            }
        } else {
            self.save()?;
        }
        Ok(failed(error, question.text))
    }

    fn both(
        &mut self,
        provider: &Provider<'_>,
        other: &Provider<'_>,
        question: &Question<'_>,
        started: Instant,
        stop: &AtomicBool,
    ) -> io::Result<Value> {
        let (send, receive) = mpsc::channel();
        let picture_paths = &question.pictures;
        std::thread::scope(|scope| {
            let chat = &*self;
            for agent in [provider, other] {
                let send = send.clone();
                scope.spawn(move || {
                    let prompt = chat.prompt(agent.id, question, false, picture_paths);
                    let result =
                        chat.invoke(agent, &prompt, picture_paths, None, started, stop, true);
                    let _ = send.send((agent.id, result));
                });
            }
        });
        let mut replies = Vec::new();
        let mut failures = Vec::new();
        for (id, result) in receive.try_iter() {
            match result {
                Ok((text, _)) => replies.push((id, text)),
                Err(error) => failures.push((id, error)),
            }
        }
        if stop.load(Ordering::Relaxed) {
            return self.stop_answer(provider, "", started);
        }
        if replies.is_empty() {
            let (_, error) = failures
                .into_iter()
                .find(|(id, _)| *id == provider.id)
                .unwrap();
            return self.reject(question, error);
        }
        emit(json!({"event": "combining"}));
        let sources = [provider.id, other.id]
            .into_iter()
            .filter_map(|id| {
                let (_, text) = replies.iter().find(|(provider, _)| *provider == id)?;
                Some(format!("Answer from {}:\n{text}", name(id)))
            })
            .collect::<Vec<_>>()
            .join("\n\n");
        let missing: String = failures
            .iter()
            .map(|(id, error)| format!("\n\n({} couldn't answer: {})", name(id), error.message))
            .collect();
        let prompt = format!(concat!(
            "{}\n\nTwo assistants answered this question independently. Write ONE answer for the user: keep ",
            "what is right in either, settle any disagreement, and say plainly if they differ on something ",
            "that matters. Don't mention the two answers unless they disagree.\n\n{sources}{missing}"
        ), self.prompt(provider.id, question, false, &[]), sources = sources, missing = missing);
        let result = self.invoke(provider, &prompt, &[], None, started, stop, false);
        if stop.load(Ordering::Relaxed) {
            return self.stop_answer(
                provider,
                &result.map(|(text, _)| text).unwrap_or_default(),
                started,
            );
        }
        match result {
            Ok((text, _)) => {
                self.sessions.clear();
                self.active.clear();
                let mut message = provider.message(&text);
                message["both"] = json!(true);
                message["sources"] = json!(replies
                    .iter()
                    .map(|(id, text)| json!({"provider": id, "text": text}))
                    .collect::<Vec<_>>());
                self.messages.push(message);
                self.save()?;
                let mut event = provider.answer(&text, started, false);
                event["both"] = json!(true);
                Ok(event)
            }
            Err(error) => self.reject(question, error),
        }
    }

    fn ask(&mut self, base: &Path, request: &Value, stop: &AtomicBool) -> io::Result<Value> {
        let started = Instant::now();
        let provider = Provider::new(
            if request["provider"] == "codex" {
                "codex"
            } else {
                "claude"
            },
            request,
        );
        let text = string(&request["question"]).trim();
        let context = &request["context"];
        if self.folder.is_none() {
            self.folder = Some(agent::archive(base, text, "chat")?);
        }
        let question = Question {
            text,
            context,
            pictures: self.attach(context)?,
        };
        let mut saved = Map::new();
        for key in ["label", "text"] {
            if let Some(value) = context[key].as_str().filter(|value| !value.is_empty()) {
                saved.insert(key.into(), json!(value));
            }
        }
        if !question.pictures.is_empty() {
            saved.insert(
                "pictures".into(),
                json!(question
                    .pictures
                    .iter()
                    .map(|path| path.file_name().unwrap_or_default().to_string_lossy())
                    .collect::<Vec<_>>()),
            );
        }
        self.messages
            .push(json!({"role": "user", "text": text, "context": saved}));
        self.save()?;
        let folder = self.folder.as_ref().unwrap();
        emit(
            json!({"event": "started", "chat": folder.file_name().unwrap_or_default().to_string_lossy(),
            "provider": provider.id, "model": provider.model, "effort": provider.effort}),
        );
        if request["both"].is_object() {
            let other = Provider::new(agent::alternate(provider.id), &request["both"]);
            return self.both(&provider, &other, &question, started, stop);
        }
        let session = self
            .sessions
            .get(provider.id)
            .and_then(Value::as_str)
            .filter(|_| self.active == provider.id);
        let prompt = self.prompt(
            provider.id,
            &question,
            session.is_some(),
            &question.pictures,
        );
        let mut result = self.invoke(
            &provider,
            &prompt,
            &question.pictures,
            session,
            started,
            stop,
            false,
        );
        if result.is_err() && session.is_some() && !stop.load(Ordering::Relaxed) {
            self.sessions.shift_remove(provider.id);
            let prompt = self.prompt(provider.id, &question, false, &question.pictures);
            result = self.invoke(
                &provider,
                &prompt,
                &question.pictures,
                None,
                started,
                stop,
                false,
            );
        }
        if stop.load(Ordering::Relaxed) {
            return self.stop_answer(
                &provider,
                &result.map(|(text, _)| text).unwrap_or_default(),
                started,
            );
        }
        match result {
            Ok((text, session)) => {
                if let Some(session) = session.filter(|session| !session.is_empty()) {
                    self.sessions.insert(provider.id.into(), json!(session));
                    self.active = provider.id.into();
                }
                self.messages.push(provider.message(&text));
                self.save()?;
                Ok(provider.answer(&text, started, false))
            }
            Err(error) => self.reject(&question, error),
        }
    }

    fn retry(&mut self, request: &mut Value) -> bool {
        let Some(index) = self
            .messages
            .iter()
            .rposition(|message| message["role"] == "user")
        else {
            return false;
        };
        let mut last = self.messages.split_off(index).swap_remove(0);
        self.sessions.clear();
        self.active.clear();
        request["question"] = last["text"].take();
        let context = &mut last["context"];
        if let Some(context) = context.as_object_mut() {
            if let Some(pictures) = context.shift_remove("pictures") {
                context.insert("kept".into(), pictures);
            }
        }
        request["context"] = context.take();
        true
    }
}

pub fn main() -> i32 {
    if let Err(error) = serve() {
        eprintln!("psc chat: {error}");
        return 1;
    }
    0
}

fn serve() -> io::Result<()> {
    let home = std::env::var_os("QUICK_CHAT_HOME")
        .filter(|home| !home.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(agent::home);
    let base = home.join("quick-chats");
    let mut worker = Worker::new(Chat::default());
    let input = agent::input()?;
    emit(json!({"event": "ready"}));
    for line in input {
        if line.is_empty() {
            break;
        }
        let mut request = match serde_json::from_str::<Value>(&line) {
            Ok(request) => request,
            Err(_) => {
                eprintln!("bad command");
                continue;
            }
        };
        match string(&request["cmd"]) {
            "ask" | "retry" if worker.idle() => {
                if request["cmd"] == "retry" && !worker.state().retry(&mut request) {
                    continue;
                }
                let base = base.clone();
                worker.start(move |chat, stop| {
                    Some(chat.ask(&base, &request, stop).unwrap_or_else(|err| {
                        failed(
                            AgentError::new(format!("Couldn't save the chat: {err}"), false),
                            string(&request["question"]).trim(),
                        )
                    }))
                });
            }
            "stop" => worker.stop(),
            "new" | "open" => {
                worker.stop();
                worker.wait();
                if request["cmd"] == "new" {
                    *worker.state() = Chat::default();
                } else {
                    agent::private_dir(&base, true)?;
                    emit(worker.state().open(&base, string(&request["id"])));
                }
            }
            "history" => emit(Chat::history(&base)?),
            _ => {}
        }
    }
    Ok(())
}
