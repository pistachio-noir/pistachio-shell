import qs
import qs.components
import qs.settings
import qs.services
import qs.panels // TuiLocalSendSending (a new sibling isn't found by implicit lookup on a live reload)
import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: root
    objectName: "tui-control"
    property bool open
    property string page
    property int selected: 0
    signal powerRequested
    signal launcherRequested(string mode)
    readonly property int side: 0
    readonly property int below: 0
    readonly property real panelWidth: Theme.tuiPanelWidth
    readonly property real panelHeight: control.height
    readonly property bool localShown: page==="localsend" && LocalSend.available
    visible:reveal.shown;focusable:true;exclusionMode:ExclusionMode.Ignore
    implicitWidth:localShown?Theme.tuiPanelWidth*2+24:Theme.tuiPanelWidth
    implicitHeight:Math.max(control.height,localShown?sharing.height:0)+10
    color:"transparent"
    WlrLayershell.namespace:"pistachio-panel"
    WlrLayershell.layer:WlrLayer.Overlay
    mask:Region { item:control; Region { x:0;y:10;width:root.localShown?sharing.width:0;height:root.localShown?sharing.height:0 } }
    Reveal { id:reveal;open:root.open }
    Timer { id:brightnessLater;interval:Theme.motionDuration+60;onTriggered:Brightness.refresh() }
    onOpenChanged: {
        if(open){brightnessLater.restart();if(LocalSend.sendRunning)page="localsend";Qt.callLater(()=>body.forceActiveFocus());}
        else page="";
    }
    onLocalShownChanged: if(localShown) {
        if(!LocalSend.sendRunning)LocalSend.scan();
        Qt.callLater(()=>selected=Math.max(0,rows.findIndex(r=>r.id==="localsend")));
    }
    onPageChanged: {selected=0;if(open)Qt.callLater(()=>body.forceActiveFocus());}
    onRowsChanged: selected=Math.max(0,Math.min(selected,rows.length-1))
    function addUrls(urls) { LocalSend.add(urls.map(u=>decodeURIComponent(u.toString().replace(/^file:\/\//,"")))); }
    function settings(section) { open=false;SettingsHub.openPage(section,""); }
    function adjust(direction) {
        const row=rows[selected];if(row?.kind==="level")row.adjust(Math.max(row.from??0,Math.min(row.to??1,row.value()+direction*((row.to??1)-(row.from??0))/20)));
    }
    readonly property var rows: {
        // the outputs (right-click vol, or Output): the current one checked, Enter or a click moves the sound there
        if(page==="output") return Audio.sinks.map(n=>({id:"output-"+n.id,kind:"toggle",text:Audio.deviceName(n),checked:()=>Audio.sink?.id===n.id,detail:()=>Audio.isUnplugged(n)?"nothing plugged in":Audio.sink?.id===n.id?"current":"",run:()=>{if(!Audio.isUnplugged(n))Audio.setSink(n);},more:()=>root.settings("sound")}));
        if(page==="mixer") return Audio.streams.map(n=>({id:"stream-"+n.id,kind:"level",text:Audio.appName(n),value:()=>n.audio?.volume??0,muted:()=>n.audio?.muted??false,run:()=>Audio.toggleStreamMute(n),adjust:v=>Audio.setStreamVolume(n,v)}));
        const out=[{id:"volume",kind:"level",text:"vol",value:()=>Audio.volume,muted:()=>Audio.muted,run:()=>Audio.toggleMute(),adjust:v=>Audio.setVolume(v),more:()=>root.page="output"}];
        if(Audio.source)out.push({id:"microphone",kind:"level",text:"mic",value:()=>Audio.micVolume,muted:()=>Audio.micMuted,run:()=>Audio.toggleMicMute(),adjust:v=>Audio.setMicVolume(v)});
        if(Brightness.available)out.push({id:"brightness",kind:"level",text:"light",value:()=>Brightness.value,run:()=>root.settings("display"),adjust:v=>Brightness.set(v)});
        if(NightLight.enabled)out.push({id:"warmth",kind:"level",text:"warm",from:2500,to:6500,value:()=>NightLight.temperature,format:v=>Math.round(v)+"K",run:()=>root.settings("display"),adjust:v=>NightLight.setTemperature(Math.round(v/50)*50)});
        out.push({id:"ethernet",kind:"toggle",text:"ethernet",checked:()=>Network.connected,detail:()=>Network.connected?"connected · "+(Network.speed>=1000?Network.speed/1000+" Gb/s":Network.speed+" Mb/s"):Network.hasLink?"connecting":"unplugged",run:()=>Network.setEnabled(!Network.connected),more:()=>root.settings("network")});
        out.push({id:"bluetooth",kind:"toggle",text:"bluetooth",checked:()=>Bluetooth.enabled,detail:()=>Bluetooth.connectedName||Bluetooth.summary,run:()=>Bluetooth.setEnabled(!Bluetooth.enabled),more:()=>root.settings("bluetooth")});
        out.push({id:"dnd",kind:"toggle",text:"do not disturb",checked:()=>Notifs.dnd,run:()=>Notifs.setDnd(!Notifs.dnd),more:()=>root.settings("notifications")});
        out.push({id:"night",kind:"toggle",text:"night light",checked:()=>NightLight.enabled,run:()=>NightLight.setEnabled(!NightLight.enabled),more:()=>root.settings("display")});
        if(LocalSend.available)out.push({id:"localsend",kind:"toggle",text:"localsend",checked:()=>LocalSend.wanted,detail:()=>LocalSend.receiving?'visible as “'+LocalSend.name+'”':LocalSend.summary,run:()=>root.page=root.page==="localsend"?"":"localsend",more:()=>root.settings("localsend")});
        if(ShellSettings.quickChatTile)out.push({id:"chat",kind:"action",text:"quick chat",detail:()=>Chat.providerName,run:()=>{root.open=false;Chat.show("");}});
        return out;
    }
    PanelFrame {
        id:control;x:root.width-width;y:10;width:Theme.tuiPanelWidth
        height:Math.min(body.implicitHeight+28,root.screen.height-Theme.tuiBarHeight-Theme.tuiPanelGap-20)
        active:!root.localShown
        title:root.page==="mixer"?"mixer":root.page==="output"?"output":"control";detail:LocalSend.name
        color:Theme.glass(Theme.bg);opacity:reveal.progress
        Flickable {
            anchors.fill:parent;anchors.margins:12;contentWidth:width;contentHeight:body.implicitHeight;clip:true;boundsBehavior:Flickable.StopAtBounds
            Column {
                id:body;width:parent.width;spacing:4;focus:true
                Keys.onEscapePressed:{if(root.page)root.page="";else if(Showoff.active)Showoff.stop();else root.open=false;}
                Keys.onUpPressed:root.selected=Math.max(0,root.selected-1)
                Keys.onDownPressed:root.selected=Math.min(root.rows.length-1,root.selected+1)
                Keys.onLeftPressed:root.adjust(-1)
                Keys.onRightPressed:root.adjust(1)
                Keys.onSpacePressed:if(root.rows[root.selected])root.rows[root.selected].run()
                Keys.onReturnPressed:if(root.rows[root.selected])root.rows[root.selected].run()
                Repeater {
                    model:root.rows
                    Column {
                        required property var modelData
                        required property int index
                        width:body.width
                        readonly property bool divides: index>0 && root.rows[index-1].kind==="level" && modelData.kind!=="level"
                        Rectangle { visible:parent.divides;width:parent.width;height:1;color:Theme.tuiBorder }
                        Item { visible:parent.divides;width:1;height:12 }
                    TuiControlRow {
                        objectName:"control-"+modelData.id;width:parent.width
                        text:modelData.text;kind:modelData.kind
                        detail:modelData.detail?modelData.detail():""
                        checked:modelData.checked?modelData.checked():false
                        selected:root.selected===index
                        value:modelData.value?modelData.value():0
                        from:modelData.from??0;to:modelData.to??1
                        muted:modelData.muted?modelData.muted():false
                        format:modelData.format??(v=>Math.round(v*100)+"%")
                        onPicked:root.selected=index
                        onActivated:modelData.run()
                        onAlternate:if(modelData.more)modelData.more()
                        onMoved:value=>modelData.adjust(value)
                    }
                    }
                }
                SettingsText { visible:root.page==="mixer"&&!root.rows.length;width:parent.width;text:"No applications playing audio.";secondary:true }
                Rectangle { width:parent.width;height:1;color:Theme.tuiBorder }
                SettingsText { text:"up "+Math.floor(Uptime.seconds/3600)+"h "+Math.floor(Uptime.seconds/60)%60+"m";secondary:true }
                Flow {
                    width:parent.width;spacing:4
                    SettingsButton { text:"Settings";onClicked:root.settings("appearance") }
                    SettingsButton { text:root.page==="mixer"||root.page==="output"?"Back":"Mixer";onClicked:root.page=root.page?"":"mixer" }
                    SettingsButton { visible:root.page==="";text:"Output";onClicked:root.page="output" }
                    SettingsButton { text:"Launcher";onClicked:root.launcherRequested("all") }
                    SettingsButton { text:"Power";danger:true;onClicked:root.powerRequested() }
                }
                SettingsText { text:"↑↓ move  Space toggle  Esc close";secondary:true }
            }
        }
    }
    DropArea {
        objectName:"localsend-drop"
        x:sharing.x;y:sharing.y;width:sharing.width;height:sharing.height
        enabled:root.localShown&&!LocalSend.sendRunning
        keys:["text/uri-list"]
        onDropped:event=>root.addUrls(event.urls)
    }
    PanelFrame {
        id:sharing;visible:root.localShown;x:0;y:10;width:Theme.tuiPanelWidth
        height:Math.min(localBody.implicitHeight+28,root.screen.height-Theme.tuiBarHeight-Theme.tuiPanelGap-20)
        active:root.localShown;title:"localsend";detail:LocalSend.send!==null?(LocalSend.sendRunning?"sending":LocalSend.send.state==="done"?"sent":"not sent"):LocalSend.devices.length+" nearby";color:Theme.glass(Theme.bg);opacity:reveal.progress
        Flickable {
            anchors.fill:parent;anchors.margins:12;contentWidth:width;contentHeight:localBody.implicitHeight;clip:true;boundsBehavior:Flickable.StopAtBounds
            Column {
                id:localBody;width:parent.width;spacing:8
                readonly property bool idle: LocalSend.send===null
                SettingsText { visible:localBody.idle;width:parent.width;text:"visible as "+LocalSend.name;secondary:true }
                TuiControlRow { visible:localBody.idle;width:parent.width;kind:"toggle";text:"receive files";checked:LocalSend.wanted;detail:LocalSend.busy?"port in use":"only while this is on";onActivated:LocalSend.setReceive(!LocalSend.wanted) }
                Rectangle { visible:localBody.idle;width:parent.width;height:1;color:Theme.tuiBorder }
                SettingsText { visible:localBody.idle;text:LocalSend.scanning?"looking for devices…":"nearby devices";secondary:true }
                Repeater {
                    model:localBody.idle?LocalSend.devices:[]
                    TuiControlRow {
                        required property var modelData
                        width:parent.width;kind:"action";text:modelData.alias;detail:"send files";enabled:LocalSend.items.length>0&&!LocalSend.sendRunning
                        onActivated:LocalSend.sendTo(modelData)
                    }
                }
                SettingsText { visible:localBody.idle&&!LocalSend.devices.length;width:parent.width;text:"No devices found yet.";secondary:true }
                SettingsText { visible:localBody.idle&&LocalSend.items.length>0;width:parent.width;text:LocalSend.items.length+" items ready · "+LocalSend.size(LocalSend.itemsSize);secondary:true }
                Flow {
                    visible:localBody.idle;width:parent.width;spacing:4
                    SettingsButton { text:"Send files…";onClicked:LocalSend.pickFiles(false) }
                    SettingsButton { text:"Folder";onClicked:LocalSend.pickFiles(true) }
                    SettingsButton { text:"Paste";onClicked:LocalSend.paste() }
                    SettingsButton { text:"Clear";visible:LocalSend.items.length>0;onClicked:LocalSend.clear() }
                    SettingsButton { text:"Settings";onClicked:root.settings("localsend") }
                }
                // a transfer out (board LocalSendSending): it takes the panel's place while there is one
                TuiLocalSendSending { visible:LocalSend.send!==null;width:parent.width }
            }
        }
    }
}
