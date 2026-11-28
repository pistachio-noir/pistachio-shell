import qs
import qs.bar
import qs.panels
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
    RealQuickSettings { id:classicQs }
    TestCase { id:qsInput;parent:classicQs.contentItem;when:false }
    function check(ok,why){if(!ok)throw Error(why);}
    function find(item,name){if(item.objectName===name)return item;for(const c of item.children??[]){const hit=find(c,name);if(hit)return hit;}return null;}
    function row(name){const r=find(bar.controls.contentItem,"control-"+name);check(!!r,"missing control "+name);return r;}
    function run(){
        input.wait(200);
        check(bar.window.objectName==="tui-bar","TUI bar chosen");
        check(bar.window.exclusiveZone===35 && bar.window.anchors.top && bar.window.anchors.left && bar.window.anchors.right,"TUI reserves 35 px at the top");
        check(bar.window.WlrLayershell.layer===WlrLayer.Overlay,"bar stays above real fullscreen windows");
        check(bar.window.height===35 && bar.window.width===bar.window.screen.width,"35 px strip fills screen width");
        Audio.micMuted=true;ScreenShare.sharing=true;Bluetooth.battery=66;input.wait(60);
        check(find(bar.window.contentItem,"tui-mic-cue")?.visible && find(bar.window.contentItem,"tui-share-cue")?.visible && find(bar.window.contentItem,"tui-bluetooth")?.visible,"privacy and Bluetooth readouts retained");
        Tray.items=Array.from({length:12},(_,i)=>({id:"fixture-"+i,title:"Fixture",icon:"",hasMenu:false}));
        Compositor.minimized=Array.from({length:20},(_,i)=>({address:String(i),title:"Fixture window"}));
        input.wait(80);
        const arrow=find(bar.window.contentItem,"tui-tray-arrow");
        check(!ShellSettings.tuiTrayOpen && arrow?.visible && arrow.value==="32" && find(bar.window.contentItem,"tui-bar-extras").contentWidth<200,"tray and minimised collapsed behind one arrow by default");
        ShellSettings.setTuiTrayOpen(true);input.wait(80);
        const cpu=find(bar.window.contentItem,"tui-cpu"), mem=find(bar.window.contentItem,"tui-mem"), extras=find(bar.window.contentItem,"tui-bar-extras");
        check(cpu.height===34 && extras.height===34,"controls fit above the bottom rule");
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
            check(bar.window.shown && bar.window.exclusiveZone===35,"strip back and reserving");
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
        check(bar.controls.rows.find(r=>r.id==="volume")?.more,"right-click on vol opens the outputs");bar.controls.rows.find(r=>r.id==="volume").more();input.wait(100);
        check(bar.controls.page==="output" && bar.controls.rows.map(r=>r.id).join()==="output-1,output-2,output-3","the output page lists every output");
        check(row("output-1").checked && !row("output-2").checked,"the current output is marked");
        check(bar.controls.rows[2].detail()==="nothing plugged in","an unplugged output says so");
        row("output-3").activated();input.wait(40);check(Audio.sink.id===1,"an unplugged output can't be chosen");
        row("output-2").activated();input.wait(60);check(Audio.sink.id===2 && row("output-2").checked,"picking an output switches the sound there");
        Audio.setSink(Audio.sinks[0]);
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
        check(bar.window.objectName==="tui-bar" && bar.window.exclusiveZone===35,"top strip restored");
        LocalSend.available=false;bar.controls.page="localsend";bar.controls.open=true;input.wait(150);
        check(!bar.controls.localShown && !find(bar.controls.contentItem,"control-localsend"),"missing optional dependency hidden");
        bar.controls.open=false;
        return "PASS top strip, reservation, actions, LocalSend and exclusive style loading";
    }
    // Classic quick settings' Sound output card (the › after the volume slider)
    function classicOutput(): string {
        try {
            root.tui=false;classicQs.open=true;qsInput.wait(300);
            const more=find(classicQs.contentItem,"slider-more");
            check(more && more.visible,"Classic volume row has a › while there is more than one output");
            qsInput.mouseClick(more);qsInput.wait(250);
            check(classicQs.popup==="output" && find(classicQs.contentItem,"output-popover").visible,"the › opens the Sound output card");
            const two=find(classicQs.contentItem,"output-2"), three=find(classicQs.contentItem,"output-3");
            check(two && three && find(classicQs.contentItem,"output-1"),"the card lists every output");
            qsInput.mouseClick(three);qsInput.wait(60);check(Audio.sink.id===1,"an unplugged output can't be picked");
            qsInput.mouseClick(two);qsInput.wait(60);check(Audio.sink.id===2,"a click moves the sound to that output");
            classicQs.popup="";qsInput.wait(250); // (Esc goes through the panel's key handler, which needs the keyboard this test window lacks)
            const all=Audio.sinks;Audio.sinks=all.slice(0,1);qsInput.wait(60);
            check(!find(classicQs.contentItem,"slider-more").visible,"with one output there is no ›");
            Audio.sinks=all;Audio.setSink(all[0]);classicQs.open=false;qsInput.wait(250);
            return "PASS Classic quick settings' Sound output card";
        } catch (e) { classicQs.open=false; return "FAIL "+e.message; }
    }
    IpcHandler { target:"barTest";function classicOutput():string{return root.classicOutput();}function classic():void{root.tui=false;Notifs.popups=[];bar.centre.open=false;}function popup(kind:string,shown:bool):void{if(kind==="toast")Notifs.popups=shown?[{}]:[];else bar.centre.open=shown;}function ready():bool{return !!bar.window&&!!bar.controls;}function run():string{try{return root.run();}catch(e){return "FAIL "+e.message+"\n"+e.stack;}} }
}
