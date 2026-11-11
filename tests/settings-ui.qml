import Quickshell
import Quickshell.Io
import QtQuick
import QtTest
import qs.services
import qs.settings

ShellRoot {
    property real fixtureWriteMs
    SettingsWindow { id: win }
    TestCase { id: input; name: "SettingsControls"; when: false }
    function find(item, name) {
        if (item.objectName === name && item.visible) return item;
        for (const child of item.children) { const match = find(child,name); if(match) return match; }
        return null;
    }
    function need(name) { const item=find(win.contentItem,name) || find(win.dialog.contentItem,name); if(!item) throw new Error("Missing "+name); return item; }
    function check(ok, why) { if(!ok) throw new Error(why); }
    function click(item) { input.mouseClick(item,item.width/2,item.height/2); input.wait(30); }
    function scrollInto(item) {
        let scroll=item.parent;
        while(scroll && scroll.contentY===undefined) scroll=scroll.parent;
        if(scroll) scroll.contentY=Math.max(0,Math.min(scroll.contentHeight-scroll.height,item.mapToItem(scroll.contentItem,0,0).y-scroll.height/2));
        input.wait(30);
    }
    function page(name) { win.navigate(name,""); input.wait(30); }
    function runChecks() {
        ShellSettings.setShadows(false);Store.fixtureWriteNow();ShellSettings.setShadows(true);input.wait(500);
        const oldNotifications=Store.saved.notifications;
        Store.saved.notifications=Array.from({length:200},(_,i)=>({id:i,body:"fixture".repeat(200)}));
        const began=Date.now();Store.fixtureWriteNow();fixtureWriteMs=Date.now()-began;
        Store.saved.notifications=oldNotifications;Store.fixtureWriteNow();
        check(Store.saved.shadows && ShellSettings.shadows,"newer preference must survive completion of an older save");
        for(const name of ["appearance","display","sound","notifications","bluetooth","network","localsend","lens","apps","system","health","about"]) page(name);
        page("health");click(need("action-health-check"));input.wait(500);
        check(SystemHealth.checked && SystemHealth.rows.some(r=>r.id==="shell" && r.status==="Running"),"local shell/helper check returns allowlisted real service status");
        click(need("action-diagnostics"));check(Clipboard.copied.startsWith("Pistachio Noir diagnostics") && !Clipboard.copied.includes("/home/") && !Clipboard.copied.includes("192.168."),"diagnostics copy excludes identities and network details");
        page("network"); check(Network.watching,"network refresh only while visible");click(need("action-ipv4"));check(Clipboard.copied==="192.0.2.4/24","network Copy preserves actual address");
        page("bluetooth");check(!Network.watching && Bluetooth.detailsWatching,"detail watchers follow page");
        page("appearance");check(!Bluetooth.detailsWatching,"Bluetooth detail watcher stops");
        ShellSettings.setShadows(false);Store.saved.ciderToken="keep-secret";
        scrollInto(need("reset-review"));click(need("reset-review"));check(!ShellSettings.shadows,"review does not apply reset");
        check(SettingsReset.reviewing==="appearance" && SettingsReset.changes("appearance").some(c=>c.key==="shadows"),"review enumerates actual shell preferences");
        scrollInto(need("reset-cancel"));click(need("reset-cancel"));check(!ShellSettings.shadows,"cancel leaves preferences intact");
        scrollInto(need("reset-review"));click(need("reset-review"));scrollInto(need("reset-apply"));click(need("reset-apply"));
        check(ShellSettings.shadows && Store.saved.ciderToken==="keep-secret","explicit reset applies shell preferences only: "+JSON.stringify({shadows:ShellSettings.shadows,storedShadows:Store.saved.shadows,secretKept:Store.saved.ciderToken==="keep-secret",review:SettingsReset.reviewing,ready:Store.ready}));
        SettingsReset.review("bluetooth");SettingsReset.apply("bluetooth");check(Store.saved.ciderToken==="keep-secret","no Bluetooth reset");
        Media.players=[{dbusName:"one",identity:"One",isPlaying:true,trackTitle:"A"},{dbusName:"two",identity:"Two",isPlaying:false,trackTitle:"B"}];
        Media.selectPlayer("two");check(Media.player.dbusName==="two","explicit session player wins");
        Media.players=Media.players.slice(0,1);check(Media.player.dbusName==="one" && Media.selectedPlayer==="two" && Media.selectionMissing,"missing selected player falls back temporarily");
        Media.players=Media.players.concat([{dbusName:"two",identity:"Two",isPlaying:false,trackTitle:"B"}]);check(Media.player.dbusName==="two","chosen player returns");
        Media.selectPlayer("");check(Media.player.dbusName==="one","Auto restores playing player");
        page("sound");check(MicCheck.state==="idle","opening Sound never accesses microphone");
        scrollInto(need("mic-meter"));click(need("mic-meter"));input.wait(180);check(MicCheck.state==="metering" && MicCheck.level>0,"explicit meter uses actual service and helper");
        page("apps");input.wait(100);check(MicCheck.state==="idle" && MicCheck.level===0,"leaving closes microphone");
        page("sound");scrollInto(need("mic-record"));click(need("mic-record"));input.wait(2000);check(MicCheck.state==="recorded" && MicCheck.seconds===5,"five seconds only, playback requires click");
        scrollInto(need("mic-play"));click(need("mic-play"));input.wait(100);check(MicCheck.state==="playing","explicit playback");
        SettingsHub.opened=false;input.wait(100);check(MicCheck.state==="idle","closing discards audio");SettingsHub.opened=true;
        page("appearance");
        check(win.width === 1040 && win.height === 760,"default size");
        const surface=need("settings-surface");
        check(surface.contentInsideBorder && surface.contentItem.width===win.width-2*surface.border.width && surface.contentItem.height===win.height-2*surface.border.width,"content stays inside the rounded window border");
        input.wait(250);
        const previousTab=need("settings-nav-appearance");
        win.navigate("sound",""); input.wait(35);
        check(previousTab.background.scale<1 && previousTab.background.scale>0.96,"previous tab animates its selection");
        const animatedPage=need("settings-page-content");
        check(animatedPage.opacity<1 && animatedPage.opacity>=0.65,"page transition starts smoothly");
        input.wait(250); check(Math.abs(animatedPage.opacity-1)<0.01,"page transition finishes visible");
        check(Math.abs(previousTab.background.scale-0.96)<0.001,"tab selection animation finishes");
        page("appearance");
        const before=ShellSettings.shadows;
        click(need("toggle-shadows"));
        check(ShellSettings.shadows!==before,"switch applies immediately");
        page("lens");
        const model=need("choice-lensClaudeModel");
        for (const provider of ["Claude","Codex"]) {
            const label=need("label-"+provider.toLowerCase()), choice=need("choice-lens"+provider+"Model");
            const toggle=need("toggle-"+provider.toLowerCase()), effortChoice=need("choice-lens"+provider+"Effort");
            check(Math.abs(label.mapToItem(win.contentItem,0,0).x-choice.mapToItem(win.contentItem,0,0).x)<1,"fallback text aligns with provider fields");
            check(Math.abs(toggle.mapToItem(win.contentItem,toggle.width,0).x-effortChoice.mapToItem(win.contentItem,effortChoice.width,0).x)<1,"fallback switch aligns with right-side controls");
        }
        click(model);
        check(model.popup.visible,"model options open");
        input.keyClick(Qt.Key_Down); input.keyClick(Qt.Key_Return); input.wait(30);
        check(ShellSettings.lensClaudeModel==="sonnet","model keyboard selection");
        const effort=need("choice-lensCodexEffort");
        click(effort); input.keyClick(Qt.Key_Down); input.keyClick(Qt.Key_Return); input.wait(30);
        check(ShellSettings.lensCodexEffort==="medium","independent Codex effort");
        check(ShellSettings.lensClaudeEffort==="medium","Claude effort preserved");
        check(ShellSettings.lensClaudeCodingModel==="sonnet" && ShellSettings.lensCodexCodingModel==="gpt-6.1-sol" && ShellSettings.lensClaudeCodingEffort==="high" && ShellSettings.lensCodexCodingEffort==="high","independent coding defaults");
        const codingToggle=need("toggle-coding");click(codingToggle);
        check(!ShellSettings.lensSuggestCoding,"coding suggestions can be disabled");click(codingToggle);
        const codingModel=need("choice-lensClaudeCodingModel");scrollInto(codingModel);click(codingModel);
        input.keyClick(Qt.Key_Down);input.keyClick(Qt.Key_Return);input.wait(30);
        check(ShellSettings.lensClaudeCodingModel==="opus" && ShellSettings.lensClaudeModel==="sonnet","coding model choice leaves normal model alone");
        const codingEffort=need("choice-lensCodexCodingEffort");scrollInto(codingEffort);click(codingEffort);
        input.keyClick(Qt.Key_Up);input.keyClick(Qt.Key_Return);input.wait(30);
        check(ShellSettings.lensCodexCodingEffort==="medium" && ShellSettings.lensClaudeCodingEffort==="high","coding efforts stay independent");
        ShellSettings.setLensChoice("lensCodexCodingEffort","invalid");
        check(ShellSettings.lensCodexCodingEffort==="medium","invalid coding choice rejected");
        page("sound");
        const slider=need("level-output");
        input.mouseClick(slider,slider.width*0.35,22);input.wait(30);
        check(Math.abs(Audio.volume-0.35)<0.04,"output volume follows slider input");
        const devices=need("choice-output");
        check(devices.choices[2].disabled,"unplugged device disabled");
        click(devices);input.keyClick(Qt.Key_Down);input.keyClick(Qt.Key_Return);input.wait(30);
        check(Audio.sink.id===2,"output chooser selects device");
        page("display");
        const warmth=need("level-warmth");
        input.mouseClick(warmth,warmth.width*0.8,22);input.wait(30);
        check(NightLight.temperature<4000,"warmth increases toward the right");
        const time=need("time-from");time.forceActiveFocus();time.selectAll();
        for (const ch of "23:15") input.keyClick(ch);input.keyClick(Qt.Key_Tab);input.wait(30);
        check(NightLight.from===1395,"time field saves a real time");
        time.forceActiveFocus();time.selectAll();for(const ch of "29:99")input.keyClick(ch);
        input.keyClick(Qt.Key_Tab);input.wait(20);
        check(NightLight.from===1395,"invalid time preserves previous time");
        NightLight.setSchedule(true,1200,420);input.wait(20);
        check(time.text==="20:00","time field follows external changes after editing");
        page("apps");click(need("action-weather"));input.wait(50);
        check(SettingsHub.editKey==="weather","weather edit opens");
        const field=need("settings-edit-field");field.text="Unknown city";
        input.keyClick(Qt.Key_Return);input.wait(20);
        check(SettingsHub.editBusy,"weather checked before saving");
        const stale=Weather.pending;SettingsHub.cancelEdit();SettingsHub.beginEdit("weather");
        stale({name:"Old response"},"");check(Weather.city==="Before","cancelled lookup ignored");
        SettingsHub.saveEdit("Missing");Weather.pending(null,"No place found");input.wait(20);
        check(SettingsHub.editError==="No place found"&&Weather.city==="Before","invalid city preserves setting and error");
        SettingsHub.saveEdit("Valid");Weather.pending({name:"After"},"");input.wait(20);
        check(Weather.city==="After"&&SettingsHub.editKey==="","valid city saved");
        for(const kind of ["confirm","authorize","service","pin","passkey","display-pin","display-passkey"]) {
            Bluetooth.ask(kind);input.wait(40);
            check(SettingsHub.page==="bluetooth","pairing opens Settings");
            const dialog=win.dialog;
            check(dialog.visible,"pairing dialog visible: "+kind);
            if(kind==="pin"||kind==="passkey") {
                const code=need("settings-edit-field");code.text=kind==="pin"?"AB12":"123456";
                dialog.submit();check(Bluetooth.answerGiven.ok,"code accepted: "+kind);
            } else { input.keyClick(Qt.Key_Escape);input.wait(20);check(!Bluetooth.answerGiven.ok,"cancel declines: "+kind); }
            input.wait(30);
        }
        page("system");check(SystemStats.watching,"stats watched on page");
        page("apps");check(!SystemStats.watching,"stats stop on leaving page");
        const search=need("settings-search");search.text="volume";input.wait(30);
        check(win.results.length===3,"search across all pages");
        search.forceActiveFocus();input.keyClick(Qt.Key_Return);input.wait(40);
        check(SettingsHub.page==="sound"&&SettingsHub.target==="output"&&search.text==="","search result navigates");
        win.implicitWidth=900;win.implicitHeight=620;input.wait(30);
        page("lens");check(need("choice-lensClaudeModel").width>=80,"model fits at minimum size");
        const narrowEffort=need("choice-lensCodexEffort");click(narrowEffort);input.wait(50);
        const bounds=narrowEffort.popup.contentItem.mapToItem(win.contentItem,0,0);
        check(bounds.x>=0 && bounds.x+narrowEffort.popup.contentItem.width<=win.width,"effort options stay inside narrow window");
        input.keyClick(Qt.Key_Escape);input.wait(20);
        LocalSend.available=false;win.showPage("localsend","");input.wait(20);check(SettingsHub.page==="appearance","missing LocalSend stays unavailable");
        page("bluetooth");Bluetooth.setScanning(true);SettingsHub.opened=false;input.wait(30);
        check(!Bluetooth.scanning,"closing stops discovery");
        ShellSettings.setLensSuggestCoding(false);
        input.wait(350);
        return "all passed (controls, selectors, validation, seven pairing kinds, search, watchers, resize)";
    }
    IpcHandler {
        target:"settingsTest"
        function ready():bool{return Store.ready;}
        function writeTime():real{return fixtureWriteMs;}
        function codingState():string{return JSON.stringify({ready:Store.ready,suggest:ShellSettings.lensSuggestCoding,claude:ShellSettings.lensClaudeCodingModel,codexEffort:ShellSettings.lensCodexCodingEffort,normalClaude:ShellSettings.lensClaudeModel});}
        function run():string{try{return runChecks();}catch(error){return "FAIL: "+error.message;}}
    }
}
