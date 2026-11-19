pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property string mode: ""
    property int generation: 0
    property string path: ""
    property string error: ""
    property bool busy: false
    property var preview: ({})
    property var handlers: []
    property string mime: ""
    property var jobs: []
    property var pending: ({})
    property bool helperReady
    property var queuedMessages: []
    property var launchFailure: ({})
    property var launchRequests: ({})
    property var queuedAction: []
    property int launchSequence
    signal present
    readonly property var actions: [
        { id: "settings", name: "Settings", target: ["settings", "open"] },
        { id: "screenshots", name: "Screenshot menu", target: ["screenshot", "menu"] },
        { id: "lens", name: "Pistachio Lens", target: ["screenshot", "lens"] },
        { id: "record", name: "Record screen", available:Screenshots.hasRecorder, target: ["screenshot", "record"] },
        { id: "jobs", name: "Background jobs", target: [] },
        { id: "overview", name: "Overview", target: ["overview", "toggle"] },
        { id: "chat", name: "Quick chat · Ask AI", target: ["chat", "open"] },
        { id: "sound", name: "Sound settings", target: ["settings", "section", "sound"] },
        { id: "network", name: "Network settings", target: ["settings", "section", "network"] }
    ].concat([
        ["appearance","Appearance"],["display","Display & night light"],["notifications","Notifications"],
        ["bluetooth","Bluetooth"],["localsend","LocalSend"],["lens-settings","Lens"],["apps-settings","Apps & places"],
        ["system-settings","System monitor"],["health","Shell health"],["about","About"]
    ].map(pair => ({id:pair[0],name:pair[1]+" settings",available:pair[0]!=="localsend" || LocalSend.available,target:["settings","section",({"lens-settings":"lens","apps-settings":"apps","system-settings":"system"})[pair[0]] ?? pair[0]]})))
    readonly property var pins: sequence(Store.saved.launcherPins) ? Array.from(Store.saved.launcherPins).filter(valid) : []
    readonly property var aliases: Store.saved.launcherAliases && typeof Store.saved.launcherAliases === "object" && !sequence(Store.saved.launcherAliases) ? Store.saved.launcherAliases : ({})
    // JsonAdapter loads QVariant sequences, which Array.isArray does not recognise.
    function sequence(value): bool { return !!value && typeof value === "object" && typeof value.length === "number" && Number.isInteger(value.length) && value.length>=0 && value.length<=1000; }
    function valid(d): bool { return d && typeof d.target === "string" && (d.kind === "app" || d.kind === "preset" || d.kind === "action" && actions.some(a => a.id === d.target)); }
    function same(a, b): bool { return a?.kind === b?.kind && a?.target === b?.target; }
    function pinned(d): bool { return pins.some(p => same(p,d)); }
    function togglePin(d) { if (valid(d)) Store.saved.launcherPins = pinned(d) ? pins.filter(p => !same(p,d)) : pins.concat([{kind:d.kind,target:d.target}]); }
    function movePin(d, delta: int) {
        const list=pins.slice(), at=list.findIndex(p => same(p,d)), to=at+delta;
        if (at<0 || to<0 || to>=list.length) return;
        const item=list.splice(at,1)[0]; list.splice(to,0,item); Store.saved.launcherPins=list;
    }
    function aliasFor(d): string { return Object.keys(aliases).find(k => same(aliases[k],d)) ?? ""; }
    function checkAlias(text: string, d): string {
        const key=text.trim().toLowerCase();
        if (key && !/^[a-z0-9_\u00c0-\u024f-]{1,32}$/i.test(key)) return "Use 1–32 letters, numbers, _ or -.";
        if (key && aliases[key] && !same(aliases[key],d)) return "That alias belongs to another item.";
        return valid(d) && d.kind!=="preset" ? "" : "Only applications and shell actions can have aliases.";
    }
    function setAlias(text: string,d) {
        if (checkAlias(text,d)) return;
        const all=Object.assign({},aliases), previous=aliasFor(d), key=text.trim().toLowerCase();
        if (previous) delete all[previous];
        if (key) all[key]={kind:d.kind,target:d.target};
        Store.saved.launcherAliases=all;
    }
    function resolve(d): var {
        if (!valid(d)) return null;
        if (d.kind === "app") {
            const app=Apps.list.find(a => a.id===d.target);
            return app ? {kind:"app",key:"pin:"+app.id,title:app.name,subtitle:aliasFor(d) ? "Alias · "+aliasFor(d) : "Pinned application",icon:Apps.icon(app.icon),app:app,descriptor:d} : null;
        }
        if (d.kind==="preset") {
            const p=Compositor.presets.find(p => p.name===d.target);
            return p ? {kind:"preset",key:"pin:preset:"+p.name,title:p.name,subtitle:"Workspace preset",preset:p,descriptor:d} : null;
        }
        const action=actions.find(a => a.id===d.target);
        if (action.available===false) return null;
        return {kind:"shellaction",key:"shellaction:"+d.target,title:action.name,subtitle:aliasFor(d) ? "Alias · "+aliasFor(d) : "Shell action",descriptor:d};
    }
    function activateAction(d) {
        const a=actions.find(a => a.id===d.target);
        if (!a || a.available===false) return;
        if (a.id === "jobs") showJobs();
        else { queuedAction=a.target; actionDelay.restart(); }
    }
    Timer { id:actionDelay; interval:240; onTriggered:Quickshell.execDetached(["qs","-c","pistachio","ipc","call"].concat(root.queuedAction)) }
    function send(message) {
        if (helperReady) helper.write(JSON.stringify(message)+"\n");
        else { queuedMessages=queuedMessages.concat([message]); if (!helper.running) helper.running=true; }
    }
    function showFile(file: string, view: string) {
        send({action:"cancel-preview"}); generation++; path=file; mode=view; error=""; preview=({}); handlers=[]; busy=true;
        send({action:view === "preview" ? "preview" : "handlers",id:generation,path:file}); present();
    }
    function showJobs() { send({action:"cancel-preview"}); generation++; mode="jobs"; error=""; busy=false; present(); }
    function close() { send({action:"cancel-preview"}); generation++; mode=""; }
    function openWith(app: string, remember: bool) { busy=true; error=""; send({action:"open",id:generation,path:path,app:app,remember:remember}); }
    function run(command: string) { send({action:"run",command:command}); }
    function cancel(job: string) { send({action:"cancel",job:job}); }
    function launch(app: string, argv, cwd: string, windowApp: string) {
        pending=Object.assign({},pending,{[app]:Date.now()});
        launchRequests=Object.assign({},launchRequests,{[app]:{argv:argv,cwd:cwd,request:++launchSequence,confirmed:false,started:Date.now(),windowApp:windowApp,initialWindows:Compositor.windows.map(w => w.address)}});
        send({action:"launch",app:app,argv:argv,cwd:cwd,request:launchSequence});
    }
    function retryLaunch() { const app=launchFailure.app, request=launchRequests[app]; close(); if (request) launch(app,request.argv,request.cwd,request.windowApp); }
    function heard(line: string) {
        try {
            const m=JSON.parse(line);
            if (m.event==="ready") {
                helperReady=true;
                const waiting=queuedMessages; queuedMessages=[];
                waiting.forEach(message => send(message)); return;
            }
            if (m.event==="jobs") { jobs=m.jobs; return; }
            if (m.event==="launch-failed") {
                const request=launchRequests[m.app];
                if (!request || request.request!==m.request || request.confirmed || appMapped(m.app)) return;
                const all=Object.assign({},pending); delete all[m.app]; pending=all;
                generation++; launchFailure={app:m.app,error:m.error}; mode="launch-failed"; error=""; busy=false; present(); return;
            }
            if (m.id!==generation) return;
            busy=false;
            if (m.event==="preview") preview=m.data;
            else if (m.event==="handlers") { handlers=m.apps; mime=m.mime; }
            else if (m.event==="opened") close();
            else if (m.event==="error") error=m.error;
        } catch(e) { console.warn("launcher tools:",e); }
    }
    function appMapped(app: string): bool {
        const request=launchRequests[app];
        if (request?.windowApp) return Compositor.windows.some(w => !request.initialWindows.includes(w.address) && (w.appId===request.windowApp || Compositor.entryOf(w.appId)===request.windowApp));
        return Compositor.windows.some(w => Compositor.entryOf(w.appId)===app || w.appId===app || w.appId===Apps.list.find(a => a.id===app)?.startupClass);
    }
    function confirmLaunches() {
        const all=Object.assign({},launchRequests);
        for (const key of Object.keys(all)) if (appMapped(key)) all[key]=Object.assign({},all[key],{confirmed:true});
        launchRequests=all;
    }
    Connections { target:Compositor; function onWindowsChanged() { root.confirmLaunches(); } }
    Timer {
        interval: 1000; repeat: true; running: Object.keys(root.pending).length>0
        onTriggered: {
            const all={};
            for (const key of Object.keys(root.pending)) if (Date.now()-root.pending[key]<10000 && !root.appMapped(key)) all[key]=root.pending[key];
            root.pending=all;
        }
    }
    Process {
        id: helper; running:true
        command:[Quickshell.env("HOME") + "/.local/bin/psc","launcher-tools"]
        stdinEnabled:true
        onExited: { root.helperReady=false; root.busy=false; if (root.mode) root.error="File and job helper stopped. Reopen this view to retry."; }
        stdout:SplitParser { onRead:data => root.heard(data) }
        stderr:SplitParser { onRead:data => console.warn("launcher tools:",data) }
    }
    IpcHandler {
        target:"jobs"
        function open(): void { root.showJobs(); }
        function close(): void { root.close(); }
        function status(): string { return JSON.stringify(root.jobs); }
        function cancel(id: string): void { root.cancel(id); }
    }
}
