import qs
import qs.components
import qs.services
import qs.settings
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls.Basic as Basic

// Existing panel style; services own every file and process operation.
PanelWindow {
    id: root
    property bool open
    property bool remember: false
    property bool hadFocus
    onOpenChanged: if (open) hadFocus=false
    property string shownMode: ""
    visible: reveal.shown
    anchors { top:true; bottom:true; left:true; right:true }
    exclusionMode: ExclusionMode.Ignore
    color:"transparent"
    WlrLayershell.namespace:"pistachio-panel"
    WlrLayershell.layer:WlrLayer.Overlay
    WlrLayershell.keyboardFocus: reveal.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    Reveal { id:reveal; open:root.open }
    Connections {
        target:LauncherTools
        function onPresent() { root.remember=false; root.shownMode=LauncherTools.mode; showDelay.restart(); }
        function onModeChanged() { if (!LauncherTools.mode) { root.open=false; showDelay.stop(); } }
    }
    Connections { target:SettingsHub; function onPresent() { root.close(); } }
    Connections { target:Session; function onLockedChanged() { if (Session.locked) root.close(); } }
    Timer { id:showDelay; interval:240; onTriggered: { root.open=true; } }
    function close() { root.open=false; LauncherTools.close(); }
    MouseArea { anchors.fill:parent; onClicked:root.close() }
    Item {
        id:card
        objectName:"launcher-extras-card"
        width:Math.min(900,root.width-80); height:Math.min(720,root.height-100)
        anchors.centerIn:parent
        opacity:reveal.progress; y:Math.round((root.height-height)/2)+12*(1-reveal.progress)
        focus:root.open && Window.active
        Window.onActiveChanged: {
            if (Window.active && root.open) { root.hadFocus=true; card.forceActiveFocus(); }
            else if (!Window.active && root.hadFocus && root.open) root.close();
        }
        Keys.onEscapePressed:root.close()
        MouseArea { anchors.fill:parent }
        Shadow { anchors.fill:panel; radius:panel.radius; kind:Theme.shadowPanel }
        Rectangle { id:panel; anchors.fill:parent; radius:Theme.panelRadius; color:Theme.surface; border.width:1; border.color:Theme.overlay2 }
        Column {
            x:24; y:20; width:parent.width-48; spacing:14
            Row {
                width:parent.width; spacing:12
                Text { width:parent.width-100; text:root.shownMode==="launch-failed" ? "Application could not start" : root.shownMode==="jobs" ? "Background jobs" : root.shownMode==="preview" ? "File preview" : "Open with"; color:Theme.textBright; font.family:Theme.fontUi; font.pixelSize:20; font.weight:Font.Bold; anchors.verticalCenter:parent.verticalCenter }
                SettingsButton { text:"Close"; onClicked:root.close() }
            }
            Text { width:parent.width; visible:root.shownMode!=="jobs" && root.shownMode!=="launch-failed"; text:LauncherTools.path; color:Theme.subtext; font.family:Theme.fontUi; font.pixelSize:12; elide:Text.ElideMiddle }
            Text { visible:LauncherTools.busy || !!LauncherTools.error; text:LauncherTools.error || "Reading…"; color:LauncherTools.error ? Theme.terracotta : Theme.subtext; width:parent.width; wrapMode:Text.Wrap; font.family:Theme.fontUi; font.pixelSize:13 }
            Flickable {
                id:scroll
                width:parent.width; height:card.height-y-30
                clip:true; contentHeight:body.implicitHeight
                boundsBehavior:Flickable.StopAtBounds
                Basic.ScrollBar.vertical:Basic.ScrollBar {}
                Column {
                    id:body; width:scroll.width; spacing:12
                    Column {
                        width:parent.width; visible:root.shownMode==="launch-failed"; spacing:12
                        Text { width:parent.width; text:Apps.nameFor(LauncherTools.launchFailure.app ?? "")+"\n"+(LauncherTools.launchFailure.error ?? ""); wrapMode:Text.Wrap; color:Theme.text; font.family:Theme.fontUi; font.pixelSize:14 }
                        SettingsButton { text:"Retry"; onClicked:LauncherTools.retryLaunch() }
                    }
                    Column {
                        width:parent.width; visible:root.shownMode==="preview"; spacing:12
                        Text { width:parent.width; text:(LauncherTools.preview.mime ?? "")+" · "+(LauncherTools.preview.size ?? 0)+" bytes · "+(LauncherTools.preview.modified ?? ""); color:Theme.subtext; font.family:Theme.fontUi; font.pixelSize:12; wrapMode:Text.Wrap }
                        Image { visible:LauncherTools.preview.kind==="image"; source:visible ? LauncherTools.preview.image ?? "" : ""; width:parent.width; height:Math.min(480,Math.max(100,sourceSize.height)); fillMode:Image.PreserveAspectFit; asynchronous:true; cache:false }
                        TextEdit { visible:LauncherTools.preview.kind==="text"; width:parent.width-18; text:LauncherTools.preview.text ?? ""; readOnly:true; selectByMouse:true; wrapMode:TextEdit.Wrap; textFormat:TextEdit.PlainText; color:Theme.text; selectionColor:Theme.pistachio; selectedTextColor:Theme.bg; font.family:Theme.fontMono; font.pixelSize:13 }
                        Text { visible:!!LauncherTools.preview.truncated || LauncherTools.preview.kind==="metadata"; text:LauncherTools.preview.truncated ? "Preview limited to 256 KiB." : LauncherTools.preview.note || "No preview for this file type."; color:Theme.subtext; font.family:Theme.fontUi; font.pixelSize:13 }
                        SettingsButton { text:"Open with…"; onClicked:LauncherTools.showFile(LauncherTools.path,"handlers") }
                    }
                    Column {
                        width:parent.width; visible:root.shownMode==="handlers"; spacing:10
                        SettingsButton { text:root.remember ? "Remember for this file type: On" : "Remember for this file type: Off"; active:root.remember; onClicked:root.remember=!root.remember }
                        Text { width:parent.width; text:LauncherTools.handlers.length ? "Choose an application. Remember changes the default for "+LauncherTools.mime+"." : "No applications registered for this file type."; wrapMode:Text.Wrap; color:Theme.subtext; font.family:Theme.fontUi; font.pixelSize:13 }
                        Repeater {
                            model:LauncherTools.handlers
                            SettingsButton { required property var modelData; width:parent.width; text:modelData.name; enabled:!LauncherTools.busy; onClicked:LauncherTools.openWith(modelData.id,root.remember) }
                        }
                    }
                    Column {
                        width:parent.width; visible:root.shownMode==="jobs"; spacing:12
                        Text { visible:!LauncherTools.jobs.length; text:"Commands run in the background from the launcher appear here."; width:parent.width; wrapMode:Text.Wrap; color:Theme.subtext; font.family:Theme.fontUi; font.pixelSize:13 }
                        Repeater { model:LauncherTools.jobs; JobCard { required property var modelData; width:parent.width; job:modelData } }
                    }
                }
            }
        }
    }
}
