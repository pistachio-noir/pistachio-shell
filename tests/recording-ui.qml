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
    RecordingTools { id: tools }
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
        function copyOutput(choice: string): string {
            ShellSettings.screenshotOutput=choice;
            Screenshots.prepare();
            const path=Screenshots.nextPath();Screenshots.saved(path,choice);
            return JSON.stringify({path:path,copies:Clipboard.paths});
        }
        function trim(): void { Screenshots.openTrim(Quickshell.shellPath("sample.mp4")); }
        function saveTrim(): void {
            const start=find(tools.contentItem,"recording-trim-start"),end=find(tools.contentItem,"recording-trim-end"),save=find(tools.contentItem,"recording-trim-save");
            start.text="0.4";end.text="1.4"; input.mouseClick(save,save.width/2,save.height/2);
        }
        function closeTools(): void { Screenshots.closeTrim(); }
        function pressEscape(): void { input.keyClick(Qt.Key_Escape); }
        function pause(): void { Screenshots.togglePause(); }
        function preferences(audio: string, countdown: int): void { ShellSettings.recordingAudio=audio; ShellSettings.recordingCountdown=countdown; }
        function queue(): void { Screenshots.queueRecord(Qt.rect(400,300,640,360),false,overlay.screen.name); }
        function cancel(): void { Screenshots.cancelCountdown(); }
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
                toolsVisible:tools.visible,trimDuration:Screenshots.trimDuration,trimError:Screenshots.trimError,trimSaved:Screenshots.trimSavedPath,trimBusy:Screenshots.trimBusy,paused:Screenshots.paused,elapsed:Screenshots.elapsedMs(Date.now()),countdown:Screenshots.countdown,path:Screenshots.recordingPath,visible:overlay.visible,width:overlay.width,height:overlay.height,
                pill:overlay.pillPlacement ? {x:pill.x,y:pill.y,width:pill.width,height:pill.height} : null,frame:frame,
                masked:overlay.mask.item===pill,keyboard:overlay.WlrLayershell.keyboardFocus===WlrKeyboardFocus.None,
                time:find(overlay.contentItem,"recording-region-time").text});
        }
    }
}
