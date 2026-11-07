import qs
import qs.services
import QtQuick

// One dot per workspace; the active one stretches into a pistachio capsule.
Row {
    id: root

    // Always 1–5, plus any higher workspace that exists.
    readonly property int count: Math.max(5, ...Compositor.workspaces.map(w => w.id))
    // the dot under the pointer, and its line for the bar's tooltip: the apps on that workspace
    property Item hoveredSlot: null
    readonly property var tooltip: {
        if (!hoveredSlot)
            return [];
        const apps = [...new Set(Compositor.windows.filter(w => w.workspace === hoveredSlot.wsId).map(w => Apps.nameFor(w.appId)))];
        const name = Compositor.nameOf(hoveredSlot.wsId);
        return [[`Workspace ${hoveredSlot.wsId}${name ? ` · ${name}` : ""}`, apps.length ? apps.join(", ") : "empty"]];
    }

    // scroll over the dots for the next or previous workspace (owner's pick, 3 November 2026); a
    // touchpad's small steps add up to a notch. Each dot's MouseArea takes the wheel: a WheelHandler
    // on the row never got it (owner, 5 November).
    property real scrolled

    function scroll(dy: real) {
        scrolled += dy;
        if (Math.abs(scrolled) < 120)
            return;
        const next = Compositor.activeWorkspace + (scrolled < 0 ? 1 : -1);
        scrolled = 0;
        if (next >= 1 && next <= count)
            Compositor.goto(next);
    }

    leftPadding: 10
    rightPadding: 6

    Repeater {
        model: root.count

        Item {
            id: slot

            required property int index
            readonly property int wsId: index + 1
            readonly property var ws: Compositor.workspaces.find(w => w.id === wsId)
            readonly property bool active: ws?.active ?? false
            readonly property bool urgent: ws?.urgent ?? false
            readonly property bool occupied: ws?.occupied ?? false

            width: active ? 34 : 20
            height: Theme.chipHeight
            Accessible.role: Accessible.Button
            Accessible.name: `Workspace ${wsId}` + (active ? ", active" : urgent ? ", urgent window" : occupied ? "" : ", empty")

            Behavior on width {
                NumberAnimation {
                    duration: Theme.motionDuration
                    easing.type: Theme.easing
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: slot.active ? 26 : 8
                height: 8
                radius: 4
                // empty workspaces are a muted ring
                color: slot.active ? Theme.pistachio : slot.urgent ? Theme.terracotta : slot.occupied ? Theme.subtext : "transparent"
                border.width: slot.active || slot.urgent || slot.occupied ? 0 : 1.5
                border.color: Theme.muted

                Behavior on width {
                    NumberAnimation {
                        duration: Theme.motionDuration
                        easing.type: Theme.easing
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        duration: Theme.motionDuration
                        easing.type: Theme.easing
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Compositor.goto(slot.wsId)
                onWheel: wheel => root.scroll(wheel.angleDelta.y)
                onContainsMouseChanged: {
                    if (containsMouse)
                        root.hoveredSlot = slot;
                    else if (root.hoveredSlot === slot)
                        root.hoveredSlot = null;
                }
            }
        }
    }
}
