import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls.Basic as Basic
import "catalog.js" as Catalog

// A normal, resizable desktop window. No exclusive layer-shell keyboard grab.
FloatingWindow {
    id: root
    title: "Pistachio Settings"
    implicitWidth: Theme.settingsWidth
    implicitHeight: Theme.settingsHeight
    minimumSize: Qt.size(900, 620)
    color: "transparent"
    visible: reveal.shown
    onClosed: SettingsHub.opened = false
    onWindowConnected: {
        const window = contentItem.Window.window;
        if (window) window.flags = Qt.Window | Qt.FramelessWindowHint;
    }
    Reveal { id: reveal; open: SettingsHub.opened }
    readonly property bool statsWanted: SettingsHub.opened && !minimized && SettingsHub.page === "system" && searchField.text.trim() === ""
    onStatsWantedChanged: SystemStats.setWatching(Theme.tui || statsWanted)
    Connections { target:Theme;function onTuiChanged(){SystemStats.setWatching(Theme.tui || root.statsWanted);} }
    Component.onCompleted: SystemStats.setWatching(Theme.tui || statsWanted)
    onMinimizedChanged: if (minimized) Bluetooth.setScanning(false)
    property int aboutPresses
    property bool funAbout
    readonly property alias dialog: settingsDialog
    property var results: Catalog.search(searchField.text, LocalSend.available, Cider.installed, Brightness.available, Theme.tui)

    function resultSpec(result) {
        const groups = pageContent.buildGroups(result[0]);
        let row = null;
        for (const group of groups || []) {
            row = group.rows.find(r => r.id === result[1]);
            if (row) break;
        }
        const subtitle = () => Catalog.page(result[0])[1] + " › " + result[3];
        if (row && (row.kind === "toggle" || row.kind === "slider" || row.kind === "audio"))
            return Object.assign({}, row, {kind: row.kind === "audio" ? "slider" : row.kind, title:result[2], mute:undefined, subtitle: subtitle});
        return {id:result[1],kind:"action",title:result[2],subtitle:subtitle,button:"Open",run:()=>root.navigate(result[0],result[1])};
    }

    function showPage(page: string, control: string) {
        const valid = Catalog.pages.some(p => p[0] === page) && (page !== "localsend" || LocalSend.available);
        SettingsHub.openPage(valid ? page : "appearance", control || "");
    }
    function navigate(page: string, control: string) {
        searchField.text = "";
        showPage(page, control);
        Qt.callLater(scrollToTarget);
    }
    function findControl(item, id) {
        if (item.objectName === "setting-"+id) return item;
        for (const child of item.children) { const found = findControl(child,id); if(found) return found; }
        return null;
    }
    function scrollToTarget() {
        const target = SettingsHub.target ? findControl(pageContent,SettingsHub.target) : null;
        scroll.contentY = target ? Math.max(0,Math.min(scroll.contentHeight-scroll.height,target.mapToItem(scroll.contentItem,0,0).y-16)) : 0;
    }
    Connections {
        target: SettingsHub
        function onPresent() {
            root.minimized = false;
            searchField.text = "";
            if (SettingsHub.page === "about") About.load();
            focusLater.restart();
            Qt.callLater(root.scrollToTarget);
        }
        function onOpenedChanged() {
            if (!SettingsHub.opened) { root.aboutPresses=0; root.funAbout=false; SettingsHub.cancelEdit(); SettingsHub.forgetDevice=null; SettingsHub.restartMode=""; Bluetooth.setScanning(false); if (Bluetooth.request) Bluetooth.answer(false,""); }
        }
    }
    Timer { id: focusLater; interval: Theme.motionDuration + 40; onTriggered: if (SettingsHub.opened) root.contentItem.Window.window?.requestActivate() }
    Connections { target: Bluetooth; function onAsked() { root.showPage("bluetooth", ""); } }
    Connections { target: Session; function onLockedChanged() { if(Session.locked) SettingsHub.opened=false; } }
    IpcHandler {
        target: "settings"
        function open(): void { root.showPage(SettingsHub.page, ""); }
        function toggle(): void { if(SettingsHub.opened && !root.minimized) SettingsHub.opened=false; else root.showPage(SettingsHub.page, ""); }
        function close(): void { SettingsHub.opened=false; }
        function section(name: string): void { root.showPage(name, ""); }
        function search(text: string): void { root.showPage(SettingsHub.page, ""); searchField.text=text; searchField.forceActiveFocus(); }
        function status(): string { return JSON.stringify({open:SettingsHub.opened,page:SettingsHub.page,minimized:root.minimized,search:searchField.text,results:root.results.length,scanning:Bluetooth.scanning,watching:SystemStats.watching}); }
    }
    Rectangle {
        objectName: "settings-title-backing"
        visible: Theme.tui
        width: parent.width
        height: surface.y
        color: surface.color
        opacity: reveal.progress
    }
    Rectangle {
        visible: Theme.tui
        x: 8; y: 0; width: frameTitle.implicitWidth+16; height:20; z:2; color:Theme.pistachio
        SettingsText { id:frameTitle;anchors.centerIn:parent;text:"settings";color:Theme.bg }
    }
    Rectangle {
        visible: Theme.tui
        anchors.right:parent.right;anchors.rightMargin:8;y:0;width:frameDetail.implicitWidth+16;height:20;z:2;color:Theme.bg
        SettingsText { id:frameDetail;anchors.centerIn:parent;text:searchField.text.trim()?"search":Catalog.page(SettingsHub.page)[1].toLowerCase();secondary:true }
    }
    ClippingRectangle {
        id: surface
        objectName: "settings-surface"
        anchors.fill: parent
        anchors.topMargin: Theme.tui ? 10 : 0
        radius: Theme.tui ? 0 : (Theme.panelRadius)
        color: Theme.tui ? Theme.bg : Theme.bgAlt
        border.width: 1; border.color: Theme.overlay2
        contentInsideBorder: true
        opacity: reveal.progress
        focus: true
        Keys.onEscapePressed: { if(searchField.text) searchField.text=""; else if (SettingsReset.reviewing) SettingsReset.cancel(); else SettingsHub.opened=false; }
        Shortcut { sequence:"Ctrl+F";enabled:SettingsHub.opened;onActivated:{searchField.forceActiveFocus();searchField.selectAll();} }
        Shortcut { sequence:"Ctrl+W";enabled:SettingsHub.opened;onActivated:SettingsHub.opened=false }
        Item {
            id: titlebar
            objectName: "settings-header"
            width: parent.width; height: Theme.tui ? Theme.tuiHeaderHeight : 64
            MouseArea { anchors.fill:parent;onPressed:root.startSystemMove();onDoubleClicked:root.maximized=!root.maximized }
            Rectangle { visible: !Theme.tui; x:22;y:14;width:36;height:36;radius: Theme.tui ? 0 : (18);color:Theme.overlay;Icon{anchors.centerIn:parent;size:18;paths:Icons.sliders;color:Theme.clay} }
            SettingsText { visible: !Theme.tui; x:70;anchors.verticalCenter:parent.verticalCenter;text:"Settings";font.weight:Font.ExtraBold }
            Row {
                id: headerActions
                anchors.right:parent.right;anchors.rightMargin:16;anchors.verticalCenter:parent.verticalCenter;spacing:12
                Basic.TextField {
                    id:searchField
                    parent: titlebar
                    x: Theme.tui ? (titlebar.width - width) / 2 : headerActions.x - width - headerActions.spacing
                    y: (titlebar.height - height) / 2
                    objectName:"settings-search"
                    width: Theme.tui ? Math.min(440, titlebar.width - 160) : 270;height: Theme.tui ? 36 : 44;leftPadding: Theme.tui ? 28 : 40;rightPadding:text?44:62
                    placeholderText:"Find a setting…";placeholderTextColor:Theme.subtext;color:Theme.textBright
                    font.family:Theme.fontUi;font.pixelSize: Theme.tui ? Theme.tuiTextSize : 12;font.weight:Font.DemiBold;selectByMouse:true
                    background:Rectangle{radius: Theme.tui ? 0 : (22);color:Theme.bg;border.width:1;border.color:searchField.activeFocus?Theme.subtext:Theme.overlay2}
                    Text{visible:Theme.tui;x:10;anchors.verticalCenter:parent.verticalCenter;text:"/";color:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize}
                    Icon{visible:!Theme.tui;x:14;anchors.verticalCenter:parent.verticalCenter;size:16;paths:Icons.search;color:Theme.subtext}
                    SettingsText{visible:!searchField.text;anchors.right:parent.right;anchors.rightMargin:12;anchors.verticalCenter:parent.verticalCenter;text:Theme.tui?"Ctrl+F":"Ctrl F";secondary:true;font.pixelSize: Theme.tui ? Theme.tuiTextSize : 10}
                    SettingsButton{visible:searchField.text!=="";anchors.right:parent.right;width:44;padding:0;quiet:true;glyph:Icons.close;onClicked:searchField.clear();Accessible.name:"Clear search"}
                    onAccepted:if(root.results.length)root.navigate(root.results[0][0],root.results[0][1])
                    Accessible.name:"Find a setting"
                }
                SettingsButton { width:44;padding:0;quiet:true;text:Theme.tui?"[x]":"";glyph:Theme.tui?[]:Icons.close;onClicked:SettingsHub.opened=false;Accessible.name:"Close settings" }
            }
            Rectangle { y:parent.height-1;width:parent.width;height:1;color:Theme.overlay }
        }
        Item {
            id:sidebar
            objectName: "settings-sidebar"
            x:0;y:titlebar.height;width:Theme.tui?Theme.tuiSidebarWidth:216;height:parent.height-titlebar.height-(Theme.tui?30:0)
            Rectangle{anchors.right:parent.right;width:1;height:parent.height;color:Theme.overlay}
            Basic.ScrollView {
                x:Theme.tui?0:12;y:Theme.tui?12:18;width:Theme.tui?224:192;height:parent.height-(Theme.tui?24:30);clip:true // all fifteen pages fit at 1040 × 760 (12 November 2026)
                contentWidth:availableWidth
                Column{
                    width:Theme.tui?224:192;spacing:Theme.tui?0:2
                    Repeater {
                        model:Catalog.pages.filter(p=>p[0]!=="localsend"||LocalSend.available)
                        Column{
                            required property var modelData
                            required property int index
                            width:Theme.tui?224:192
                            readonly property bool first:index===0||Catalog.pages.filter(p=>p[0]!=="localsend"||LocalSend.available)[index-1][3]!==modelData[3]
                            Item { width:1;height:index>0&&parent.first?10:0 }
                            SettingsText{x:Theme.tui?16:12;height:parent.first?22:0;visible:parent.first;text:Theme.tui?modelData[3].toLowerCase():modelData[3].toUpperCase();secondary:true;font.pixelSize: Theme.tui ? Theme.tuiTextSize : 10;font.weight:Font.Bold;font.letterSpacing:0.6}
                            SettingsButton {
                                objectName:"settings-nav-"+modelData[0];width:Theme.tui?224:192;height:Theme.tui?40:36;text:modelData[1];active:!searchField.text.trim()&&SettingsHub.page===modelData[0];quiet:true;animateSelection:true
                                leftPadding:navIcon.x+navIcon.width+10;rightPadding:8
                                contentItem:Text{text:parent.text;font:parent.font;color:parent.active?Theme.bg:Theme.subtext;verticalAlignment:Text.AlignVCenter;elide:Text.ElideRight;Behavior on color { ColorAnimation { duration: Theme.hoverDuration; easing.type: Theme.easing } }}
                                Icon{id:navIcon;x:Theme.tui?16:12;anchors.verticalCenter:parent.verticalCenter;size:17;paths:Icons[modelData[4]]||Icons.sliders;color:parent.active?Theme.bg:Theme.subtext;Behavior on color { ColorAnimation { duration: Theme.hoverDuration; easing.type: Theme.easing } }}
                                onClicked:{ if(modelData[0]==="about" && !root.funAbout && ++root.aboutPresses>=10) root.funAbout=true; root.navigate(modelData[0],""); }
                            }
                        }
                    }
                }
            }
        }
        Basic.ScrollView {
            id:scroller
            x:sidebar.width;y:titlebar.height;width:parent.width-sidebar.width;height:parent.height-titlebar.height-(Theme.tui?30:0)
            clip:true
            contentWidth:availableWidth
            Flickable {
                id:scroll
                contentWidth:width;contentHeight:contents.height+48;boundsBehavior:Flickable.StopAtBounds
                Column {
                    id:contents
                    x:Theme.tui?24:26;y:Theme.tui?16:24;width:scroll.width-(Theme.tui?48:52);spacing:Theme.tui?8:14
                    SettingsContent {
                        id:pageContent
                        funAbout:root.funAbout
                        objectName:"settings-page-content"
                        width:parent.width
                        visible:!searchField.text.trim()
                        active:SettingsHub.opened&&!root.minimized&&!searchField.text.trim()
                        onPageChanged: pageFade.restart()
                        NumberAnimation { id:pageFade; target:pageContent; property:"opacity"; from:Theme.tui?0:0.65; to:1; duration:Theme.motionDuration; easing.type:Theme.easing }
                    }
                    Column {
                        visible:searchField.text.trim()!=="";width:parent.width;spacing:14
                        SettingsText{text:"Search results";font.pixelSize: Theme.tui ? Theme.tuiTextSize : 18;font.weight:Font.ExtraBold}
                        SettingsText{width:parent.width;secondary:true;text:root.results.length?`${root.results.length} settings for “${searchField.text}”`:`No matches for “${searchField.text}”`}
                        Repeater {
                            model:Theme.tui ? [] : root.results
                            SettingsButton{
                                required property var modelData
                                width:parent.width;height:80;text:modelData[2];card:true
                                contentItem:Item {
                                    Column { anchors.verticalCenter:parent.verticalCenter;width:parent.width-30;spacing:3;SettingsText{width:parent.width;text:modelData[2]}SettingsText{width:parent.width;secondary:true;font.pixelSize: Theme.tui ? Theme.tuiTextSize : 11;text:Catalog.page(modelData[0])[1]+" · "+modelData[3]} }
                                    Icon { anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter;size:18;paths:Icons.chevronRight;color:Theme.subtext }
                                }
                                onClicked:root.navigate(modelData[0],modelData[1])
                            }
                        }
                        Repeater {
                            model: Theme.tui ? root.results : []
                            SettingsRow {
                                required property var modelData
                                width: parent.width
                                spec: root.resultSpec(modelData)
                            }
                        }
                        SettingsEmpty { visible:!root.results.length;width:parent.width;title:"No settings found";description:"Try sound, Bluetooth or Lens.";button:"Clear search";onActivated:searchField.clear() }
                    }
                }
            }
        }
        Rectangle {
            visible: Theme.tui
            anchors.bottom: parent.bottom
            width: parent.width; height: 30; color: Theme.bgAlt
            Rectangle { width:parent.width;height:1;color:Theme.tuiBorder }
            SettingsText { x:12;anchors.verticalCenter:parent.verticalCenter;text:"Tab next  Space toggle  Ctrl+F search  Esc close";secondary:true }
            SettingsText { anchors.right:parent.right;anchors.rightMargin:12;anchors.verticalCenter:parent.verticalCenter;text:"psc settings open";secondary:true }
        }
        SettingsDialog { id:settingsDialog }
        MouseArea{anchors.right:parent.right;anchors.bottom:parent.bottom;width:12;height:12;cursorShape:Qt.SizeFDiagCursor;onPressed:root.startSystemResize(Qt.RightEdge|Qt.BottomEdge)}
    }
}
