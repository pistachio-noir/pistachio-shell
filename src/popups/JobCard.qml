import qs
import qs.components
import qs.services
import QtQuick
import QtQuick.Controls.Basic as Basic

// A background job (LauncherTools), restyled by Claude (owner's request, 12 November 2026): its state
// as a mark (pistachio while running, teal when done, terracotta when it failed), the command, how
// long and how it ended, and its output on demand in a code block. A running emerge is one too (psc's
// emerge.rs, 28 November 2026): what it builds, the phase and "3 of 12"; view only, and "Ended" when
// emerge.log can't be read to say how.
Rectangle {
    id:root
    required property var job
    property bool expanded
    property real now:Date.now()
    readonly property bool running: job.state === "running"
    readonly property bool emerge: job.kind === "emerge"
    readonly property bool unknown: job.state === "cancelled" || job.state === "ended"
    readonly property bool failed: job.state === "failed" || !running && job.code !== null && job.code !== 0 && job.state !== "cancelled"
    readonly property int seconds: Math.max(0,Math.floor(((job.ended ?? now)-job.started)/1000))
    readonly property string took: seconds < 60 ? `${seconds} s` : `${Math.floor(seconds/60)} min ${seconds%60} s`
    readonly property string stateText: running ? (emerge ? ((job.packages ?? []).length ? "Building " + Array.from(job.packages).join(", ") : "Working") : "Running")
        : job.state === "cancelled" ? (emerge ? "Stopped" : "Cancelled") : job.state === "ended" ? "Ended" : failed ? "Failed" : "Done"
    implicitHeight: body.implicitHeight + 32
    radius: Theme.tileRadius
    color: Theme.overlay
    Timer { interval:1000; repeat:true; running:root.running; onTriggered:root.now=Date.now() }

    Column {
        id:body; x:16; y:16; width:parent.width-32; spacing:12

        Item {
            width: parent.width
            height: Math.max(40, info.implicitHeight)

            // the state's mark
            Rectangle {
                id: mark
                width: 32; height: 32; radius: Theme.tui ? 0 : 16
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.bg
                Rectangle {
                    visible: root.running
                    anchors.centerIn: parent; width: 10; height: 10; radius: Theme.tui ? 0 : 5; color: Theme.pistachio
                    SequentialAnimation on opacity {
                        running: root.running; loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                    }
                }
                Icon {
                    visible: !root.running
                    anchors.centerIn: parent; size: 14
                    paths: root.failed ? Icons.close : root.unknown ? Icons.minus : Icons.check
                    color: root.failed ? Theme.terracotta : root.unknown ? Theme.subtext : Theme.teal
                }
            }

            Column {
                id: info
                anchors.left: mark.right; anchors.leftMargin: 12
                anchors.right: actions.left; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Text { width:parent.width; text:root.job.command; color:Theme.textBright; font.family:Theme.fontMono; font.pixelSize:13; font.weight: Font.Bold; wrapMode:Text.Wrap; maximumLineCount:2; elide:Text.ElideRight }
                Text { text: [root.stateText, root.running && root.emerge ? root.job.phase : "", root.running && root.emerge ? root.job.step : "", root.took, root.job.code !== null && root.job.code !== undefined && !root.running ? `exit ${root.job.code}` : ""].filter(Boolean).join(" · "); color:root.failed ? Theme.terracotta : Theme.subtext; font.family:Theme.fontUi; font.pixelSize:12; font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
            }

            Row {
                id: actions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                ActionButton { text: root.expanded ? "Hide output" : "Output"; icon: root.expanded ? Icons.chevronUp : Icons.chevronDown; base: Theme.overlay2; onClicked: root.expanded = !root.expanded }
                ActionButton { visible: !root.emerge; text: root.running ? "Cancel" : "Run again"; icon: root.running ? Icons.stop : Icons.reboot; base: Theme.overlay2; onClicked: root.running ? LauncherTools.cancel(root.job.id) : LauncherTools.run(root.job.command) }
            }
        }

        // its output, the latest 64 KB
        Rectangle {
            visible: root.expanded
            width: parent.width
            height: Math.min(240, out.implicitHeight + 28)
            radius: Theme.tui ? 0 : 14
            color: Theme.bg
            clip: true
            Flickable {
                id: outScroll
                anchors.fill: parent; anchors.margins: 14
                contentHeight: out.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                Basic.ScrollBar.vertical: Basic.ScrollBar {}
                TextEdit { id: out; width: outScroll.width - 10; text:root.job.output || root.job.error || "No output yet."; readOnly:true; selectByMouse:true; wrapMode:TextEdit.WrapAnywhere; color:root.job.output || root.job.error ? Theme.text : Theme.subtext; selectionColor:Theme.pistachio; selectedTextColor:Theme.bg; font.family:Theme.fontMono; font.pixelSize:12; textFormat:TextEdit.PlainText }
            }
        }
    }
}
