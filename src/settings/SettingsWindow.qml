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
    onStatsWantedChanged: SystemStats.setWatching(statsWanted)
    onMinimizedChanged: if (minimized) Bluetooth.setScanning(false)
    readonly property alias dialog: settingsDialog
    property var results: Catalog.search(searchField.text, LocalSend.available, Cider.installed, Brightness.available)

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
            if (!SettingsHub.opened) { SettingsHub.cancelEdit(); SettingsHub.forgetDevice=null; Bluetooth.setScanning(false); if (Bluetooth.request) Bluetooth.answer(false,""); }
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
    ClippingRectangle {
        id: surface
        objectName: "settings-surface"
        anchors.fill: parent
        radius: Theme.panelRadius
        color: Theme.bgAlt
        border.width: 1; border.color: Theme.overlay2
        contentInsideBorder: true
        opacity: reveal.progress
        focus: true
        Keys.onEscapePressed: { if(searchField.text) searchField.text=""; else if (SettingsReset.reviewing) SettingsReset.cancel(); else SettingsHub.opened=false; }
        Shortcut { sequence:"Ctrl+F";enabled:SettingsHub.opened;onActivated:{searchField.forceActiveFocus();searchField.selectAll();} }
        Shortcut { sequence:"Ctrl+W";enabled:SettingsHub.opened;onActivated:SettingsHub.opened=false }
        Item {
            id: titlebar
            width: parent.width; height:64
            MouseArea { anchors.fill:parent;onPressed:root.startSystemMove();onDoubleClicked:root.maximized=!root.maximized }
            Rectangle { x:22;y:14;width:36;height:36;radius:18;color:Theme.overlay;Icon{anchors.centerIn:parent;size:18;paths:Icons.sliders;color:Theme.clay} }
            SettingsText { x:70;anchors.verticalCenter:parent.verticalCenter;text:"Settings";font.weight:Font.ExtraBold }
            Row {
                anchors.right:parent.right;anchors.rightMargin:16;anchors.verticalCenter:parent.verticalCenter;spacing:12
                Basic.TextField {
                    id:searchField
                    objectName:"settings-search"
                    width:270;height:44;leftPadding:40;rightPadding:text?44:62
                    placeholderText:"Find a setting…";placeholderTextColor:Theme.subtext;color:Theme.textBright
                    font.family:Theme.fontUi;font.pixelSize:12;font.weight:Font.DemiBold;selectByMouse:true
                    background:Rectangle{radius:22;color:Theme.bg;border.width:1;border.color:searchField.activeFocus?Theme.subtext:Theme.overlay2}
                    Icon{x:14;anchors.verticalCenter:parent.verticalCenter;size:16;paths:Icons.search;color:Theme.subtext}
                    SettingsText{visible:!searchField.text;anchors.right:parent.right;anchors.rightMargin:12;anchors.verticalCenter:parent.verticalCenter;text:"Ctrl F";secondary:true;font.pixelSize:10}
                    SettingsButton{visible:searchField.text!=="";anchors.right:parent.right;width:44;padding:0;quiet:true;glyph:Icons.close;onClicked:searchField.clear();Accessible.name:"Clear search"}
                    onAccepted:if(root.results.length)root.navigate(root.results[0][0],root.results[0][1])
                    Accessible.name:"Find a setting"
                }
                SettingsButton { width:44;padding:0;quiet:true;glyph:Icons.minus;onClicked:root.minimized=true;Accessible.name:"Minimise settings" }
                SettingsButton { width:44;padding:0;quiet:true;glyph:Icons.close;onClicked:SettingsHub.opened=false;Accessible.name:"Close settings" }
            }
            Rectangle { y:63;width:parent.width;height:1;color:Theme.overlay }
        }
        Item {
            id:sidebar
            x:0;y:64;width:216;height:parent.height-64
            Rectangle{anchors.right:parent.right;width:1;height:parent.height;color:Theme.overlay}
            Basic.ScrollView {
                x:12;y:18;width:192;height:parent.height-30;clip:true // all fifteen pages fit at 1040 × 760 (12 November 2026)
                contentWidth:availableWidth
                Column{
                    width:192;spacing:2
                    Repeater {
                        model:Catalog.pages.filter(p=>p[0]!=="localsend"||LocalSend.available)
                        Column{
                            required property var modelData
                            required property int index
                            width:192
                            readonly property bool first:index===0||Catalog.pages.filter(p=>p[0]!=="localsend"||LocalSend.available)[index-1][3]!==modelData[3]
                            Item { width:1;height:index>0&&parent.first?10:0 }
                            SettingsText{x:12;height:parent.first?22:0;visible:parent.first;text:modelData[3].toUpperCase();secondary:true;font.pixelSize:10;font.weight:Font.Bold;font.letterSpacing:0.6}
                            SettingsButton {
                                objectName:"settings-nav-"+modelData[0];width:192;height:36;text:modelData[1];active:!searchField.text.trim()&&SettingsHub.page===modelData[0];quiet:true;animateSelection:true
                                leftPadding:39;rightPadding:8
                                contentItem:Text{text:parent.text;font:parent.font;color:parent.active?Theme.bg:Theme.subtext;verticalAlignment:Text.AlignVCenter;elide:Text.ElideRight;Behavior on color { ColorAnimation { duration: Theme.hoverDuration; easing.type: Theme.easing } }}
                                Icon{x:12;anchors.verticalCenter:parent.verticalCenter;size:17;paths:Icons[modelData[4]]||Icons.sliders;color:parent.active?Theme.bg:Theme.subtext;Behavior on color { ColorAnimation { duration: Theme.hoverDuration; easing.type: Theme.easing } }}
                                onClicked:root.navigate(modelData[0],"")
                            }
                        }
                    }
                }
            }
        }
        Basic.ScrollView {
            id:scroller
            x:216;y:64;width:parent.width-216;height:parent.height-64
            clip:true
            contentWidth:availableWidth
            Flickable {
                id:scroll
                contentWidth:width;contentHeight:contents.height+48;boundsBehavior:Flickable.StopAtBounds
                Column {
                    id:contents
                    x:26;y:24;width:scroll.width-52;spacing:14
                    SettingsContent {
                        id:pageContent
                        objectName:"settings-page-content"
                        width:parent.width
                        visible:!searchField.text.trim()
                        active:SettingsHub.opened&&!root.minimized&&!searchField.text.trim()
                        onPageChanged: pageFade.restart()
                        NumberAnimation { id:pageFade; target:pageContent; property:"opacity"; from:0.65; to:1; duration:Theme.motionDuration; easing.type:Theme.easing }
                    }
                    Column {
                        visible:searchField.text.trim()!=="";width:parent.width;spacing:14
                        SettingsText{text:"Search results";font.pixelSize:18;font.weight:Font.ExtraBold}
                        SettingsText{width:parent.width;secondary:true;text:root.results.length?`${root.results.length} settings for “${searchField.text}”`:`No matches for “${searchField.text}”`}
                        Repeater {
                            model:root.results
                            SettingsButton{
                                required property var modelData
                                width:parent.width;height:80;text:modelData[2];card:true
                                contentItem:Item {
                                    Column { anchors.verticalCenter:parent.verticalCenter;width:parent.width-30;spacing:3;SettingsText{width:parent.width;text:modelData[2]}SettingsText{width:parent.width;secondary:true;font.pixelSize:11;text:Catalog.page(modelData[0])[1]+" · "+modelData[3]} }
                                    Icon { anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter;size:18;paths:Icons.chevronRight;color:Theme.subtext }
                                }
                                onClicked:root.navigate(modelData[0],modelData[1])
                            }
                        }
                        SettingsEmpty { visible:!root.results.length;width:parent.width;title:"No settings found";description:"Try sound, Bluetooth or Lens.";button:"Clear search";onActivated:searchField.clear() }
                    }
                }
            }
        }
        SettingsDialog { id:settingsDialog }
        MouseArea{anchors.right:parent.right;anchors.bottom:parent.bottom;width:12;height:12;cursorShape:Qt.SizeFDiagCursor;onPressed:root.startSystemResize(Qt.RightEdge|Qt.BottomEdge)}
    }
}
