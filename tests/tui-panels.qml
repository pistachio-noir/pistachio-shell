import qs
import qs.panels
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick
import QtTest
ShellRoot {
 id:root
 property bool tui:Quickshell.env("PISTACHIO_PANELS_CLASSIC_ONLY")!=="1"
 Binding {target:Theme;property:"tui";value:root.tui}
 property string launched
 Overview {id:overview;onLauncherRequested:mode=>root.launched=mode}
 NotificationCentre {id:centre;anchors.top:true;anchors.left:true;margins.left:64;margins.top:46;exclusionMode:ExclusionMode.Ignore}
 FocusGrab {windows:[centre];active:centre.open}
 TestCase {id:input;parent:overview.contentItem;when:false}
 TestCase {id:popupInput;parent:centre.contentItem;when:false}
 function check(ok,why){if(!ok)throw Error(why);}
 function find(item,name){if(item.objectName===name)return item;for(const c of item.children??[]){const r=find(c,name);if(r)return r;}return null;}
 function capture(name){const folder=Quickshell.env("PISTACHIO_PANELS_SHOTS");if(!folder)return;input.wait(150);Quickshell.execDetached(["grim",folder+"/"+name+".png"]);input.wait(250);}
 function run(){
  const windows=Compositor.windows;
  overview.show();input.tryVerify(()=>overview.contentItem.Window.active,1500);input.wait(100);
  check(!!find(overview.contentItem,"tui-overview"),"TUI Overview layout selected");check(!find(overview.contentItem,"classic-overview"),"unused Classic Overview absent");
  check(overview.list.length===3,"Overview keeps real workspace/group model: "+overview.list.length+" workspace "+overview.active+" source "+Compositor.windows.length);capture("overview-here");
  input.keyClick(Qt.Key_Tab);check(overview.mode==="all","Tab retains All windows");
  input.keyClick(Qt.Key_Q);check(overview.query==="q","plain letters remain search");input.keyClick(Qt.Key_Escape);check(!overview.searching&&overview.open,"Escape clears search first");
  overview.mode="here";input.wait(60);
  const tile=find(overview.contentItem,"overview-window-pointer"),space=find(overview.contentItem,"overview-space-2");
  const destination=space.mapToItem(tile,space.width/2,space.height/2);
  input.mousePress(tile,30,30);input.mouseMove(tile,48,48,30);input.mouseMove(tile,destination.x,destination.y,30);capture("overview-drag");input.mouseRelease(tile,destination.x,destination.y);
  check(Compositor.sent[0]?.workspace===2&&!overview.drag&&overview.open,"native drop sends without activating window");
  Compositor.windows=[];input.wait(80);check(!!find(overview.contentItem,"tui-overview-empty"),"empty workspace board");capture("overview-empty");
  overview.hide();input.wait(100);Compositor.windows=windows;
  centre.calendarShown=false;centre.open=true;popupInput.wait(180);
  const notice=find(centre.contentItem,"tui-notifications");check(notice&&notice.width===400,"400px notification board");capture("notifications");
  const dnd=find(centre.contentItem,"notifications-dnd");popupInput.mouseClick(dnd,64,16);check(Notifs.dnd,"mouse DND action");popupInput.keyClick(Qt.Key_Space);check(!Notifs.dnd,"keyboard Space DND action");
  check(centre.ordered.length===4,"notification model retained");centre.toggleGroup("Mail");popupInput.wait(50);check(centre.openGroups.Mail,"group expansion retained");
  notice.view.currentIndex=0;notice.activateCurrent();check(Notifs.invoked===1,"default action retained");
  centre.calendarShown=true;popupInput.wait(100);
  const calendar=find(centre.contentItem,"tui-calendar"),weather=find(centre.contentItem,"tui-weather");
  popupInput.tryVerify(()=>centre.contentItem.Window.active,1500);
  check(calendar&&calendar.width===232&&weather&&weather.width===264,"calendar/weather board widths");check(!find(centre.contentItem,"centre-weather-shadow").visible,"TUI weather has no Classic shadow");capture("calendar-weather");
  const initialMonth=centre.calendar.month;popupInput.keyClick(Qt.Key_Right);check(centre.calendar.month===(initialMonth+1)%12,"native month key");const year=centre.calendar.year,month=centre.calendar.month;
  centre.weather.expanded=true;popupInput.wait(100);check(centre.weather.height===458,"expanded weather board");capture("calendar-weather-details");
  root.tui=false;popupInput.wait(220);check(centre.calendar.year===year&&centre.calendar.month===month&&centre.weather.expanded,"shared date/weather state survives Classic");
  check(!find(centre.contentItem,"tui-calendar")&&!find(centre.contentItem,"tui-notifications"),"unused TUI views destroyed");
  root.tui=true;popupInput.wait(100);check(centre.calendar.month===month,"state survives TUI return");
  const beforeC=Notifs.notifications.length;popupInput.keyClick(Qt.Key_C);check(Notifs.notifications.length===beforeC,"decorative C is not a shortcut");
  Weather.available=false;popupInput.wait(80);check(centre.panelWidth===648,"missing weather keeps compact calendar and notices");Weather.available=true;
  centre.show(Notifs.notifications[1]);popupInput.wait(180);check(centre.openGroups.Mail&&centre.spotlight===Notifs.notifications[1],"spotlight retains grouped notification");
  Events.enabled=true;Events.events=[{title:"Fixture meeting",calendar:"test",allDay:true,start:Date.now(),end:Date.now()+3600000}];popupInput.wait(100);check(centre.calendar.dayEvents.length===1,"existing events included");
  centre.open=false;input.wait(100);check(!Events.watching,"event watcher cleanup retained");
  root.tui=false;overview.show();input.wait(250);check(!!find(overview.contentItem,"classic-overview")&&!find(overview.contentItem,"tui-overview"),"Classic Overview restored");overview.hide();
  return "PASS Overview, notifications, calendar/weather actions and live state/style lifecycle";
 }
 function saveItem(item,name){const folder=Quickshell.env("PISTACHIO_PANELS_SHOTS");if(!folder)return;item.grabToImage(r=>r.saveToFile(folder+"/"+name+".png"));input.wait(150);}
 function classic(){
  root.tui=false;centre.open=true;popupInput.wait(350);capture("classic-centre");saveItem(find(centre.contentItem,"centre-capture"),"classic-centre-content");
  root.tui=true;popupInput.wait(120);root.tui=false;popupInput.wait(350);capture("classic-centre-roundtrip");saveItem(find(centre.contentItem,"centre-capture"),"classic-centre-roundtrip-content");
  centre.open=false;input.wait(250);overview.show();input.wait(650);capture("classic-overview");saveItem(find(overview.contentItem,"overview-capture"),"classic-overview-content");
  root.tui=true;input.wait(120);root.tui=false;input.wait(650);capture("classic-overview-roundtrip");saveItem(find(overview.contentItem,"overview-capture"),"classic-overview-roundtrip-content");overview.hide();return "PASS Classic capture and live roundtrip";
 }
 IpcHandler {target:"panelsTest";function classic():string{return root.classic();}function ready():bool{return true;}function run():string{try{return root.run();}catch(e){return "FAIL "+e.message+"\n"+e.stack;}}}
}
