import qs
import qs.components
import qs.panels
import qs.services
import QtQuick
import "catalog.js" as Catalog

Column {
    id: root
    property bool funAbout
    property string page: SettingsHub.page
    property string soundTab: "devices"
    property bool discovering
    property bool active
    spacing: Theme.tui ? 0 : 14
    readonly property var info: Catalog.page(page)
    readonly property var groups: buildGroups()
    onPageChanged: { SettingsReset.cancel(); discovering = false; soundTab = SettingsHub.target === "applications" ? "applications" : "devices"; Qt.callLater(() => arrival++); }
    // bumped once a new page's groups are built: they rise in one after another (not on the rebuilds
    // a live page makes every second)
    property int arrival
    Connections { target: SettingsHub; function onTargetChanged() { if (root.page === "sound") root.soundTab = SettingsHub.target === "applications" ? "applications" : "devices"; } }
    readonly property bool scanWanted: active && page === "bluetooth" && discovering && Bluetooth.ready
    onScanWantedChanged: Bluetooth.setScanning(scanWanted)
    Component.onDestruction: if (scanWanted) Bluetooth.setScanning(false)

    readonly property bool networkWanted: active && page === "network"
    readonly property bool bluetoothDetailsWanted: active && page === "bluetooth"
    readonly property bool micWanted: active && page === "sound" && soundTab === "devices"
    onNetworkWantedChanged: Network.watching = networkWanted
    onBluetoothDetailsWantedChanged: Bluetooth.detailsWatching = bluetoothDetailsWanted
    onMicWantedChanged: MicCheck.active = micWanted
    onActiveChanged: if (!active) SettingsReset.cancel()
    Component.onCompleted: { Network.watching = networkWanted; Bluetooth.detailsWatching = bluetoothDetailsWanted; MicCheck.active = micWanted; }
    Connections { target: SettingsHub; function onOpenedChanged() { if (!SettingsHub.opened) { MicCheck.stop(); SettingsReset.cancel(); } } }

    Item {
        width: parent.width; height: Math.max(48, heading.height)
        Column {
            id: heading
            width: parent.width - (headingAction.visible ? headingAction.width + 16 : 0); spacing: 3
            SettingsText { width: parent.width; text: root.info[1]; font.pixelSize: Theme.tui ? Theme.tuiTextSize : 18; font.weight: Font.ExtraBold }
            SettingsText { visible: !Theme.tui; width: parent.width; text: root.info[2]; secondary: true }
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
    Column {
        objectName: "about-fun"
        visible: root.page === "about" && root.funAbout
        width: parent.width
        spacing: Theme.tui ? 12 : 16

        Rectangle {
            width:parent.width; height: Math.max(128, hero.implicitHeight + 32)
            color:Theme.overlay; radius:Theme.tui ? 0 : Theme.tileRadius
            border.width:Theme.tui ? 1 : 0; border.color:Theme.tuiBorder
            Column {
                id:hero; x:16; y:16; width:parent.width-144; spacing:8
                SettingsText { width:parent.width; text:"THE CAT’S VERY OFFICIAL REPORT"; secondary:true; font.pixelSize:Theme.tui?Theme.tuiTextSize:11; font.letterSpacing:Theme.tui?0:0.6 }
                SettingsText { width:parent.width; text:"Welcome to Pistachio Shell"; font.pixelSize:Theme.tui?Theme.tuiTextSize:20; font.weight:Font.ExtraBold }
                SettingsText { width:parent.width; secondary:true; text:"A small desktop with suspiciously large plans." }
                SettingsText { width:parent.width; secondary:true; text:"“I inspected the windows. Then I sat on the keyboard.” — The desktop cat" }
            }
            DesktopCat { anchors.right:parent.right; anchors.rightMargin:16; anchors.verticalCenter:parent.verticalCenter; active:root.page === "about" && root.funAbout }
        }
        SettingsText { width:parent.width; text:"Meet the crew"; font.pixelSize:Theme.tui?Theme.tuiTextSize:16; font.weight:Font.ExtraBold }
        Rectangle {
            width:parent.width; height:crew.implicitHeight + 20
            color:Theme.overlay; radius:Theme.tui?0:Theme.tileRadius
            border.width:Theme.tui?1:0; border.color:Theme.tuiBorder
            Column {
                id:crew; x:16; y:10; width:parent.width-32; spacing:0
                Repeater {
                    model:[
                        ["You", "Captain of this operation, keeper of ideas and final decisions."],
                        ["Claude", "Our dear helper, turning ideas into features and investigating suspicious logs."],
                        ["Codex", "Our dear helper, building, testing and taking one more screenshot just to be sure."],
                        ["The desktop cat", "Chief inspector of important things. Credentials: impeccable whiskers."]
                    ]
                    Column {
                        required property var modelData
                        required property int index
                        width:crew.width; spacing:4
                        Rectangle { width:parent.width; height:parent.index?1:0; color:Theme.overlay2 }
                        Item { width:1; height:parent.index?8:2 }
                        SettingsText { width:parent.width; text:parent.modelData[0]; font.weight:Font.ExtraBold }
                        SettingsText { width:parent.width; text:parent.modelData[1]; secondary:true }
                        Item { width:1; height:8 }
                    }
                }
            }
        }
        SettingsText { width:parent.width; secondary:true; text:"Find things in the launcher, make room for Focus, capture a moment with Lens, or share nearby with LocalSend. Classic and TUI are both excellent nap spots." }
        SettingsText { width:parent.width; secondary:true; text:"Built together with curiosity, patience, and a few rounds of ‘wait, why did the bar move?’" }
        SettingsText { width:parent.width; text:"What’s under the shell?"; font.pixelSize:Theme.tui?Theme.tuiTextSize:16; font.weight:Font.ExtraBold }
        SettingsText { width:parent.width; secondary:true; text:"Quickshell runs the panels, Hyprland wrangles the windows, and Qt holds the pixels together. The cat checked their papers and the current build below." }
        SettingsText { width:parent.width; secondary:true; text:"Settings can be exported and reviewed before import. Tokens and history stay out of the suitcase; the cat promises not to press Apply for you." }
    }
    Rectangle { visible:Theme.tui;width:parent.width;height:1;color:Theme.tuiBorder }
    AppearancePreview { width: parent.width; visible: root.page === "appearance" }
    Row {
        objectName: "about-normal-header"
        width: parent.width; height: 82; spacing: 16; visible: root.page === "about" && !root.funAbout
        Rectangle { visible:!Theme.tui;width:60;height:60;radius: Theme.tui ? 0 : (30);color:Theme.overlay;Icon{anchors.centerIn:parent;size:28;paths:Icons.sliders;color:Theme.clay} }
        Column { anchors.verticalCenter:parent.verticalCenter;spacing:4;SettingsText{text:"Pistachio Shell";font.pixelSize: Theme.tui ? Theme.tuiTextSize : 17;font.weight:Font.ExtraBold}SettingsText{text:"A shell for Hyprland.";secondary:true} }
        // the branch it runs from: main is stable, any other may not be (owner's request, 12 November 2026)
        Rectangle {
            objectName: "setting-branch-chip"
            visible: About.branch !== ""
            anchors.verticalCenter: parent.verticalCenter
            height: 40; radius: Theme.tui ? 0 : (20); color: Theme.overlay
            width: branchRow.implicitWidth + 32
            Row {
                id: branchRow
                anchors.centerIn: parent; spacing: 10
                Icon { anchors.verticalCenter: parent.verticalCenter; size: 18; paths: About.stable ? Icons.shieldCheck : About.kind === "cooking" ? Icons.sparkles : Icons.flask; color: About.stable ? Theme.teal : About.kind === "cooking" ? Theme.lavender : Theme.gold }
                SettingsText { anchors.verticalCenter: parent.verticalCenter; text: About.branch; font.weight: Font.ExtraBold }
                SettingsText { anchors.verticalCenter: parent.verticalCenter; text: About.mood; secondary: true }
            }
        }
    }
    Row {
        visible: root.page === "sound"; spacing: 4
        SettingsButton { text: "Devices"; selected: root.soundTab === "devices"; quiet: true; onClicked: root.soundTab = "devices" }
        SettingsButton { text: "Applications"; selected: root.soundTab === "applications"; quiet: true; onClicked: root.soundTab = "applications" }
    }
    ProviderCards { width: parent.width; visible: root.page === "lens" }
    HealthSection { width:parent.width;visible:root.page === "health" }
    DriveResult { width:parent.width;visible:root.page === "system" && Drives.result !== null }
    StatsCards { width: parent.width; visible: root.page === "system" }
    Repeater {
        model: root.groups
        SettingsGroup { required property var modelData; required property int index; width: root.width; title: modelData.title || ""; rows: modelData.rows; order: index; arrival: root.arrival }
    }
    SettingsGroup {
        visible: root.page === "bluetooth" && root.discovering
        width: parent.width
        title: Bluetooth.scanning ? "Nearby · scanning" : "Nearby"
        rows: Bluetooth.nearby.map(d => ({ id: d.address, kind: "action", title: Bluetooth.name(d), subtitle: () => [Bluetooth.status(d), Bluetooth.audioDetail(d)].filter(Boolean).join(" · "), button: d.pairing ? "Pairing…" : "Pair", enabled: () => !d.pairing && Bluetooth.agent, run: () => Bluetooth.pair(d) }))
    }
    Rectangle {
        visible: root.page === "bluetooth" && root.discovering && !Bluetooth.nearby.length
        width: parent.width; height: 150; radius: Theme.tui ? 0 : (Theme.tileRadius); color: Theme.overlay
        Column {
            anchors.centerIn: parent; width: parent.width - 48; spacing: 8
            SettingsText { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: Bluetooth.scanning ? "Looking for nearby devices…" : "Nothing nearby yet"; font.pixelSize: Theme.tui ? Theme.tuiTextSize : 14 }
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

    MicCheckCard { width:parent.width;visible:root.page === "sound" && root.soundTab === "devices" }
    ResetSection { width:parent.width;page:root.page;visible:SettingsReset.available(root.page) }
    ImportReview { width:parent.width;visible:root.page === "about" && Preferences.reviewing }

    function group(title, rows) { return { title: title, rows: rows }; }
    function toggle(id, title, subtitle, get, set) { return { id: id, kind: "toggle", title: title, subtitle: () => subtitle, checked: get, toggle: () => set(!get()) }; }
    function action(id, title, subtitle, button, run) { return { id: id, kind: "action", title: title, subtitle: typeof subtitle === "function" ? subtitle : () => subtitle, button: button, run: run }; }
    // value and subtitle may be functions, read live by the row: a page whose readings change (System
    // monitor) must not rebuild its groups for it, or they're made anew and rise in again each time
    // "1.2% · 620 MB" for a share of the CPU (0–1, -1 while unknown) and memory in MB
    function usage(cpu, mb) { return `${cpu < 0 ? "—" : (cpu*100).toFixed(1)+"%"} · ${Math.round(mb)} MB`; }
    function read(id, title, value, subtitle) { return { id: id, title: title, value: typeof value === "function" ? value : () => value, subtitle: typeof subtitle === "function" ? subtitle : () => subtitle || "" }; }
    function time(id, title, get, set) { return { id: id, kind: "time", title: title, value: get, set: set }; }
    function buildGroups(page = root.page) {
        // Experimental (owner's call, 15 November 2026; sorted 19 November): the TUI style and features still
        // being tested (game mode, phone preview); Colours, wallpaper/cat, clipboard and restart live on their own pages
        if (page === "experimental") return [
            group("Style", [
                { id: "style", kind: "choice", title: "Style", subtitle: () => "Applied live across the shell.", choices: () => [{value:"classic",title:"Classic"},{value:"tui",title:"TUI"}], value: () => ShellSettings.appearanceStyle, set: ShellSettings.setAppearanceStyle }
            ]),
            group("Game mode", [
                toggle("game-mode", "Game mode", "While a fullscreen game is focused: quiet notifications, no animations or blur.", () => ShellSettings.gameMode, ShellSettings.setGameMode),
                action("game-classes", "Extra game windows", () => ShellSettings.gameClasses.length ? ShellSettings.gameClasses.join(", ") : "Steam, Sober and gamescope only", "Change", () => SettingsHub.beginEdit("games"))
            ]),
            group("Phone preview", [
                toggle("phone-preview", "Phone timer preview", "Share the active Focus or Pomodoro timer on your local network.", () => ShellSettings.phonePreview, ShellSettings.setPhonePreview)
            ])
        ];
        if (page === "appearance") return [
            group("Colours", [
                { id: "colours", kind: "choice", title: "Colours", subtitle: () => "Pistachio Noir, or Noir in greys with one red for errors.", choices: () => [{value:"pistachio",title:"Pistachio Noir"},{value:"noir",title:"Noir"}], value: () => ShellSettings.colourScheme, set: ShellSettings.setColourScheme },
            ]),
            group("Surfaces", [
                { id: "frost", kind: "choice", title: "Frosted panels", subtitle: () => "Choose how much of the desktop shows through.", choices: () => [{value:"solid",title:"Solid"},{value:"subtle",title:"Subtle"},{value:"glassy",title:"Glassy"}], value: () => !ShellSettings.frosted ? "solid" : ShellSettings.glassy ? "glassy" : "subtle", set: v => { ShellSettings.setGlassy(v === "glassy"); ShellSettings.setFrosted(v !== "solid"); } },
                toggle("shadows", "Drop shadows", "Soft depth around panels and popups.", () => ShellSettings.shadows, ShellSettings.setShadows)
            ]),
            group("Desktop", [action("wallpaper", "Wallpaper", "Your images, with a fit kept for each one.", "Choose wallpaper", () => SettingsHub.wallpapersRequested()), toggle("desktop", "Desktop icons", "Show files and folders from your Desktop.", () => Desktop.enabled, Desktop.setEnabled), toggle("monochrome-wallpaper", "Monochrome wallpaper", "Desaturate the wallpaper in Noir. Original image stays unchanged.", () => ShellSettings.monochromeWallpaper, ShellSettings.setMonochromeWallpaper), toggle("desktop-cat", "Desktop cat", "Meoww", () => ShellSettings.desktopCat, ShellSettings.setDesktopCat)]),
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
            return [group("", [audio(false)]), group("", [audio(true)]), group("Media player", [{id:"player",kind:"choice",title:"Player",subtitle:()=>Media.selectionMissing ? "Chosen player unavailable · using Auto temporarily." : "For the bar and media card · this session only.",choices:()=>Media.choices,value:()=>Media.selectedPlayer,set:Media.selectPlayer}]), group("Behaviour", [toggle("takeover", "Headphones take over", "Move sound to Bluetooth headphones when they connect.", () => ShellSettings.headphonesTakeOver, ShellSettings.setHeadphonesTakeOver), toggle("tick", "Volume tick", "Play a soft click when volume keys change the level.", () => ShellSettings.volumeTick, ShellSettings.setVolumeTick)])];
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
        if (page === "bluetooth") return [group("", [toggle("power", "Bluetooth", Bluetooth.summary, () => Bluetooth.enabled, Bluetooth.setEnabled)]), group("Your devices", Bluetooth.paired.map(d => ({ id: d.address, kind: "action", title: Bluetooth.name(d), subtitle: () => [Bluetooth.status(d), Bluetooth.audioDetail(d)].filter(Boolean).join(" · "), button: d.connected ? "Disconnect" : "Connect", enabled: () => Bluetooth.ready && !/Connecting|Disconnecting/.test(Bluetooth.status(d)), run: () => Bluetooth.toggleConnection(d), forget: () => SettingsHub.forgetDevice = d })))];
        if (page === "network") return [group("", [read("ethernet", "Ethernet", Network.connected ? "Connected" : Network.hasLink ? "Connecting" : "Not connected", Network.connected ? "Connected" : Network.hasLink ? "Cable connected" : "Cable unplugged")]), group("Connection details", [read("type", "Connection", "Wired Ethernet"), read("speed", "Link speed", Network.connected ? Network.speed >= 1000 ? (Network.speed/1000) + " Gbps" : Network.speed + " Mbps" : "—", "Speed reported by the connection.")]), group("Addresses", [read("interface","Interface",Network.interfaceName || "—"), ...[["ipv4","IPv4"],["ipv6","IPv6"],["gateways","Gateway"],["dns","DNS"]].map(pair=>({id:pair[0],kind:"action",title:pair[1],subtitle:()=>(Network.details[pair[0]] || []).join(" · ") || "Not reported",button:"Copy",enabled:()=>(Network.details[pair[0]] || []).length>0,run:()=>Network.copyDetail(pair[0])}))])];
        if (page === "focus") {
            const choose = (id, title, subtitle, values, unit) => ({ id: id, kind: "choice", title: title, subtitle: () => subtitle, choices: () => values.map(v => ({ value: String(v), title: `${v}${unit}` })), value: () => String(Store.saved[id]), set: v => FocusMode.setOption(id, parseInt(v)) });
            const opt = (id, title, subtitle) => toggle(id, title, subtitle, () => Store.saved[id] === true, on => FocusMode.setOption(id, on));
            // apps that sent notifications, and those already allowed
            const apps = [...new Set(Notifs.notifications.map(n => n.appName ?? "").concat(FocusMode.allowed))].filter(a => a).sort((a, b) => a.localeCompare(b));
            return [
                group("Zen mode", [
                    toggle("zen", "Zen mode", "No bar, pills or desktop icons, no gaps or borders; toasts wait.", () => FocusMode.zen, on => on ? FocusMode.startZen(false) : FocusMode.stopZen()),
                    opt("zenPomodoro", "Pomodoro in Zen", "A Pomodoro runs while Zen is on, its time where the bar would be.")
                ]),
                group("Focus", [
                    toggle("focus", "Focus session", FocusMode.focusing ? `${FocusMode.phaseName()} · ${FocusMode.clock(FocusMode.left())} left` : "Toasts wait until it ends, but from the apps you allow.", () => FocusMode.focusing, () => FocusMode.toggleFocus()),
                    { id: "focusPomodoro", kind: "choice", title: "Session", subtitle: () => "One stretch, or Pomodoro rounds with breaks.", choices: () => [{ value: "single", title: "One stretch" }, { value: "pomodoro", title: "Pomodoro" }], value: () => Store.saved.focusPomodoro ? "pomodoro" : "single", set: v => FocusMode.setOption("focusPomodoro", v === "pomodoro") },
                    choose("focusMinutes", "Length", "A single stretch.", [15, 25, 30, 45, 50, 60, 90, 120], " min"),
                    opt("focusZen", "Zen during Focus", "Zen mode turns on with the session and off with it.")
                ]),
                group("Pomodoro", [
                    toggle("pomodoro", "Pomodoro", FocusMode.pomodoring ? `${FocusMode.phaseName()} · ${FocusMode.clock(FocusMode.left())} left` : "On its own: the rounds and the pill, nothing held back.", () => FocusMode.pomodoring, () => FocusMode.togglePomodoro()),
                    choose("pomodoroWork", "Work", "Each round of work.", [15, 20, 25, 30, 45, 50], " min"),
                    choose("pomodoroBreak", "Break", "After each round.", [3, 5, 10, 15], " min"),
                    choose("pomodoroLongBreak", "Long break", "After the last round.", [10, 15, 20, 30], " min"),
                    choose("pomodoroRounds", "Rounds", "Work rounds before the long break.", [2, 3, 4, 5, 6], "")
                ]),
                group("Allowed during Focus", apps.length ? apps.map(a => toggle("allow:" + a, a, "Its toasts still show during Focus (not in Zen).", () => FocusMode.allowed.includes(a), on => FocusMode.setAllowed(a, on)))
                    : [read("allowed", "No apps yet", "", "Apps appear here once they have sent a notification.")])
            ];
        }
        if (page === "integrations") {
            // other apps the shell works with (owner's request, 12 November 2026): each can be switched
            // off; off, the shell acts as if the app weren't there
            const has = id => Apps.list.some(a => a.id === id);
            const one = (id, title, what, installed) => toggle(id, title, installed ? what : "Not installed · " + what, () => ShellSettings.integration(id), on => ShellSettings.setIntegration(id, on));
            return [
                group("Calendar and clock", [
                    toggle("calendar", "GNOME Calendar events", Events.available ? `Dots and the chosen day's events in the month calendar${Events.calendars.length ? ` · ${Events.calendars.length} calendars` : ""}. Read-only.` : "Not installed · events in the month calendar", () => ShellSettings.calendarEvents, ShellSettings.setCalendarEvents),
                    one("clocks", "GNOME Clocks alarms", "The shell rings Clocks' alarms with its own card; off, Clocks rings them itself while it runs.", Clocks.clocksInstalled)
                ]),
                group("Panels", [one("weather", "Weather", "Open-Meteo, above the calendar and on the lock screen.", true)]),
                group("Launcher", [
                    one("vscode", "VS Code", "Recent folders and workspaces: type vscode, code or a folder's name.", has("com.microsoft.VSCode") || has("code")),
                    one("clion", "CLion", "Recent projects: type clion or a project's name.", has("jetbrains-clion")),
                    one("steam", "Steam games", "Your installed games, with covers, as you type their names.", has("steam")),
                    one("sober", "Sober (Roblox)", "Among the games.", has("org.vinegarhq.Sober")),
                    one("cider", "Cider", "m and a song plays from Apple Music; Up next in the media card.", Cider.installed),
                    one("claude", "Claude Desktop", "claude and a question opens a new chat.", has("com.anthropic.Claude")),
                    one("qalc", "libqalculate", "Harder maths after = or when the calculator can't read it.", Qalc.found),
                    one("tldr", "tldr", "tldr and a command shows its examples.", true)
                ])
            ];
        }
        if (page === "lens") return [group("", [action("chats", "Saved chats", "~/lens-chats · snip and Markdown", "Open folder", SettingsHub.openChats)]),
            group("Quick chat", [toggle("quickchat", "Quick chat in quick settings", "A tile beside LocalSend opens it. Off, LocalSend takes the whole row.", () => ShellSettings.quickChatTile, ShellSettings.setQuickChatTile),
                action("quickchats", "Saved quick chats", "~/quick-chats · Markdown", "Open folder", SettingsHub.openQuickChats)])];
        if (page === "apps") return [group("Launcher", [toggle("clipboard-history", "Clipboard history", "Save copied text on disk; it may include secrets.", () => ShellSettings.clipboardHistory, ShellSettings.setClipboardHistory)]), group("Open things with", [{id:"terminal",kind:"choice",title:"Terminal",subtitle:()=>"For commands, terminal apps and showoff.", choices:()=>Apps.terminalChoices.map(v=>({value:v,title:Apps.terminalName(v)})),value:()=>Apps.terminal,set:Apps.setTerminal}]), group("Places", [action("weather","Weather location",Weather.placeName,"Change",()=>SettingsHub.beginEdit("weather")), action("wallpapers","Wallpapers",Wallpapers.folder.replace(/^\/home\/[^/]+/,"~"),"Open folder",Wallpapers.openFolder)]), ...(Cider.installed ? [group("Integrations",[action("cider","Cider token",Cider.usable ? "Set · enables Up next and Apple Music search." : "Not set · for Up next and Apple Music search.","Change",()=>SettingsHub.beginEdit("cider"))])] : [])];
        if (page === "localsend" && LocalSend.available) return [group("",[toggle("receive","Receive files",LocalSend.summary,()=>LocalSend.wanted,LocalSend.setReceive)]),group("This device",[action("name","Device name",LocalSend.name,"Change",()=>SettingsHub.beginEdit("name")),action("folder","Save received files to",LocalSend.folderShown,"Change",LocalSend.pickFolder)]),group("Incoming requests",[toggle("known","Accept known devices","Skip asking for devices you have accepted before.",()=>LocalSend.acceptKnown,LocalSend.setAcceptKnown)])];
        // only which disks there are shapes the page; the readings are read by the rows themselves
        if (page === "system") return [group("Storage",SystemStats.diskMounts.map(m=>read("storage",m === "/" ? "System disk" : "Home",()=>{ const d=SystemStats.disks.find(x=>x.mount===m); return d ? `${SystemStats.gigabytes(d.free)} free of ${SystemStats.gigabytes(d.size)}` : "—"; },m))),group("Shell",[read("shell","Pistachio Noir",()=>root.usage(SystemStats.shellCpu,SystemStats.shellMem),"CPU and memory, including its helpers."),read("hyprland","Hyprland",()=>SystemStats.hyprMem > 0 ? root.usage(SystemStats.hyprCpu,SystemStats.hyprMem) : "—","The compositor."),read("desktop","Shell and Hyprland",()=>SystemStats.hyprMem > 0 ? root.usage(SystemStats.shellCpu < 0 || SystemStats.hyprCpu < 0 ? -1 : SystemStats.shellCpu+SystemStats.hyprCpu,SystemStats.shellMem+SystemStats.hyprMem) : "—","Both together.")]),group("Removable drives",Drives.mounted.map(d=>action("drive:"+d.path,d.name,`${d.mountpoint} · ${d.size}`,"Eject",()=>Drives.eject(d))))];
        if (page === "about") return [group(root.funAbout ? "The cat’s build inspection" : "",[read("branch",root.funAbout ? "The branch we’re perched on" : "Branch",About.branch || "—",About.branch ? About.moodLong : ""),read("build",root.funAbout ? "Today’s shell specimen" : "Build",About.commit || "Reading…",[About.date,About.subject,About.changed ? `${About.changed} changed files` : ""].filter(Boolean).join(" · ")),read("quickshell",root.funAbout ? "Quickshell · panel wrangler" : "Quickshell",About.quickshell || "—"),read("hyprland",root.funAbout ? "Hyprland · window herder" : "Hyprland",About.hyprland || "—"),read("qt",root.funAbout ? "Qt · keeper of pixels" : "Qt",About.qt || "—"),action("source",root.funAbout ? "Peek behind the whiskers" : "Source code",root.funAbout ? "The shell and its design boards, no secret catnip required." : "The shell and its design boards.","View source",SettingsHub.openSource)]),
            // export and import (owner's call, 15 November 2026): one file, a review before anything changes
            group(root.funAbout ? "Pack your settings" : "Your settings",[action("export",root.funAbout ? "Pack the suitcase" : "Export settings",()=>Preferences.status && !Preferences.reviewing ? Preferences.status : `Every preference and the launcher's pins, aliases and presets, to ${Preferences.shownPath}.`,"Export",Preferences.exportNow),action("import",root.funAbout ? "Unpack with care" : "Import settings",`Read ${Preferences.shownPath} and review the changes before they apply.`,"Review import",Preferences.review)])];
        if (page === "health") return [group("Restart", [action("restart-shell", "Restart shell", "Restart the shell and its helpers.", "Restart", () => SettingsHub.restartMode = "restart"), action("force-restart-shell", "Force restart shell", "Immediately stop the shell and its helpers.", "Force restart", () => SettingsHub.restartMode = "force-restart")])];
        return [];
    }
}
