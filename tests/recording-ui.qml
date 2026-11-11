import qs
import qs.popups
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtTest

Scope {
    id: fixture
    property bool calibration
    // A known, click-through patch for the opt-in real video test; it contains no owner content.
    PanelWindow {
        visible: fixture.calibration
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"; mask: Region {}
        WlrLayershell.namespace: "pistachio-recording-fixture"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        Rectangle { x: 400; y: 300; width: 640; height: 362; color: Theme.bg }
    }
    RecordingRegion { id: overlay }
    TestCase { id: input; when: false }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children) { const match = find(child,name); if (match) return match; }
        return null;
    }
    IpcHandler {
        target: "recordingTest"
        function ready(): bool { return Screenshots.hasRecorder && Screenshots.videos === Quickshell.shellPath("videos"); }
        function paint(): void { fixture.calibration = true; }
        function start(which: int): void {
            const w=overlay.screen.width,h=overlay.screen.height;
            const areas = [Qt.rect(400.4,300.4,641.3,361.8),Qt.rect(400,0,640,360),Qt.rect(400,h-360,640,360),
                Qt.rect(0,0,640,h),Qt.rect(w-640,0,640,h),Qt.rect(0,0,w,h)];
            Screenshots.record(which === 7 ? Qt.rect(10,10,1,1) : areas[Math.min(which,5)], which === 6, overlay.screen.name);
        }
        function stop(): void { Screenshots.stopRecording(); }
        function clickStop(): void {
            const stop = find(overlay.contentItem,"recording-region-stop");
            input.mouseClick(stop,stop.width/2,stop.height/2);
        }
        function state(): string {
            const pill=find(overlay.contentItem,"recording-region-control"), frame=[];
            for(let i=0;i<4;i++) {
                const strip=find(overlay.contentItem,"recording-frame-"+i);
                frame.push({x:strip.x,y:strip.y,width:strip.width,height:strip.height});
            }
            return JSON.stringify({recording:Screenshots.recording,whole:Screenshots.recordingWhole,area:Screenshots.recordingArea,
                path:Screenshots.recordingPath,visible:overlay.visible,width:overlay.width,height:overlay.height,
                pill:overlay.pillPlacement ? {x:pill.x,y:pill.y,width:pill.width,height:pill.height} : null,frame:frame,
                masked:overlay.mask.item===pill,keyboard:overlay.WlrLayershell.keyboardFocus===WlrKeyboardFocus.None,
                time:find(overlay.contentItem,"recording-region-time").text});
        }
    }
}
