import qs
import qs.components
import qs.panels
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland // the layer and its keyboard (Wayland protocols, not a compositor module)
import QtQuick
import QtQuick.Shapes
import "../panels/desktopGrid.js" as Grid

// The widget studio (owner's request, 20 November 2026; laid out by Claude, no board; spec
// docs/superpowers/specs/2026-11-20-desktop-widgets-design.md): the desktop over everything, so it
// works over windows and in TUI. The wallpaper dimmed, the grid's dots, the icons' cells as faint
// outlines, and the widgets with a dashed frame and a ✕. Drag one: a dashed outline shows where it
// snaps (terracotta where it can't go; dropped there, it goes back). The pill at the bottom adds the
// blocks not placed and has Done; Esc does the same. Every change is saved as it happens.
PanelWindow {
    id: root

    readonly property real cellWidth: DesktopWidgets.cellWidth
    readonly property real cellHeight: DesktopWidgets.cellHeight
    readonly property var names: ({ clock: "Clock", weather: "Weather", stats: "CPU/RAM", media: "Now playing", timers: "Timers", system: "Disk & GPU" })

    visible: reveal.shown
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "pistachio-widget-studio"
    WlrLayershell.keyboardFocus: DesktopWidgets.arranging ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Reveal {
        id: reveal
        open: DesktopWidgets.arranging
    }

    IpcHandler {
        target: "widgets"
        function arrange(): void { DesktopWidgets.arrange(); }
        function done(): void { DesktopWidgets.done(); }
        function status(): string { return JSON.stringify({ enabled: DesktopWidgets.enabled, arranging: DesktopWidgets.arranging, shown: DesktopWidgets.shown, columns: DesktopWidgets.columns, rows: DesktopWidgets.rows, layout: DesktopWidgets.layout }); }
    }

    Item {
        id: stage
        objectName: "studio-stage"
        anchors.fill: parent
        opacity: reveal.progress
        focus: true
        Keys.onEscapePressed: DesktopWidgets.done()

        WallpaperView {
            anchors.fill: parent
            path: DesktopWidgets.arranging || reveal.shown ? Wallpapers.current : ""
            loadSize: Qt.size(root.width, root.height)
        }
        Rectangle {
            anchors.fill: parent
            color: Theme.bg
            opacity: 0.55
        }

        // the grid: a dot at each cell's corner
        Repeater {
            model: (DesktopWidgets.columns + 1) * (DesktopWidgets.rows + 1)
            Rectangle {
                required property int index
                readonly property int col: index % (DesktopWidgets.columns + 1)
                readonly property int row: Math.floor(index / (DesktopWidgets.columns + 1))
                // every other dot (an icon cell's corner) a little bigger
                readonly property bool major: col % 2 === 0 && row % 2 === 0
                x: DesktopWidgets.xOf(col) - width / 2
                y: DesktopWidgets.yOf(row) - height / 2
                width: major ? 3 : 2
                height: width
                radius: Theme.tui ? 0 : width / 2
                color: major ? Theme.overlay2 : Theme.overlay
            }
        }

        // the centre cross (owner's request, 20 November 2026): the grid's middle; a line brightens while
        // the dragged widget's middle is on it
        Shape {
            id: cross
            readonly property real centreX: target.index >= 0 ? DesktopWidgets.xOf(target.col) + DesktopWidgets.sizes[target.kind][0] * root.cellWidth / 2 : -1
            readonly property real centreY: target.index >= 0 ? DesktopWidgets.yOf(target.row) + DesktopWidgets.sizes[target.kind][1] * root.cellHeight / 2 : -1
            readonly property bool onX: Math.abs(centreX - DesktopWidgets.middleX) < 0.5
            readonly property bool onY: Math.abs(centreY - DesktopWidgets.middleY) < 0.5
            objectName: "studio-cross"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: cross.onX ? Theme.textBright : Theme.overlay2
                strokeWidth: cross.onX ? 2 : 1
                strokeStyle: ShapePath.DashLine
                dashPattern: [6, 6]
                fillColor: "transparent"
                startX: DesktopWidgets.middleX; startY: DesktopWidgets.top
                PathLine { x: DesktopWidgets.middleX; y: DesktopWidgets.yOf(DesktopWidgets.rows) }
            }
            ShapePath {
                strokeColor: cross.onY ? Theme.textBright : Theme.overlay2
                strokeWidth: cross.onY ? 2 : 1
                strokeStyle: ShapePath.DashLine
                dashPattern: [6, 6]
                fillColor: "transparent"
                startX: DesktopWidgets.margin; startY: DesktopWidgets.middleY
                PathLine { x: DesktopWidgets.xOf(DesktopWidgets.columns); y: DesktopWidgets.middleY }
            }
        }

        // where the desktop icons sit (Classic, icons on), around the widgets
        Repeater {
            model: !Theme.tui && Desktop.enabled ? Desktop.items.map(i => i.name) : []
            DashedFrame {
                required property string modelData
                readonly property var cell: Grid.iconLayout(Desktop.items.map(i => i.name), Desktop.positions, DesktopWidgets.columns, DesktopWidgets.rows, DesktopWidgets.cells)[modelData] ?? [0, 0]
                x: DesktopWidgets.margin + cell[0] * 104 + 24
                y: DesktopWidgets.margin + cell[1] * 104 + 16
                width: 56
                height: 56
                radius: Theme.tui ? 0 : 14
                color: Theme.overlay2
            }
        }

        // the drop target while a widget is dragged
        DashedFrame {
            id: target
            property int index: -1
            property string kind
            property int col
            property int row
            readonly property bool ok: index >= 0 && DesktopWidgets.fits(index, kind, col, row)
            visible: index >= 0
            x: DesktopWidgets.xOf(col) + 6
            y: DesktopWidgets.yOf(row) + 6
            width: kind ? DesktopWidgets.sizes[kind][0] * root.cellWidth - 12 : 0
            height: kind ? DesktopWidgets.sizes[kind][1] * root.cellHeight - 12 : 0
            radius: Theme.tileRadius
            lineWidth: 2
            color: ok ? Theme.subtext : Theme.terracotta
        }

        Repeater {
            model: ScriptModel {
                values: DesktopWidgets.layout
                objectProp: "kind"
            }

            Item {
                id: block
                objectName: "studio-" + kind
                required property var modelData
                required property int index
                readonly property string kind: modelData.kind
                readonly property var at: DesktopWidgets.layout.find(w => w.kind === kind) ?? modelData
                readonly property int place: DesktopWidgets.layout.findIndex(w => w.kind === kind)
                property bool dragging
                property point grabbed // where the pointer took it, inside the block

                x: DesktopWidgets.xOf(at.col) + 6
                y: DesktopWidgets.yOf(at.row) + 6
                z: dragging ? 2 : 1
                width: DesktopWidgets.sizes[kind][0] * root.cellWidth - 12
                height: DesktopWidgets.sizes[kind][1] * root.cellHeight - 12

                Behavior on x { enabled: !block.dragging; NumberAnimation { duration: Theme.motionDuration; easing.type: Theme.easing } }
                Behavior on y { enabled: !block.dragging; NumberAnimation { duration: Theme.motionDuration; easing.type: Theme.easing } }

                DesktopWidget {
                    anchors.fill: parent
                    kind: block.kind
                    live: DesktopWidgets.arranging
                    opacity: block.dragging ? 0.85 : 1
                }

                DashedFrame {
                    anchors.fill: parent
                    anchors.margins: -5
                    radius: Theme.tui ? 0 : Theme.tileRadius + 5
                    color: drag.containsMouse || block.dragging ? Theme.text : Theme.subtext
                }

                MouseArea {
                    id: drag
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: block.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    Accessible.role: Accessible.Button
                    Accessible.name: `Move ${root.names[block.kind]}`
                    onPressed: mouse => {
                        block.grabbed = Qt.point(mouse.x, mouse.y);
                        block.dragging = true;
                        target.kind = block.kind;
                        target.index = block.place;
                        target.col = block.at.col;
                        target.row = block.at.row;
                    }
                    onPositionChanged: mouse => {
                        if (!block.dragging)
                            return;
                        const p = mapToItem(stage, mouse.x, mouse.y);
                        block.x = p.x - block.grabbed.x;
                        block.y = p.y - block.grabbed.y;
                        // the cell under the block's top-left corner, rounded to the nearest
                        target.col = Math.round((block.x - 6 - DesktopWidgets.margin) / root.cellWidth);
                        target.row = Math.round((block.y - 6 - DesktopWidgets.top) / root.cellHeight);
                    }
                    onReleased: block.drop()
                    onCanceled: block.drop()
                }

                function drop() {
                    if (!dragging)
                        return;
                    const ok = target.ok;
                    const col = target.col, row = target.row;
                    target.index = -1;
                    dragging = false;
                    if (ok)
                        DesktopWidgets.move(place, col, row);
                    // back onto its place (the new one, or where it was)
                    x = Qt.binding(() => DesktopWidgets.xOf(at.col) + 6);
                    y = Qt.binding(() => DesktopWidgets.yOf(at.row) + 6);
                }

                // ✕ takes the block off the desktop (+ in the pill brings it back)
                Rectangle {
                    x: parent.width - width / 2 - 6
                    y: -height / 2 + 6
                    width: 26
                    height: 26
                    radius: Theme.tui ? 0 : 13
                    visible: !block.dragging
                    color: remove.containsMouse ? Theme.overlay2 : Theme.overlay
                    border.width: 1
                    border.color: Theme.overlay2
                    Accessible.role: Accessible.Button
                    Accessible.name: `Remove ${root.names[block.kind]}`
                    objectName: "remove-" + block.kind

                    Icon {
                        anchors.centerIn: parent
                        size: 13
                        paths: Icons.close
                        color: remove.containsMouse ? Theme.textBright : Theme.subtext
                    }
                    MouseArea {
                        id: remove
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: DesktopWidgets.remove(block.place)
                    }
                }
            }
        }

        // the pill: add what isn't placed, and Done
        Rectangle {
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.barMargin
            width: tools.implicitWidth + 16
            height: Theme.chipHeight + 16
            radius: Theme.tui ? 0 : height / 2
            color: Theme.bgAlt
            border.width: 1
            border.color: Theme.overlay2
            transform: Translate { y: 8 * (1 - reveal.progress) }

            Row {
                id: tools
                anchors.centerIn: parent
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: 10
                    rightPadding: 4
                    text: Theme.tui ? "drag to move · esc done" : "Drag to move · Esc when done"
                    color: Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.tui ? Theme.tuiTextSize : 13
                    font.weight: Font.DemiBold
                }

                Repeater {
                    model: DesktopWidgets.kinds.filter(k => !DesktopWidgets.has(k))
                    ActionButton {
                        required property string modelData
                        objectName: "add-" + modelData
                        readonly property bool room: DesktopWidgets.freeSpot(modelData) !== null
                        anchors.verticalCenter: parent?.verticalCenter
                        height: Theme.chipHeight
                        text: room ? `+ ${root.names[modelData]}` : `No room for ${root.names[modelData]}`
                        enabled: room
                        opacity: room ? 1 : 0.5
                        onClicked: DesktopWidgets.add(modelData)
                    }
                }

                ActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    height: Theme.chipHeight
                    text: "Done"
                    primary: true
                    onClicked: DesktopWidgets.done()
                }
            }
        }
    }
}
