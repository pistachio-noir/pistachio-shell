import Quickshell
import Quickshell.Io
import QtQuick
import QtTest
import qs.services
import qs.settings

ShellRoot {
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
    function page(name) { win.navigate(name,""); input.wait(30); }
    function runChecks() {
        for(const name of ["appearance","display","sound","notifications","bluetooth","network","localsend","lens","apps","system","about"]) page(name);
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
        return "all passed (controls, selectors, validation, seven pairing kinds, search, watchers, resize)";
    }
    IpcHandler {
        target:"settingsTest"
        function ready():bool{return Store.ready;}
        function run():string{try{return runChecks();}catch(error){return "FAIL: "+error.message;}}
    }
}
