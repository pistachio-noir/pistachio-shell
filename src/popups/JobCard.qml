import qs
import qs.services
import qs.settings
import QtQuick
Rectangle {
    id:root
    required property var job
    property bool expanded
    property real now:Date.now()
    implicitHeight:body.implicitHeight+32
    radius:Theme.tileRadius; color:Theme.overlay
    Timer { interval:1000; repeat:true; running:root.job.state==="running"; onTriggered:root.now=Date.now() }
    Column {
        id:body; x:16; y:16; width:parent.width-32; spacing:10
        Text { width:parent.width; text:root.job.command; color:Theme.textBright; font.family:Theme.fontMono; font.pixelSize:13; wrapMode:Text.Wrap; maximumLineCount:3; elide:Text.ElideRight }
        Text { text:root.job.state+" · "+Math.max(0,Math.floor(((root.job.ended ?? root.now)-root.job.started)/1000))+" s"+(root.job.code!==null ? " · exit "+root.job.code : ""); color:root.job.state==="failed" ? Theme.terracotta : Theme.subtext; font.family:Theme.fontUi; font.pixelSize:12 }
        Row {
            spacing:8
            SettingsButton { text:root.expanded ? "Hide output" : "Show output"; onClicked:root.expanded=!root.expanded }
            SettingsButton { text:root.job.state==="running" ? "Cancel" : "Run again"; danger:root.job.state==="running"; onClicked:root.job.state==="running" ? LauncherTools.cancel(root.job.id) : LauncherTools.run(root.job.command) }
        }
        Text { visible:root.expanded; text:"Most recent 64 KiB of output"; color:Theme.subtext; font.family:Theme.fontUi; font.pixelSize:11 }
        TextEdit { width:parent.width; visible:root.expanded; text:root.job.output || root.job.error || "No output yet."; readOnly:true; selectByMouse:true; wrapMode:TextEdit.WrapAnywhere; color:Theme.text; selectionColor:Theme.pistachio; selectedTextColor:Theme.bg; font.family:Theme.fontMono; font.pixelSize:12; textFormat:TextEdit.PlainText }
    }
}
