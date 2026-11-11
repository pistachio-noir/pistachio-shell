pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Manual local checks only. The helper publishes allowlisted status, never CLI identity/output.
Singleton {
    id: root
    property var rows: []
    readonly property bool busy: probe.running
    property bool checked
    property string error
    function check(auth: bool) {
        if (busy) return;
        error = "";
        probe.command = ["python3", "-I", Quickshell.shellPath("services/system-tools.py"), "health", "--pid", String(Quickshell.processId)].concat(auth ? ["--auth"] : []);
        probe.running = true;
    }
    function diagnostics(): string {
        return "Pistachio Noir diagnostics\nLocal status only; personal data and raw logs excluded.\n" + rows.map(r => r.title + ": " + r.status).join("\n");
    }
    function copyDiagnostics() { Clipboard.copyText(diagnostics()); }
    Process {
        id: probe
        stdout: StdioCollector { onStreamFinished: { try { root.rows = JSON.parse(text); root.checked = true; } catch(e) { root.error = "Could not read local health checks."; } } }
        onExited: code => { if (code !== 0) root.error = "Local health check could not start."; }
    }
}
