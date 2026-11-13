import qs
import qs.components
import qs.services
import QtQuick
import "../launcher"

Item {
    id: view
    objectName: "tui-overview"
    required property var controller
    required property real progress
    anchors.fill: parent
    visible: controller.shown
    opacity: progress
    focus: controller.open
    Keys.onPressed: event => controller.key(event)
    Canvas {
        width: parent.width; height: parent.height // the strip hides under the Overview
        onPaint: {
            const c=getContext("2d"); c.fillStyle=Theme.deep; c.fillRect(0,0,width,height);
            c.fillStyle=Theme.tuiRule;
            for(let x=8;x<width;x+=16) for(let y=10;y<height;y+=20) c.fillRect(x,y,1,1);
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        MouseArea { anchors.fill: parent; onClicked: if(!view.controller.drag) view.controller.hide() }
    }
    Row {
        id: strip
        visible: !view.controller.searching && view.controller.mode==="here"
        anchors.horizontalCenter: parent.horizontalCenter
        y:72; spacing:24
        readonly property real tileWidth: Math.min(208,(view.width-112-view.controller.spaces.length*spacing)/(view.controller.spaces.length+1))
        Repeater {
            model: view.controller.spaces.concat([-1])
            PanelFrame {
                id: space
                required property int modelData
                objectName: "overview-space-"+modelData
                readonly property bool fresh: modelData===-1
                readonly property bool target: view.controller.drag!==null && view.controller.dropTarget===modelData
                readonly property var windows: fresh?[]:view.controller.everyWindow.filter(w=>w.workspace===modelData&&!w.hidden)
                width: strip.tileWidth; height:104
                title: fresh?"+ new":String(modelData)+(Compositor.nameOf(modelData)?" "+Compositor.nameOf(modelData):"")
                // as the boards: "3 win", "empty"
                detail: target?"move here":fresh?"":view.controller.count(modelData)?view.controller.count(modelData)+" win":"empty"
                active: target || modelData===view.controller.active
                Repeater {
                    model:space.windows
                    Rectangle {
                        required property var modelData
                        x:12+modelData.bounds.x*(space.width-24)/view.width
                        y:18+modelData.bounds.y*66/view.height
                        width:Math.max(8,modelData.bounds.width*(space.width-24)/view.width)
                        height:Math.max(6,modelData.bounds.height*66/view.height)
                        color:Theme.bgAlt;border.width:1;border.color:Theme.tuiBorder
                    }
                }
                Text { visible:space.fresh;anchors.centerIn:parent;text:"+";color:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:24 }
                MouseArea {anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:view.controller.gotoSpace(space.fresh?view.controller.newSpace:space.modelData);Accessible.role:Accessible.Button;Accessible.name:space.fresh?"New workspace":"Workspace "+space.title}
            }
        }
    }
    Text {
        x:56;y:view.controller.searching?84:212;width:parent.width-112
        text:view.controller.searching?`search: ${view.controller.query}  ·  ${view.controller.matches} matches`:view.controller.mode==="all"?"all windows":"this workspace"
        color:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize
    }
    Flickable {
        id: grid
        visible: view.controller.searching || view.controller.mode==="here" && view.controller.hereCards.length>0
        x:56;y:view.controller.searching?140:242;width:parent.width-112;height:Math.max(0,hints.y-y-24)
        clip:true;contentWidth:width;contentHeight:Math.ceil(cards.count/columns)*249
        readonly property int columns:Math.max(1,Math.floor((width+40)/404))
        Repeater {
            id:cards
            model:view.controller.searching?view.controller.found:view.controller.hereCards
            TuiOverviewWindow {
                required property var modelData
                required property int index
                controller:view.controller;card:modelData
                x:index%grid.columns*(width+40);y:10+Math.floor(index/grid.columns)*249
                width:Math.min(364,(grid.width-(grid.columns-1)*40)/grid.columns);height:225
                selected:view.controller.selected?.key===modelData.key
                draggable:!view.controller.searching
                live:view.controller.shown
                onDragMoved: at=>{
                    const s=strip.childAt(at.x-strip.x,at.y-strip.y);
                    view.controller.dropTarget=s&&s.modelData!==undefined&&at.y-strip.y<104?s.modelData:0;
                }
            }
        }
    }
    Flickable {
        id: all
        visible:!view.controller.searching&&view.controller.mode==="all"
        x:56;y:140;width:parent.width-112;height:Math.max(0,hints.y-y-24);clip:true
        contentWidth:Math.max(width,allColumns.width);contentHeight:allColumns.height
        Row {
            id:allColumns;spacing:40
            Repeater {
                model:view.controller.columns
                Column {
                    required property var modelData
                    width:Math.min(364,(all.width-80)/3);spacing:24
                    Text {text:view.controller.title(parent.modelData.id);color:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize}
                    Repeater {
                        model:parent.modelData.cards
                        TuiOverviewWindow {required property var modelData;controller:view.controller;card:modelData;width:parent.width;height:225;selected:view.controller.selected?.key===modelData.key;live:view.controller.shown}
                    }
                }
            }
        }
    }
    Loader {
        active:!view.controller.searching&&view.controller.mode==="here"&&view.controller.hereCards.length===0
        anchors.horizontalCenter:parent.horizontalCenter;y:252
        sourceComponent:PanelFrame {
            objectName:"tui-overview-empty";width:520;height:150;title:view.controller.title(view.controller.active);active:true
            Text {x:24;y:24;text:"This workspace is empty.";color:Theme.text;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize}
            Row {x:24;y:76;spacing:12
                ActionButton {text:"Open launcher";onClicked:{view.controller.hide();view.controller.launcherRequested("all");}}
                ActionButton {text:"Load a preset";onClicked:{view.controller.hide();view.controller.launcherRequested("workspaces");}}
            }
        }
    }
    TuiOverviewWindow {
        visible:view.controller.drag!==null
        controller:view.controller;card:view.controller.drag?.card??({w:null,tabs:[]})
        x:(view.controller.drag?.x??0)-96;y:(view.controller.drag?.y??0)-60;width:192;height:120;selected:true;live:false;z:10
    }
    KeyHints {
        id:hints;x:56;y:parent.height-height-88;width:parent.width-112
        hints:view.controller.drag?[["Drop","on a workspace"],["Esc","cancel"]]:[["Tab",view.controller.mode==="all"?"this workspace":"all windows"],["Enter","focus"],["Ctrl+W","close"],["Ctrl+F","float"],["Ctrl+1…0","workspace"],["Type","search"],["Esc","close"]]
    }
}
