import qs
import qs.components
import qs.services
import qs.settings
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls.Basic as Basic

// The launcher's extra panels (LauncherTools): background jobs, a file's preview, Open with, and an
// app that couldn't start. Restyled by Claude (owner's request, 12 November 2026; no board): over a
// dimmed screen, a panel sized to what it shows, with a header (an icon well, a title, a line about
// it, ✕) in the Pistachio Noir way; services own every file and process operation.
PanelWindow {
    id: root
    property bool open
    property bool remember: false
    property bool hadFocus
    onOpenChanged: if (open) hadFocus=false
    property string shownMode: ""
    readonly property var preview: LauncherTools.preview ?? ({})
    readonly property var jobs: LauncherTools.jobs ?? []
    readonly property int running: jobs.filter(j => j.state === "running").length
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

    // "12.4 KB", for the preview's size
    function bytes(n: real): string {
        if (!(n >= 0)) return "";
        const units = ["bytes", "KB", "MB", "GB"];
        let i = 0;
        while (n >= 1000 && i < units.length - 1) { n /= 1000; i++; }
        return i === 0 ? `${n} bytes` : `${n.toFixed(n < 10 ? 1 : 0)} ${units[i]}`;
    }

    readonly property string title: shownMode==="launch-failed" ? "Couldn't start the app" : shownMode==="jobs" ? "Background jobs" : shownMode==="preview" ? (LauncherTools.path.split("/").pop() || "File preview") : "Open with"
    readonly property string detail: shownMode==="jobs" ? (jobs.length ? [running ? `${running} running` : "", jobs.length - running ? `${jobs.length - running} finished` : ""].filter(Boolean).join(" · ") : "Nothing yet")
        : shownMode==="launch-failed" ? Apps.nameFor(LauncherTools.launchFailure.app ?? "")
        : LauncherTools.path.replace(Quickshell.env("HOME"), "~")
    readonly property var glyph: shownMode==="jobs" ? Icons.terminal : shownMode==="launch-failed" ? Icons.shieldAlert : shownMode==="handlers" ? Icons.folderOpen
        : preview.kind==="image" ? Icons.image : preview.kind==="text" ? Icons.fileCode : Icons.file
    // the panel's width for what it shows
    readonly property real wide: shownMode==="preview" ? 760 : shownMode==="jobs" ? 640 : 480

    // the dimmed screen; a click on it closes
    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        opacity: 0.45 * reveal.progress
        MouseArea { anchors.fill:parent; onClicked:root.close() }
    }

    Item {
        id:card
        objectName:"launcher-extras-card"
        width:Math.min(root.wide, root.width-80)
        height:Math.min(content.implicitHeight + 48, root.height-140)
        anchors.horizontalCenter: parent.horizontalCenter
        y:Math.round((root.height-height)/2)+12*(1-reveal.progress)
        opacity:reveal.progress
        scale: 0.97 + 0.03 * reveal.progress
        focus:root.open && Window.active
        Window.onActiveChanged: {
            if (Window.active && root.open) { root.hadFocus=true; card.forceActiveFocus(); }
            else if (!Window.active && root.hadFocus && root.open) root.close();
        }
        Keys.onEscapePressed:root.close()
        Behavior on width { NumberAnimation { duration: Theme.motionDuration; easing.type: Theme.easing } }
        Behavior on height { enabled: reveal.progress === 1; NumberAnimation { duration: Theme.motionDuration; easing.type: Theme.easing } }
        MouseArea { anchors.fill:parent }
        Shadow { anchors.fill:panel; radius:panel.radius; kind:Theme.shadowModal; frostable:true }
        Rectangle { id:panel; anchors.fill:parent; radius:Theme.panelRadius; color:Theme.surface; border.width:1; border.color:Theme.overlay2 }

        Column {
            id: content
            x:24; y:24; width:parent.width-48; spacing:18

            // the header: what this is, and ✕
            Item {
                width: parent.width
                height: 44
                Rectangle {
                    id: well
                    width: 44; height: 44; radius: 22
                    color: root.shownMode==="launch-failed" ? Qt.rgba(Theme.terracotta.r, Theme.terracotta.g, Theme.terracotta.b, 0.16) : Theme.overlay
                    Icon { anchors.centerIn: parent; size: 20; paths: root.glyph; color: root.shownMode==="launch-failed" ? Theme.terracotta : Theme.text }
                }
                Column {
                    anchors.left: well.right; anchors.leftMargin: 14
                    anchors.right: closeButton.left; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { width: parent.width; text: root.title; elide: Text.ElideMiddle; color: Theme.textBright; font.family: Theme.fontUi; font.pixelSize: 17; font.weight: Font.ExtraBold }
                    Text { width: parent.width; visible: text !== ""; text: root.detail; elide: Text.ElideMiddle; color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
                }
                IconButton { id: closeButton; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; icon: Icons.close; iconSize: 16; onClicked: root.close(); Accessible.name: "Close" }
            }

            Text { visible:LauncherTools.busy || !!LauncherTools.error; text:LauncherTools.error || "Reading…"; color:LauncherTools.error ? Theme.terracotta : Theme.subtext; width:parent.width; wrapMode:Text.Wrap; font.family:Theme.fontUi; font.pixelSize:13; font.weight: Font.Medium }

            // an app that couldn't start
            Column {
                width:parent.width; visible:root.shownMode==="launch-failed"; spacing:16
                Rectangle {
                    width: parent.width; height: failText.implicitHeight + 28; radius: Theme.tileRadius; color: Theme.bg; border.width: 1; border.color: Theme.overlay
                    Text { id: failText; x: 16; y: 14; width: parent.width - 32; text: LauncherTools.launchFailure.error ?? ""; wrapMode: Text.Wrap; color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 12 }
                }
                ActionButton { anchors.right: parent.right; text: "Try again"; icon: Icons.reboot; primary: true; onClicked: LauncherTools.retryLaunch() }
            }

            // a file's preview: what it is, then the picture or the text, then Open with
            Column {
                width:parent.width; visible:root.shownMode==="preview"; spacing:14
                Row {
                    spacing: 6
                    Repeater {
                        model: [root.preview.mime ?? "", root.bytes(root.preview.size), root.preview.modified ?? ""].filter(Boolean)
                        Rectangle {
                            required property string modelData
                            height: 26; width: metaText.implicitWidth + 22; radius: 13; color: Theme.overlay
                            Text { id: metaText; anchors.centerIn: parent; text: parent.modelData; color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 11; font.weight: Font.Bold; font.features: { "tnum": 1 } }
                        }
                    }
                }
                Rectangle {
                    width: parent.width
                    visible: root.preview.kind==="image" || root.preview.kind==="text"
                    height: root.preview.kind==="image" ? Math.min(460, Math.max(160, picture.sourceSize.width > 0 ? (width - 24) * picture.sourceSize.height / picture.sourceSize.width + 24 : 160)) : Math.min(440, textBody.implicitHeight + 32)
                    radius: Theme.tileRadius; color: Theme.bg; border.width: 1; border.color: Theme.overlay
                    clip: true
                    Image { id: picture; visible:root.preview.kind==="image"; anchors.fill: parent; anchors.margins: 12; source:visible ? root.preview.image ?? "" : ""; fillMode:Image.PreserveAspectFit; asynchronous:true; cache:false; smooth: true; mipmap: true }
                    Flickable {
                        id: textScroll
                        visible: root.preview.kind==="text"
                        anchors.fill: parent; anchors.margins: 16
                        clip: true; contentHeight: textBody.implicitHeight; boundsBehavior: Flickable.StopAtBounds
                        Basic.ScrollBar.vertical: Basic.ScrollBar {}
                        TextEdit { id: textBody; width: textScroll.width - 12; text:root.preview.text ?? ""; readOnly:true; selectByMouse:true; wrapMode:TextEdit.Wrap; textFormat:TextEdit.PlainText; color:Theme.text; selectionColor:Theme.pistachio; selectedTextColor:Theme.bg; font.family:Theme.fontMono; font.pixelSize:13 }
                    }
                }
                // nothing to show: a quiet card saying so
                Rectangle {
                    width: parent.width; height: 120; radius: Theme.tileRadius; color: Theme.bg; border.width: 1; border.color: Theme.overlay
                    visible: root.preview.kind==="metadata"
                    Column {
                        anchors.centerIn: parent; spacing: 8
                        Icon { anchors.horizontalCenter: parent.horizontalCenter; size: 24; paths: Icons.file; color: Theme.subtext }
                        Text { text: root.preview.note || "No preview for this kind of file."; color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 13; font.weight: Font.Medium }
                    }
                }
                Item {
                    width: parent.width; height: 40
                    Text { anchors.verticalCenter: parent.verticalCenter; visible: !!root.preview.truncated; text: "Showing the first 256 KB"; color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold }
                    ActionButton { anchors.right: parent.right; text: "Open with…"; icon: Icons.folderOpen; onClicked: LauncherTools.showFile(LauncherTools.path,"handlers") }
                }
            }

            // Open with: the apps for this type, and whether to remember the choice
            Column {
                width:parent.width; visible:root.shownMode==="handlers"; spacing:6
                Rectangle {
                    width: parent.width; height: 56; radius: Theme.tileRadius; color: Theme.overlay
                    Column {
                        x: 16; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 32 - rememberSwitch.width
                        Text { text: "Remember for this type"; color: Theme.text; font.family: Theme.fontUi; font.pixelSize: 13; font.weight: Font.Bold }
                        Text { width: parent.width; text: LauncherTools.mime ? `Makes it the default for ${LauncherTools.mime}` : ""; elide: Text.ElideRight; color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 11; font.weight: Font.DemiBold }
                    }
                    Switch { id: rememberSwitch; anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; checked: root.remember; onToggled: root.remember = !root.remember }
                }
                Item { width: 1; height: 6 }
                Text { visible: !LauncherTools.handlers.length; width:parent.width; text:"No applications are registered for this type of file."; wrapMode:Text.Wrap; color:Theme.subtext; font.family:Theme.fontUi; font.pixelSize:13 }
                Repeater {
                    model:LauncherTools.handlers
                    Rectangle {
                        required property var modelData
                        width: parent.width; height: 48; radius: 24
                        color: appMouse.containsMouse ? Theme.overlay : "transparent"
                        opacity: LauncherTools.busy ? 0.5 : 1
                        Behavior on color { ColorAnimation { duration: Theme.hoverDuration; easing.type: Theme.easing } }
                        Image { x: 14; anchors.verticalCenter: parent.verticalCenter; width: 24; height: 24; sourceSize: Qt.size(48, 48); source: Apps.iconFor(parent.modelData.id.replace(/\.desktop$/, "")) }
                        Text { x: 50; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 64; text: parent.modelData.name; elide: Text.ElideRight; color: Theme.text; font.family: Theme.fontUi; font.pixelSize: 13; font.weight: Font.Bold }
                        MouseArea { id: appMouse; anchors.fill: parent; enabled: !LauncherTools.busy; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: LauncherTools.openWith(parent.modelData.id,root.remember) }
                    }
                }
            }

            // background jobs, newest first
            Column {
                width:parent.width; visible:root.shownMode==="jobs"; spacing:10
                Rectangle {
                    visible: !root.jobs.length
                    width: parent.width; height: 140; radius: Theme.tileRadius; color: Theme.bg; border.width: 1; border.color: Theme.overlay
                    Column {
                        anchors.centerIn: parent; spacing: 8
                        Icon { anchors.horizontalCenter: parent.horizontalCenter; size: 24; paths: Icons.terminal; color: Theme.subtext }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "No background jobs"; color: Theme.text; font.family: Theme.fontUi; font.pixelSize: 14; font.weight: Font.Bold }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Shift+Enter on a $ command in the launcher runs it here."; color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 12; font.weight: Font.Medium }
                    }
                }
                Flickable {
                    id: jobScroll
                    visible: root.jobs.length > 0
                    width: parent.width
                    height: Math.min(jobList.implicitHeight, root.height - 140 - 48 - 44 - 18 - 24)
                    clip: true; contentHeight: jobList.implicitHeight; boundsBehavior: Flickable.StopAtBounds
                    Basic.ScrollBar.vertical: Basic.ScrollBar {}
                    Column {
                        id: jobList; width: jobScroll.width; spacing: 10
                        Repeater { model:root.jobs; JobCard { required property var modelData; width:parent.width; job:modelData } }
                    }
                }
            }
        }
    }
}
