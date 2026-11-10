pragma Singleton

import qs
import Quickshell
import Quickshell.Io
import QtQuick

// Owner's call, 10 November 2026: Claude Code or Codex, with independent settings and fallback.
// The helper owns CLI sessions and disk access. UI reads this state and sends user actions here.
Singleton {
    id: root

    property bool open
    property string state: "prompt"
    property string path
    property rect area
    property var still: null // holds the ItemGrabResult, keeping its in-memory URL valid
    property string question
    property string answer
    property var lastAnswer: null
    property var actions: []
    property string provider: ShellSettings.lensProvider
    property string model
    property string problem
    property string notice
    property string folder
    property real seconds
    property real started
    property bool ready
    property bool beginning
    property bool stoppedRequest
    readonly property bool busy: state === "reading"
    readonly property string providerName: provider === "codex" ? "ChatGPT" : "Claude"

    function begin(file: string, rect: rect, capture: var) {
        release.stop();
        path = file;
        area = rect;
        still = capture;
        question = "";
        answer = "";
        lastAnswer = null;
        actions = [];
        problem = "";
        notice = "";
        folder = "";
        seconds = 0;
        provider = ShellSettings.lensProvider;
        state = "prompt";
        stoppedRequest = false;
        beginning = true;
        if (ready)
            initialise();
        else
            helper.running = true;
        showAfterPicker.restart();
    }

    function initialise() {
        helper.write(JSON.stringify({ event: "begin", path: path }) + "\n");
        beginning = false;
    }

    function ask(text: string) {
        if (busy || !ready || beginning || !text.trim())
            return;
        question = text.trim();
        problem = "";
        notice = "";
        provider = ShellSettings.lensProvider;
        stoppedRequest = false;
        state = "reading";
        started = Date.now();
        seconds = 0;
        helper.write(JSON.stringify({ event: "ask", question: question, provider: provider,
            claude: { model: ShellSettings.lensClaudeModel, effort: ShellSettings.lensClaudeEffort, fallback: ShellSettings.lensClaudeFallback },
            codex: { model: ShellSettings.lensCodexModel, effort: ShellSettings.lensCodexEffort, fallback: ShellSettings.lensCodexFallback }
        }) + "\n");
    }

    function retry() { ask(question); }
    function edit() { state = "prompt"; problem = ""; }
    function cancel() {
        if (busy)
            helper.write('{"event":"cancel"}\n');
    }
    function cancelled() {
        stoppedRequest = true;
        if (lastAnswer) {
            provider = lastAnswer.provider;
            model = lastAnswer.model;
            seconds = lastAnswer.seconds;
            question = lastAnswer.question;
        }
        notice = "Request stopped.";
        state = answer ? "answer" : "prompt";
    }
    function close() {
        showAfterPicker.stop();
        open = false;
        helper.write('{"event":"close"}\n');
        // Retain the still through the closing fade, then release it and the helper.
        release.restart();
    }
    function search(query: string) { Apps.searchWeb(query); }
    function openLink(link: string) {
        if (/^https?:\/\//i.test(link)) Quickshell.execDetached(["xdg-open", link]);
    }

    Timer {
        id: showAfterPicker
        interval: Theme.motionDuration + 40
        onTriggered: root.open = true
    }
    Timer {
        id: release
        interval: Theme.motionDuration + 60
        onTriggered: if (!root.open) { helper.running = false; root.still = null; }
    }
    Timer {
        running: root.busy
        interval: 100
        repeat: true
        onTriggered: root.seconds = (Date.now() - root.started) / 1000
    }
    Process {
        id: helper
        command: ["python3", "-I", Quickshell.shellPath("services/lens.py")]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const m = JSON.parse(line);
                    if (m.event === "ready") {
                        root.ready = true;
                        if (root.beginning) root.initialise();
                    } else if (m.event === "reading") {
                        root.provider = m.provider;
                        root.model = m.model;
                    } else if (m.event === "fallback") {
                        root.provider = m.provider;
                        root.notice = `Trying ${root.providerName}: the other provider is unavailable.`;
                    } else if (m.event === "answer") {
                        root.provider = m.provider;
                        root.model = m.model;
                        root.answer = m.answer;
                        root.actions = m.actions;
                        root.seconds = m.seconds;
                        root.folder = m.folder;
                        root.notice = m.warning || root.notice;
                        root.lastAnswer = { provider: m.provider, model: m.model, seconds: m.seconds, question: root.question };
                        root.state = "answer";
                    } else if (m.event === "error") {
                        root.problem = m.message;
                        root.state = "error";
                    } else if (m.event === "cancelled") {
                        root.cancelled();
                    }
                } catch (e) { console.warn("lens: invalid helper message", e); }
            }
        }
        stderr: SplitParser { onRead: line => console.warn("lens:", line) }
        onExited: code => {
            root.ready = false;
            if (root.open && code !== 0) {
                root.problem = `Lens helper stopped (exit ${code}). Close Lens and take a new snip.`;
                root.state = "error";
            }
        }
    }
}
