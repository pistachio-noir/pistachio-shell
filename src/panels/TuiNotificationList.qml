import qs
import qs.components
import qs.services
import Quickshell
import QtQuick
import "../launcher"

PanelFrame {
    id: root
    objectName:"tui-notifications"
    required property var controller
    property alias view: list
    readonly property bool combined: controller.calendarShown
    readonly property int header: combined?20:56
    title:"notifications"
    detail:String(Showoff.active?0:Notifs.notifications.length)
    active:!combined
    implicitHeight:header+Math.min(448,Math.max(80,list.contentHeight))+40
    function activateCurrent() {
        const n=controller.ordered[list.currentIndex];
        if(n) Notifs.invokeDefault(n);
    }
    function key(event) {
        if(event.key===Qt.Key_Up||event.key===Qt.Key_Down) {
            const step=event.key===Qt.Key_Down?1:-1;
            let i=list.currentIndex;
            for(let n=0;n<list.count;n++) {
                i=(i+step+list.count)%list.count;
                const item=controller.ordered[i],members=controller.groups.by[item?.appName??""]??[];
                if(members.length<2||members[0]===item||controller.openGroups[item?.appName??""]) break;
            }
            list.currentIndex=i;list.positionViewAtIndex(i,ListView.Contain);
        } else if(event.key===Qt.Key_Return||event.key===Qt.Key_Enter) activateCurrent();
        else return false;
        event.accepted=true;return true;
    }
    TuiControlRow {objectName:"notifications-dnd";activeFocusOnTab:true;Keys.onSpacePressed:event=>{Notifs.setDnd(!Notifs.dnd);event.accepted=true;}onPicked:forceActiveFocus();visible:!root.combined;x:12;y:12;width:parent.width-24;height:32;kind:"toggle";text:"do not disturb";checked:Notifs.dnd;onActivated:Notifs.setDnd(!Notifs.dnd)}
    Text {visible:list.count===0;anchors.centerIn:parent;text:"inbox zero";color:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize}
    ListView {
        id:list
        x:12;y:root.header;width:parent.width-24;height:parent.height-y-40
        clip:true;spacing:0;currentIndex:0
        model:ScriptModel {values:Showoff.active?[]:root.controller.ordered;objectProp:""}
        add:Transition {NumberAnimation {property:"opacity";from:0;to:1;duration:Theme.motionDuration;easing.type:Theme.easing}}
        remove:Transition {NumberAnimation {property:"opacity";to:0;duration:Theme.motionDuration;easing.type:Theme.easing}}
        delegate:Item {
            id:entry
            required property var modelData
            required property int index
            readonly property var n:modelData??({})
            readonly property string app:n.appName??""
            readonly property var members:root.controller.groups.by[app]??[]
            readonly property bool lead:members.length>1&&members[0]===modelData
            readonly property bool folded:members.length>1&&!lead&&!root.controller.openGroups[app]
            property bool ruling
            readonly property var actions:ruling?Notifs.ruleChoices(app):n.saved?[]:(n.actions??[]).filter(a=>a.identifier!=="default")
            readonly property bool expanded:ruling||hover.hovered&&actions.length>0
            width:list.width;height:folded?0:(lead?24:0)+card.height+8;visible:!folded
            Row {
                visible:entry.lead;width:parent.width;height:24;spacing:8
                Text {width:parent.width-152;text:`${entry.app} (${entry.members.length})`;elide:Text.ElideRight;color:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:12}
                ActionButton {width:88;height:20;horizontalPadding:4;text:root.controller.openGroups[entry.app]?"fold":"show all";onClicked:root.controller.toggleGroup(entry.app)}
                ActionButton {width:48;height:20;horizontalPadding:4;text:"clear";onClicked:Notifs.clearApp(entry.app)}
            }
            Rectangle {
                id:card
                y:entry.lead?24:0;width:parent.width
                height:Math.max(56,32+message.implicitHeight)+(preview.visible?preview.height+8:0)+(entry.expanded?buttons.height+8:0)
                color:entry.index===list.currentIndex||root.controller.spotlight===entry.modelData?Theme.tuiHover:Theme.deep
                border.width:root.controller.spotlight===entry.modelData?1:0;border.color:Theme.tuiBorder
                HoverHandler {id:hover;onHoveredChanged:if(!hovered)entry.ruling=false}
                MouseArea {
                    anchors.fill:parent;acceptedButtons:Qt.LeftButton|Qt.RightButton;cursorShape:Qt.PointingHandCursor
                    onClicked:e=>{list.currentIndex=entry.index;if(e.button===Qt.RightButton)entry.ruling=!entry.ruling;else if(entry.modelData)Notifs.invokeDefault(entry.modelData);}
                    Accessible.role:Accessible.Button;Accessible.name:(entry.n.summary??"")+" "+(entry.n.body??"")
                }
                Text {x:10;y:6;width:parent.width-76;text:entry.app;elide:Text.ElideRight;color:Theme.text;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize;font.bold:true}
                Text {anchors.right:close.left;anchors.rightMargin:6;y:6;text:root.controller.age(Notifs.received(entry.n));color:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:11}
                Rectangle {visible:Notifs.received(entry.n)>Notifs.seenBefore;x:3;y:10;width:3;height:3;color:Theme.pistachio}
                Text {
                    id:message;x:10;y:24;width:parent.width-44
                    text:[entry.n.summary,entry.n.body].filter(s=>s).join(" · ");textFormat:Text.PlainText
                    wrapMode:Text.Wrap;color:Notifs.isCritical(entry.n)?Theme.terracotta:Theme.text;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize
                }
                ActionButton {id:close;anchors.right:parent.right;y:18;width:28;height:28;horizontalPadding:0;base:"transparent";text:"×";onClicked:if(entry.modelData)Notifs.dismiss(entry.modelData);Accessible.name:"Dismiss notification"}
                NotificationPreview {id:preview;x:10;y:message.y+message.height+8;width:parent.width-20;notification:entry.modelData}
                Flow {
                    id:buttons;visible:entry.expanded;x:10;y:Math.max(56,message.y+message.height+8)+(preview.visible?preview.height+8:0);width:parent.width-20;spacing:4
                    Repeater {model:entry.actions
                        ActionButton {required property var modelData;maximumWidth:buttons.width;height:28;primary:modelData.active??false;text:modelData.text??"Action";onClicked:{if(entry.modelData)modelData.invoke();entry.ruling=false;}}
                    }
                }
            }
        }
    }
    KeyHints {anchors.bottom:parent.bottom;hints:[["C","clear all"],["Enter","open"],["Esc","close"]];clickableKeys:({C:true,Enter:true,Esc:true});onActivated:k=>{if(k==="C")Notifs.clearAll();else if(k==="Enter")root.activateCurrent();else root.controller.open=false;}}
}
