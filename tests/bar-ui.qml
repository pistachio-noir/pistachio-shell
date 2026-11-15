import qs
import qs.bar
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtTest

ShellRoot {
    id:root
    property bool tui:true
    Binding { target:Theme;property:"tui";value:root.tui }
    Bar { id:bar;onLauncherRequested:mode=>root.launched=mode }
    property string launched
    TestCase { id:input;parent:bar.controls?.contentItem??null;when:false }
    function check(ok,why){if(!ok)throw Error(why);}
    function find(item,name){if(item.objectName===name)return item;for(const c of item.children??[]){const hit=find(c,name);if(hit)return hit;}return null;}
    function row(name){const r=find(bar.controls.contentItem,"control-"+name);check(!!r,"missing control "+name);return r;}
    function run(){
        input.wait(200);
        check(bar.window.objectName==="tui-bar","TUI bar chosen");
        check(bar.window.exclusiveZone===41 && bar.window.anchors.top && bar.window.anchors.left && bar.window.anchors.right,"TUI reserves top strip");
        check(bar.window.WlrLayershell.layer===WlrLayer.Overlay,"bar stays above real fullscreen windows");
        check(bar.window.height===41 && bar.window.width===bar.window.screen.width,"strip fills screen width");
        Audio.micMuted=true;ScreenShare.sharing=true;Bluetooth.battery=66;input.wait(60);
        check(find(bar.window.contentItem,"tui-mic-cue")?.visible && find(bar.window.contentItem,"tui-share-cue")?.visible && find(bar.window.contentItem,"tui-bluetooth")?.visible,"privacy and Bluetooth readouts retained");
        Tray.items=Array.from({length:12},(_,i)=>({id:"fixture-"+i,title:"Fixture",icon:"",hasMenu:false}));
        Compositor.minimized=Array.from({length:20},(_,i)=>({address:String(i),title:"Fixture window"}));
        input.wait(80);
        const arrow=find(bar.window.contentItem,"tui-tray-arrow");
        check(!ShellSettings.tuiTrayOpen && arrow?.visible && arrow.value==="32" && find(bar.window.contentItem,"tui-bar-extras").contentWidth<200,"tray and minimised collapsed behind one arrow by default");
        ShellSettings.setTuiTrayOpen(true);input.wait(80);
        const cpu=find(bar.window.contentItem,"tui-cpu"), mem=find(bar.window.contentItem,"tui-mem"), extras=find(bar.window.contentItem,"tui-bar-extras");
        check(cpu.mapToItem(bar.window.contentItem,0,0).x>=0 && mem.mapToItem(bar.window.contentItem,mem.width,0).x<=bar.window.width,"CPU and memory remain on screen when crowded");
        check(extras.contentWidth>extras.width && extras.x+extras.width<=bar.window.width,"crowded extras scroll within strip");
        ShellSettings.setTuiTrayOpen(false);Tray.items=[];Compositor.minimized=[];input.wait(40);
        check(!find(bar.window.contentItem,"tui-tray-arrow").visible,"arrow hidden with nothing behind it");
        Audio.micMuted=false;ScreenShare.sharing=false;
        for (const hide of [()=>Compositor.fullscreen=true,()=>FocusMode.zen=true,()=>bar.overviewOpen=true]) {
            hide();input.wait(80);
            check(!bar.window.shown && bar.window.exclusiveZone===0 && bar.window.visible,"TUI hides for fullscreen/Zen/Overview, keeping its edge");
            bar.window.peek();input.wait(40);
            check(bar.window.shown,"peek reveals the hidden strip (Zen too)");
            if(FocusMode.zen) {bar.window.revealed=false;input.wait(40);check(bar.window.mask.height===0,"Zen has no top-edge strip");}
            bar.window.revealed=false;Compositor.fullscreen=false;FocusMode.zen=false;bar.overviewOpen=false;input.wait(40);
            check(bar.window.shown && bar.window.exclusiveZone===41,"strip back and reserving");
        }
        bar.toggle(bar.controls);input.wait(200);
        check(bar.controls.open && bar.controls.objectName==="tui-control","TUI control chosen");
        const vol=row("volume"), slider=vol.children.find(c=>c.shownValue!==undefined);
        check(slider.width===140,"control meter matches board width");
        input.mouseClick(slider,slider.width*0.3,16);input.wait(100);
        check(Math.abs(Audio.volume-0.3)<0.06,"control level updates actual service boundary");
        row("dnd").activated();check(Notifs.dnd,"DND action routed");
        bar.controls.page="localsend";input.wait(100);
        check(bar.controls.localShown && bar.controls.width===792,"LocalSend sits beside control");
        check(bar.controls.panelWidth===384,"control frame matches board");
        check(find(bar.controls.contentItem,"localsend-drop")?.enabled,"idle LocalSend accepts file drops");
        bar.controls.addUrls(["file:///tmp/fixture%20file.png"]);
        check(LocalSend.addedPaths[0]==="/tmp/fixture file.png","drop URL decoded at service boundary");
        Audio.streams=[{id:88,name:"A very long application name",audio:{volume:0.5,muted:false}}];
        bar.controls.selected=8;bar.controls.page="mixer";input.wait(100);
        check(bar.controls.selected===0,"mixer selection resets");
        const stream=row("stream-88"), streamLabel=find(stream,"control-label"), streamSlider=find(stream,"control-slider");
        check(streamLabel.y+streamLabel.height<=streamSlider.y || streamLabel.x+streamLabel.width<=streamSlider.x,"mixer label cannot overlap meter");
        Audio.streams=[];input.wait(60);check(bar.controls.selected===0,"removed stream clamps selection");
        bar.controls.page="";input.wait(80);
        bar.controls.selected=bar.controls.rows.findIndex(r=>r.id==="dnd");
        input.keyClick(Qt.Key_Space);check(!Notifs.dnd,"control Space toggles selected row");
        input.keyClick(Qt.Key_Down);check(bar.controls.rows[bar.controls.selected].id==="night","control Down moves selection");
        input.keyClick(Qt.Key_Escape);input.wait(100);check(!bar.controls.open,"Escape closes control");
        const old=bar.window;
        root.tui=false;input.wait(300);
        check(bar.window!==old && bar.window.objectName==="classic-bar","style destroys unused bar: "+JSON.stringify({tui:Theme.tui,name:bar.window?.objectName,same:bar.window===old}));
        check(bar.window.exclusiveZone===0 && bar.window.anchors.bottom,"Classic reservation restored");
        check(!bar.controls.open,"switch releases old control surface");
        root.tui=true;input.wait(200);
        check(bar.window.objectName==="tui-bar" && bar.window.exclusiveZone===41,"top strip restored");
        LocalSend.available=false;bar.controls.page="localsend";bar.controls.open=true;input.wait(150);
        check(!bar.controls.localShown && !find(bar.controls.contentItem,"control-localsend"),"missing optional dependency hidden");
        bar.controls.open=false;
        return "PASS top strip, reservation, actions, LocalSend and exclusive style loading";
    }
    IpcHandler { target:"barTest";function classic():void{root.tui=false;Notifs.popups=[];bar.centre.open=false;}function popup(kind:string,shown:bool):void{if(kind==="toast")Notifs.popups=shown?[{}]:[];else bar.centre.open=shown;}function ready():bool{return !!bar.window&&!!bar.controls;}function run():string{try{return root.run();}catch(e){return "FAIL "+e.message+"\n"+e.stack;}} }
}
