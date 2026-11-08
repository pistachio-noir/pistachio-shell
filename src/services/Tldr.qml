pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// `tldr <command>` in the launcher (owner's pick, 8 November 2026): tldr's page for it, as its
// description and examples; the launcher copies the example picked.
Singleton {
    id: root

    property string page // the command the description and examples are for
    property string wanted // the command asked for last
    property string asked // the one tldr is reading now
    property string description
    property string more // the page's "More information" link
    property var examples: [] // { what, command }
    property bool missing // tldr has no page for it
    property bool busy

    // as the search changes: once typing pauses, tldr reads the page; exec() stops a reading still
    // going (setting `running` off and on at once didn't restart it, and the launcher stayed on
    // "Looking it up…", owner, 9 November)
    function lookup(name: string) {
        const clean = name.trim().toLowerCase().replace(/\s+/g, "-");
        if (!clean || clean === wanted)
            return;
        wanted = clean;
        busy = true;
        typing.restart();
    }

    Timer {
        id: typing
        interval: 250
        onTriggered: {
            root.asked = root.wanted;
            reader.exec({ command: ["tldr", "-m", root.asked] });
        }
    }

    Process {
        id: reader
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.asked !== root.wanted)
                    return; // typed on meanwhile: the next reading follows
                const lines = text.split("\n");
                const about = lines.filter(l => l.startsWith("> ") && !l.includes("More information")).map(l => l.slice(2));
                const examples = [];
                let what = "";
                for (const l of lines) {
                    if (l.startsWith("- "))
                        what = l.slice(2).replace(/:$/, "");
                    else if (l.startsWith("`") && what) {
                        examples.push({ what: (w => w.charAt(0).toUpperCase() + w.slice(1))(what.replace(/\[(\w+)\]/g, "$1")), command: l.replace(/^`|`$/g, "").replace(/\{\{|\}\}/g, "") });
                        what = "";
                    }
                }
                root.description = about.join(" ");
                root.more = (lines.find(l => l.includes("More information")) ?? "").replace(/^.*<|>.*$/g, "");
                root.examples = examples;
                root.missing = examples.length === 0;
                root.page = root.asked;
                root.busy = false;
            }
        }
    }
}
