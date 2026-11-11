import qs.services
import qs.popups
import Quickshell
import Quickshell.Io
import QtTest

// Real Lens windows with fake providers and an isolated home, driven only by test IPC.
Scope {
    LensCard { id:lens }
    TestCase { id:input; when:false }

    IpcHandler {
        target: "lensNative"
        function beginFixture(path: string): void { Lens.begin(path, Qt.rect(420, 160, 520, 220), null); }
        function questionFixture(): void { Lens.question = "Compare these images and explain the change."; }
        function imageFixture(): void { Lens.attachImage(); }
        function bothFixture(): void { Lens.askBoth("Compare these images and explain the change."); }
        function toolbarFixture(): string {
            const card=input.findChild(lens,"lens-card"),buttons={};
            function walk(item) {
                if (item.horizontalPadding!==undefined && item.text!==undefined && item.visible) {
                    const p=item.mapToItem(card,0,0);buttons[item.text]={x:p.x,y:p.y,width:item.width};
                }
                for (const child of item.children ?? []) walk(child);
            }
            walk(card);return JSON.stringify(buttons);
        }
        function oneImageFixture(): void { Lens.images.slice(1).forEach(image=>Lens.removeImage(image.id)); }
        function crowdedFixture(): void {
            Lens.answer="A long answer.\n\n".repeat(100);
            Lens.actions=[{kind:"search",label:"Search the documentation for a detailed explanation of this error and its remedy",query:"fixture"}];
            Lens.attachment="a-very-long-source-file-name-that-must-stay-inside-the-card.qml";
        }
        function geometryFixture(): string {
            const header=input.findChild(lens,"lens-answer-header"),close=input.findChild(lens,"lens-close"),card=input.findChild(lens,"lens-card"),actions=input.findChild(lens,"lens-answer-actions");
            return JSON.stringify({headerWidth:header.width,closeRight:close.mapToItem(header,close.width,0).x,
                cardHeight:card.height,limit:lens.height-48,actionsWidth:actions.width,
                actions:Array.from(actions.children).filter(c=>c.visible && c.text!==undefined).map(c=>({x:c.x,width:c.width}))});
        }
        function closeFixture(): void { Lens.close(); }
        function state(): string { return JSON.stringify({ ready: Lens.ready, open: Lens.open, state: Lens.state,
            count: Lens.images.length, combined: Lens.combined, picking: Lens.pickingFile }); }
    }
}
