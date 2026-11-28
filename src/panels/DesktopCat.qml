import qs
import qs.services
import QtQuick

// The wallpaper forwards empty-desktop hover and clicks; icons remain above the cat.
Canvas {
    id: root
    property bool active
    property bool interactive
    property bool hovered
    property bool happy
    property int petCount
    readonly property bool purring: petCount >= 3
    property string skin: "cream"
    readonly property var coat: Theme.catSkins.find(option => option.value === skin) ?? Theme.catSkins[0]
    property bool laptopPose
    property real laptopOffset
    readonly property bool holdingClock: interactive && visible &&
        (!!FocusMode.session?.endsAt || !!Clocks.stopwatch?.since || Clocks.timers.some(timer => timer.endsAt))
    readonly property bool coding: interactive && visible && isCodingWindow(Compositor.focusedWindow)
    readonly property bool atLaptop: !holdingClock && (laptopPose || coding)
    readonly property bool wearingHeadphones: interactive && visible && Media.players.some(player => player.isPlaying)
    property string reactionText
    property int frame
    property int idleLine
    readonly property bool animating: tick.running
    width: 96; height: 96
    visible: active
    function isCodingWindow(window): bool {
        const appId = (window?.appId ?? "").toLowerCase();
        const app = appId.split(".").pop();
        const editors = ["code", "vscode", "code-oss", "code-insiders", "codium", "vscodium", "neovide", "neovim", "nvim"];
        if (editors.includes(app) || app.startsWith("jetbrains-"))
            return true;
        // A terminal can identify Neovim in its title. A browser page about Neovim is just a page.
        return /\b(?:nvim|neovim)\b/i.test(window?.title ?? "")
            && Object.values(Apps.terminals).some(terminal => terminal.appId.toLowerCase() === appId);
    }
    function pet() {
        if (!interactive || !visible) return;
        if (laptopPose) clearReaction();
        petCount = Math.min(petCount + 1, 3);
        happy = true;
        happyTimer.restart();
    }
    function react(message: string) {
        if (!visible) return;
        laptopPose = false;
        reactionText = message;
        reactionTimer.restart();
    }
    function sayIdle() {
        if (!visible || reactionText || atLaptop || holdingClock || happy) return;
        const lines = ["Meow!", "", "hii!!", "Nice to see you.", "Time for a stretch?"];
        const line = lines[idleLine++ % lines.length];
        if (!line && interactive) {
            laptopPose = true;
            reactionTimer.restart();
        } else {
            react(line || "Meow!");
        }
    }
    function clearReaction() { reactionText = ""; laptopPose = false; reactionTimer.stop(); }
    function stopPetting() { happy = false; petCount = 0; happyTimer.stop(); }
    onVisibleChanged: if (!visible) { hovered = false; stopPetting(); clearReaction(); }
    onReactionTextChanged: requestPaint()
    onCoatChanged: requestPaint()
    onAtLaptopChanged: {
        if (atLaptop) laptopLanding.restart();
        else laptopLanding.stop();
        requestPaint();
    }
    onHoldingClockChanged: requestPaint()
    onWearingHeadphonesChanged: requestPaint()
    onLaptopOffsetChanged: requestPaint()
    onPurringChanged: requestPaint()
    Connections { target:Clocks; function onRingingChanged() { if (Clocks.ringing) root.react(Clocks.ringing.kind === "alarm" ? "Alarm time!" : "Timer's up!"); } }
    Connections { target:FocusMode; function onPhaseFinished(message) { root.react(message); } }
    Timer { interval:300000; running:root.visible; repeat:true; onTriggered:root.sayIdle() }
    Timer { id:reactionTimer; interval:4000; onTriggered:root.clearReaction() }
    Rectangle {
        objectName: "cat-reaction"
        x: Math.min(0, 32 - width); y: -height - 6
        width: reactionLabel.implicitWidth + 24; height: reactionLabel.implicitHeight + 18
        radius: Theme.tileRadius; color: Theme.bgAlt; border.width: 1; border.color: Theme.overlay2
        opacity: reactionLabel.text ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.motionDuration; easing.type: Theme.easing } }
        Text { id:reactionLabel; anchors.centerIn:parent; text:root.reactionText || (root.purring ? "Purr…" : ""); textFormat:Text.PlainText; color:Theme.text; font.family:Theme.fontUi; font.pixelSize:13; font.weight:Font.Bold }
    }
    onFrameChanged: requestPaint()
    onHoveredChanged: requestPaint()
    onHappyChanged: requestPaint()
    Connections { target:Theme; function onNoirChanged(){root.requestPaint();} function onOledChanged(){root.requestPaint();} }
    Timer { id:tick; running:root.visible; repeat:true; interval:root.purring ? 150 : 650; onTriggered:root.frame=(root.frame+1)%10 }
    Timer { id:happyTimer; interval:1800; onTriggered:root.stopPetting() }
    NumberAnimation {
        id: laptopLanding
        target: root; property: "laptopOffset"
        from: -8; to: 0; duration: 220; easing.type: Theme.easing
    }
    function drawLaptop(ctx) {
        ctx.fillStyle = Theme.subtext;
        ctx.fillRect(4, 60, 44, 28);
        ctx.fillStyle = Theme.bg;
        ctx.fillRect(8, 64, 36, 20);
        ctx.fillStyle = Theme.sageBlue;
        ctx.fillRect(12, 68, 20, 4);
        ctx.fillRect(16, 76, 12, 4);
        ctx.fillStyle = Theme.overlay2;
        ctx.fillRect(4, 84, 84, 4);
        ctx.fillStyle = Theme.subtext;
        ctx.fillRect(0, 88, 92, 4);
        ctx.fillStyle = Theme.overlay;
        ctx.fillRect(4, 92, 84, 4);
        ctx.fillStyle = Theme.bgAlt;
        ctx.fillRect(36, 88, 20, 4);
    }
    function drawClock(ctx) {
        ctx.fillStyle = Theme.gold;
        ctx.fillRect(36, 56, 28, 28);
        ctx.fillRect(32, 60, 36, 20);
        ctx.fillStyle = Theme.bg;
        ctx.fillRect(36, 60, 28, 20);
        ctx.fillStyle = Theme.gold;
        ctx.fillRect(44, 52, 12, 4);
        ctx.fillStyle = Theme.textBright;
        ctx.fillRect(48, 62, 4, 10);
        ctx.fillRect(52, 68, 6, 4);
        ctx.fillStyle = root.coat.fur;
        ctx.fillRect(32, 68, 8, 8);
        ctx.fillRect(60, 68, 8, 8);
    }
    function drawHeadphones(ctx) {
        ctx.fillStyle = Theme.sageBlue;
        ctx.fillRect(28, 0, 40, 4);
        ctx.fillRect(20, 4, 8, 4);
        ctx.fillRect(68, 4, 8, 4);
        ctx.fillRect(16, 8, 4, 8);
        ctx.fillRect(76, 8, 4, 8);
        ctx.fillRect(12, 12, 12, 12);
        ctx.fillRect(72, 12, 12, 12);
        ctx.fillStyle = Theme.bgAlt;
        ctx.fillRect(16, 16, 4, 8);
        ctx.fillRect(76, 16, 4, 8);
    }
    onPaint: {
        const ctx=getContext('2d'); ctx.clearRect(0,0,width,height);
        ctx.save();
        if (root.atLaptop) {
            root.drawLaptop(ctx);
            ctx.translate(24, 18 + Math.round(root.laptopOffset));
            ctx.scale(0.75, 0.75);
        }
        const rows=[
            '........................',
            '........................',
            '...ss..............ss...',
            '...scs............scs...',
            '...sccs..........sccs...',
            '...sccssssssssssssccs...',
            '..sccccccccccccccccccs..',
            '..sccccccccccccccccccs..',
            '..sccccccccccccccccccs..',
            '..sccccccccccccccccccs..',
            '..sccccccccccccccccccs..',
            '...sccccccccccccccccs...',
            '....ssssccccccccssss....',
            '......sccccccccccs......',
            '.....sccccccccccccs.....',
            '.....sccccccccccccs.....',
            '.....sccccccccccccs.....',
            '.....sccccccccccccs...ss.',
            '.....sccccccccccccs..scs.',
            '.....sccccccccccccssssc.',
            '.....sccccccccccccccccs.',
            '.....sssssssssssssssss..',
            '......sss......sss......',
            '........................'
        ];
        if (root.purring && root.frame % 2 === 0) {
            rows[17] = '.....sccccccccccccs.....';
            rows[18] = '.....sccccccccccccs...ss';
            rows[19] = '.....sccccccccccccsssscs';
        }
        const colors={s:root.coat.outline,c:root.coat.fur};
        for(let y=0;y<rows.length;y++) for(let x=0;x<rows[y].length;x++) {
            const color=colors[rows[y][x]];
            if(color){ctx.fillStyle=color;ctx.fillRect(x*4,y*4,4,4);}
        }
        if (root.coat.stripes) {
            ctx.fillStyle = root.coat.stripes;
            ctx.fillRect(8*4, 6*4, 2*4, 4);
            ctx.fillRect(11*4, 6*4, 2*4, 2*4);
            ctx.fillRect(14*4, 6*4, 2*4, 4);
            ctx.fillRect(6*4, 14*4, 3*4, 4);
            ctx.fillRect(6*4, 16*4, 2*4, 4);
        }
        ctx.fillStyle=root.coat.eyes;
        if(root.happy || root.reactionText || (root.laptopPose && root.atLaptop && !root.coding) || root.frame===9) {
            ctx.fillRect(6*4,9*4,3*4,4);ctx.fillRect(15*4,9*4,3*4,4);
        } else {
            ctx.fillRect(7*4,8*4,4,2*4);ctx.fillRect(16*4,8*4,4,2*4);
        }
        ctx.fillRect(11*4,10*4,2*4,4);
        ctx.fillStyle=root.coat.cheeks;
        ctx.fillRect(5*4,10*4,2*4,4);ctx.fillRect(17*4,10*4,2*4,4);
        if(root.happy || root.hovered) {
            const heart=['.h.h.','hhhhh','.hhh.','..h..'];
            for(let y=0;y<heart.length;y++)for(let x=0;x<heart[y].length;x++)
                if(heart[y][x]==='h')ctx.fillRect((18+x)*4,y*4,4,4);
        }
        if(root.frame%2===0 && !root.purring){ctx.fillStyle=root.coat.outline;ctx.fillRect(22*4,16*4,4,4);}
        if (root.holdingClock) root.drawClock(ctx);
        if (root.wearingHeadphones) root.drawHeadphones(ctx);
        ctx.restore();
    }
}
