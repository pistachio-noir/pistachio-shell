import qs
import qs.components
import qs.services
import QtQuick

// The shared thumbnail still owns capture, aspect ratio and grouped tabs.
PanelFrame {
    id: root
    required property var controller
    required property var card
    property bool selected
    property bool live: true
    property bool draggable
    signal dragMoved(point at)
    title: controller.label(card.w)
    detail: card.tabs.length > 1 ? `${card.tabs.length} tabs` : ""
    active: selected
    opacity: card.match === false ? 0.35 : controller.drag?.card.key === card.key ? 0.3 : 1
    OverviewThumb {
        anchors.fill: parent; anchors.margins: 12
        w: root.card.w; tabs: root.card.tabs; radius: 0
        atTop: true; live: root.live; closable: false
    }
    MouseArea {
        id: mouse
        objectName: "overview-window-pointer"
        property point start
        property bool moved
        anchors.fill: parent
        enabled: root.card.match !== false
        hoverEnabled: true
        preventStealing: root.draggable
        cursorShape: root.controller.drag ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        Accessible.role: Accessible.Button
        Accessible.name: root.title
        onPressed: e => { start = Qt.point(e.x,e.y); moved = false; }
        onPositionChanged: e => {
            const at = mapToItem(root.controller.contentItem,e.x,e.y);
            if (!pressed) {
                const old = root.controller.pointer;
                if (old.x >= 0 && Math.hypot(at.x-old.x,at.y-old.y)>0.5) {
                    const i = root.controller.list.findIndex(c=>c.key===root.card.key);
                    if(i>=0) root.controller.current=i;
                }
                root.controller.pointer=at;
            }
            if(pressed && root.draggable && Math.hypot(e.x-start.x,e.y-start.y)>8) moved=true;
            if(moved && pressed) {
                root.controller.drag={card:root.card,x:at.x,y:at.y};
                root.dragMoved(at);
            }
        }
        onReleased: if(moved) root.controller.finishDrag()
        onCanceled: { root.controller.drag=null; root.controller.dropTarget=0; moved=false; }
        onClicked: if(!moved) root.controller.activate(root.card)
    }
}
