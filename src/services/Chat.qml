pragma Singleton

import qs
import Quickshell
import Quickshell.Io
import QtQuick

// The quick chat (owner's call, 13 November 2026; boards pistachio-shell-design/QuickChat*.html): short questions to
// Claude Code or Codex, the provider and model chosen in Settings → Lens (the same preferred provider,
// models and efforts). psc chat runs the requests and saves each chat in ~/quick-chats/;
// popups/QuickChat.qml draws it above the bar. The helper runs while the chat is open and for five
// minutes after it closes; opened again later, the same chat is loaded back from its folder.
//
// Context (the boards' "with context"): the text selected when the chat opens (the primary
// selection) is attached as a card, which ✕ removes; Include adds a picture of the window that had
// the focus (QuickChat.qml takes it) or the clipboard (its text, or its picture). All of it goes with
// the next question only. Snip a region hands over to Lens (owner's call, 13 November 2026): the chat
// closes, Lens's area selection starts, and what was typed becomes Lens's question.
Singleton {
    id: root

    property bool open
    property string view: "chat" // "chat" | "history"
    property var messages: [] // { role: "user" | "assistant", text, provider, context (a label), stopped }
    property string state: "idle" // "idle" | "writing" | "error"
    property bool combining // Ask both: the two answers are in, the combined one is being written
    property bool streamed // the last answer was written out on screen (it doesn't arrive again)
    property string partial // the answer so far, while Claude writes it
    property real started // ms, while writing
    property real seconds
    property var error: null // { message, unavailable, question }
    property string chatId // the saved chat being continued, for loading it back
    property var chats: [] // the history: { id, title, time }
    property string draft // the input's text, kept across closing and for Edit question

    // what goes with the next question
    property var selection: null // { label, text, lines, first }
    property bool withWindow
    property string windowPicture // QuickChat.qml's picture of the focused window, once taken
    property string windowApp // that window's app, for the labels
    property var windowSource: null // the window that had the focus as the chat opened (a Toplevel)
    property bool withClipboard
    property bool includeShown // the Include row (the paperclip, or context attached)

    // Who answers: Settings → Lens's preferred provider, or this chat's own choice from the header's
    // menu (Claude, ChatGPT or Ask both; until a new chat, Settings untouched). Ask both: each answers,
    // then the preferred one (or the chosen one) writes one answer from the two.
    property string choice // "" (Settings'), "claude", "codex", "both"
    readonly property string preferred: ShellSettings.lensProvider === "codex" ? "codex" : "claude"
    readonly property bool both: choice === "both"
    readonly property string provider: choice === "claude" || choice === "codex" ? choice : preferred
    readonly property string providerName: both ? "Claude + ChatGPT" : nameOf(provider)
    readonly property string model: modelOf(provider)
    readonly property string effort: effortOf(provider)

    function nameOf(p: string): string {
        return p === "codex" ? "ChatGPT" : "Claude";
    }
    function modelOf(p: string): string {
        return p === "codex" ? ShellSettings.lensCodexModel : ShellSettings.lensClaudeModel;
    }
    function effortOf(p: string): string {
        return p === "codex" ? ShellSettings.lensCodexEffort : ShellSettings.lensClaudeEffort;
    }
    // the request's provider part: Ask both names the other provider's model too
    function asking(): var {
        const other = provider === "codex" ? "claude" : "codex";
        return Object.assign({ provider: provider, model: model, effort: effort }, both ? { both: { model: modelOf(other), effort: effortOf(other) } } : {});
    }
    readonly property bool writing: state === "writing"
    readonly property bool hasContext: selection !== null || withWindow || withClipboard
    readonly property bool installed: provider === "codex" ? codexFound : claudeFound
    property bool claudeFound: true
    property bool codexFound: true

    signal focusInput // the input should take the keyboard (after Edit question, a chip, a reopen)
    signal lensRequested // for ScreenshotPicker: Lens's area selection, the chat's question handed over

    function show(question: string) {
        if (!open) {
            view = "chat";
            // the window being worked in, before the chat takes the keyboard
            windowSource = Compositor.focusedWindow;
            windowApp = Apps.nameFor(Compositor.focusedWindow?.appId ?? "");
            windowPicture = "";
            readSelection.running = true;
        }
        open = true;
        idle.stop();
        helper.running = true;
        if (question)
            send(question);
        else
            focusInput();
    }

    function toggle() {
        if (open)
            close();
        else
            show("");
    }

    function close() {
        open = false;
        idle.restart();
    }

    function command(m) {
        if (helper.running)
            helper.write(JSON.stringify(m) + "\n");
        else
            waiting = waiting.concat([m]);
    }
    property var waiting: [] // commands for the helper while it starts

    // the question, with what's included; the clipboard is read first if it's included
    function send(text: string) {
        const question = text.trim();
        if (!question || writing)
            return;
        if (withClipboard && !clipboardRead.running) {
            pendingQuestion = question;
            clipboardRead.running = true;
            return;
        }
        ask(question, null);
    }
    property string pendingQuestion
    property var lastContext: ({}) // what went with the last question, for Try again

    function ask(question: string, clipboard) {
        const images = [];
        if (withWindow && windowPicture)
            images.unshift(windowPicture);
        const texts = [], labels = [];
        if (selection) {
            texts.push(selection.text);
            labels.push(selection.label);
        }
        if (clipboard?.text) {
            texts.push(clipboard.text);
            labels.push("Clipboard");
        }
        if (clipboard?.image)
            images.push(clipboard.image);
        if (withWindow && windowPicture)
            labels.push(`A picture of ${windowApp || "the active window"}`);
        const context = { label: labels.join(", "), text: texts.join("\n\n"), images: images };
        lastContext = context;
        messages = messages.concat([{ role: "user", text: question, provider: provider, context: context.label }]);
        draft = "";
        error = null;
        partial = "";
        state = "writing";
        started = Date.now();
        seconds = 0;
        view = "chat";
        command(Object.assign({ cmd: "ask", question: question, context: context }, asking()));
        // context goes with one question only
        selection = null;
        withWindow = false;
        withClipboard = false;
        includeShown = false;
    }

    function stop() {
        if (writing)
            command({ cmd: "stop" });
    }

    // the last question once more, its answer replaced (the answer's ↻, or Try again after an error)
    function retry() {
        if (writing)
            return;
        if (state === "error" && error) {
            // the failed question stays on screen; it goes again, with what was attached to it
            const question = error.question;
            error = null;
            partial = "";
            state = "writing";
            started = Date.now();
            command(Object.assign({ cmd: "ask", question: question, context: lastContext }, asking()));
            return;
        }
        const last = messages.map(m => m.role).lastIndexOf("user");
        if (last < 0)
            return;
        messages = messages.slice(0, last + 1);
        partial = "";
        state = "writing";
        started = Date.now();
        command(Object.assign({ cmd: "retry" }, asking()));
    }

    // the failed question back in the input, to change it
    function editQuestion() {
        if (state !== "error" || !error)
            return;
        draft = error.question;
        messages = messages.slice(0, -1);
        error = null;
        state = "idle";
        focusInput();
    }

    function newChat() {
        command({ cmd: "new" });
        choice = "";
        messages = [];
        chatId = "";
        partial = "";
        error = null;
        state = "idle";
        view = "chat";
        draft = "";
        focusInput();
    }

    function showHistory() {
        if (view === "history") {
            view = "chat";
            focusInput();
            return;
        }
        chats = [];
        view = "history";
        command({ cmd: "history" });
    }

    function openChat(id: string) {
        if (writing)
            return;
        view = "chat";
        messages = [];
        error = null;
        state = "idle";
        command({ cmd: "open", id: id });
    }

    // a suggestion on the start screen: a question with what fits it attached
    function suggest(kind: string) {
        if (kind === "oneliner") {
            draft = "Write a shell one-liner that ";
            focusInput();
            return;
        }
        if (kind === "clipboard") {
            withClipboard = true;
            send("Summarise this.");
        } else if (kind === "error") {
            if (!selection)
                withClipboard = true;
            send("Explain this error and how to fix it.");
        } else if (kind === "translate") {
            if (!selection)
                withClipboard = true;
            send("Translate this to English.");
        }
    }

    // Snip a region: on to Lens, with what was typed as its question
    function snip() {
        Lens.handedQuestion = draft.trim();
        draft = "";
        close();
        snipAfterFade.restart(); // the picker's frozen screen mustn't show the chat
    }

    // The conversation continued in the provider's own app, as a new chat with the transcript in it:
    // Claude Desktop through its claude:// link, the ChatGPT app with chatgpt.com's ?q= (the app takes
    // https links). The apps take one prompt, so a long chat is cut from its start.
    function openExternally() {
        const said = messages.map(m => `${m.role === "user" ? "Me" : providerName}: ${m.text}`).join("\n\n");
        const prompt = messages.length > 1 ? `Let's continue this conversation from my desktop's quick chat:\n\n${said}` : (messages[0]?.text ?? draft);
        const text = prompt.length > 6000 ? "…" + prompt.slice(-6000) : prompt;
        if (provider === "codex")
            Quickshell.execDetached(["chatgpt", `https://chatgpt.com/?q=${encodeURIComponent(text)}`]);
        else
            Quickshell.execDetached(["xdg-open", `claude://claude.ai/new?surface=chat&q=${encodeURIComponent(text)}`]);
        close();
    }

    function copy(text: string) {
        Clipboard.copyText(text);
    }

    function openLink(link: string) {
        if (/^https?:\/\//i.test(link))
            Quickshell.execDetached(["xdg-open", link]);
    }

    function heard(m) {
        if (m.event === "ready") {
            if (chatId)
                helper.write(JSON.stringify({ cmd: "open", id: chatId }) + "\n");
            for (const w of waiting)
                helper.write(JSON.stringify(w) + "\n");
            waiting = [];
        } else if (m.event === "started") {
            chatId = m.chat;
        } else if (m.event === "combining") {
            combining = true;
        } else if (m.event === "delta") {
            partial = m.text;
        } else if (m.event === "answer") {
            streamed = partial !== "";
            partial = "";
            combining = false;
            seconds = m.seconds;
            if (m.text)
                messages = messages.concat([{ role: "assistant", text: m.text, provider: m.provider, context: "", stopped: m.stopped, both: !!m.both }]);
            state = "idle";
            if (open)
                focusInput();
        } else if (m.event === "error") {
            partial = "";
            combining = false;
            if (writing) {
                error = { message: m.message, unavailable: m.unavailable, question: m.question ?? messages[messages.length - 1]?.text ?? "" };
                state = "error";
            } else {
                console.warn("quick chat:", m.message);
            }
        } else if (m.event === "history") {
            chats = m.chats;
        } else if (m.event === "loaded") {
            chatId = m.id;
            messages = m.messages.map(x => ({ role: x.role, text: x.text, provider: x.provider, context: x.context ?? "" }));
            focusInput();
        }
    }

    // the helper: up while the chat is open, and for five minutes after
    Timer {
        id: idle
        interval: 5 * 60 * 1000
        onTriggered: if (!root.open && !root.writing) helper.running = false
    }

    Timer {
        id: snipAfterFade
        interval: Theme.motionDuration + 60
        onTriggered: root.lensRequested()
    }

    Timer {
        running: root.writing
        interval: 100
        repeat: true
        onTriggered: root.seconds = (Date.now() - root.started) / 1000
    }

    Process {
        id: helper
        command: [Quickshell.env("HOME") + "/.local/bin/psc", "chat"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.heard(JSON.parse(line));
                } catch (e) {
                    console.warn("quick chat:", line);
                }
            }
        }
        stderr: SplitParser {
            onRead: line => console.warn("quick chat:", line)
        }
        onExited: code => {
            if (root.writing) {
                root.error = { message: "The chat's helper stopped.", unavailable: false, question: root.messages[root.messages.length - 1]?.text ?? "" };
                root.state = "error";
            }
        }
    }

    // the selected text, as the chat opens: a card to ask about (the boards' "Selected text from kitty")
    Process {
        id: readSelection
        command: ["sh", "-c", "wl-paste --primary --no-newline --type text 2>/dev/null | head -c 20000"]
        stdout: StdioCollector {
            id: selectionText
            onStreamFinished: {
                const text = selectionText.text.replace(/\s+$/, "");
                if (!text.trim()) {
                    root.selection = null;
                    return;
                }
                const lines = text.split("\n");
                const app = Apps.nameFor(Compositor.focusedWindow?.appId ?? "") || root.windowApp;
                root.selection = {
                    label: app ? `Selected text from ${app}` : "Selected text",
                    text: text,
                    lines: lines.length,
                    first: lines.find(l => l.trim())?.trim() ?? ""
                };
                root.includeShown = true;
            }
        }
    }

    // the clipboard, when it's included: its text, or its picture saved to the runtime folder
    Process {
        id: clipboardRead
        command: ["sh", "-c", `
            types=$(wl-paste --list-types 2>/dev/null)
            if printf '%s\n' "$types" | grep -q '^image/png$'; then
                f="\${XDG_RUNTIME_DIR:-/tmp}/pistachio-chat-clip-$(date +%s%N).png"
                wl-paste --type image/png > "$f" && printf 'image\n%s' "$f"
            else
                printf 'text\n'; wl-paste --no-newline --type text 2>/dev/null | head -c 20000
            fi`]
        stdout: StdioCollector {
            id: clipboardText
            onStreamFinished: {
                const kind = clipboardText.text.split("\n")[0], rest = clipboardText.text.slice(kind.length + 1);
                const question = root.pendingQuestion;
                root.pendingQuestion = "";
                if (question)
                    root.ask(question, kind === "image" ? { image: rest } : { text: rest });
            }
        }
    }

    // whether the providers' CLIs are there, for the error a missing one gives
    Process {
        running: true
        command: ["sh", "-c", "command -v claude >/dev/null && echo claude; command -v codex >/dev/null && echo codex"]
        stdout: StdioCollector {
            id: found
            onStreamFinished: {
                root.claudeFound = found.text.includes("claude");
                root.codexFound = found.text.includes("codex");
            }
        }
    }

    // For a keybind: qs -c pistachio ipc call chat toggle; chat ask "a question"
    IpcHandler {
        target: "chat"

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            root.show("");
        }
        function close(): void {
            root.close();
        }
        function ask(text: string): void {
            root.show(text);
        }
        function status(): string {
            return JSON.stringify({ open: root.open, view: root.view, state: root.state, provider: root.provider, both: root.both, messages: root.messages.length, chat: root.chatId, context: root.hasContext });
        }
    }
}
