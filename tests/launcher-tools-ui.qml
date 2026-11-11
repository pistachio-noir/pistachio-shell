import qs
import qs.popups
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick
import QtTest
ShellRoot {
    Component.onCompleted: LauncherTools.showFile(Quickshell.env("TOOL_TEST_TEXT"),"preview")
    LauncherExtras { id:extra }
    TestCase { id:test; name:"Launcher tools"; when:false }
    function check(ok,message) { if (!ok) throw Error(message); }
    IpcHandler {
        target:"toolsTest"
        function ready(): bool { return Store.ready && LauncherTools.helperReady; }
        function run(): string {
            try {
                check(LauncherTools.preview.text==="fixture text\n","startup request queued until helper ready");
                const d={kind:"app",target:"fixture"};
                LauncherTools.togglePin(d); check(LauncherTools.pinned(d),"pin saved");
                LauncherTools.togglePin({kind:"action",target:"jobs"}); LauncherTools.movePin(d,1);
                check(LauncherTools.pins[1].target==="fixture","manual pin order");
                LauncherTools.setAlias(" editor ",d); check(LauncherTools.aliases.editor.target==="fixture","exact alias");
                LauncherTools.setAlias("",d); check(!LauncherTools.aliasFor(d),"alias removal"); LauncherTools.setAlias("editor",d);
                check(LauncherTools.checkAlias("not valid",d)!=="","bad alias rejected");
                check(LauncherTools.checkAlias("x",{kind:"command",target:"rm"})!=="","commands cannot alias");
                LauncherTools.togglePin({kind:"action",target:"unapproved"}); check(LauncherTools.pins.length===2,"action allowlist");
                check(LauncherTools.resolve({kind:"preset",target:"Work"}).preset.name==="Work","preset pin");
                LocalSend.available=false;Screenshots.hasRecorder=false;
                check(!LauncherTools.resolve({kind:"action",target:"localsend"}) && !LauncherTools.resolve({kind:"action",target:"record"}),"optional actions absent without tools");
                LocalSend.available=true;Screenshots.hasRecorder=true;
                LauncherTools.showFile(Quickshell.env("TOOL_TEST_TEXT"),"preview"); test.wait(400);
                check(LauncherTools.preview.text==="fixture text\n","real preview bridge");
                check(extra.visible,"preview mapped");
                test.keyClick(Qt.Key_Escape); test.wait(300); check(!extra.visible,"Escape closes real preview");
                LauncherTools.showFile(Quickshell.env("TOOL_TEST_TEXT"),"preview"); test.wait(300);
                const old=LauncherTools.generation; LauncherTools.showJobs();
                LauncherTools.heard(JSON.stringify({event:"error",id:old,error:"stale"})); check(LauncherTools.error==="","old preview discarded");
                LauncherTools.run("printf fixture-output; exit 7"); test.wait(1100);
                check(LauncherTools.jobs.length===1 && LauncherTools.jobs[0].code===7,"real background job");
                check(LauncherTools.jobs[0].output==="fixture-output","captured output");
                LauncherTools.run("sleep 30"); test.wait(1000);
                const job=LauncherTools.jobs.find(j=>j.state==="running"); check(!!job,"running job");
                LauncherTools.cancel(job.id); test.wait(1000);
                check(LauncherTools.jobs.find(j=>j.id===job.id).state==="cancelled","job cancelled");
                LauncherTools.launch("fixture",["/no/such/pistachio-test-program"],"",""); test.wait(300);
                check(LauncherTools.mode==="launch-failed" && !!LauncherTools.launchFailure.error,"confirmed spawn failure with details");
                const request=LauncherTools.launchRequests.fixture.request;
                Compositor.windows=[{appId:"fixture"}]; test.wait(50); Compositor.windows=[];
                LauncherTools.showJobs(); LauncherTools.heard(JSON.stringify({event:"launch-failed",app:"fixture",request:request,error:"late failure"}));
                check(LauncherTools.mode==="jobs","mapped app later exit is not startup failure");
                LauncherTools.heard(JSON.stringify({event:"launch-failed",app:"fixture",request:request-1,error:"old request"}));
                check(LauncherTools.mode==="jobs","old launch cannot replace current view");
                Compositor.windows=[{appId:"fixture-terminal",address:"old-terminal"}];
                LauncherTools.launch("terminal-app",["sh","-c","sleep 0.3; exit 7"],"","fixture-terminal");
                check(!LauncherTools.appMapped("terminal-app"),"existing terminal cannot confirm new launch");
                Compositor.windows=[{appId:"fixture-terminal",address:"old-terminal"},{appId:"fixture-terminal",address:"new-terminal"}];
                test.wait(500);
                check(LauncherTools.launchRequests["terminal-app"].confirmed && LauncherTools.mode==="jobs","terminal app mapped before later program failure");
                LauncherTools.close(); test.wait(300); check(!extra.visible,"panel fade closed");
                return "PASS launcher tools real QML + helper";
            } catch(e) { return "FAIL "+e; }
        }
        function persisted(): string { return JSON.stringify({pins:LauncherTools.pins,rawPins:Store.saved.launcherPins,rawArray:Array.isArray(Store.saved.launcherPins),rawLength:Store.saved.launcherPins.length,aliases:LauncherTools.aliases,jobs:LauncherTools.jobs.length}); }
        function dismiss(): void { LauncherTools.close(); }
        function showPreview(): void { LauncherTools.showFile(Quickshell.env("TOOL_TEST_TEXT"),"preview"); }
    }
}
