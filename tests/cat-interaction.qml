import qs
import qs.panels
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick
import QtTest
ShellRoot {
    id:root
    FloatingWindow {
        id:window; visible:true; implicitWidth:500; implicitHeight:400
        DesktopCat { id:cat; x:238; y:30; active:true; interactive:true; skin:ShellSettings.catSkin }
        DesktopIcons {
            id:icons; anchors.fill:parent
            onCatHover:(p,inside)=>cat.hovered=inside && cat.visible && cat.contains(cat.mapFromItem(icons,p.x,p.y))
            onCatClick:p=>{if(cat.visible && cat.contains(cat.mapFromItem(icons,p.x,p.y)))cat.pet()}
        }
        MouseArea { anchors.fill:cat;enabled:FocusMode.zen && !Showoff.active && cat.visible;visible:enabled;hoverEnabled:true;onEntered:cat.hovered=true;onExited:cat.hovered=false;onEnabledChanged:if(!enabled)cat.hovered=false;onClicked:cat.pet() }
    }
    TestCase { id:input; parent:window.contentItem; when:false }
    function run(){
        Compositor.windows=[];Compositor.workspaces=[{id:1,active:true,occupied:false}];input.wait(100);
        if(!cat.active)throw Error('cat appears on an empty workspace');
        if(cat.coat.value!=="cream")throw Error('Cream is the default coat');
        ShellSettings.catSkin="midnight";
        if(cat.coat.value!=="midnight")throw Error('the visible cat changes coat live');
        ShellSettings.catSkin="cream";
        cat.sayIdle();if(!cat.reactionText)throw Error('visible cat speaks');
        Clocks.ringing={kind:'timer'};input.wait(50);if(cat.reactionText!=="Timer's up!")throw Error('timer reaction');
        Clocks.ringing={kind:'alarm'};input.wait(50);if(cat.reactionText!=="Alarm time!")throw Error('alarm reaction');
        FocusMode.phaseFinished('Break time!');input.wait(50);if(cat.reactionText!=="Break time!")throw Error('focus reaction');
        cat.sayIdle();if(cat.reactionText!=="Break time!")throw Error('idle speech must not interrupt reaction');
        input.tryVerify(()=>cat.reactionText==='',5000);
        Clocks.ringing=null;
        ShellSettings.desktopCat=false;input.wait(50);Clocks.ringing={kind:'timer'};input.wait(50);
        if(cat.reactionText!=='')throw Error('hidden cat must ignore reactions');
        ShellSettings.desktopCat=true;Clocks.ringing=null;input.wait(50);
        Compositor.windows=[{workspace:1,floating:true,hidden:false,minimized:false}];Compositor.workspaces=[{id:1,active:true,occupied:true}];input.wait(100);
        if(!cat.active)throw Error('floating window must not hide cat');
        Compositor.focusedWindow={appId:"com.microsoft.VSCode",title:"Fixture editor"};
        if(!cat.atLaptop)throw Error('focused floating VS Code shows the laptop');
        Media.players=[{isPlaying:false},{isPlaying:true}];
        if(!cat.wearingHeadphones || !cat.atLaptop)throw Error('playing media adds headphones alongside the laptop');
        Clocks.timers=[{endsAt:Date.now()+60000}];
        if(!cat.holdingClock || cat.atLaptop || !cat.wearingHeadphones)throw Error('running timer takes the laptop’s place and keeps headphones');
        Clocks.timers=[{endsAt:0,left:60000}];
        if(cat.holdingClock || !cat.atLaptop)throw Error('paused timer gives the laptop back');
        Clocks.stopwatch={since:Date.now()};
        if(!cat.holdingClock)throw Error('running stopwatch shows the clock');
        Clocks.stopwatch={since:0};
        if(cat.holdingClock)throw Error('paused stopwatch puts the clock down');
        for (const session of [{owner:"focus",phase:"work"},{owner:"pomodoro",phase:"break"},{owner:"zen",phase:"work"}]) {
            FocusMode.session=Object.assign({endsAt:Date.now()+60000}, session);
            if(!cat.holdingClock)throw Error('active focus or Pomodoro phase shows the clock');
            FocusMode.session=Object.assign({endsAt:0}, session);
            if(cat.holdingClock)throw Error('paused focus or Pomodoro phase puts the clock down');
        }
        FocusMode.session=null;Clocks.timers=[];Clocks.stopwatch=null;
        Media.players=[{isPlaying:false}];
        if(cat.wearingHeadphones)throw Error('pause takes the headphones off');
        Compositor.focusedWindow={appId:"dev.neovide.neovide",title:"Fixture editor"};
        if(!cat.atLaptop)throw Error('Neovide app ID shows the laptop');
        Compositor.focusedWindow={appId:"kitty",title:"nvim src/main.rs"};
        if(!cat.atLaptop)throw Error('terminal Neovim title shows the laptop');
        Compositor.focusedWindow={appId:"helium",title:"Neovim documentation"};
        if(cat.atLaptop)throw Error('a browser page about Neovim leaves the laptop idle');
        Compositor.focusedWindow={appId:"code",title:"Fixture editor"};
        Compositor.windows=[{workspace:1,floating:false,hidden:false,minimized:false}];input.wait(100);
        if(cat.active || cat.atLaptop)throw Error('tiled VS Code hides the cat and its laptop');
        Compositor.focusedWindow=null;Media.players=[];
        Compositor.windows=[{workspace:1,floating:true},{workspace:1,floating:false}];input.wait(100);
        if(cat.active)throw Error('tiled window hides cat even with floating windows');
        Compositor.windows=[{workspace:2,floating:false,hidden:false,minimized:false}];input.wait(100);
        if(!cat.active)throw Error('other workspace does not hide cat');
        Compositor.fullscreen=true;input.wait(100);if(cat.active)throw Error('fullscreen hides cat');
        Compositor.fullscreen=false;Compositor.workspaces=[];input.wait(100);if(cat.active)throw Error('unknown workspace hides cat');
        Compositor.workspaces=[{id:1,active:true,occupied:true}];Compositor.windows=[{workspace:1,floating:true}];input.wait(100);
        input.wait(200);
        input.mouseMove(window.contentItem,270,70);input.wait(100);
        if(!cat.hovered) throw Error('hover reaches cat through desktop background');
        input.mouseClick(window.contentItem,270,70);input.wait(60);
        if(!cat.happy) throw Error('click on empty desktop pets cat');
        input.mouseClick(window.contentItem,270,70);
        input.mouseClick(window.contentItem,270,70);
        if(!cat.purring)throw Error('three quick pets start a purr');
        const shot=Quickshell.env('PISTACHIO_CAT_HAPPY_SHOT');if(shot){cat.grabToImage(r=>r.saveToFile(shot));input.wait(250);}
        input.tryVerify(()=>!cat.happy,3500);
        if(cat.purring)throw Error('purring ends when petting settles');
        cat.sayIdle();
        if(!cat.laptopPose)throw Error('the second idle beat puts the cat on a laptop');
        Clocks.ringing={kind:'timer'};
        if(cat.laptopPose || cat.reactionText!=="Timer's up!")throw Error('timer reaction replaces the laptop pose');
        Clocks.ringing=null;cat.clearReaction();
        Desktop.items=[{name:'fixture',kind:'folder',url:'file:///tmp/fixture'}];input.wait(150);
        input.mouseClick(window.contentItem,270,70);input.wait(60);
        if(cat.happy || icons.selection.indexOf('fixture')<0)throw Error('icon over cat retains its click');
        Desktop.items=[];FocusMode.zen=true;input.wait(100);input.mouseClick(window.contentItem,270,70);input.wait(60);
        if(!cat.happy)throw Error('cat can be petted while Zen hides desktop icons');
        FocusMode.zen=false;ShellSettings.desktopCat=false;input.wait(80);
        if(cat.happy || cat.purring || cat.laptopPose || cat.hovered || cat.animating)throw Error('hidden cat clears interactions and stops');
        ShellSettings.desktopCat=true;Theme.tui=true;input.wait(150);
        if(!cat.visible || !cat.animating)throw Error('TUI keeps the desktop cat');
        input.mouseClick(window.contentItem,270,70);input.wait(60);
        if(!cat.happy)throw Error('TUI cat can be petted without Zen');
        Theme.tui=false;FocusMode.zen=false;input.wait(150);
        if(!cat.visible || !ShellSettings.desktopCat)throw Error('Classic restores the saved desktop cat');
        return 'PASS desktop cat interaction, coats, activity props, icon priority and hidden cleanup';
    }
    IpcHandler {target:'catTest';function ready():bool{return true;}function run():string{try{return root.run()}catch(e){return 'FAIL '+e.message+'\n'+e.stack}}}
}
