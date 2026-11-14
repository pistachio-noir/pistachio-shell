import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: root
    objectName: "tui-bar"
    required property var controller
    // Hidden in Zen, over a fullscreen window and under the Overview (owner's bug report, 13 November
    // 2026, reversing "always shown"): no reserved space, and a 2 px strip along the top edge brings it
    // back over the window until the pointer leaves; it stays while one of its panels or menus is open.
    readonly property bool hiding: Compositor.fullscreen || FocusMode.zen || (controller.overviewOpen ?? false)
    property bool revealed
    readonly property bool panelsOpen: (controller.controls?.open ?? false) || (controller.centre?.open ?? false) || workspaceMenu.open || trayMenu.open || mediaWindow.open
    readonly property bool shown: !hiding || revealed || panelsOpen
    property real progress: shown ? 1 : 0
    Behavior on progress { NumberAnimation { duration: Theme.motionDuration; easing.type: Theme.easing } }
    onHidingChanged: if (hiding) revealed = false
    function startIntro() {}
    function endIntro() {}
    function peek() { revealed = true; leave.interval = 2000; leave.restart(); }
    anchors { top:true;left:true;right:true }
    implicitHeight: Theme.tuiBarHeight
    exclusiveZone: hiding ? 0 : Theme.tuiBarHeight
    color: "transparent"
    mask: Region { width: root.width; height: root.shown ? root.height : 2 }
    Timer { id:leave;interval:400;onTriggered:if(!edge.hovered)root.revealed=false }
    // the edge strip and the bar itself: hovering either keeps it out
    Item {
        anchors.fill:parent
        HoverHandler {
            id:edge
            onHoveredChanged:{ if(hovered){ if(root.hiding)root.revealed=true; leave.stop(); } else { leave.interval=400; leave.restart(); } }
        }
    }
    Binding { target:root.contentItem;property:"opacity";value:root.progress }
    // It fades rather than slides (owner's report, 14 November 2026): content moving under a still
    // pointer made Qt report it leaving, so the revealed bar hid again at once and looped
    Rectangle { anchors.fill:parent;color:Theme.surface }
    WlrLayershell.namespace: "pistachio-bar"
    WlrLayershell.layer: WlrLayer.Overlay
    readonly property var workspaceIds: Array.from(new Set([1,2,3,4,5].concat(Compositor.workspaces.filter(w=>w.id>5).map(w=>w.id)))).sort((a,b)=>a-b)
    SystemClock { id:clock;precision:SystemClock.Minutes }
    Rectangle { anchors.bottom:parent.bottom;width:parent.width;height:1;color:Theme.tuiBorder }
    Row {
        id:spaces
        Repeater {
            model:root.workspaceIds
            TuiBarButton {
                required property int modelData
                readonly property var ws:Compositor.workspaces.find(w=>w.id===modelData)
                width:Theme.tuiBarCell;padding:0;centered:true
                text:"";value:ws?.occupied || modelData===Compositor.activeWorkspace ? String(modelData) : "·"
                active:modelData===Compositor.activeWorkspace
                Accessible.name:"Workspace "+modelData
                onClicked:button=>{if(button===Qt.RightButton){workspaceMenu.kind="workspace";workspaceMenu.at=mapToItem(null,width/2,0).x;workspaceMenu.open=true;}else Compositor.goto(modelData);}
                onScrolled:delta=>Compositor.goto(Math.max(1,Compositor.activeWorkspace+(delta<0?1:-1)))
            }
        }
        TuiBarButton {
            text:Compositor.isTabbed(Compositor.activeWorkspace)?"[tabs]":"[]="
            Accessible.name:"Workspace layout and menu"
            onClicked:button=>{workspaceMenu.at=spaces.width;workspaceMenu.kind="workspace";workspaceMenu.open=true;}
        }
    }
    TuiBarButton {
        x:spaces.width;maximumWidth:Math.max(0,date.x-spaces.width-8)
        // while the Overview is open, it names itself (Overview boards: "overview — workspace 3")
        readonly property var wallpapers:root.controller.wallpaperSwitcher?.open?root.controller.wallpaperSwitcher:null
        text:root.controller.overviewOpen?"overview":wallpapers?"wallpapers":Chat.open?(Chat.both?"claude + chatgpt":Chat.providerName.toLowerCase()):""
        value:Chat.open&&!root.controller.overviewOpen&&!wallpapers?(Chat.view==="history"?"— recent chats":"— quick chat"):wallpapers?"— "+(wallpapers.images.length===0?"empty":wallpapers.chosen?.name??""):root.controller.overviewOpen?"— workspace "+Compositor.activeWorkspace+(Compositor.nameOf(Compositor.activeWorkspace)?" "+Compositor.nameOf(Compositor.activeWorkspace):"")
            :(Showoff.active?Compositor.focusedWindow?.appId:Compositor.focusedWindow?.title)??""
        Accessible.name:"Focused window. Open launcher"
        onClicked:button=>{if(button===Qt.RightButton){workspaceMenu.at=x;workspaceMenu.kind="workspace";workspaceMenu.open=true;}else root.controller.launcherRequested("windows");}
    }
    TuiBarButton {
        id:date
        x:Math.max(spaces.width+8,Math.min((root.width-width)/2,status.x-width-8))
        text:Qt.formatDate(clock.date,"ddd d MMM");value:Qt.formatTime(clock.date,"hh:mm")
        active:root.controller.centre?.open??false
        onClicked:button=>{if(button===Qt.RightButton){workspaceMenu.at=x+width/2;workspaceMenu.kind="clock";workspaceMenu.open=true;}else root.controller.toggleCentre(true);}
    }
    Row {
        id:status;anchors.right:parent.right
        TuiBarButton {
            id:mediaButton
            visible:!!Media.player?.trackTitle && maximumWidth>=48
            maximumWidth:Math.max(0,Math.min(144,root.width/2-date.width/2-fixedStatus.width-8))
            text:Media.player?.isPlaying?"▶":"Ⅱ";value:Media.player?.trackTitle??"";tint:Theme.teal
            Accessible.name:"Media. "+value
            onClicked:button=>{if(button===Qt.MiddleButton)Media.togglePlaying();else mediaWindow.open=!mediaWindow.open;}
            onScrolled:delta=>delta>0?Media.previous():Media.next()
        }
        Row {
            id:fixedStatus
            Row { id:essentials
            TuiBarButton { objectName:"tui-cpu";text:"cpu";value:SystemStats.cpu<0?"—":Math.round(SystemStats.cpu*100)+"%";tint:Theme.clay;onClicked:{SettingsHub.openPage("system","");} }
            TuiBarButton { objectName:"tui-mem";text:"mem";value:SystemStats.memUsed.toFixed(1)+"G";tint:Theme.gold;onClicked:{SettingsHub.openPage("system","");} }
            TuiBarButton { text:"vol";value:Audio.muted?"muted":Math.round(Audio.volume*100)+"%";tint:Theme.lavender;active:root.controller.controls?.open??false;onClicked:button=>{if(button===Qt.MiddleButton)Audio.toggleMute();else root.controller.toggle(root.controller.controls);};onScrolled:delta=>Audio.setVolume(Math.max(0,Math.min(1,Audio.volume+(delta>0?0.05:-0.05)))) }
            TuiBarButton { objectName:"tui-bluetooth";text:"bt";value:Bluetooth.enabled?(Bluetooth.battery>=0?Bluetooth.battery+"%":Bluetooth.connectedName?"on":"idle"):"off";tint:Theme.sageBlue;Accessible.name:"Bluetooth settings";onClicked:SettingsHub.openPage("bluetooth","") }
            TuiBarButton { objectName:"tui-mic-cue";visible:Audio.micMuted||Audio.recorders.length>0;text:"mic";value:Audio.micMuted?"muted":"in use";tint:Theme.clay;Accessible.name:Audio.micMuted?"Microphone muted":"Microphone in use by "+Audio.recorders.map(n=>Audio.appName(n)).join(", ");onClicked:root.controller.toggle(root.controller.controls) }
            TuiBarButton { objectName:"tui-share-cue";visible:ScreenShare.sharing;text:"share";value:String(ScreenShare.apps.length);tint:Theme.clay;Accessible.name:"Screen shared with "+ScreenShare.apps.join(", ");onClicked:root.controller.toggle(root.controller.controls) }
            TuiBarButton { text:"bell";value:Notifs.dnd?"dnd":String(Notifs.unreadCount);onClicked:root.controller.toggleCentre(false) }
            }
            Flickable {
                objectName:"tui-bar-extras"
                width:Math.min(extraItems.implicitWidth,Math.max(40,root.width-spaces.width-date.implicitWidth-essentials.width-32))
                height:Theme.tuiBarCell;contentWidth:extraItems.implicitWidth
                clip:true;flickableDirection:Flickable.HorizontalFlick;boundsBehavior:Flickable.StopAtBounds
                Row { id:extraItems
            // one arrow (owner's call): collapsed by default, showing how many it holds; open, the tray
            // icons and the minimised windows as two groups
            TuiBarButton {
                objectName:"tui-tray-arrow"
                readonly property int count:Tray.items.length+Compositor.minimized.length
                visible:count>0
                text:ShellSettings.tuiTrayOpen?"›":"‹";value:ShellSettings.tuiTrayOpen?"":String(count)
                Accessible.name:ShellSettings.tuiTrayOpen?"Hide tray icons and minimised windows":"Show tray icons and minimised windows"
                onClicked:ShellSettings.setTuiTrayOpen(!ShellSettings.tuiTrayOpen)
            }
            Repeater {
                model:ShellSettings.tuiTrayOpen?Tray.items:[]
                TuiBarButton {
                    required property var modelData
                    width:32;text:"";padding:0
                    Accessible.name:modelData.tooltipTitle||modelData.title||modelData.id
                    Image { anchors.centerIn:parent;width:18;height:18;source:modelData.icon;asynchronous:true }
                    onClicked:button=>{
                        if(button===Qt.MiddleButton)Tray.secondaryActivate(modelData);
                        else if(button===Qt.RightButton||modelData.onlyMenu){if(modelData.hasMenu)trayMenu.show(modelData);}
                        else Tray.activate(modelData);
                    }
                    onScrolled:delta=>Tray.scroll(modelData,delta,false)
                }
            }
            Text {
                visible:ShellSettings.tuiTrayOpen&&Tray.items.length>0&&Compositor.minimized.length>0
                height:Theme.tuiBarCell;verticalAlignment:Text.AlignVCenter;leftPadding:4;rightPadding:4
                text:"│";color:Theme.tuiBorder;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize
            }
            Repeater {
                model:ShellSettings.tuiTrayOpen?Compositor.minimized:[]
                TuiBarButton { required property var modelData;required property int index;text:"";value:"["+(index+1)+"]";Accessible.name:"Restore "+modelData.title;onClicked:Compositor.restore(modelData.address) }
            }
            TuiBarButton {
                visible:Screenshots.recording
                property real now:Date.now()
                readonly property int seconds:Math.floor(Screenshots.elapsedMs(now)/1000)
                text:Screenshots.paused?"Ⅱ rec":"● rec";value:Math.floor(seconds/60)+":"+String(seconds%60).padStart(2,"0");tint:Theme.terracotta
                Timer { running:parent.visible;repeat:true;interval:500;onTriggered:parent.now=Date.now() }
                onClicked:button=>button===Qt.RightButton?Screenshots.togglePause():Screenshots.stopRecording()
            }
            Repeater {
                model:Clocks.timers.slice(0,2)
                TuiBarButton {
                    required property var modelData
                    text:"timer";value:Clocks.clock(Clocks.left(modelData));onClicked:button=>{if(button===Qt.RightButton){workspaceMenu.kind="clock";workspaceMenu.at=root.width-160;workspaceMenu.open=true;}else Clocks.pauseTimer(modelData.id);}
                }
            }
            TuiBarButton { visible:Clocks.stopwatch!==null;text:"sw";value:Clocks.clock(Clocks.elapsed());onClicked:button=>{if(button===Qt.RightButton){workspaceMenu.kind="clock";workspaceMenu.at=root.width-100;workspaceMenu.open=true;}else Clocks.pauseStopwatch();} }
            TuiBarButton { visible:FocusMode.session!==null;text:FocusMode.phaseName();value:FocusMode.clock(FocusMode.left());onClicked:button=>{if(button===Qt.RightButton){workspaceMenu.kind="clock";workspaceMenu.at=root.width-100;workspaceMenu.open=true;}else FocusMode.pause();} }
                }
            }
        }
    }
    BarMenu {
        id:workspaceMenu;topEdge:true;lift:Theme.tuiBarHeight
        onRenameRequested:ws=>root.controller.renameWorkspaceRequested(ws)
        onTimerRequested:root.controller.timerRequested()
        onAlarmRequested:root.controller.alarmRequested()
    }
    TrayMenu { id:trayMenu;WlrLayershell.layer:WlrLayer.Overlay;exclusionMode:ExclusionMode.Ignore;anchors.top:true;anchors.right:true;margins.top:Theme.tuiBarHeight+Theme.tuiPanelGap;margins.right:12;onOpenChanged:trayGrab.active=open }
    FocusGrab { id:trayGrab;windows:[trayMenu,root];onCleared:trayMenu.open=false }
    PanelWindow {
        id:mediaWindow;property bool open
        WlrLayershell.layer:WlrLayer.Overlay
        exclusionMode:ExclusionMode.Ignore
        visible:mediaReveal.shown;focusable:true;exclusiveZone:0
        anchors.top:true;anchors.right:true;margins.top:Theme.tuiBarHeight+Theme.tuiPanelGap;margins.right:Theme.tuiPanelMargin
        implicitWidth:360;implicitHeight:mediaCard.height
        color:"transparent";WlrLayershell.namespace:"pistachio-panel"
        Reveal { id:mediaReveal;open:mediaWindow.open }
        MediaCard { id:mediaCard;width:360;color:Theme.tuiSurface;border.width:1;border.color:Theme.tuiBorder;showQueue:true;opacity:mediaReveal.progress;focus:true;Keys.onEscapePressed:mediaWindow.open=false }
        onOpenChanged:mediaGrab.active=open
    }
    FocusGrab { id:mediaGrab;windows:[mediaWindow,root];onCleared:mediaWindow.open=false }
}
