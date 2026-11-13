import qs
import qs.components
import qs.launcher
import qs.services
import QtQuick

Item {
    id: view
    objectName: "tui-window-switcher"
    required property var controller
    required property real progress
    anchors.fill: parent
    focus: true
    Component.onCompleted: forceActiveFocus()
    Keys.onPressed: event=>controller.key(event)
    Keys.onReleased: event=>{if(event.key===Qt.Key_Alt)controller.commit();}
    PanelFrame {
        id:panel
        x:Math.round((parent.width-width)/2);y:Theme.tuiSwitcherTop
        width:Theme.tuiSwitcherWidth;height:header.height+list.height+footer.height+16
        title:view.controller.tabsOnly?"tabs":"windows"
        detail:(view.controller.current+1)+" of "+view.controller.windows.length
        color:Theme.bg;opacity:view.progress
        Accessible.role:Accessible.List;Accessible.name:"Open windows"
        MouseArea {anchors.fill:parent}
        Item {
            id:header;width:parent.width;height:50
            Text {x:12;y:20;text:"ws   app      title";color:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize}
            Rectangle {x:12;anchors.bottom:parent.bottom;width:parent.width-40;height:1;color:Theme.tuiBorder}
        }
        ListView {
            id:list;objectName:"tui-switcher-list"
            y:header.height+8;width:parent.width;height:Math.min(contentHeight,340,Math.max(32,view.height-panel.y-header.height-footer.height-40))
            clip:true;boundsBehavior:Flickable.StopAtBounds
            model:view.controller.windows
            currentIndex:view.controller.current
            onCurrentIndexChanged:positionViewAtIndex(currentIndex,ListView.Contain)
            delegate:Rectangle {
                required property var modelData
                required property int index
                readonly property bool selected:view.controller.current===index
                width:list.width-8;height:Theme.tuiLauncherRowHeight
                color:selected?Theme.pistachio:"transparent"
                Accessible.role:Accessible.ListItem;Accessible.name:modelData.title+", workspace "+modelData.workspace;Accessible.selected:selected
                Text {x:12;width:32;anchors.verticalCenter:parent.verticalCenter;text:"["+parent.modelData.workspace+"]";color:parent.selected?Theme.bg:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize}
                Text {x:52;width:64;anchors.verticalCenter:parent.verticalCenter;text:Apps.nameFor(parent.modelData.appId);textFormat:Text.PlainText;elide:Text.ElideRight;color:parent.selected?Theme.bg:Theme.textBright;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize;font.weight:Font.Bold}
                Text {x:124;width:parent.width-x-12;anchors.verticalCenter:parent.verticalCenter;text:parent.modelData.title;textFormat:Text.PlainText;elide:Text.ElideRight;color:parent.selected?Theme.bg:parent.modelData.urgent?Theme.terracotta:Theme.text;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize;TipHover {}}
                MouseArea {
                    anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor
                    onPositionChanged:event=>{view.controller.pointer(mapToItem(null,event.x,event.y));if(view.controller.pointerMoved)view.controller.current=index;}
                    onClicked:{view.controller.current=index;view.controller.commit();}
                }
            }
        }
        Rectangle {
            visible:list.contentHeight>list.height;x:parent.width-9;y:list.y;width:8;height:list.height;color:Theme.overlay
            Rectangle {width:parent.width;height:Math.max(24,parent.height*list.height/list.contentHeight);y:(parent.height-height)*Math.max(0,Math.min(1,(list.contentY-list.originY)/(list.contentHeight-list.height)));color:Theme.subtext}
        }
        KeyHints {
            id:footer
            y:list.y+list.height+8;width:parent.width
            hints:[[view.controller.tabsOnly?"`":"Tab","next"],["Q","close"],["Enter","focus"],["Esc","cancel"]]
        }
    }
}
