import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland // layer-shell keyboard focus and screen capture (Wayland protocols, not a compositor module)
import QtQuick
import QtQuick.Effects

// Power menu (PowerMenu board): lock, log out, suspend, reboot, shut down, centred over a blurred,
// dimmed still of the screen. Letter keys act at once; arrows and Enter pick one; a click on the
// background closes it.
PanelWindow {
    id: root

    readonly property var actions: [
        { name: "Lock", key: Qt.Key_L, icon: Icons.lock, run: () => Session.lock() },
        { name: "Log out", key: Qt.Key_E, icon: Icons.logOut, run: () => Session.logout() },
        { name: "Suspend", key: Qt.Key_S, icon: Icons.moon, run: () => Session.suspend() },
        { name: "Reboot", key: Qt.Key_R, icon: Icons.reboot, run: () => Session.reboot() },
        { name: "Shut down", key: Qt.Key_P, icon: Icons.power, run: () => Session.shutdown(), danger: true }
    ]
    property int current
    property bool open
    // The still arrived (or took too long: then the menu opens over the dim alone). The menu waits
    // for it, so the capture never contains the menu itself.
    property bool captured

    function run(i: int) {
        open = false;
        actions[i].run();
    }

    function key(event) {
        const i = actions.findIndex(a => a.key === event.key);
        if (event.key === Qt.Key_Escape)
            open = false;
        else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right)
            current = (current + (event.key === Qt.Key_Right ? 1 : -1) + actions.length) % actions.length;
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            run(current);
        else if (i >= 0)
            run(i);
    }

    onOpenChanged: {
        if (!open)
            return;
        current = 0;
        shot.captureSource = screen;
        captureTimeout.restart();
    }
    onVisibleChanged: {
        if (visible)
            return;
        captured = false;
        shot.captureSource = null; // so the next opening waits for a fresh still
    }

    // up (transparent) while the still is taken, then until the fade-out ends
    visible: open || reveal.shown
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay // above fullscreen windows
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Timer {
        id: captureTimeout
        interval: 300
        onTriggered: root.captured = true
    }

    // For a keybind: qs -c pistachio ipc call power toggle
    IpcHandler {
        target: "power"

        function toggle(): void {
            root.open = !root.open;
        }
    }

    Reveal {
        id: reveal
        open: root.open && root.captured
    }

    // the blurred, dimmed still; fades in over the live screen
    Item {
        anchors.fill: parent
        opacity: reveal.progress

        ScreencopyView {
            id: shot
            anchors.fill: parent
            visible: false // drawn through the blur
            onHasContentChanged: if (hasContent) root.captured = true
        }

        MultiEffect {
            anchors.fill: parent
            source: shot
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1
            blurMax: 64
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.bg
            opacity: 0.45
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.open = false
        }
    }

    Column {
        id: content

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        // fades in rising 12 px, and back
        anchors.verticalCenterOffset: 12 * (1 - reveal.progress)
        opacity: reveal.progress
        spacing: 20
        focus: true
        Keys.onPressed: event => root.key(event)

        Rectangle {
            id: panel

            width: buttons.implicitWidth + 48
            height: buttons.implicitHeight + 48
            radius: 32
            color: Theme.bgAlt
            border.width: 1
            border.color: Theme.overlay2
            Accessible.role: Accessible.Grouping
            Accessible.name: "Power menu"

            Shadow {
                z: -1 // beneath the panel, fading with it
                kind: Theme.shadowModal
                anchors.fill: parent
                radius: parent.radius
            }

            // clicks between the buttons don't reach the background
            MouseArea {
                anchors.fill: parent
            }

            Row {
                id: buttons

                anchors.centerIn: parent
                spacing: 12

                Repeater {
                    model: root.actions

                    Rectangle {
                        id: button

                        required property var modelData
                        required property int index
                        readonly property bool selected: root.current === index

                        width: 120
                        height: 132
                        radius: 24
                        color: selected ? Theme.overlay2 : Theme.overlay
                        Accessible.role: Accessible.Button
                        Accessible.name: `${modelData.name}, key ${String.fromCharCode(modelData.key)}`

                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.hoverDuration
                                easing.type: Theme.easing
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.current = button.index
                            onClicked: root.run(button.index)
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 10

                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                size: 30
                                paths: button.modelData.icon
                                color: button.selected ? Theme.pistachio : button.modelData.danger ? Theme.terracotta : Theme.text
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: button.modelData.name
                                color: button.selected ? Theme.textBright : Theme.text
                                font.family: Theme.fontUi
                                font.pixelSize: 14
                                font.weight: Font.Bold
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: String.fromCharCode(button.modelData.key)
                                color: Theme.subtext
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                font.letterSpacing: 0.66
                            }
                        }
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "← → move · Enter confirm · Esc cancel"
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
    }
}
