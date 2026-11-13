import qs
import qs.launcher
import qs.panels
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick
import QtTest
ShellRoot {
 id:root
 property bool tui:false
 Binding {target:Theme;property:"tui";value:root.tui}
 Launcher {id:launcher}
 WindowSwitcher {id:switcher}
 TestCase {id:input;parent:launcher.contentItem;when:false}
 TestCase {id:switchInput;parent:switcher.contentItem;when:false}
 function check(ok,why){if(!ok)throw Error(why);}
 function find(item,name){if(item.objectName===name)return item;for(const c of item.children??[]){const r=find(c,name);if(r)return r;}return null;}
 function capture(name){const folder=Quickshell.env("PISTACHIO_LAUNCHER_SHOTS");if(!folder)return;input.wait(150);Quickshell.execDetached(["grim",folder+"/"+name+".png"]);input.wait(500);}
 function type(text){for(const ch of text)input.keyClick(ch.toUpperCase().charCodeAt(0),ch===ch.toUpperCase()?Qt.ShiftModifier:Qt.NoModifier);}
 property bool pairingSawGrab
 Timer {id:pairingPresentation;interval:Theme.motionDuration+40;onTriggered:root.pairingSawGrab=launcher.visible}
 Connections {target:Bluetooth;function onAsked(){root.pairingSawGrab=true;pairingPresentation.restart();}}
 function findRow(item,kind){if(item.objectName==="tui-launcher-row"&&item.row.kind===kind)return item;for(const c of item.children??[]){const r=findRow(c,kind);if(r)return r;}return null;}
 function regression(name){
  const workspaces=Compositor.workspaces, windows=Compositor.windows;
  try {
   root.tui=true;
   if(name!=="switcher") {
    launcher.show(name==="scan"||name==="pairing"?"bluetooth":name==="bounds"?"workspaces":name==="pins"?"all":"apps");
    input.tryVerify(()=>launcher.contentItem.Window.active,1500);input.wait(100);
   }
   const field=find(launcher.contentItem,"launcher-field");
   if(name==="scan") {
    check(Bluetooth.scanning,"opening Bluetooth starts discovery");
    launcher.open=false;input.wait(100);check(!Bluetooth.scanning,"closing Bluetooth stops discovery");
   } else if(name==="pairing") {
    Bluetooth.nearby=[{name:"Pairing fixture",address:"fixture",paired:false}];input.wait(60);
    launcher.current=launcher.rows.findIndex(r=>r.kind==="btdevice");input.keyClick(Qt.Key_Return);input.wait(200);
    check(Bluetooth.request&&!launcher.open&&!launcher.visible&&!root.pairingSawGrab,"pair request releases exclusive layer before Settings presentation");
   } else if(name==="bounds") {
    input.keyClick(Qt.Key_Up);check(launcher.column===0,"Up at first workspace stays first");
    Compositor.workspaces=[{id:19,active:false}];launcher.snapshot();field.text="1";input.wait(60);
    const last=launcher.gridLength(launcher.rows[launcher.current])-1;launcher.column=last;input.keyClick(Qt.Key_Down);
    check(launcher.column===last,"Down at last matching workspace stays last");
   } else if(name==="note") {
    field.text="tldr tar";input.wait(100);const note=findRow(launcher.contentItem,"note");
    check(note&&note.height>32,"multiline help reserves wrapped height");
    const text=find(note,"tui-launcher-note");check(text&&text.text.includes("\nMore:")&&text.height>=text.implicitHeight,"full description and manual URL fit");
   } else if(name==="emoji") {
    field.text=":smile";input.wait(100);const row=findRow(launcher.contentItem,"emoji");
    check(row&&find(row,"tui-launcher-prefix")?.text===row.row.emoji,"emoji symbol remains visible beside its description");capture("tui-emoji");
   } else if(name==="pins") {
    LauncherTools.pins=[{kind:"app",target:"fixture0"}];input.wait(60);
    check(launcher.rows.findIndex(r=>r.title==="Pinned")<launcher.rows.findIndex(r=>r.title==="Frequent")&&launcher.rows.some(r=>r.key==="pin:fixture0"),"pins remain before frequent results");
    LauncherTools.aliases=({web:{kind:"app",target:"fixture0"}});field.text="web";input.wait(60);
    check(launcher.rows[0].title==="Alias"&&launcher.rows[launcher.current].key==="alias:web","exact alias remains first and selected");
    input.keyClick(Qt.Key_Return);check(Apps.launched==="fixture0"&&!launcher.open,"alias Enter retains launch action");
   } else if(name==="style") {
    launcher.show("system");input.wait(80);launcher.current=launcher.rows.findIndex(r=>r.key==="volume");
    root.tui=false;input.wait(100);check(launcher.rows[launcher.current].key==="volume","open launcher keeps selected action into Classic");
    root.tui=true;input.wait(100);check(launcher.rows[launcher.current].key==="volume","open launcher keeps selected action into TUI");
   } else if(name==="switcher") {
    switcher.show(1,false);switchInput.tryVerify(()=>switcher.contentItem.Window.active,1500);switchInput.wait(100);
    switcher.pointerStart=Qt.point(-1,-1);switcher.pointerMoved=false;
    switcher.pointer(Qt.point(10,10));switcher.pointer(Qt.point(13,10));check(!switcher.pointerMoved,"initial pointer and small jitter do not take selection");switcher.pointer(Qt.point(15,10));check(switcher.pointerMoved,"deliberate movement can select");
    const selected=switcher.chosen.address;root.tui=false;check(!switcher.pointerMoved,"style change rearms stationary-pointer guard");switchInput.wait(120);check(switcher.open&&switcher.chosen.address===selected&&!!find(switcher.contentItem,"classic-window-switcher"),"open switcher preserves selection into Classic");
    switchInput.keyClick(Qt.Key_Right);const next=switcher.chosen.address;root.tui=true;switchInput.wait(100);check(switcher.open&&switcher.chosen.address===next&&!!find(switcher.contentItem,"tui-window-switcher"),"open switcher preserves selection into TUI");
    switcher.current=switcher.windows.length-1;Compositor.windows=windows.slice(0,1);switchInput.wait(60);check(switcher.current===0&&switcher.chosen.address===windows[0].address,"removed windows clamp selection");
    Compositor.windows=[];switchInput.wait(100);check(!switcher.open,"last window removal closes switcher");
   }
   return "PASS regression "+name;
  }catch(e){return "FAIL regression "+name+": "+e.message+"\n"+e.stack;}
  finally {launcher.open=false;switcher.cancel();Bluetooth.request=null;Bluetooth.nearby=[];Compositor.workspaces=workspaces;Compositor.windows=windows;LauncherTools.pins=[];LauncherTools.aliases=({});input.wait(250);root.tui=false;}
 }
 function run(){
  const initialWindows=Compositor.windows;
  switcher.show(1,false);switchInput.tryVerify(()=>switcher.contentItem.Window.active,1500);switchInput.keyClick(Qt.Key_Left);
  check(switcher.current===0,"fresh Classic grid receives keyboard input: "+JSON.stringify({index:switcher.current,focus:find(switcher.contentItem,"classic-window-switcher").activeFocus,window:switcher.contentItem.Window.active,item:switcher.contentItem.Window.window.activeFocusItem?.objectName}));switcher.cancel();switchInput.wait(250);
  root.tui=true;
  launcher.show("all");input.tryVerify(()=>launcher.contentItem.Window.active,1500);input.wait(100);
  const panel=find(launcher.contentItem,"launcher-panel"),field=find(launcher.contentItem,"launcher-field"),list=find(launcher.contentItem,"launcher-results");
  check(panel&&panel.width===576,"TUI launcher matches 576px board frame");
  check(panel.y===104,"TUI launcher uses board top offset");capture("tui-home");
  type("helium");input.wait(100);check(launcher.query==="helium"&&launcher.rows.some(r=>r.kind==="app"),"typing filters actual model: "+JSON.stringify({query:launcher.query,open:launcher.open,focus:field.activeFocus,rows:launcher.rows.map(r=>r.kind)}));
  input.keyClick(Qt.Key_Return);check(Apps.launched==="fixture0"&&!launcher.open,"Enter launches selected app through service");
  launcher.show("apps");input.wait(150);check(list.contentHeight>list.height,"many apps scroll");
  type("w");check(launcher.query==="w","decorative letters remain typing");
  launcher.show("workspaces");input.wait(100);capture("tui-workspaces");const c=launcher.column;input.keyClick(Qt.Key_Down);check(launcher.column===c+1,"vertical workspace rows navigate: "+JSON.stringify({before:c,after:launcher.column,current:launcher.current,kind:launcher.rows[launcher.current]?.kind,rows:launcher.rows.map(r=>r.kind),query:launcher.query,workspaces:launcher.workspaces}));
  input.keyClick(Qt.Key_Return);check(Compositor.went===2,"workspace Enter retains action");
  Compositor.workspaces=[{id:30,active:false}];launcher.show("workspaces");input.wait(100);
  input.keyClick(Qt.Key_Down);input.wait(50);
  let top=list.itemAtIndex(launcher.current).y+launcher.column*32-list.contentY;
  check(top>=0&&top+32<=list.height,"first workspace move stays visible in long list");
  for(let i=0;i<19;i++)input.keyClick(Qt.Key_Down);
  input.wait(80);top=list.itemAtIndex(launcher.current).y+launcher.column*32-list.contentY;
  check(launcher.column===20&&top>=0&&top+32<=list.height,"long workspace list keeps selected row in view");
  Compositor.workspaces=[{id:1,active:true},{id:2,active:false}];
  launcher.show("bluetooth");input.wait(120);check(launcher.mode==="bluetooth"&&launcher.open,"TUI basic Bluetooth view available");capture("tui-bluetooth");
  input.keyClick(Qt.Key_Escape);check(launcher.open&&launcher.mode==="system"&&!Bluetooth.scanning,"Bluetooth Esc returns and stops scan");
  launcher.show("system");input.wait(100);check(find(findRow(launcher.contentItem,"slider"),"tui-launcher-heading")?.text==="quick controls","TUI system retains board section heading");launcher.current=launcher.rows.findIndex(r=>r.key==="volume");const v=Audio.volume;input.keyClick(Qt.Key_Left);check(Audio.volume<v,"meter keyboard retains service boundary");capture("tui-system");
  root.tui=false;input.wait(150);check(panel.width===640,"Classic frame restored live");check(!find(launcher.contentItem,"tui-launcher-row"),"unused TUI rows destroyed");
  root.tui=true;input.wait(150);check(panel.width===576,"TUI frame restored");launcher.open=false;input.wait(100);
  switcher.show(1,false);switchInput.wait(180);check(!!find(switcher.contentItem,"tui-window-switcher"),"TUI switcher list chosen");check(!find(switcher.contentItem,"classic-window-switcher"),"Classic thumbnails not instantiated");capture("tui-switcher-many");
  const selected=switcher.current;switchInput.keyClick(Qt.Key_Down);check(switcher.current===selected+1,"switcher Down selects next row");
  switchInput.keyRelease(Qt.Key_Alt);switchInput.wait(100);check(!switcher.open&&Compositor.focused[Compositor.focused.length-1]===String(selected+1),"Alt release focuses chosen window");
  Compositor.windows=[{address:"single",title:"Only window",appId:"kitty",workspace:1,recency:0,group:[],minimized:false}];switcher.show(1,false);switchInput.wait(100);check(switcher.windows.length===1&&switcher.open,"single window TUI drawn");capture("tui-switcher-single");
  switchInput.keyClick(Qt.Key_Escape);check(!switcher.open,"Escape cancels");
  Compositor.windows=initialWindows.slice(0,3).map(w=>Object.assign({},w,{group:["0","1","2"]}));
  switcher.show(1,true);switchInput.wait(150);check(switcher.tabsOnly&&switcher.windows.length===3,"grouped tabs reuse existing order");
  const focusedBefore=Compositor.focused.length;switchInput.keyRelease(Qt.Key_Alt);switchInput.wait(350);
  check(Compositor.focused.length===focusedBefore+2&&Compositor.focused[Compositor.focused.length-1]==="1","grouped tab refocused after keyboard release");
  Compositor.windows=initialWindows;root.tui=false;switcher.show(1,false);switchInput.wait(150);
  check(!!find(switcher.contentItem,"classic-window-switcher")&&!find(switcher.contentItem,"tui-window-switcher"),"Classic grid restored without TUI list");
  switchInput.keyClick(Qt.Key_Left);check(switcher.current===0,"Classic grid retains keyboard focus");
  switchInput.keyClick(Qt.Key_Escape);check(!switcher.open,"Classic Escape cancels");
  return "PASS TUI launcher, real input/actions, style loading and switcher";
 }
 IpcHandler {target:"tuiLauncherTest";function regression(name:string):string{return root.regression(name);}function ready():bool{return true;}function run():string{try{return root.run();}catch(e){return "FAIL "+e.message+"\n"+e.stack;}}}
}
