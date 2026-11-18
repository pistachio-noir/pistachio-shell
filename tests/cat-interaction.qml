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
        DesktopCat { id:cat; x:238; y:30; active:true; interactive:true }
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
        Compositor.windows=[{workspace:1,floating:false,hidden:false,minimized:false}];input.wait(100);
        if(cat.active)throw Error('tiled window hides cat');
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
        const shot=Quickshell.env('PISTACHIO_CAT_HAPPY_SHOT');if(shot){cat.grabToImage(r=>r.saveToFile(shot));input.wait(250);}
        input.tryVerify(()=>!cat.happy,3500);
        Desktop.items=[{name:'fixture',kind:'folder',url:'file:///tmp/fixture'}];input.wait(150);
        input.mouseClick(window.contentItem,270,70);input.wait(60);
        if(cat.happy || icons.selection.indexOf('fixture')<0)throw Error('icon over cat retains its click');
        Desktop.items=[];FocusMode.zen=true;input.wait(100);input.mouseClick(window.contentItem,270,70);input.wait(60);
        if(!cat.happy)throw Error('cat can be petted while Zen hides desktop icons');
        FocusMode.zen=false;ShellSettings.desktopCat=false;input.wait(80);
        if(cat.happy || cat.hovered || cat.animating)throw Error('hidden cat clears interactions and stops');
        return 'PASS desktop hover, pet, icon priority and hidden cleanup';
    }
    IpcHandler {target:'catTest';function ready():bool{return true;}function run():string{try{return root.run()}catch(e){return 'FAIL '+e.message+'\n'+e.stack}}}
}
