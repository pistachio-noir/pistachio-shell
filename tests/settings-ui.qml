import Quickshell
import Quickshell.Io
import QtQuick
import QtTest
import qs
import qs.services
import qs.settings

ShellRoot {
    Component.onCompleted: if (Quickshell.env("PISTACHIO_SETTINGS_NATIVE")==="1") SettingsHub.openPage("appearance", "")
    Binding { target: Theme; property: "tui"; value: ShellSettings.appearanceStyle === "tui" }
    property real fixtureWriteMs
    SettingsWindow { id: win }
    TestCase { id: input; parent: win.contentItem; name: "SettingsControls"; when: false }
    function find(item, name) {
        if (item.objectName === name && item.visible) return item;
        for (const child of item.children) { const match = find(child,name); if(match) return match; }
        return null;
    }
    function need(name) { const item=find(win.contentItem,name) || find(win.dialog.contentItem,name); if(!item) throw new Error("Missing "+name); return item; }
    function hasText(item, value) { if (item.visible && item.text === value) return true; for (const child of item.children) if (hasText(child,value)) return true; return false; }
    function check(ok, why) { if(!ok) throw new Error(why); }
    function click(item) { try { input.mouseClick(item,item.width/2,item.height/2); } catch(e) { throw new Error("Click failed: "+item.objectName+" "+e.message); } input.wait(30); }
    function scrollInto(item) {
        let scroll=item.parent;
        while(scroll && scroll.contentY===undefined) scroll=scroll.parent;
        if(scroll) scroll.contentY=Math.max(0,Math.min(scroll.contentHeight-scroll.height,item.mapToItem(scroll.contentItem,0,0).y-scroll.height/2));
        input.wait(30);
    }
    function page(name) { win.navigate(name,""); input.wait(Quickshell.env("PISTACHIO_SETTINGS_NATIVE")==="1" ? Theme.motionDuration+100 : 30); }
    function capture(name) {
        const folder=Quickshell.env("PISTACHIO_SETTINGS_SHOTS");
        if (!folder) return;
        if (Quickshell.env("PISTACHIO_SETTINGS_NATIVE")==="1") {
            Quickshell.execDetached(["grim", folder+"/"+name+".png"]);
            input.wait(250);
            return;
        }
        const item=win.dialog.visible ? win.dialog.contentItem : need("settings-surface");
        item.grabToImage(result=>result.saveToFile(folder+"/"+name+".png"));
        input.wait(80);
    }
    function runChecks() {
        check(ShellSettings.appearanceStyle === "classic", "missing style defaults to Classic");
        check(!ShellSettings.tuiHyprland, "Hyprland integration defaults off");
        check(!ShellSettings.phonePreview, "phone preview defaults off");
        check(!ShellSettings.devFeatures, "dev features default off (opt-in)");
        check(!ShellSettings.gameMode && ShellSettings.gameClasses.length === 0, "game mode defaults off with no extra classes");
        check(!ShellSettings.desktopCat, "desktop cat defaults off");
        check(!ShellSettings.clipboardHistory, "clipboard history defaults off");
        check(!ShellSettings.monochromeWallpaper, "monochrome wallpaper defaults off");
        ShellSettings.setAppearanceStyle("tui");
        check(ShellSettings.appearanceStyle === "tui" && Theme.tui, "style applies live");
        // Native fixture stubs compositor remapping; exercise watcher-only lifecycle offscreen.
        if(Quickshell.env("PISTACHIO_SETTINGS_NATIVE")!=="1") {
            SettingsHub.opened=false;input.wait(30);
            check(SystemStats.watching, "TUI keeps stats watched with Settings closed");
            win.minimized=true;input.wait(30);check(SystemStats.watching,"TUI keeps stats watched while minimized");win.minimized=false;
        }
        ShellSettings.setAppearanceStyle("invalid");
        check(ShellSettings.appearanceStyle === "tui", "invalid style is rejected");
        Store.saved.appearanceStyle = "broken";
        check(ShellSettings.appearanceStyle === "classic", "invalid stored style defaults to Classic");
        ShellSettings.setAppearanceStyle("classic");
        ShellSettings.setShadows(false);Store.fixtureWriteNow();ShellSettings.setShadows(true);input.wait(500);
        const oldNotifications=Store.saved.notifications;
        Store.saved.notifications=Array.from({length:200},(_,i)=>({id:i,body:"fixture".repeat(200)}));
        const began=Date.now();Store.fixtureWriteNow();fixtureWriteMs=Date.now()-began;
        Store.saved.notifications=oldNotifications;Store.fixtureWriteNow();
        check(Store.saved.shadows && ShellSettings.shadows,"newer preference must survive completion of an older save");
        for(const name of ["appearance","display","sound","notifications","bluetooth","network","localsend","lens","apps","system","health","about"]) page(name);
        page("appearance");
        // performance notes under visual settings (20 November 2026)
        const frostImpact=find(win.contentItem,"impact-frost"),shadowImpact=find(win.contentItem,"impact-shadows");
        check(frostImpact&&frostImpact.visible&&frostImpact.children[1].text==="Performance impact: Medium","frost shows a Medium impact note");
        check(shadowImpact&&shadowImpact.visible&&shadowImpact.children[1].text==="Performance impact: Low","shadows show a Low impact note");
        check(!find(win.contentItem,"impact-wallpaper")?.visible,"no note on the wallpaper picker");
        const aboutNav=need("settings-nav-about");
        for(let i=0;i<9;i++) click(aboutNav);
        check(!find(win.contentItem,"about-fun"),"nine About presses do not reveal the surprise");
        click(aboutNav);check(!!find(win.contentItem,"about-fun"),"tenth About press reveals surprise");capture("about-fun");
        check(!find(win.contentItem,"about-normal-header"),"normal About header is hidden in fun mode");
        check(need("label-branch").text === "The branch we’re perched on" && need("label-build").text === "Today’s shell specimen", "build details are presented in the cat report");
        check(!!need("setting-quickshell") && !!need("setting-hyprland") && !!need("setting-qt") && !!need("action-source") && !!need("action-export") && !!need("action-import"),"versions and About actions remain available");
        scrollInto(need("action-setup"));click(need("action-setup"));check(FirstRun.opened && !SettingsHub.opened,"About → Run setup closes Settings and opens first-run setup");SettingsHub.openPage("about","");input.wait(30);for(let i=0;i<10;i++) click(need("settings-nav-about"));
        check(hasText(need("setting-branch"),About.branch) && hasText(need("setting-build"),About.commit) && hasText(need("setting-quickshell"),About.quickshell) && hasText(need("setting-hyprland"),About.hyprland) && hasText(need("setting-qt"),About.qt),"fun report shows real branch, build and versions");
        scrollInto(need("setting-branch"));capture("about-build");
        ShellSettings.setAppearanceStyle("tui");input.wait(100);check(!!need("about-fun") && !find(win.contentItem,"about-normal-header") && hasText(need("setting-build"),About.commit),"fun report and build details remain in TUI");ShellSettings.setAppearanceStyle("classic");input.wait(100);
        page("appearance");page("about");check(!!find(win.contentItem,"about-fun"),"surprise persists across pages");
        SettingsHub.opened=false;input.wait(250);page("about");check(!find(win.contentItem,"about-fun") && !!need("about-normal-header") && need("label-branch").text === "Branch","closing Settings restores normal About");
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
        check(win.width === 1040 && win.height === 760,"default size: "+win.width+"x"+win.height+" style="+ShellSettings.appearanceStyle);
        const originalSearchWidth=win.width;
        const originalSearchX=need("settings-search").mapToItem(win.contentItem,0,0).x;
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
        page("appearance");input.wait(60);
        check(AppTheming.enabled && need("toggle-theming").checked!==false, "theming integration shows on by default");
        click(need("toggle-theming"));check(!AppTheming.enabled,"theming switch turns it off");click(need("toggle-theming"));check(AppTheming.enabled,"and on again");
        check(hasText(need("setting-theming-kitty"),"Follows Colours") && !!need("action-theming-neovim"),"apps list their state, own theme offers Use Pistachio");
        click(need("action-theming-neovim"));check(AppTheming.used==="neovim","Use Pistachio on the row sets it up");AppTheming.used="";
        AppTheming.conflict=AppTheming.apps[1];input.wait(60);
        check(win.dialog.visible && hasText(win.dialog.contentItem,"Neovim has its own theme"),"a conflict asks in the Settings dialog");
        win.dialog.cancel();input.wait(60);check(AppTheming.kept.includes("neovim") && !win.dialog.visible,"Keep mine keeps the app's theme");
        AppTheming.conflict=AppTheming.apps[0];input.wait(60);check(win.dialog.visible && hasText(win.dialog.contentItem,"Kitty has its own theme"),"the next conflict shows after the first");
        win.dialog.submit();input.wait(60);check(AppTheming.used==="kitty" && !win.dialog.visible,"Use Pistachio in the dialog sets it up");
        const placed={appearance:["setting-colours","setting-monochrome-wallpaper","setting-desktop-cat"],apps:["setting-clipboard-history"],health:["setting-restart-shell","setting-force-restart-shell"],experimental:["setting-style","setting-tui-hyprland","setting-game-mode","setting-game-classes","setting-phone-preview","setting-dev-features","setting-cat-skin"]};
        for (const where of Object.keys(placed)) { page(where);input.wait(60); for (const id of placed[where]) check(!!find(win.contentItem,id),id+" is on "+where); }
        page("appearance");const catToggle=need("toggle-desktop-cat");scrollInto(catToggle);click(catToggle);check(ShellSettings.desktopCat,"cat switch enables preference");click(catToggle);check(!ShellSettings.desktopCat,"cat switch disables preference");
        page("experimental");input.wait(60);for (const id of ["setting-colours","setting-monochrome-wallpaper","setting-desktop-cat","setting-clipboard-history","setting-restart-shell"]) check(!find(win.contentItem,id),id+" left Experimental");
        const roundingToggle=need("toggle-tui-hyprland");scrollInto(roundingToggle);
        click(roundingToggle);check(ShellSettings.tuiHyprland, "Settings turns Hyprland integration on");
        const catSkin=need("choice-cat-skin");scrollInto(catSkin);click(catSkin);
        input.keyClick(Qt.Key_Down);input.keyClick(Qt.Key_Return);input.wait(30);
        check(ShellSettings.catSkin==="ginger","cat coat picker applies Ginger");
        SettingsReset.review("experimental");SettingsReset.apply("experimental");
        check(!ShellSettings.tuiHyprland, "Experimental reset turns the integration off");
        check(ShellSettings.catSkin==="cream","Experimental reset restores the original coat");
        page("experimental");scrollInto(need("toggle-game-mode"));click(need("toggle-game-mode"));input.wait(20);check(ShellSettings.gameMode,"game mode switch turns on");
        click(need("action-game-classes"));input.wait(50);check(SettingsHub.editKey==="games","extra game windows edit opens");
        need("settings-edit-field").text="Minecraft, foo";input.keyClick(Qt.Key_Return);input.wait(20);
        check(SettingsHub.editKey===""&&JSON.stringify(ShellSettings.gameClasses)==='["minecraft","foo"]',"game classes saved lowercase");
        SettingsHub.beginEdit("games");SettingsHub.saveEdit("bad class!");input.wait(20);
        check(SettingsHub.editError!==""&&SettingsHub.editKey==="games"&&ShellSettings.gameClasses.length===2,"bad class refused, list kept");
        SettingsHub.saveEdit("");input.wait(20);
        check(SettingsHub.editKey===""&&ShellSettings.gameClasses.length===0,"empty input clears game classes");
        ShellSettings.setGameMode(false);
        for(const kind of ["confirm","authorize","service","pin","passkey","display-pin","display-passkey"]) {
            Bluetooth.ask(kind);input.wait(40);
            check(SettingsHub.page==="bluetooth","pairing opens Settings");
            const dialog=win.dialog;
            capture("classic-pair-"+kind);
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
        ShellSettings.setAppearanceStyle("tui");
        input.wait(180);
        win.implicitWidth=1040;win.implicitHeight=800;
        page("appearance");
        check(need("settings-surface").radius===0, "TUI Settings has square frame");
        check(need("settings-sidebar").width===224, "TUI sidebar matches board width");
        const appearanceNav = need("settings-nav-appearance");
        const appearanceIcon = appearanceNav.children.find(child => child.paths?.length);
        check(appearanceIcon?.visible && appearanceIcon.x + appearanceIcon.width < appearanceNav.contentItem.x, "TUI Settings shows a sidebar icon with room before the label");
        check(need("settings-header").height===52, "TUI header matches board height");
        check(need("toggle-shadows").contentItem.text.includes("["), "TUI toggle draws bracket state");
        LocalSend.available=true;
        for (const name of ["appearance","display","sound","notifications","focus","integrations","bluetooth","network","localsend","lens","apps","system","health","experimental","about"]) {
            page(name);input.wait(90);
            check(need("settings-page-content").opacity > 0.99, "TUI page fade finishes quickly: "+name);
            capture("tui-"+name);
        }
        for (const size of [[1040,800],[900,620]]) {
            win.implicitWidth=size[0];win.implicitHeight=size[1];input.wait(30);
            page("lens");
            const choice=need("choice-lensClaudeModel");scrollInto(choice);click(choice);input.wait(30);
            if (size[0]===1040) {
                const filter=input.findChild(choice.popup.contentItem,"choice-filter");
                check(filter && filter.visible, "TUI model selector offers filter");
                filter.forceActiveFocus();filter.selectAll();
                for(const ch of "Opus") input.keyClick(ch);
                input.wait(40);
                check(choice.shownChoices.length===1 && choice.shownChoices[0].value==="opus", "model filter matches real choices");
                input.keyClick(Qt.Key_Down);input.keyClick(Qt.Key_Return);input.wait(50);
                check(ShellSettings.lensClaudeModel==="opus" && !choice.popup.visible, "model filter Down and Enter selects the match");
                click(choice);input.wait(30);
            }
            capture("tui-model-"+size[0]);
            const point=choice.popup.contentItem.mapToItem(win.contentItem,0,0);
            check(point.x>=0 && point.x+choice.popup.contentItem.width<=win.width, "TUI model popup contained");
            input.keyClick(Qt.Key_Escape);
            page("sound");const level=need("level-output");scrollInto(level);
            input.mouseClick(level,level.width*0.7,22);input.wait(90);
            check(Math.abs(Audio.volume-0.7)<0.06, "TUI volume drag retains input contract");
            page("display");const heat=need("level-warmth");scrollInto(heat);
            input.mouseClick(heat,heat.width*0.8,22);input.wait(90);
            check(NightLight.temperature<4000, "TUI slider keeps Kelvin units");
            page("apps");SettingsHub.beginEdit("weather");input.wait(40);
            check(win.dialog.visible, "TUI edit opens");
            const saveButton=win.dialog.contentItem.children.find(c=>c.children && c.children.some(b=>b.text==="Save"))?.children.find(b=>b.text==="Save");
            check(saveButton && saveButton.contentItem.width >= saveButton.contentItem.implicitWidth, "TUI Save label fits its button");
            SettingsHub.editError="No location found. Try a city and country.";
            capture("tui-weather-error-"+size[0]);
            ShellSettings.setAppearanceStyle("classic");input.wait(90);
            check(win.dialog.visible && SettingsHub.editKey==="weather", "switch retains pending edit");
            input.keyClick(Qt.Key_Escape);input.wait(40);
            ShellSettings.setAppearanceStyle("tui");input.wait(90);
        }
        win.implicitWidth=1040;win.implicitHeight=800;input.wait(30);
        for(const kind of ["confirm","authorize","service","pin","passkey","display-pin","display-passkey"]) {
            Bluetooth.ask(kind);input.wait(50);capture("tui-pair-"+kind);win.dialog.cancel();input.wait(30);
        }
        page("network");Network.connected=false;Network.hasLink=false;input.wait(50);capture("tui-network-unplugged");Network.connected=true;Network.hasLink=true;
        page("bluetooth");Bluetooth.nearby=[{name:"Desk speaker",address:"fixture"}];
        need("settings-page-content").discovering=true;input.wait(50);capture("tui-bluetooth-scan");
        Bluetooth.nearby=[];Bluetooth.scanning=false;input.wait(50);capture("tui-bluetooth-empty");
        page("sound");
        Audio.streams=[{id:99,name:"Fixture music",audio:{volume:0.5,muted:false}}];
        need("settings-page-content").soundTab="applications";input.wait(50);
        const appRow=need("setting-stream:99"), appLabel=need("label-stream:99");
        const muteButton=appRow.children.find(c=>c.visible && c.text==="[x]");
        check(muteButton && muteButton.mapToItem(appRow,muteButton.width,0).x <= appLabel.mapToItem(appRow,0,0).x, "TUI application mute reserves space beside label");
        capture("tui-sound-applications");
        page("sound");need("settings-page-content").soundTab="devices";input.wait(40);const outputChoice=need("choice-output");click(outputChoice);capture("tui-sound-output");input.keyClick(Qt.Key_Escape);
        page("apps");const terminalChoice=need("choice-terminal");click(terminalChoice);capture("tui-terminal");input.keyClick(Qt.Key_Escape);
        page("lens");const effortChoice=need("choice-lensClaudeEffort");scrollInto(effortChoice);click(effortChoice);capture("tui-effort");input.keyClick(Qt.Key_Escape);
        page("appearance");
        const tuiSearch=need("settings-search");tuiSearch.text="volume";input.wait(50);
        check(need("level-output").visible && need("toggle-tick").visible, "TUI search exposes actual level and toggle controls");
        capture("tui-search");
        const wasTick=ShellSettings.volumeTick;click(need("toggle-tick"));
        check(ShellSettings.volumeTick!==wasTick, "TUI search control applies real preference");
        tuiSearch.text="";
        page("health");for (const mode of ["restart", "force-restart"]) { const button=need("action-"+mode+"-shell"); scrollInto(button); click(button); check(win.dialog.visible && SettingsHub.restartMode===mode,"restart asks for confirmation"); win.dialog.cancel(); check(SettingsHub.restartMode==="","restart cancellation"); } page("experimental");input.wait(60);const phoneToggle=need("toggle-phone-preview");scrollInto(phoneToggle);click(phoneToggle);check(ShellSettings.phonePreview,"phone preview switch enables preference");click(phoneToggle);check(!ShellSettings.phonePreview,"phone preview switch disables preference");const devToggle=need("toggle-dev-features");scrollInto(devToggle);click(devToggle);check(ShellSettings.devFeatures,"dev features switch enables preference");click(devToggle);check(!ShellSettings.devFeatures,"dev features switch disables preference");page("apps");input.wait(60);const clipToggle=need("toggle-clipboard-history");scrollInto(clipToggle);click(clipToggle);check(ShellSettings.clipboardHistory,"clipboard history switch enables preference");click(clipToggle);check(!ShellSettings.clipboardHistory,"clipboard history switch disables preference");page("appearance");input.wait(60);const monoToggle=need("toggle-monochrome-wallpaper");scrollInto(monoToggle);click(monoToggle);check(ShellSettings.monochromeWallpaper,"wallpaper switch enables preference");click(monoToggle);check(!ShellSettings.monochromeWallpaper,"wallpaper switch disables preference");page("experimental");input.wait(60);const styleChoice=need("choice-style");scrollInto(styleChoice);click(styleChoice);
        input.keyClick(Qt.Key_Up);input.keyClick(Qt.Key_Return);input.wait(150);
        check(!Theme.tui && ShellSettings.appearanceStyle==="classic", "Appearance selector switches to Classic live");
        click(styleChoice);input.keyClick(Qt.Key_Down);input.keyClick(Qt.Key_Return);input.wait(150);
        check(Theme.tui && ShellSettings.appearanceStyle==="tui", "Appearance selector switches to TUI live");
        ShellSettings.setAppearanceStyle("classic");input.wait(180);
        win.implicitWidth=1040;win.implicitHeight=760;input.wait(Quickshell.env("PISTACHIO_SETTINGS_NATIVE")==="1"?300:30);
        check(Math.abs(need("settings-search").mapToItem(win.contentItem,0,0).x-originalSearchX-(win.width-originalSearchWidth))<1, "Classic search position survives style roundtrip: "+JSON.stringify({before:originalSearchX,after:need("settings-search").mapToItem(win.contentItem,0,0).x,width:win.width,height:win.height}));
        check(need("settings-surface").radius===28 && Theme.fontUi==="Manrope", "Classic frame and font restored");
        ShellSettings.setAppearanceStyle("tui");
        input.wait(50);
        check(Theme.tui && Theme.fontUi === "JetBrainsMono Nerd Font", "TUI uses installed Nerd font");
        check(!hasText(need("settings-header"), "[_]"), "TUI Settings header has no minimise button");
        const headerBacking=need("settings-title-backing");
        check(headerBacking.color===Theme.bg && headerBacking.height===need("settings-surface").y && headerBacking.opacity===1, "TUI title gap is solid");
        page("appearance");
        check(!find(win.contentItem,"setting-desktop"), "TUI hides the desktop icons control");
        check(!!find(win.contentItem,"setting-desktop-cat"), "desktop cat controls are available in TUI");
        check(!!find(win.contentItem,"setting-wallpaper"), "wallpaper controls are available in TUI");
        const desktopSearch=need("settings-search");
        desktopSearch.text="desktop icons";check(win.results.length===0, "TUI desktop icons controls are absent from search");
        desktopSearch.text="desktop cat";check(win.results.some(r=>r[1]==="desktop-cat"), "TUI desktop cat control is searchable");
        desktopSearch.clear();
        ShellSettings.setLensSuggestCoding(false);
        input.wait(350);
        return "all passed (controls, selectors, validation, seven pairing kinds, search, watchers, resize)";
    }
    IpcHandler {
        target:"settingsTest"
        function ready():bool{return Store.ready;}
        function writeTime():real{return fixtureWriteMs;}
        function codingState():string{return JSON.stringify({ready:Store.ready,style:ShellSettings.appearanceStyle,suggest:ShellSettings.lensSuggestCoding,claude:ShellSettings.lensClaudeCodingModel,codexEffort:ShellSettings.lensCodexCodingEffort,normalClaude:ShellSettings.lensClaudeModel});}
        function run():string{try{return runChecks();}catch(error){return "FAIL: "+error.message+"\n"+error.stack;}}
    }
}
