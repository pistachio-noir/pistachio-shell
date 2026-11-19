pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property string state: "idle"
    property real level
    property real seconds
    property string error
    property string wanted
    property bool stopping
    property bool active
    onActiveChanged: if (!active) stop()
    readonly property string input: Audio.source?.name ?? ""
    onInputChanged: stop()
    function start(command: string) {
        if (!active || !input || !["meter", "record", "play"].includes(command)) return;
        error = "";
        if (stopping) { wanted = command; return; }
        if (helper.running) helper.write(JSON.stringify({command:command}) + "\n");
        else if (command !== "play") {
            wanted = command;
            helper.command = [Quickshell.env("HOME") + "/.local/bin/psc", "mic-check", input];
            helper.running = true;
            state = "starting";
        }
    }
    function stop() {
        wanted = "";
        stopping = helper.running;
        helper.running = false;
        state = "idle"; level = 0; seconds = 0;
    }
    Process {
        id: helper
        stdinEnabled: true
        stdout: SplitParser { onRead: data => {
            try {
                const m=JSON.parse(data);
                if (m.event === "ready") {
                    if (root.active && root.wanted) helper.write(JSON.stringify({command:root.wanted}) + "\n");
                    else root.stop();
                    root.wanted = "";
                } else if (m.event === "state" && root.active) { root.state=m.state; if (m.state === "recorded") root.level=0; }
                else if (m.event === "level" && root.active) { root.level=m.value; root.seconds=m.seconds; }
                else if (m.event === "error") { root.error=m.message; root.stop(); }
            } catch(e) { root.error="Could not read microphone check."; root.stop(); }
        } }
        onExited: code => {
            const restart = root.wanted;
            if (code !== 0 && root.active && !root.stopping) root.error="Microphone check stopped unexpectedly.";
            root.stopping=false; root.state="idle"; root.level=0; root.wanted="";
            if (restart && root.active) Qt.callLater(() => root.start(restart));
        }
    }
}
