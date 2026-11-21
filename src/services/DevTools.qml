pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Experimental → Dev features (opt-in; owner, 21 November 2026): launcher actions for working on the
// shell, each a background job (LauncherTools.run), so the output, elapsed time, Cancel and Run again
// are the launcher's Background jobs. The repo is the folder above the shell's src/ (followed through
// the ~/.config/quickshell/pistachio link). A toast says how tests and the rebuild ended; clicking it
// opens Background jobs.
Singleton {
    id: root

    // shell-quoted, for the sh -c line a job runs
    function quoted(text: string): string { return "'" + text.replace(/'/g, "'\\''") + "'"; }
    readonly property string repo: `cd -P ${quoted(Quickshell.shellPath(""))} && cd -P ..`
    readonly property string psc: `"$HOME/.local/bin/psc"`

    function command(kind: string): string {
        if (kind === "tests") return `${repo} && sh tests/run.sh`;
        if (kind === "native") return `${repo} && sh tests/run.sh --native`;
        if (kind === "errors") return `${psc} log --errors`;
        // psc only (the all-day helpers need ./install.sh); the old file goes first, so a running
        // helper keeps its inode. The shell's helpers use the new one after a restart.
        if (kind === "rebuild") return `${repo} && cd rust && cargo build --release -p psc && cd .. && rm -f ${psc} && install -m 755 rust/target/release/psc ${psc} && echo "psc rebuilt and installed. Restart the shell (Settings → Shell health) so its helpers use it."`;
        return "";
    }

    // command -> { kind, since }: jobs started here whose end gets a toast
    property var watching: ({})

    function run(kind: string) {
        const line = command(kind);
        if (!line)
            return;
        if (kind !== "errors") {
            const all = Object.assign({}, watching);
            all[line] = { kind: kind, since: Date.now() - 2000 };
            watching = all;
        }
        LauncherTools.run(line);
        LauncherTools.showJobs();
    }

    function ended(job) {
        const watch = watching[job.command];
        if (!watch || job.state === "running" || job.started < watch.since)
            return;
        const all = Object.assign({}, watching);
        delete all[job.command];
        watching = all;
        if (job.state === "cancelled")
            return;
        const ok = job.state === "finished";
        const failedSuites = Number(job.code) > 0 && Number(job.code) < 100 ? Number(job.code) : 0;
        const title = watch.kind === "rebuild" ? (ok ? "psc rebuilt" : "psc didn't build")
            : ok ? "Dev tests passed" : failedSuites ? `Dev tests: ${failedSuites} ${failedSuites === 1 ? "suite" : "suites"} failed` : "Dev tests didn't finish";
        toast.createObject(root, { title: title, body: ok && watch.kind === "rebuild" ? "Restart the shell so its helpers use it." : "Click to see the output in Background jobs." });
    }

    Connections {
        target: LauncherTools
        function onJobsChanged() {
            if (Object.keys(root.watching).length)
                Array.from(LauncherTools.jobs ?? []).forEach(job => root.ended(job));
        }
    }

    Component {
        id: toast
        Process {
            property string title
            property string body
            running: true
            command: ["setpriv", "--pdeathsig", "TERM", "notify-send", "--app-name=Dev features", "--icon=utilities-terminal",
                "--action=default=Open", title, body]
            stdout: SplitParser { onRead: data => { if (data === "default") LauncherTools.showJobs(); } }
            onExited: destroy()
        }
    }
}
