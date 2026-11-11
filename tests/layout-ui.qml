import qs
import qs.launcher
import qs.components
import Quickshell
import Quickshell.Io
import QtQuick
import QtTest
Scope {
    property string tapped
    FloatingWindow {
        id:win; visible:true; implicitWidth:640; implicitHeight:240
        ActionButton { id:normal; x:8; y:180; text:"Open" }
        ActionButton { id:bounded; x:120; y:180; text:"A very long action which must fit inside its available space"; maximumWidth:180 }
        KeyHints { id:footer; width:parent.width; hints:[]; clickableKeys:({"Esc":true}); onActivated:key=>tapped=key }
    }
    TestCase { id:input; when:false }
    IpcHandler {
        target:"layoutTest"
        function ready():bool {return true;}
        function run():string {
            try {
                input.wait(50);
                const normalLabel=normal.children.find(c=>c.text!==undefined),boundedLabel=bounded.children.find(c=>c.text!==undefined);
                if (Math.abs(normal.width-normalLabel.implicitWidth-32)>.5 || bounded.width>180 || boundedLabel.width>=boundedLabel.implicitWidth) throw Error("action button natural size or bounded elision");
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
                return "PASS footer hints fit and remain clickable at 640/480/320 px";
            } catch(e) { return "FAIL "+e; }
        }
    }
}
