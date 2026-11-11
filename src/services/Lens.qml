pragma Singleton

import qs
import Quickshell
import Quickshell.Io
import QtQuick

// Owner's call, 10 November 2026: Claude Code or Codex, with independent settings and fallback.
// The helper owns CLI sessions, attachment proposals and disk access. UI sends user actions here.
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
    property string effort
    property string purpose: "auto"
    property bool codingEnabled
    property bool codingAsked
    property bool upgradePrompt
    property string problem
    property string notice
    property string folder
    property string attachment
    property string diff
    property bool pickingFile
    property real seconds
    property real started
    property bool ready
    property bool beginning
    property bool stoppedRequest
    readonly property bool busy: state === "reading"
    readonly property string providerName: provider === "codex" ? "ChatGPT" : "Claude"
    readonly property string codingPrefix: provider === "codex" ? "lensCodexCoding" : "lensClaudeCoding"
    readonly property string codingLabel: ShellSettings.lensLabel(codingPrefix + "Model") + " · " + ShellSettings.lensLabel(codingPrefix + "Effort")
    readonly property string modelLabel: (provider === "codex" ? ShellSettings.lensCodexModels : ShellSettings.lensClaudeModels).find(choice => choice.value === model)?.title ?? model

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
        attachment = "";
        diff = "";
        effort = "";
        purpose = "auto";
        codingEnabled = false;
        codingAsked = false;
        upgradePrompt = false;
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

    function ask(text: string) { askTask(text, "auto"); }
    function askTask(text: string, task: string) { askWithProvider(text, ShellSettings.lensProvider, false, task, false); }
    function askWithProvider(text: string, chosenProvider: string, transfer: bool, task: string, upgrade: bool) {
        if (busy || !ready || beginning || !text.trim())
            return;
        question = text.trim();
        problem = "";
        notice = "";
        provider = chosenProvider;
        purpose = task;
        upgradePrompt = false;
        if (!upgrade) diff = "";
        stoppedRequest = false;
        state = "reading";
        started = Date.now();
        seconds = 0;
        helper.write(JSON.stringify({ event: "ask", question: question, provider: provider, transfer: transfer,
            purpose: task, upgrade: upgrade, coding_enabled: codingEnabled && ShellSettings.lensSuggestCoding,
            claude: { model: ShellSettings.lensClaudeModel, effort: ShellSettings.lensClaudeEffort, fallback: ShellSettings.lensClaudeFallback,
                coding: { model: ShellSettings.lensClaudeCodingModel, effort: ShellSettings.lensClaudeCodingEffort } },
            codex: { model: ShellSettings.lensCodexModel, effort: ShellSettings.lensCodexEffort, fallback: ShellSettings.lensCodexFallback,
                coding: { model: ShellSettings.lensCodexCodingModel, effort: ShellSettings.lensCodexCodingEffort } }
        }) + "\n");
    }

    function retry() { askWithProvider(question, provider, false, purpose, false); }
    function askOther() { askWithProvider(question, provider === "claude" ? "codex" : "claude", true, purpose, false); }
    function respondCodingUpgrade(accept: bool) {
        if (!upgradePrompt) return;
        codingAsked = true;
        upgradePrompt = false;
        if (accept) {
            codingEnabled = true;
            askWithProvider(question, provider, true, purpose, true);
        }
    }
    function attachFile() {
        if (busy || !ready || pickingFile) return;
        pickingFile = true;
        notice = "";
        chooseAfterFade.restart();
    }
    function detachFile() {
        if (!busy) helper.write('{"event":"attach","path":""}\n');
    }
    function review(apply: bool) {
        if (!busy && diff) helper.write(JSON.stringify({ event: apply ? "apply" : "discard" }) + "\n");
    }
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
            effort = lastAnswer.effort || "";
            purpose = lastAnswer.purpose || "auto";
            seconds = lastAnswer.seconds;
            question = lastAnswer.question;
        }
        notice = "Request stopped.";
        state = answer ? "answer" : "prompt";
    }
    function close() {
        showAfterPicker.stop();
        upgradePrompt = false;
        chooseAfterFade.stop();
        filePicker.running = false;
        pickingFile = false;
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
        id: chooseAfterFade
        interval: Theme.motionDuration + 60
        onTriggered: filePicker.running = true
    }
    Process {
        id: filePicker
        // env exits normally with 127 if zenity is missing, so the card always returns.
        command: ["env", "zenity", "--file-selection", "--title=Attach a text file to Lens"]
        stdout: StdioCollector {
            onStreamFinished: {
                const file = text.replace(/\n$/, "");
                if (file && root.open) helper.write(JSON.stringify({ event: "attach", path: file }) + "\n");
            }
        }
        stderr: SplitParser { onRead: line => console.warn("lens file picker:", line) }
        onExited: code => {
            root.pickingFile = false;
            if (code !== 0 && code !== 1) root.notice = "Couldn't open the file picker. Install zenity to attach files.";
        }
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
                        root.effort = m.effort || "";
                    } else if (m.event === "fallback") {
                        root.provider = m.provider;
                        root.notice = `Trying ${root.providerName}: the other provider is unavailable.`;
                    } else if (m.event === "answer") {
                        root.provider = m.provider;
                        root.model = m.model;
                        root.effort = m.effort || "";
                        root.answer = m.answer;
                        root.actions = m.actions;
                        root.diff = m.diff || "";
                        root.seconds = m.seconds;
                        root.folder = m.folder;
                        root.notice = m.warning || root.notice;
                        root.lastAnswer = { provider: m.provider, model: m.model, effort: root.effort, seconds: m.seconds, question: root.question, purpose: root.purpose };
                        root.upgradePrompt = !!m.offer_coding && ShellSettings.lensSuggestCoding && !root.codingAsked;
                        root.state = "answer";
                    } else if (m.event === "upgrade_failed") {
                        root.cancelled();
                        root.notice = "Couldn't use the coding preset. Your previous answer is kept. " + m.message;
                    } else if (m.event === "attached") {
                        root.attachment = m.name;
                        root.diff = "";
                    } else if (m.event === "reviewed") {
                        root.diff = "";
                        root.notice = m.message + (m.warning ? ". " + m.warning : "");
                    } else if (m.event === "notice") {
                        root.notice = m.message;
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
