pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// libqalculate for the launcher's harder maths (owner's request, 9 November 2026; on 26 October they had
// kept the simple calc.js, as qalc reads app names as units): only after `=`, or when calc.js can't
// read a query that clearly is maths (Launcher.looksLikeMaths). qalc answers each query in ~50 ms; the
// launcher shows the answer when it comes.
Singleton {
    id: root

    readonly property bool installed: found
    property bool found
    property string wanted // the expression asked for last
    property string asked // the one qalc is working on
    property string expression // the one `answer` is for
    property string answer
    property bool failed // qalc couldn't make sense of it

    function ask(expr: string) {
        expr = expr.trim();
        if (!found || !expr || expr === wanted)
            return;
        wanted = expr;
        typing.restart();
    }

    Timer {
        id: typing
        interval: 150
        onTriggered: {
            root.asked = root.wanted;
            reader.exec({ command: ["timeout", "3", "qalc", "-t", "--", root.asked] });
        }
    }

    Process {
        id: reader
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.asked !== root.wanted)
                    return; // typed on meanwhile
                const out = text.trim().split("\n").filter(l => l.trim()).pop() ?? "";
                root.expression = root.asked;
                root.failed = !out || /error|warning/i.test(out);
                root.answer = root.failed ? "" : out;
            }
        }
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v qalc"]
        onExited: code => root.found = code === 0
    }
}
