pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The polkit agent: apps asking for admin rights (pkexec, GParted, an app managing system services).
// Quickshell's own agent starts PAM as soon as a request comes in, so even Cancel counted as a failed
// login for pam_faillock; services/polkit-agent.py starts it only when a password is submitted, and
// also tells which app asked. Requests queue; the dialog shows the oldest.
Singleton {
    id: root

    readonly property bool agent: agentReady && agentProcess.running // registered with polkit for this session
    property bool agentReady
    // { cookie, action, message, user, requester, vendor }, oldest first; requester and vendor may be ""
    property var requests: []
    readonly property var request: requests[0] ?? null
    property bool checking // PAM has the password
    property string error // why the last try failed, or ""
    // PAM asks for more than the password (e.g. a one-time code): its question, else ""
    property string prompt
    property bool promptVisible // the answer to `prompt` may show as typed

    function submit(text: string) {
        if (!request || checking)
            return;
        checking = true;
        error = "";
        tell({ cookie: request.cookie, response: text });
    }

    // not while PAM checks a password: stopping it then would count as a failed login
    function cancel() {
        if (!request || checking)
            return;
        tell({ cookie: request.cookie, cancel: true });
        drop(request.cookie);
    }

    function tell(message) {
        agentProcess.write(JSON.stringify(message) + "\n");
    }

    function drop(cookie: string) {
        if (request?.cookie === cookie) {
            checking = false;
            error = "";
            prompt = "";
        }
        requests = requests.filter(r => r.cookie !== cookie);
    }

    // the agent can't answer polkit any more, so neither can the dialog
    function forget() {
        requests = [];
        checking = false;
        error = "";
        prompt = "";
    }

    function heard(line: string) {
        let m;
        try {
            m = JSON.parse(line);
        } catch (e) {
            console.warn("polkit agent:", line);
            return;
        }
        const current = m.cookie !== undefined && m.cookie === request?.cookie;
        if (m.event === "ready") {
            agentReady = true;
        } else if (m.event === "lost") {
            agentReady = false;
            forget();
        } else if (m.event === "request") {
            requests = requests.concat([{ cookie: m.cookie, action: m.action, message: m.message, user: m.user, requester: m.requester, vendor: m.vendor }]);
        } else if (m.event === "done" || m.event === "cancel") {
            drop(m.cookie);
        } else if (m.event === "failed" && current) {
            checking = false;
            prompt = "";
            error = m.error || "Wrong password. Try again.";
        } else if (m.event === "prompt" && current) {
            checking = false;
            prompt = m.text.replace(/:\s*$/, "");
            promptVisible = m.echo;
        }
    }

    Process {
        id: agentProcess
        running: true
        command: ["python3", "-I", Quickshell.shellPath("services/polkit-agent.py")]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => root.heard(data)
        }
        stderr: SplitParser {
            onRead: data => console.warn("polkit agent:", data)
        }
        onExited: code => {
            if (code !== 0 && !root.agentReady)
                console.warn("polkit agent exited with code", code, "before registering (is python-gobject installed?)");
            root.agentReady = false;
            root.forget();
        }
    }
}
