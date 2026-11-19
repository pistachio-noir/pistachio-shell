import qs
import qs.launcher
import qs.components
import qs.panels
import Quickshell
import Quickshell.Io
import QtQuick
import QtTest
Scope {
    property string tapped
    DesktopCat { id: cat; parent:win.contentItem; active:false }
    Switch { id: probeSwitch; parent:win.contentItem;y:100;checked:true }
    Slider { id: probeSlider;parent:win.contentItem;x:80;y:100;width:240; from:2500;to:6500;value:4500 }

    FloatingWindow {
        id:win; visible:true; implicitWidth:640; implicitHeight:240
        ActionButton { id:normal; x:8; y:180; text:"Open" }
        ActionButton { id:bounded; x:120; y:180; text:"A very long action which must fit inside its available space"; maximumWidth:180 }
        ActionButton { id:wide; x:8; y:230; width:140; text:"Stop" }
        KeyHints { id:footer; width:parent.width; hints:[]; clickableKeys:({"Esc":true}); onActivated:key=>tapped=key }
    }
    PanelFrame { id:frame;parent:win.contentItem;width:192;height:80;title:"A very long window title that must stay inside the frame";detail:"workspace information";visible:false }
    TestCase { id:input; when:false }
    function checkCat() {
        if(cat.visible || cat.animating) throw Error("disabled desktop cat remains idle");
        cat.active=true;input.wait(100);cat.pet();if(cat.happy)throw Error("decorative cat cannot be petted");cat.interactive=true;if(!cat.visible || !cat.animating)throw Error("active desktop cat animates");
        cat.pet();if(!cat.happy)throw Error("pet makes cat happy");
        cat.active=false;input.wait(50);if(cat.happy)throw Error("hidden cat clears interaction");cat.active=true;
        const path=Quickshell.env("PISTACHIO_CAT_SHOT");if(path){cat.grabToImage(r=>r.saveToFile(path));input.wait(200);}
        cat.active=false;input.wait(50);if(cat.visible || cat.animating)throw Error("hidden desktop cat stops animating");
    }
    IpcHandler {
        target:"layoutTest"
        function ready():bool {return true;}
        function run():string {
            try {
                input.wait(50);
                const normalLabel=normal.children.find(c=>c.text!==undefined),boundedLabel=bounded.children.find(c=>c.text!==undefined);
                if (Math.abs(normal.width-normalLabel.implicitWidth-32)>.5 || bounded.width>180 || boundedLabel.width>=boundedLabel.implicitWidth) throw Error("action button natural size or bounded elision");
                const wideLabel=wide.children.find(c=>c.text!==undefined);
                const glyphCentre=wideLabel.x+(wideLabel.width-wideLabel.contentWidth)*(wideLabel.horizontalAlignment===Text.AlignHCenter?0.5:0)+wideLabel.contentWidth/2;
                if (Math.abs(glyphCentre-wide.width/2)>1) throw Error("a short label in a fixed-width action button sits in the middle: "+glyphCentre+" vs "+wide.width/2);
                for (const width of [640,480,320]) {
                    tapped=""; win.width=width;
                    footer.hints=[["↵","switch"],["Ctrl W","close window"],["Ctrl F","float"],["Ctrl P","pin"],["Ctrl 1–9","move"],["Esc","close"]];
                    input.wait(80);
                    const flow=input.findChild(footer,"key-hints-flow");
                    for (const hint of flow.children) {
                        if (!hint.visible || hint.modelData===undefined) continue;
                        const p=hint.mapToItem(footer,0,0);
                        if (p.x<0 || p.x+hint.width>footer.width+.5 || p.y+hint.height>footer.height+.5) throw Error("clipped hint "+JSON.stringify({width:width,key:hint.modelData[0],x:p.x,right:p.x+hint.width,height:footer.height}));
                        if (hint.modelData[0]==="Esc") input.mouseClick(hint,hint.width/2,hint.height/2);
                    }
                    if (tapped!=="Esc") throw Error("wrapped hint must remain clickable");
                }
                checkCat();
                Theme.tui=true;input.wait(100);
                for(const tab of frame.children){if(tab.width===undefined||!tab.visible)continue;const at=tab.mapToItem(frame,0,0);if(at.x<0||at.x+tab.width>frame.width)throw Error("long title/detail escape frame");}
                const state=input.findChild(probeSwitch,"switch-state");
                if(!state || state.text!=="[x]") throw Error("TUI switch reflects on state");
                probeSwitch.checked=false;input.wait(100);
                if(state.text!=="[ ]") throw Error("TUI switch reflects off state");
                if(Math.abs(probeSlider.shownValue-4500)>1) throw Error("TUI meter preserves original units");
                probeSlider.value=2500;input.wait(100);
                const meter=input.findChild(probeSlider,"slider-meter");
                if(!meter) throw Error("TUI meter is present");
                const emptyWidth=meter.implicitWidth;
                if(probeSlider.filledCells!==0) throw Error("TUI meter empty at lower endpoint");
                probeSlider.value=6500;input.wait(100);
                if(Math.abs(meter.implicitWidth-emptyWidth)>1) throw Error("TUI meter brackets stay fixed at empty and full");
                if(probeSlider.filledCells!==probeSlider.cells) throw Error("TUI meter full at upper endpoint");
                probeSlider.value=4500;input.wait(100);
                if(Math.abs(meter.implicitWidth-emptyWidth)>1) throw Error("TUI meter width fixed at midpoint");
                probeSlider.LayoutMirroring.enabled=true;input.wait(100);
                if(!probeSlider.mirrored || !meter.text.startsWith("[&nbsp;")) throw Error("mirrored TUI fill starts from the right");
                probeSlider.LayoutMirroring.enabled=false;input.wait(100);
                input.mousePress(probeSlider,20,22);input.mouseMove(probeSlider,200,22,30);input.mouseRelease(probeSlider,200,22);input.wait(100);
                if(probeSlider.value<5500) throw Error("TUI meter drag changes real value");
                probeSlider.forceActiveFocus();const oldValue=probeSlider.value;input.keyClick(Qt.Key_Left);input.wait(100);
                if(probeSlider.value>=oldValue) throw Error("TUI meter keyboard preserves input");
                probeSlider.enabled=false;const disabledValue=probeSlider.value;input.mouseClick(probeSlider,20,22);input.wait(100);
                if(probeSlider.value!==disabledValue) throw Error("disabled TUI meter changes value");
                Theme.tui=false;input.wait(100);
                if(normal.radius!==normal.height/2) throw Error("Classic button restored");
                return "PASS footer hints fit and remain clickable at 640/480/320 px";
            } catch(e) { return "FAIL "+e; }
        }
    }
}
