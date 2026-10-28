import qs
import qs.services
import Quickshell
import QtQuick

// The tray pill: apps' tray icons, next to the bar while any app has one. The bar positions it and
// hides and reveals it along with itself. Left click activates an icon, middle click runs its
// secondary action, right click (or any click on a menu-only icon) opens the app's menu, and
// scrolling goes to the app.
PanelWindow {
    id: root

    property bool shown: true // the bar's state
    property bool instant // the bar's: a change of `shown` jumps instead of easing
    readonly property bool hovered: hover.hovered
    readonly property bool menuOpen: menu.open // the bar stays up meanwhile
    property real menuCentre // x of the icon whose menu is open, in this window
    // the icon under the pointer, for the bar's tooltip: the app's name, centred on it on screen
    property Item tipIcon: null
    readonly property var tipLines: tipIcon ? [[tipIcon.modelData.tooltipTitle || tipIcon.modelData.title || tipIcon.modelData.id]] : []
    readonly property real tipCentre: tipIcon ? margins.left + tipIcon.mapToItem(null, tipIcon.width / 2, 0).x : 0

    // the app's menu above its icon; the same icon again closes it
    function openMenu(icon) {
        if (menu.open && menu.item === icon.modelData) {
            menu.open = false;
            return;
        }
        menuCentre = icon.mapToItem(null, icon.width / 2, 0).x;
        menu.show(icon.modelData);
    }

    visible: Tray.items.length > 0
    exclusiveZone: 0
    implicitWidth: pill.width
    implicitHeight: Theme.barHeight + Theme.barMargin // like the bar, so it slides off the same way
    color: "transparent"

    // takes no clicks while hidden; the bar's edge strip brings both back
    mask: Region {
        width: root.shown ? root.width : 0
        height: root.shown ? Theme.barHeight : 0
    }

    HoverHandler {
        id: hover
    }

    // 12 px above the tray, like quick settings above the bar, kept on screen
    TrayMenu {
        id: menu
        anchors.bottom: true
        anchors.left: true
        margins.left: Math.min(screen.width - width - 8, root.margins.left + root.menuCentre - width / 2)
        margins.bottom: root.height + 12
        onOpenChanged: grab.active = open
    }

    // a click outside the menu and the tray closes the menu; the tray stays clickable
    FocusGrab {
        id: grab
        windows: [menu, root]
        onCleared: menu.open = false
    }

    // 0 hidden, 1 shown, on the bar's curve: the pill buds out of its edge beside the bar as the bar's
    // content shows, and goes with it (Bar.qml grows the bar out of its handle)
    property real grown: shown ? 1 : 0

    Behavior on grown {
        enabled: !root.instant

        NumberAnimation {
            duration: Theme.growDuration
            easing.type: Theme.easing
        }
    }

    Rectangle {
        id: pill

        readonly property real shownPart: Math.max(0, 2 * root.grown - 1)

        width: icons.implicitWidth + 18 // 1 px border + 8 px padding each side, as in the bar
        height: Theme.barHeight
        opacity: shownPart
        scale: 0.8 + 0.2 * shownPart
        transformOrigin: Item.Left // the edge nearest the bar
        radius: Theme.barRadius
        color: Theme.bgAlt
        border.width: 1
        border.color: Theme.overlay2

        Row {
            id: icons

            anchors.centerIn: parent
            spacing: 4

            Repeater {
                // keeps the icons when one is added or removed
                model: ScriptModel {
                    values: Tray.items
                }

                TrayIcon {}
            }
        }
    }

    component TrayIcon: Rectangle {
        id: icon

        required property var modelData

        width: Theme.chipHeight
        height: Theme.chipHeight
        radius: Theme.chipRadius
        color: mouse.containsMouse ? Theme.overlay2 : "transparent"
        Accessible.role: Accessible.Button
        Accessible.name: modelData.tooltipTitle || modelData.title || modelData.id

        Behavior on color {
            ColorAnimation {
                duration: Theme.hoverDuration
                easing.type: Theme.easing
            }
        }

        Image {
            anchors.centerIn: parent
            width: 20
            height: 20
            sourceSize: Qt.size(40, 40)
            source: icon.modelData.icon
            fillMode: Image.PreserveAspectFit
        }

        MouseArea {
            id: mouse

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onContainsMouseChanged: {
                if (containsMouse)
                    root.tipIcon = icon;
                else if (root.tipIcon === icon)
                    root.tipIcon = null;
            }
            cursorShape: Qt.PointingHandCursor
            onClicked: event => {
                const item = icon.modelData;
                if (event.button === Qt.MiddleButton)
                    Tray.secondaryActivate(item);
                else if (event.button === Qt.RightButton || item.onlyMenu) {
                    if (item.hasMenu)
                        root.openMenu(icon);
                } else
                    Tray.activate(item);
            }
            onWheel: event => {
                const horizontal = event.angleDelta.y === 0;
                Tray.scroll(icon.modelData, horizontal ? event.angleDelta.x : event.angleDelta.y, horizontal);
            }
        }
    }
}
