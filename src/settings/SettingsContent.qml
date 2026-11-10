import qs
import qs.components
import qs.services
import QtQuick
import "catalog.js" as Catalog

Column {
    id: root
    property string page: SettingsHub.page
    property string soundTab: "devices"
    property bool discovering
    property bool active
    spacing: 14
    readonly property var info: Catalog.page(page)
    readonly property var groups: buildGroups()
    onPageChanged: { discovering = false; soundTab = SettingsHub.target === "applications" ? "applications" : "devices"; }
    Connections { target: SettingsHub; function onTargetChanged() { if (root.page === "sound") root.soundTab = SettingsHub.target === "applications" ? "applications" : "devices"; } }
    readonly property bool scanWanted: active && page === "bluetooth" && discovering && Bluetooth.ready
    onScanWantedChanged: Bluetooth.setScanning(scanWanted)
    Component.onDestruction: if (scanWanted) Bluetooth.setScanning(false)

    Item {
        width: parent.width; height: Math.max(48, heading.height)
        Column {
            id: heading
            width: parent.width - (headingAction.visible ? headingAction.width + 16 : 0); spacing: 3
            SettingsText { width: parent.width; text: root.page === "lens" ? "Pistachio Lens" : root.info[1]; font.pixelSize: 18; font.weight: Font.ExtraBold }
            SettingsText { width: parent.width; text: root.info[2]; secondary: true }
        }
        SettingsButton {
            id: headingAction
            anchors.right: parent.right
            visible: root.page === "bluetooth" || root.page === "localsend" && LocalSend.available
            text: root.page === "bluetooth" ? (root.discovering && Bluetooth.scanning ? "Stop scanning" : "Add a device") : "Send files"
            enabled: root.page !== "bluetooth" || Bluetooth.ready
            onClicked: {
                if (root.page === "bluetooth") { root.discovering = !root.discovering || !Bluetooth.scanning; Bluetooth.setScanning(root.discovering); }
                else LocalSend.openRequested();
            }
        }
    }
    AppearancePreview { width: parent.width; visible: root.page === "appearance" }
    Row {
        width: parent.width; height: 82; spacing: 16; visible: root.page === "about"
        Rectangle { width:60;height:60;radius:30;color:Theme.overlay;Icon{anchors.centerIn:parent;size:28;paths:Icons.sliders;color:Theme.clay} }
        Column { anchors.verticalCenter:parent.verticalCenter;spacing:4;SettingsText{text:"Pistachio Noir Shell";font.pixelSize:17;font.weight:Font.ExtraBold}SettingsText{text:"Quickshell for Hyprland.";secondary:true} }
    }
    Row {
        visible: root.page === "sound"; spacing: 4
        SettingsButton { text: "Devices"; selected: root.soundTab === "devices"; quiet: true; onClicked: root.soundTab = "devices" }
        SettingsButton { text: "Applications"; selected: root.soundTab === "applications"; quiet: true; onClicked: root.soundTab = "applications" }
    }
    ProviderCards { width: parent.width; visible: root.page === "lens" }
    StatsCards { width: parent.width; visible: root.page === "system" }
    Repeater {
        model: root.groups
        SettingsGroup { required property var modelData; width: root.width; title: modelData.title || ""; rows: modelData.rows }
    }
    SettingsGroup {
        visible: root.page === "bluetooth" && root.discovering
        width: parent.width
        title: Bluetooth.scanning ? "Nearby · scanning" : "Nearby"
        rows: Bluetooth.nearby.map(d => ({ id: d.address, kind: "action", title: Bluetooth.name(d), subtitle: () => Bluetooth.status(d), button: d.pairing ? "Pairing…" : "Pair", enabled: () => !d.pairing && Bluetooth.agent, run: () => Bluetooth.pair(d) }))
    }
    Rectangle {
        visible: root.page === "bluetooth" && root.discovering && !Bluetooth.nearby.length
        width: parent.width; height: 150; radius: Theme.tileRadius; color: Theme.overlay
        Column {
            anchors.centerIn: parent; width: parent.width - 48; spacing: 8
            SettingsText { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: Bluetooth.scanning ? "Looking for nearby devices…" : "Nothing nearby yet"; font.pixelSize: 14 }
            SettingsText { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Make your device discoverable, then scan again."; secondary: true }
            SettingsButton { anchors.horizontalCenter: parent.horizontalCenter; text: "Scan again"; enabled: Bluetooth.ready; onClicked: Bluetooth.setScanning(true) }
        }
    }
    SettingsText {
        width: parent.width; secondary: true
        text: root.page === "bluetooth" ? (!Bluetooth.agent ? "Pairing agent is unavailable. Existing devices can still connect." : !Bluetooth.paired.length ? "No paired devices yet. Choose Add a device to find one." : "Need to connect something new? Make it discoverable, then choose Add a device.")
            : root.page === "network" ? Network.connected ? "Your wired connection is up." : Network.hasLink ? "Cable connected. Waiting for a network connection." : "Connect the Ethernet cable to your computer and your router or switch."
            : root.page === "sound" && root.soundTab === "applications" ? "Apps appear here while they play sound. Each app keeps its own level."
            : root.page === "apps" ? "Weather locations are checked before they are saved."
            : root.page === "system" ? "Readings update while this page is open."
            : root.page === "localsend" ? LocalSend.available ? "Incoming requests still appear during Do not disturb." : "Install LocalSend to use shell sharing."
            : ""
        visible: text !== ""
    }

    function group(title, rows) { return { title: title, rows: rows }; }
    function toggle(id, title, subtitle, get, set) { return { id: id, kind: "toggle", title: title, subtitle: () => subtitle, checked: get, toggle: () => set(!get()) }; }
    function action(id, title, subtitle, button, run) { return { id: id, kind: "action", title: title, subtitle: () => subtitle, button: button, run: run }; }
    function read(id, title, value, subtitle) { return { id: id, title: title, value: () => value, subtitle: () => subtitle || "" }; }
    function time(id, title, get, set) { return { id: id, kind: "time", title: title, value: get, set: set }; }
    function buildGroups() {
        if (page === "appearance") return [
            group("Surfaces", [
                { id: "frost", kind: "choice", title: "Frosted panels", subtitle: () => "Choose how much of the desktop shows through.", choices: () => [{value:"solid",title:"Solid"},{value:"subtle",title:"Subtle"},{value:"glassy",title:"Glassy"}], value: () => !ShellSettings.frosted ? "solid" : ShellSettings.glassy ? "glassy" : "subtle", set: v => { ShellSettings.setGlassy(v === "glassy"); ShellSettings.setFrosted(v !== "solid"); } },
                toggle("shadows", "Drop shadows", "Soft depth around panels and popups.", () => ShellSettings.shadows, ShellSettings.setShadows)
            ]),
            group("Desktop", [action("wallpaper", "Wallpaper", "Your images, with a fit kept for each one.", "Choose wallpaper", () => SettingsHub.wallpapersRequested()), toggle("desktop", "Desktop icons", "Show files and folders from your Desktop.", () => Desktop.enabled, Desktop.setEnabled)]),
            group("At a glance", [toggle("workspace", "Workspace OSD", "On workspace changes.", () => ShellSettings.workspaceOsd, ShellSettings.setWorkspaceOsd), toggle("tabbed", "Tabbed OSD", "When tabs switch.", () => ShellSettings.tabbedOsd, ShellSettings.setTabbedOsd)])
        ];
        if (page === "sound") {
            if (soundTab === "applications") {
                // App process ids connect PipeWire streams to the compositor's workspace data.
                const here = n => Compositor.windows.some(w => String(w.pid) === String(n.properties?.["application.process.id"]) && w.workspace === Compositor.activeWorkspace);
                const streams = Audio.streams.slice().sort((a,b) => Number(here(b)) - Number(here(a)) || Audio.appName(a).localeCompare(Audio.appName(b)));
                return [group("", [action("devices", Audio.sink ? Audio.deviceName(Audio.sink) : "No output device", "Current output", "Devices", () => soundTab = "devices")]), group("Playing applications", streams.map(n => ({ id: "stream:" + n.id, kind: "slider", title: Audio.appName(n), subtitle: () => here(n) ? "On this workspace" : "Playing audio", level: () => n.audio?.volume || 0, adjust: v => Audio.setStreamVolume(n,v), mute: () => Audio.toggleStreamMute(n), muted: () => n.audio?.muted || false })))];
            }
            const audio = (input) => ({ id: input ? "input" : "output", kind: "audio", title: input ? "Input" : "Output", subtitle: () => input ? "Your microphone" : "Where your sound plays", choices: () => (input ? Audio.sources : Audio.sinks).map(n => ({ value: n.id, title: Audio.deviceName(n), subtitle: Audio.isUnplugged(n) ? "Nothing plugged in" : n.id === (input ? Audio.source?.id : Audio.sink?.id) ? "Current " + (input ? "input" : "output") : "Available", disabled: Audio.isUnplugged(n) })), value: () => input ? Audio.source?.id : Audio.sink?.id, set: id => { const n = (input ? Audio.sources : Audio.sinks).find(n => n.id === id); if (n && !Audio.isUnplugged(n)) { if (input) Audio.setSource(n); else Audio.setSink(n); } }, level: () => input ? Audio.micVolume : Audio.volume, adjust: v => input ? Audio.setMicVolume(v) : Audio.setVolume(v), mute: () => input ? Audio.toggleMicMute() : Audio.toggleMute(), muted: () => input ? Audio.micMuted : Audio.muted });
            return [group("", [audio(false)]), group("", [audio(true)]), group("Behaviour", [toggle("takeover", "Headphones take over", "Move sound to Bluetooth headphones when they connect.", () => ShellSettings.headphonesTakeOver, ShellSettings.setHeadphonesTakeOver), toggle("tick", "Volume tick", "Play a soft click when volume keys change the level.", () => ShellSettings.volumeTick, ShellSettings.setVolumeTick)])];
        }
        if (page === "display") return [
            ...(Brightness.available ? [group("", [{ id: "brightness", kind: "slider", title: "Brightness", subtitle: () => "Your external display", level: () => Brightness.value, adjust: Brightness.set }])] : []),
            group("", [toggle("night", "Night light", NightLight.available ? "Warmer light for the evening." : "Install hyprsunset to enable night light.", () => NightLight.enabled, NightLight.setEnabled), ...(NightLight.available ? [{ id: "warmth", kind: "slider", title: "Warmth", level: () => 9000 - NightLight.temperature, from: 2500, to: 6500, format: v => Math.round(9000-v) + " K", adjust: v => NightLight.setTemperature(Math.round((9000-v)/50)*50) }] : [])]),
            group("Schedule", [toggle("schedule", "Daily schedule", "Turn night light on and off at these times.", () => NightLight.scheduled, on => NightLight.setSchedule(on,NightLight.from,NightLight.to)), {id:"times",kind:"times",title:"Times",subtitle:()=>"Every day · from / until",start:()=>NightLight.from,end:()=>NightLight.to,setStart:v=>NightLight.setSchedule(NightLight.scheduled,v,NightLight.to),setEnd:v=>NightLight.setSchedule(NightLight.scheduled,NightLight.from,v)}])
        ];
        if (page === "notifications") return [
            group("", [toggle("dnd", "Do not disturb", "Keep notifications in the centre without toasts.", () => Notifs.dnd, Notifs.setDnd), toggle("schedule", "Schedule", "Quiet hours, every day.", () => Notifs.dndScheduled, Notifs.setDndSchedule), toggle("follow", "Use night light’s times", "Follow the schedule in Display & night light.", () => Notifs.dndFollowsNight, Notifs.setDndFollowsNight), ...(!Notifs.dndFollowsNight ? [{id:"times",kind:"times",title:"Quiet hours",subtitle:()=>"From / until",start:()=>Notifs.dndFrom,end:()=>Notifs.dndTo,setStart:v=>Notifs.setDndTimes(v,Notifs.dndTo),setEnd:v=>Notifs.setDndTimes(Notifs.dndFrom,v)}] : [read("times", "Quiet hours", NightLight.timeText(Notifs.dndFrom) + "–" + NightLight.timeText(Notifs.dndTo))])]),
            group("While you are busy", [toggle("fullscreen", "Quiet in fullscreen", "Hold toasts while a game or video fills the screen.", () => ShellSettings.quietFullscreen, ShellSettings.setQuietFullscreen), toggle("calls", "Quiet during calls", "Hold toasts while an app uses your microphone.", () => ShellSettings.quietCalls, ShellSettings.setQuietCalls), toggle("chime", "Notification sound", "A soft chime when a toast arrives.", () => ShellSettings.notificationSound, ShellSettings.setNotificationSound)]),
            group("App rules", Object.keys(Notifs.rules).sort().map(app => action("rule:"+app, app || "Unnamed app", Notifs.ruleText(app), "Restore", () => Notifs.setRule(app,null))))
        ];
        if (page === "bluetooth") return [group("", [toggle("power", "Bluetooth", Bluetooth.summary, () => Bluetooth.enabled, Bluetooth.setEnabled)]), group("Your devices", Bluetooth.paired.map(d => ({ id: d.address, kind: "action", title: Bluetooth.name(d), subtitle: () => Bluetooth.status(d), button: d.connected ? "Disconnect" : "Connect", enabled: () => Bluetooth.ready && !/Connecting|Disconnecting/.test(Bluetooth.status(d)), run: () => Bluetooth.toggleConnection(d), forget: () => SettingsHub.forgetDevice = d })))];
        if (page === "network") return [group("", [read("ethernet", "Ethernet", Network.connected ? "Connected" : Network.hasLink ? "Connecting" : "Not connected", Network.connected ? "Connected" : Network.hasLink ? "Cable connected" : "Cable unplugged")]), group("Connection details", [read("type", "Connection", "Wired Ethernet"), read("speed", "Link speed", Network.connected ? Network.speed >= 1000 ? (Network.speed/1000) + " Gbps" : Network.speed + " Mbps" : "—", "Speed reported by the connection.")])];
        if (page === "lens") return [group("", [action("chats", "Saved chats", "~/lens-chats · snip and Markdown", "Open folder", SettingsHub.openChats)])];
        if (page === "apps") return [group("Open things with", [{id:"terminal",kind:"choice",title:"Terminal",subtitle:()=>"For commands, terminal apps and showoff.", choices:()=>Apps.terminalChoices.map(v=>({value:v,title:Apps.terminalName(v)})),value:()=>Apps.terminal,set:Apps.setTerminal}]), group("Places", [action("weather","Weather location",Weather.placeName,"Change",()=>SettingsHub.beginEdit("weather")), action("wallpapers","Wallpapers",Wallpapers.folder.replace(/^\/home\/[^/]+/,"~"),"Open folder",Wallpapers.openFolder)]), ...(Cider.installed ? [group("Integrations",[action("cider","Cider token",Cider.usable ? "Set · enables Up next and Apple Music search." : "Not set · for Up next and Apple Music search.","Change",()=>SettingsHub.beginEdit("cider"))])] : [])];
        if (page === "localsend" && LocalSend.available) return [group("",[toggle("receive","Receive files",LocalSend.summary,()=>LocalSend.wanted,LocalSend.setReceive)]),group("This device",[action("name","Device name",LocalSend.name,"Change",()=>SettingsHub.beginEdit("name")),action("folder","Save received files to",LocalSend.folderShown,"Change",LocalSend.pickFolder)]),group("Incoming requests",[toggle("known","Accept known devices","Skip asking for devices you have accepted before.",()=>LocalSend.acceptKnown,LocalSend.setAcceptKnown)])];
        if (page === "system") return [group("Storage",SystemStats.disks.map(d=>read("storage",d.mount === "/" ? "System disk" : "Home",`${SystemStats.gigabytes(d.free)} free of ${SystemStats.gigabytes(d.size)}`,d.mount))),group("Shell",[read("shell","Pistachio Noir",`${SystemStats.shellCpu < 0 ? "—" : (SystemStats.shellCpu*100).toFixed(1)+"%"} · ${Math.round(SystemStats.shellMem)} MB`,"CPU and memory, including its helpers.")]),group("Removable drives",Drives.mounted.map(d=>action("drive:"+d.path,d.name,`${d.mountpoint} · ${d.size}`,"Eject",()=>Drives.eject(d))))];
        if (page === "about") return [group("",[read("build","Build",About.commit || "Reading…",[About.date,About.subject,About.changed ? `${About.changed} changed files` : ""].filter(Boolean).join(" · ")),read("quickshell","Quickshell",About.quickshell || "—"),read("hyprland","Hyprland",About.hyprland || "—"),read("qt","Qt",About.qt || "—"),action("source","Source code","The shell and its design boards.","View source",SettingsHub.openSource)]),group("",[action("showoff","Showoff mode","Arrange the desktop for a setup screenshot.","Start showoff",()=>SettingsHub.showoffRequested())])];
        return [];
    }
}
