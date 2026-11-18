import qs
import qs.panels
import qs.popups
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Shared ownership of IPC and panels; only the chosen bar/control layout is instantiated.
Scope {
    id: root
    property bool overviewOpen
    property var wallpaperSwitcher // the TUI strip names it while it's open (WallpapersEmpty board)
    property real sessionPillWidth
    readonly property var window: Theme.tui ? tuiBarLoader.item : classicBarLoader.item
    readonly property var controls: Theme.tui ? tuiControlLoader.item : classicControlLoader.item
    readonly property alias centre: centreWindow
    readonly property real width: window?.width ?? Theme.barWidth
    readonly property real height: window?.height ?? Theme.barHeight + Theme.barMargin
    readonly property var screen: window?.screen ?? Quickshell.screens[0]
    readonly property bool shown: window?.shown ?? true
    readonly property int stageMargin: 48
    property bool staged
    signal launcherRequested(string mode)
    signal renameWorkspaceRequested(int workspace)
    signal timerRequested
    signal alarmRequested
    function startIntro() { window?.startIntro(); }
    function endIntro() { window?.endIntro(); }
    function showNotification(n) { if (controls) controls.open=false; if(Theme.tui)centreWindow.calendarShown=false; centreWindow.show(n); }
    function toggleCentre(calendar) {
        if(Theme.tui && centreWindow.open && centreWindow.calendarShown!==calendar) {
            centreWindow.calendarShown=calendar;
            return;
        }
        if(Theme.tui)centreWindow.calendarShown=calendar;
        toggle(centreWindow);
    }
    function toggle(panel) {
        if (!panel) return;
        const open=!panel.open;
        if (controls) controls.open=false;
        centreWindow.open=false;
        panel.open=open;
    }
    LazyLoader { id:classicBarLoader;active:!Theme.tui;component:classicBar }
    LazyLoader { id:tuiBarLoader;active:Theme.tui;component:tuiBar }
    Component { id: classicBar; ClassicBar {
        controller: root; overviewOpen: root.overviewOpen; sessionPillWidth: root.sessionPillWidth
        onLauncherRequested: mode=>root.launcherRequested(mode)
        onRenameWorkspaceRequested: ws=>root.renameWorkspaceRequested(ws)
        onTimerRequested: root.timerRequested()
        onAlarmRequested: root.alarmRequested()
    } }
    Component { id: tuiBar; TuiBar { controller: root } }
    LazyLoader { id:classicControlLoader;active:!Theme.tui;component:classicControl }
    LazyLoader { id:tuiControlLoader;active:Theme.tui;component:tuiControl }
    Component { id: classicControl; QuickSettings {
        anchors.bottom: true; anchors.left: true
        margins.left: root.staged ? screen.width-root.stageMargin-panelWidth-side : (screen.width+root.width)/2-width+side
        margins.bottom: root.height+12-below
        slide: root.staged ? 36 : 0
        onOpenChanged: grab.active=(open || centreWindow.open) && !Showoff.active
        onPowerRequested: { open=false; powerMenu.open=true; }
        onLauncherRequested: mode=>{open=false;root.launcherRequested(mode);}
    } }
    Component { id: tuiControl; TuiQuickSettings {
        anchors.top: true; anchors.right: true
        margins.top: Theme.tuiBarHeight + Theme.tuiPanelGap - 10
        margins.right: Theme.tuiPanelMargin
        onOpenChanged: grab.active=(open || centreWindow.open) && !Showoff.active
        onPowerRequested: { open=false;powerMenu.open=true; }
        onLauncherRequested: mode=>{open=false;root.launcherRequested(mode);}
    } }
    Connections {
        target: Theme
        function onTuiChanged() { grab.active=false;centreWindow.open=false; }
    }
    Connections { target: LocalSend; function onOpenRequested() { if(root.controls) {root.controls.page="localsend";root.controls.open=true;} } }
    Connections {
        target: Showoff
        function onActiveChanged() {
            grab.active=false;
            if(root.controls) root.controls.open=false;
            centreWindow.open=false;stageSteps.stop();
            if(Showoff.active) {unstage.stop();root.staged=true;stageSteps.start();}
            else unstage.restart();
        }
    }
    SequentialAnimation {
        id: stageSteps
        PauseAnimation { duration:150 }
        ScriptAction { script:centreWindow.open=true }
        PauseAnimation { duration:150 }
        ScriptAction { script:if(root.controls)root.controls.open=true }
        PauseAnimation { duration:150 }
        ScriptAction { script: {
            if(Theme.tui) {
                // TUI (owner's report, 14 November 2026): the centre and calendar sit in a row in the
                // middle under the strip, the control panel at the right; the terminal goes under that
                // row, as wide as it and clear of the control panel (Classic's in-between gap was 432 px)
                const centreLeft=Math.round((root.screen.width-centreWindow.implicitWidth)/2);
                const tRight=Math.min(centreLeft+centreWindow.implicitWidth,root.screen.width-Theme.tuiPanelMargin-(root.controls?.panelWidth??Theme.tuiPanelWidth)-24);
                const tTop=Theme.tuiBarHeight+Theme.tuiPanelGap+centreWindow.implicitHeight+24;
                const tBottom=Math.min(root.screen.height-24,tTop+480); // about fastfetch's own height, not the rest of the screen
                Showoff.openTerminal(Qt.rect(centreLeft,tTop,Math.max(1,tRight-centreLeft),Math.max(1,tBottom-tTop)));
                return;
            }
            const bottom=root.screen.height-(Theme.tui?16:root.height+16);
            const left=root.stageMargin+centreWindow.panelWidth+40;
            const right=root.screen.width-root.stageMargin-(root.controls?.panelWidth??380)-40;
            const top=Theme.tui ? root.height+Math.max(centreWindow.panelHeight,root.controls?.panelHeight??0)+40 : bottom-Math.max(centreWindow.panelHeight,root.controls?.panelHeight??0);
            Showoff.openTerminal(Qt.rect(left,top,Math.max(1,right-left),Math.max(1,bottom-top)));
        } }
    }
    Timer { id:unstage;interval:Theme.motionDuration+50;onTriggered:root.staged=false }
    PowerMenu { id:powerMenu }
    NotificationCentre {
        id:centreWindow
        WlrLayershell.layer:Theme.tui?WlrLayer.Overlay:WlrLayer.Top
        exclusionMode:Theme.tui?ExclusionMode.Ignore:ExclusionMode.Normal
        anchors.bottom: !Theme.tui; anchors.top: Theme.tui; anchors.left:true
        margins.left: Theme.tui ? Math.round((screen.width-implicitWidth)/2) : root.staged ? root.stageMargin-side : (screen.width-implicitWidth)/2
        margins.bottom: Theme.tui?0:root.height+16-below
        margins.top: Theme.tui?Theme.tuiBarHeight+Theme.tuiPanelGap-(implicitHeight-panelHeight-below):0
        slide: root.staged && !Theme.tui ? -36 : 0
        onOpenChanged: grab.active=(open || (root.controls?.open??false)) && !Showoff.active
    }
    Toasts {
        id:toasts
        suppressNotifications:centreWindow.open
        WlrLayershell.layer:Theme.tui?WlrLayer.Overlay:WlrLayer.Top
        exclusionMode:Theme.tui?ExclusionMode.Ignore:ExclusionMode.Normal
        visible:Notifs.popups.length>0 && !centreWindow.open || LocalSend.toastShown || toasts.phoneShown
        anchors.bottom:!Theme.tui;anchors.top:Theme.tui;anchors.right:Theme.tui
        margins.bottom:Theme.tui?0:root.height+16-below
        margins.top:Theme.tui?Theme.tuiBarHeight+Theme.tuiPanelGap-above:0
        margins.right:Theme.tui?Theme.tuiPanelMargin-side:0
    }
    Osd { anchors.bottom:true;lift:Theme.tui?Theme.barMargin:root.shown?root.height+16:Theme.barMargin;suppressed:root.controls?.open??false;overviewOpen:root.overviewOpen }
    FocusGrab {
        id:grab
        windows: [root.controls,centreWindow,root.window].filter(w=>!!w)
        onCleared:{if(root.controls)root.controls.open=false;centreWindow.open=false;}
    }
    IpcHandler { target:"quicksettings";function toggle():void{root.toggle(root.controls);}function mixer():void{if(root.controls){root.controls.page="mixer";root.controls.open=true;}} }
    IpcHandler { target:"bar";function peek():void{root.window?.peek();} }
    IpcHandler { target:"showoff";function toggle():void{Showoff.toggle();} }
    IpcHandler { target:"notifications";function toggle():void{root.toggleCentre(false);}function toggleDnd():void{Notifs.setDnd(!Notifs.dnd);} }
}
