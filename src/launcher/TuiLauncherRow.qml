import qs
import qs.components
import qs.services
import QtQuick

// One model/action path, with flat terminal rows in place of Classic cards and grids.
Item {
    id: root
    objectName: "tui-launcher-row"
    required property var row
    required property var controller
    required property int rowIndex
    property bool selected
    readonly property bool grid: row.kind === "workspaces" || row.kind === "controls"
    readonly property bool question: !!row.question
    readonly property bool level: row.kind === "slider"
    readonly property bool heading: row.kind === "section"
    readonly property bool checked: row.kind === "switch" && row.on()
    readonly property var node: row.node ?? null
    readonly property real value: node ? node.audio?.volume ?? 0 : row.key === "volume" ? Audio.volume : row.key === "mic" ? Audio.micVolume : row.key === "warmth" ? NightLight.temperature : Brightness.value
    readonly property bool muted: node ? node.audio?.muted ?? false : row.key === "volume" ? Audio.muted : row.key === "mic" && Audio.micMuted
    implicitHeight: content.implicitHeight+(row.kind==="settingslink"?16:0)

    function pick(column, menu, at) {
        controller.current = rowIndex;
        controller.column = column;
        if (menu) controller.openMenu(row,column,at);
        else controller.activate(row,column,false);
    }
    function prefix() {
        if(row.emoji)return row.emoji;
        if (row.kind === "window") return row.badge ? "["+row.badge+"]" : "[-]";
        if (row.kind === "switch") return checked ? "[x]" : "[ ]";
        if (row.kind === "presetsave") return "[+]";
        if (row.kind === "app") {
            const kind=(row.app.genericName??"").toLowerCase();
            return "["+(kind.includes("browser")?"W":kind.includes("terminal")?"T":kind.includes("editor")?"E":kind.includes("music")?"M":row.title.slice(0,1).toUpperCase())+"]";
        }
        if (row.kind === "btdevice") return "["+row.title.slice(0,1).toUpperCase()+"]";
        return ["empty","note","aboutline","stat","calc"].includes(row.kind) ? "" : "[>]";
    }
    function detail() {
        if (row.kind === "switch") return row.status();
        if (row.kind === "btdevice") return Bluetooth.status(row.device);
        if (row.kind === "window") return controller.mode === "windows" ? row.subtitle.split(" · ").slice(1).join(" · ") : row.badge?"workspace "+row.badge:"minimised";
        if (row.kind === "app" && LauncherTools.pending[row.app.id]) return "Starting…";
        if (row.kind === "time") return NightLight.timeText(row.minutes());
        return row.subtitle ?? "";
    }
    component Line: Rectangle {
        id: line
        property string prefix
        property string title
        property string detail
        property bool chosen
        property bool marked
        property bool pictograph
        property bool actionable: true
        signal picked(bool menu, point at)
        width: root.width
        height: Theme.tuiLauncherRowHeight
        color: chosen ? Theme.pistachio : hover.containsMouse && actionable ? Theme.bgAlt : "transparent"
        Accessible.role: Accessible.ListItem
        Accessible.name: title+(detail?", "+detail:"")
        Accessible.selected: chosen
        Text {
            objectName:"tui-launcher-prefix"
            x:12;width:32;anchors.verticalCenter:parent.verticalCenter
            text:line.prefix;textFormat:Text.PlainText
            color:line.chosen?Theme.bg:line.marked?Theme.pistachio:Theme.subtext
            font.family:line.pictograph?Theme.fontEmoji:Theme.fontTui;font.pixelSize:line.pictograph?Theme.tuiLineHeight:Theme.tuiTextSize;font.weight:Font.Bold
        }
        Text {
            x:line.prefix?52:12;width:Math.max(0,parent.width-x-meta.width-24)
            anchors.verticalCenter:parent.verticalCenter;text:line.title;textFormat:Text.PlainText;elide:Text.ElideRight
            color:line.chosen?Theme.bg:!line.enabled?Theme.subtext:Theme.text;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize;font.weight:line.chosen?Font.Bold:Font.Medium
            TipHover {}
        }
        Text {
            id:meta;anchors.right:parent.right;anchors.rightMargin:12;anchors.verticalCenter:parent.verticalCenter
            width:Math.min(implicitWidth,parent.width*0.48);text:line.detail;textFormat:Text.PlainText;elide:Text.ElideRight
            color:line.chosen?Theme.bg:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize
            TipHover {}
        }
        MouseArea {
            id:hover;anchors.fill:parent;hoverEnabled:true;enabled:line.actionable;acceptedButtons:Qt.LeftButton|Qt.RightButton;cursorShape:Qt.PointingHandCursor
            onClicked:event=>line.picked(event.button===Qt.RightButton,mapToItem(null,event.x,event.y))
        }
    }
    Column {
        id:content;width:parent.width;y:root.row.kind==="settingslink"?16:0
        Item {
            visible:root.heading||(root.row.key==="volume"&&root.controller.mode==="system");width:parent.width;height:Theme.tuiLauncherRowHeight
            Text {objectName:"tui-launcher-heading";x:12;anchors.bottom:parent.bottom;anchors.bottomMargin:4;text:root.heading?(root.row.title??"").toLowerCase():"quick controls";color:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize}
        }
        Text {
            objectName:"tui-launcher-note"
            visible:root.row.kind==="note";x:12;width:parent.width-24;topPadding:2;bottomPadding:10
            text:root.row.title??"";textFormat:Text.PlainText;wrapMode:Text.Wrap
            color:Theme.text;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize
            lineHeight:Theme.tuiLineHeight;lineHeightMode:Text.FixedHeight
        }
        Line {
            visible:!root.grid&&!root.heading&&!root.question&&!root.level&&root.row.kind!=="note"
            prefix:root.prefix();chosen:root.selected;marked:root.checked;pictograph:!!root.row.emoji;enabled:!root.row.off
            title:root.row.kind==="window"&&root.controller.mode==="windows"?(Apps.nameFor(root.row.subtitle.split(" · ")[0]).slice(0,8).padEnd(8," ")+" "+root.row.title):root.row.kind==="cheat"?(root.row.keys.join(" ")+"  "+root.row.title):["switch","settingslink","btlink"].includes(root.row.kind)?root.row.title.toLowerCase():root.row.title??""
            detail:root.detail();actionable:root.controller.selectable(root.rowIndex)
            onPicked:(menu,at)=>root.pick(0,menu,at)
        }
        Repeater {
            model:root.grid?(root.row.cards??root.controller.controls):[]
            Line {
                required property var modelData
                required property int index
                chosen:root.selected&&root.controller.column===index
                prefix:root.row.cards?"["+modelData.id+"]":"[>]"
                title:root.row.cards?(Compositor.nameOf(modelData.id)||"unnamed"):modelData.label.toLowerCase()
                detail:root.row.cards?(modelData.count?modelData.count+" window"+(modelData.count===1?"":"s")+(Compositor.isTabbed(modelData.id)?" · tabbed":""):"empty"):modelData.value
                marked:root.row.cards?modelData.active:false
                onPicked:(menu,at)=>root.pick(index,menu,at)
            }
        }
        Rectangle {
            visible:root.level;width:parent.width;height:Theme.tuiLauncherRowHeight
            color:root.selected?Theme.pistachio:"transparent"
            MouseArea {anchors.fill:parent;onClicked:{root.controller.current=root.rowIndex;root.controller.activate(root.row,0,false);}}
            Text {x:12;width:80;anchors.verticalCenter:parent.verticalCenter;text:(root.row.title??"").toLowerCase();textFormat:Text.PlainText;elide:Text.ElideRight;color:root.selected?Theme.bg:Theme.text;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize}
            Slider {
                id:meter;x:100;width:Math.min(Theme.tuiLauncherMeterWidth,parent.width-x-72);height:parent.height
                from:root.row.key==="warmth"?2500:0;to:root.row.key==="warmth"?6500:1;value:root.value;fillColor:root.selected?Theme.bg:Theme.pistachio;bracketColor:root.selected?Theme.bg:Theme.subtext
                Accessible.name:root.row.title??""
                onMoved:{root.controller.current=root.rowIndex;if(root.node)Audio.setStreamVolume(root.node,value);else if(root.row.key==="volume")Audio.setVolume(value);else if(root.row.key==="mic")Audio.setMicVolume(value);else if(root.row.key==="warmth")NightLight.setTemperature(value);else Brightness.set(value);root.controller.focusField();}
            }
            Text {anchors.right:parent.right;anchors.rightMargin:12;anchors.verticalCenter:parent.verticalCenter;text:root.muted?"muted":root.row.key==="warmth"?Math.round(meter.shownValue)+"K":Math.round(meter.shownValue*100)+"%";color:root.selected?Theme.bg:Theme.text;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize}
        }
        Column {
            visible:root.question;width:parent.width;spacing:8
            Text {x:12;width:parent.width-24;text:root.row.question?.title??"";textFormat:Text.PlainText;wrapMode:Text.Wrap;color:Theme.textBright;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize;font.weight:Font.Bold}
            Text {x:12;width:parent.width-24;text:root.row.question?.text??"";textFormat:Text.PlainText;wrapMode:Text.Wrap;color:root.row.question?.error?Theme.terracotta:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize}
            Text {x:12;visible:text!=="";text:root.row.question?.code??"";color:Theme.textBright;font.family:Theme.fontTui;font.pixelSize:Theme.tuiCodeSize}
            Flow {
                x:12;width:parent.width-24;spacing:8
                Repeater {
                    model:root.row.question?.choices??[]
                    ActionButton {required property string modelData;required property int index;text:modelData;primary:root.selected&&root.controller.column===index;enabled:!root.row.question?.input||index===0||root.controller.inputValid;onClicked:root.pick(index,false,Qt.point(0,0))}
                }
            }
            Item {width:1;height:8}
        }
    }
}
