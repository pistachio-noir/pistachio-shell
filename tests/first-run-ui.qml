import qs
import qs.setup
import Quickshell
import Quickshell.Io
import QtQuick
import QtTest

// The first-run view alone, in a normal window at its real size, with fixture inputs and no services.
ShellRoot {
    id: root
    property int requests
    property var change
    property var action
    property var actions: []
    property string destination
    readonly property var checkRows: [
        ["Hyprland", "Required"], ["Quickshell", "Required"], ["Python", "Required"], ["Wayland clipboard", "Required"],
        ["PipeWire's pactl", "pipewire-pulse"], ["Manrope font", "install.sh downloads it"], ["Bluetooth", "bluez bluez-utils"],
        ["Monitor brightness", "ddcutil"], ["Night light", "hyprsunset"], ["Screenshots", "grim"], ["Drive eject", "udisks2"],
        ["Clipboard history", "cliphist"], ["Opening files", "xdg-utils"], ["Notification service", "The shell shows them"]
    ]
    readonly property var wizard: host.item?.wizard ?? null
    readonly property bool nativeSurface: Quickshell.env("PISTACHIO_SETUP_NATIVE") === "1"
    LazyLoader {
        id: host
        active: true
        component: Component {
            FloatingWindow {
                property alias wizard: embedded
                implicitWidth: Theme.setupWidth
                implicitHeight: Theme.setupHeight
                color: Theme.bgAlt
                FirstRunWizard { id: embedded; anchors.fill: parent }
            }
        }
    }
    Connections {
        target: root.wizard
        function onCheckRequested() { root.requests++; root.wizard.checkState = "checking"; root.wizard.checks = []; }
        function onValueRequested(key, value) {
            root.change = [key, value];
            const updated = Object.assign({}, root.wizard.values);
            updated[key] = value;
            root.wizard.values = updated;
        }
        function onActionRequested(key, payload) { root.action = [key, payload]; root.actions = root.actions.concat([key]); }
        function onFinished(result) { root.destination = result; root.wizard.open = false; }
    }
    onWizardChanged: if (wizard) {
        wizard.reducedMotion = true;
        wizard.values = ({colourScheme: "pistachio", frostStyle: "subtle", shadows: true, desktopIcons: false, wallpaper: "dusk",
                outputLevel: 0.72, inputLevel: 0.48, brightness: 0.7, outputDevice: "speaker", inputDevice: "mic", nightLight: true,
                quietFullscreen: true, quietCalls: true, notificationSound: true, bluetooth: true,
                localSend: false, lensProvider: "claude", lensModel: "haiku", lensEffort: "medium",
                lensFallback: false, terminal: "kitty", weatherLocation: "Warsaw, Poland"})
        wizard.options = ({
                wallpaper: [
                    {title:"Pistachio dusk",value:"dusk",source:preview("#9FD88A",78,20)},
                    {title:"Teal tide",value:"tide",source:preview("#7FC9A8",20,80)},
                    {title:"Clay hour",value:"hour",source:preview("#D9975A",70,75)},
                    {title:"Night bloom",value:"bloom",source:preview("#AC8ED0",30,25)}
                ],
                outputDevice: [{title:"USB audio interface",value:"speaker"}], inputDevice: [{title:"Desk microphone",value:"mic"}],
                lensProvider: [{title:"Claude",value:"claude",subtitle:"Found"}, {title:"ChatGPT",value:"codex",subtitle:"Not found · optional",disabled:true}],
                lensModel: [{title:"Haiku 5.5",value:"haiku"}], lensEffort: [{title:"Medium",value:"medium"}],
                terminal: [{title:"kitty",value:"kitty"}, {title:"foot",value:"foot"}]})
        wizard.details = ({outputDevice:"USB audio interface",inputDevice:"Desk microphone",brightness:"Your external display, over DDC/CI",
                nightLight:"Warmth 3800 K", localSendName:"workstation", ethernet:"Wired · connected · 1 Gbps. The shell shows wired status only.",
                lensFallback:"Needs Codex CLI", terminal:"kitty opens commands, terminal apps and showoff.",wallpaperFolder:"~/Pictures/Wallpapers",
                screenshotFolder:"Saved in ~/Pictures/Screenshots",lensArchive:"Saved chats go to ~/lens-chats.",
                bindTip:'hl.bind("SUPER + space", hl.dsp.exec_cmd("psc launcher toggle"))'})
        wizard.available = ({lensFallback:false})
        wizard.devices = [{title:"Studio headphones",detail:"Connected · 80%"},{title:"Compact keyboard",detail:"Paired"}]
        wizard.summary = [{title:"Look",detail:"Pistachio Noir · subtle panels"},{title:"Sound",detail:"USB audio interface, 72%"},
                {title:"Notifications",detail:"quiet in fullscreen, quiet in calls, sound on"},{title:"Connections",detail:"Bluetooth on, LocalSend off"},
                {title:"Lens",detail:"Claude, Haiku 5.5"},{title:"Places",detail:"kitty, Warsaw"}]
        wizard.shortcuts = [{title:"Launcher",note:"Super Space",detail:"psc launcher toggle"},{title:"Quick settings",note:"Super A",detail:"psc quicksettings toggle"},
                {title:"Notifications",note:"Super N",detail:"psc notifications toggle"},{title:"Power menu",note:"Super Esc",detail:"psc power toggle"},
                {title:"Screenshot",note:"Print",detail:"psc screenshot region"},{title:"Overview",note:"Super O",detail:"psc overview toggle"}]
        wizard.commands = [{command:"psc status",detail:"Running? Memory and helpers"},{command:"psc doctor",detail:"What's installed, what's missing"},
                {command:"psc ipc",detail:"Every command you can bind"},{command:"psc log --errors",detail:"Recent errors only"},
                {command:"psc restart",detail:"Stop and start the shell"},{command:"psc setup",detail:"Open this setup again"}]
        wizard.open = true;
    }
    TestCase {
        id: input
        parent: wizard
        when: false
    }

    function find(item, name) {
        if (item.objectName === name && item.visible) return item;
        for (const child of item.children) {
            const hit = find(child, name);
            if (hit) return hit;
        }
        return null;
    }
    function check(ok, why) { if (!ok) throw Error(why); }
    function preview(color, x, y) {
        return "data:image/svg+xml," + encodeURIComponent(
            '<svg xmlns="http://www.w3.org/2000/svg" width="150" height="96"><defs><radialGradient id="g" cx="'
            + x + '%" cy="' + y + '%" r="85%"><stop stop-color="' + color + '" stop-opacity=".55"/>'
            + '<stop offset="1" stop-color="#15170F"/></radialGradient></defs><rect width="150" height="96" fill="url(#g)"/></svg>');
    }
    function click(name) {
        const target = find(wizard.Window.window.contentItem, name);
        check(target && target.enabled, "Missing or disabled: " + name);
        input.mouseClick(target, target.width / 2, target.height / 2);
        input.wait(40);
    }
    function capture(name) {
        const directory = Quickshell.env("PISTACHIO_SETUP_SHOTS");
        if (!directory) return;
        const path = directory + "/" + name + ".png";
        const window = wizard.Window.window;
        if (nativeSurface) Quickshell.execDetached(["grim", "-g", `${window.x},${window.y} ${window.width}x${window.height}`, path]);
        else if (!wizard.confirmingSkip) wizard.grabToImage(result => result.saveToFile(path));
        input.wait(nativeSurface ? 300 : 170);
    }

    function run() {
        input.wait(80);
        capture("01-welcome");
        click("setup-start");
        check(wizard.pageId === "check" && requests === 1, "start requests checks");
        check(!find(wizard, "setup-continue").enabled, "waits for a check result");
        wizard.checks = checkRows.slice(0, 9).map(([title,detail]) => ({title, detail, status:"pass"}));
        wizard.checkTotal = checkRows.length;
        input.wait(40);
        capture("02-checking");
        wizard.checks = [
            {title:"mako is running", detail:"Only one program can show notifications.", status:"conflict", command:"pkill -x mako"},
            {title:"Monitor brightness", detail:"Without it: the brightness slider is hidden.", status:"optional", package:"ddcutil"},
            {title:"Wayland clipboard", detail:"Without it: copying text, emoji and screenshots.", status:"warning", package:"wl-clipboard"}
        ].concat(checkRows.slice(0, 11).filter(([t]) => t !== "Monitor brightness" && t !== "Wayland clipboard").map(([title,detail]) => ({title,detail,status:"pass"})));
        wizard.checkNote = "1 optional tool not installed: ddcutil";
        wizard.checkState = "attention";
        input.wait(40);
        capture("03-attention");
        click("setup-copy-command");
        check(action[0] === "copyCommand" && action[1] === "pkill -x mako", "the conflict's command is copied first: " + JSON.stringify(action));
        click("setup-retry");
        check(requests === 2 && wizard.checkState === "checking", "recheck requests checks again");
        wizard.checks = checkRows.map(([title,detail]) => ({title,detail,status:"pass"}));
        wizard.checkNote = "";
        wizard.checkState = "clear";
        input.wait(40);
        capture("04-all-clear");
        click("setup-continue");
        check(wizard.pageId === "look", "Look follows Check");
        capture("05-look");
        click("setup-option-noir");
        check(change[0] === "colourScheme" && change[1] === "noir", "Colours choice routes: " + JSON.stringify(change));
        click("setup-shadows");
        check(change[0] === "shadows" && change[1] === false, "native toggle routes choice");
        click("setup-wallpaper-1");
        check(change[0] === "wallpaper" && change[1] === "tide", "wallpaper tile routes its value");
        click("setup-skip");
        input.wait(200);
        check(wizard.confirmingSkip, "skip opens confirmation");
        capture("06-skip");
        input.keyClick(Qt.Key_Escape);
        input.wait(220);
        check(!wizard.confirmingSkip && wizard.pageId === "look", "Escape closes confirmation");
        click("setup-continue");
        const output = find(wizard, "setup-outputLevel");
        check(output, "Sound has output controls");
        capture("07-sound");
        input.mouseClick(output, output.width * 0.4, output.height / 2);
        check(change[0] === "outputLevel" && Math.abs(change[1] - 0.4) < 0.06, "slider reports a normalized level");
        click("setup-continue");
        capture("08-notifications");
        click("setup-play-sound");
        check(action[0] === "playNotificationSound", "sound preview action reaches controller");
        click("setup-continue");
        check(find(wizard, "setup-localSend"), "Connections has LocalSend toggle");
        capture("09-connections");
        wizard.available = ({lensFallback:false, localSend:false});
        input.wait(40);
        check(!find(wizard, "setup-localSend"), "LocalSend hides without the app");
        wizard.available = ({lensFallback:false});
        click("setup-continue");
        check(find(wizard, "setup-lensModel") && !find(wizard, "setup-lens-none"), "Lens has model picker");
        capture("10-lens");
        wizard.available = ({lensFallback:false, lensProvider:false});
        input.wait(40);
        check(find(wizard, "setup-lens-none") && !find(wizard, "setup-lensModel") && !find(wizard, "setup-lensProvider"),
            "no assistant: Lens says so and offers nothing to pick");
        capture("10b-lens-none");
        wizard.available = ({lensFallback:false});
        click("setup-continue");
        capture("11-places");
        check(!find(wizard, "setup-choose-folder"), "folders are fixed text, no Change button");
        const city = find(wizard, "setup-weatherLocation");
        city.forceActiveFocus();
        city.text = "Gdańsk";
        input.keyClick(Qt.Key_Return);
        check(change[0] === "weatherLocation" && change[1] === "Gdańsk" && wizard.pageId === "places",
            "city entry submits in place: " + JSON.stringify({change, page: wizard.pageId, focus: city.activeFocus}));
        click("setup-continue");
        check(wizard.pageId === "done" && find(wizard, "setup-psc-guide") && find(wizard, "setup-keys"), "All set shows the psc tip and guide");
        capture("12-done");
        click("setup-open-settings");
        check(destination === "settings" && !wizard.open, "Finish routes to Settings");

        // Restore my settings: review, apply, check, done
        wizard.open = true;
        input.wait(80);
        check(wizard.page === 0 && wizard.mode === "full", "reopen resets navigation");
        click("setup-restore");
        check(wizard.pageId === "restore" && action[0] === "restoreReview", "Restore asks for a review");
        check(wizard.steps.join() === "Restore,Check,All set", "restore has its own short steps: " + wizard.steps.join());
        wizard.restore = ({state:"busy", path:"~/.config/pistachio/pistachio-shell/settings.toml", changes:[]});
        input.wait(40);
        check(!find(wizard, "setup-continue").enabled, "continue waits for the review");
        wizard.restore = ({state:"missing", path:"~/.config/pistachio/pistachio-shell/settings.toml", message:"Nothing at that path.", changes:[]});
        input.wait(40);
        capture("13-restore-missing");
        click("setup-restore-choose");
        check(action[0] === "restoreChoose", "choose another file");
        wizard.restore = ({state:"reviewing", path:"~/settings.toml", changes:[{title:"Colours",from:"pistachio",to:"noir"},{title:"Drop shadows",from:"On",to:"Off"}], skipped:1});
        input.wait(40);
        capture("14-restore-review");
        check(find(wizard, "setup-continue").text === "Apply 2 settings", "apply names the count");
        click("setup-back");
        check(wizard.page === 0 && action[0] === "restoreCancel" && wizard.mode === "full", "Back cancels the review");
        click("setup-restore");
        wizard.restore = ({state:"reviewing", path:"~/settings.toml", changes:[{title:"Colours",from:"pistachio",to:"noir"}], skipped:0});
        input.wait(40);
        click("setup-continue");
        check(actions.slice(-2).join() === "restoreReview,restoreApply" && wizard.pageId === "check" && requests === 3, "Apply, then the check: " + actions.slice(-3));
        wizard.checkState = "clear";
        click("setup-continue");
        check(wizard.pageId === "done", "restore ends on All set");
        click("setup-continue");
        check(destination === "shell" && !wizard.open, "Open the shell finishes");

        wizard.open = true;
        input.wait(80);
        wizard.reducedMotion = false;
        click("setup-start");
        check(wizard.panelReveal > 0 && wizard.panelReveal < 1, "panel fades in when motion is allowed");
        input.tryVerify(() => wizard.panelReveal === 1, 1000);
        wizard.checkState = "attention";
        click("setup-continue-anyway");
        check(wizard.pageId === "look", "attention can be bypassed");
        input.wait(250);
        click("setup-skip");
        input.wait(240);
        check(wizard.confirmingSkip, "animated skip opens");
        click("setup-confirm-skip");
        check(destination === "skip" && !wizard.open, "confirmed skip reaches controller");
        if (!nativeSurface) {
            input.tryVerify(() => !wizard.confirmingSkip && !wizard.shown, 1000);
            wizard.anchors.fill = null;
            wizard.width = 760;
            wizard.height = 540;
            Theme.tui = true;
            wizard.reducedMotion = true;
            wizard.open = true;
            input.wait(80);
            capture("15-tui-welcome");
            const start = find(wizard, "setup-start");
            check(start.font.family === "Manrope" && start.background.radius > 0, "setup keeps the Classic look in TUI: " + start.font.family);
            click("setup-start");
            check(wizard.pageId === "check", "compact TUI welcome accepts input");
            wizard.checkState = "clear";
            click("setup-continue");
            capture("16-tui-look");
            const panel = find(wizard, "setup-panel");
            check(panel.width <= wizard.width && panel.height <= wizard.height, "compact TUI setup fits its window");
            Theme.tui = false;
        }
        return "PASS welcome, checks, every page, restore, skip and completion";
    }
    IpcHandler {
        target: "firstRunTest"
        function ready(): bool { return wizard?.open ?? false; }
        function run(): string { try { return root.run(); } catch (e) { return "FAIL " + e.message + "\n" + e.stack; } }
    }
}
