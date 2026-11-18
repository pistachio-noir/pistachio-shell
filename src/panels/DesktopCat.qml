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
    property string reactionText
    property int frame
    property int idleLine
    readonly property bool animating: tick.running
    width: 96; height: 96
    visible: active
    function pet() {
        if (!interactive || !visible) return;
        happy = true;
        happyTimer.restart();
    }
    function react(message: string) {
        if (!visible) return;
        reactionText = message;
        reactionTimer.restart();
    }
    function sayIdle() {
        if (!visible || reactionText) return;
        const lines = ["Meow!", "hii!!", "Nice to see you.", "Time for a stretch?"];
        react(lines[idleLine % lines.length]);
        idleLine++;
    }
    function clearReaction() { reactionText = ""; reactionTimer.stop(); }
    onVisibleChanged: if (!visible) { happy=false; hovered=false; happyTimer.stop(); clearReaction(); }
    onReactionTextChanged: requestPaint()
    Connections { target:Clocks; function onRingingChanged() { if (Clocks.ringing) root.react(Clocks.ringing.kind === "alarm" ? "Alarm time!" : "Timer's up!"); } }
    Connections { target:FocusMode; function onPhaseFinished(message) { root.react(message); } }
    Timer { interval:300000; running:root.visible; repeat:true; onTriggered:root.sayIdle() }
    Timer { id:reactionTimer; interval:4000; onTriggered:root.clearReaction() }
    Rectangle {
        objectName: "cat-reaction"
        x: Math.min(0, 32 - width); y: -height - 6
        width: reactionLabel.implicitWidth + 24; height: reactionLabel.implicitHeight + 18
        radius: Theme.tileRadius; color: Theme.bgAlt; border.width: 1; border.color: Theme.overlay2
        opacity: root.reactionText ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.motionDuration; easing.type: Theme.easing } }
        Text { id:reactionLabel; anchors.centerIn:parent; text:root.reactionText; textFormat:Text.PlainText; color:Theme.text; font.family:Theme.fontUi; font.pixelSize:13; font.weight:Font.Bold }
    }
    onFrameChanged: requestPaint()
    onHoveredChanged: requestPaint()
    onHappyChanged: requestPaint()
    Connections { target:Theme; function onNoirChanged(){root.requestPaint();} }
    Timer { id:tick; running:root.visible; repeat:true; interval:650; onTriggered:root.frame=(root.frame+1)%10 }
    Timer { id:happyTimer; interval:1800; onTriggered:root.happy=false }
    onPaint: {
        const ctx=getContext('2d'); ctx.clearRect(0,0,width,height);
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
        const colors={s:Theme.catOutline,c:Theme.catFur};
        for(let y=0;y<rows.length;y++) for(let x=0;x<rows[y].length;x++) {
            const color=colors[rows[y][x]];
            if(color){ctx.fillStyle=color;ctx.fillRect(x*4,y*4,4,4);}
        }
        ctx.fillStyle=Theme.catEyes;
        if(root.happy || root.reactionText || root.frame===9) {
            ctx.fillRect(6*4,9*4,3*4,4);ctx.fillRect(15*4,9*4,3*4,4);
        } else {
            ctx.fillRect(7*4,8*4,4,2*4);ctx.fillRect(16*4,8*4,4,2*4);
        }
        ctx.fillRect(11*4,10*4,2*4,4);
        ctx.fillStyle=Theme.catCheeks;
        ctx.fillRect(5*4,10*4,2*4,4);ctx.fillRect(17*4,10*4,2*4,4);
        if(root.happy || root.hovered) {
            const heart=['.h.h.','hhhhh','.hhh.','..h..'];
            for(let y=0;y<heart.length;y++)for(let x=0;x<heart[y].length;x++)
                if(heart[y][x]==='h')ctx.fillRect((18+x)*4,y*4,4,4);
        }
        if(root.frame%2===0){ctx.fillStyle=Theme.catOutline;ctx.fillRect(22*4,16*4,4,4);}
    }
}
