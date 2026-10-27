import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland // the session-lock protocol and screen capture (Wayland, not a compositor module)
import QtQuick
import QtQuick.Effects

// Lock screen (Lock board), over a blurred, dimmed still of the desktop and with what's playing (owner's
// request, after phase 8; the board has a plain background). The password goes to PAM through
// Session. If the shell dies while locked, the screen stays locked; from a TTY:
// hyprctl --instance 0 eval 'hl.clear_crashed_lockscreen()'
Scope {
    id: root

    // Once locked, the compositor shows nothing but the lock, so the still is taken just before: the
    // lock waits for it, at most 300 ms, and goes up over the plain background without it.
    property bool ready
    property var still: null // the grabbed still (ItemGrabResult); its url is valid while this holds it
    // the right password was given: the lock stays up while it fades back to the still
    property bool leaving

    // A live reload recreates Session (singletons keep nothing) while the screen stays locked, so
    // carry the lock state over; otherwise the right password would find nothing to unlock. The still
    // is gone, and a new one would show the lock itself.
    PersistentProperties {
        id: persist
        reloadableId: "lock"
        property bool locked
        onReloaded: {
            if (!locked)
                return;
            root.ready = true;
            Session.lock();
        }
    }

    Connections {
        target: Session

        function onLockedChanged() {
            persist.locked = Session.locked;
            if (Session.locked) {
                root.leaving = false;
                leave.stop();
                if (!root.ready)
                    catcher.take();
            } else if (root.ready) {
                root.leaving = true;
                leave.restart();
            }
        }
    }

    Timer {
        id: leave
        interval: Theme.growDuration
        onTriggered: {
            root.leaving = false;
            root.ready = false;
            root.still = null;
        }
    }

    // Takes the still: shows the capture full-screen, click-through (the screen looks the same), and
    // grabs it into an image the lock surface can show; no file is written.
    PanelWindow {
        id: catcher

        property bool taking

        function take() {
            taking = true;
            shot.captureSource = screen;
            giveUp.restart();
        }

        function done() {
            giveUp.stop();
            taking = false;
            shot.captureSource = null;
            root.ready = true;
        }

        visible: taking
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        ScreencopyView {
            id: shot
            anchors.fill: parent
            onHasContentChanged: {
                if (!hasContent || !catcher.taking)
                    return;
                const grabbing = grabToImage(result => {
                    if (!catcher.taking)
                        return; // too late: locked without it
                    root.still = result;
                    catcher.done();
                });
                if (!grabbing)
                    catcher.done();
            }
        }

        Timer {
            id: giveUp
            interval: 300
            onTriggered: catcher.done()
        }
    }

    WlSessionLock {
        locked: root.ready && (Session.locked || root.leaving)
        onSecureChanged: Session.secure = secure

        WlSessionLockSurface {
            id: surface

            // 0 to 1 as the lock comes up, back to 0 as it lets go: the blur and dim fade over the
            // sharp still, and the clock and field settle in from slightly larger, and leave growing
            property real shown

            color: Theme.bg
            Component.onCompleted: shown = Qt.binding(() => root.leaving ? 0 : 1)

            Behavior on shown {
                NumberAnimation {
                    duration: Theme.growDuration
                    easing.type: Theme.easing
                }
            }

            SystemClock {
                id: clock
                precision: SystemClock.Minutes
            }

            // a wrong password: the field shakes, then the dots fade away
            Connections {
                target: Session

                function onErrorChanged() {
                    if (Session.error)
                        refuse.restart();
                }
            }

            SequentialAnimation {
                id: refuse

                NumberAnimation {
                    target: shake
                    property: "x"
                    to: -10
                    duration: 50
                    easing.type: Theme.easing
                }
                NumberAnimation {
                    target: shake
                    property: "x"
                    to: 8
                    duration: 70
                    easing.type: Theme.easing
                }
                NumberAnimation {
                    target: shake
                    property: "x"
                    to: -5
                    duration: 60
                    easing.type: Theme.easing
                }
                NumberAnimation {
                    target: shake
                    property: "x"
                    to: 0
                    duration: 60
                    easing.type: Theme.easing
                }
                NumberAnimation {
                    target: dotsBox
                    property: "opacity"
                    to: 0
                    duration: Theme.hoverDuration
                    easing.type: Theme.easing
                }
                ScriptAction {
                    script: {
                        field.text = "";
                        dotsBox.opacity = 1;
                    }
                }
            }

            // the desktop as it was, sharp, so the lock's first frame matches the screen it covers
            Image {
                id: desktop
                anchors.fill: parent
                source: root.still?.url ?? ""
            }

            Item {
                anchors.fill: parent
                opacity: surface.shown

                MultiEffect {
                    anchors.fill: parent
                    source: desktop
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blur: 1
                    blurMax: 64
                }

                Rectangle {
                    anchors.fill: parent
                    color: Theme.bg
                    opacity: 0.6
                }
            }

            Item {
                anchors.fill: parent
                opacity: surface.shown
                scale: 1 + 0.04 * (1 - surface.shown)

                // a soft dark patch behind the clock and field, so the date and hint read over a
                // bright desktop while the rest of it shows through the lighter dim
                RectangularShadow {
                    anchors.centerIn: column
                    width: column.width + 120
                    height: column.height + 100
                    radius: 120
                    blur: 120
                    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.45)
                }

                Column {
                    id: column

                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -20
                    spacing: 44

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 4

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatTime(clock.date, "hh:mm")
                            color: Theme.textBright
                            font.family: Theme.fontUi
                            font.pixelSize: 132
                            font.weight: Font.ExtraBold
                            font.letterSpacing: -2.64
                            font.features: { "tnum": 1 }
                            lineHeight: 132
                            lineHeightMode: Text.FixedHeight
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDate(clock.date, "dddd, d MMMM")
                            color: Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                        }
                    }

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 16

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 64
                            height: 64
                            radius: 32
                            color: Theme.overlay

                            Icon {
                                anchors.centerIn: parent
                                size: 30
                                paths: Icons.user
                                color: Theme.subtext
                            }
                        }

                        Rectangle {
                            width: 320
                            height: 56
                            radius: 28
                            color: Theme.bgAlt
                            border.width: 1
                            border.color: Theme.overlay2
                            transform: Translate {
                                id: shake
                            }

                            // the board's shadow under the field
                            Shadow {
                                z: -1
                                kind: Theme.shadowSmall
                                anchors.fill: parent
                                radius: parent.radius
                            }

                            // takes the keys; the dots below draw what's typed
                            TextInput {
                                id: field

                                anchors.fill: parent
                                opacity: 0
                                echoMode: TextInput.Password
                                readOnly: Session.checking || refuse.running
                                focus: true
                                Accessible.role: Accessible.EditableText
                                Accessible.passwordEdit: true
                                Accessible.name: "Password"
                                onAccepted: {
                                    if (text !== "") // an empty try would cost a pam_faillock strike
                                        Session.unlock(text);
                                }
                                Keys.onEscapePressed: text = ""
                                onTextChanged: {
                                    while (typed.count < text.length)
                                        typed.append({});
                                    while (typed.count > text.length)
                                        typed.remove(typed.count - 1);
                                    blink.on = true;
                                    blink.restart();
                                }
                            }

                            ListModel {
                                id: typed
                            }

                            // a dot per character, popping in as it's typed, and the caret after them
                            Item {
                                id: dotsBox

                                anchors.fill: parent
                                anchors.leftMargin: 24
                                anchors.rightMargin: 24
                                clip: true

                                Row {
                                    id: dots

                                    // pulses while PAM checks the password
                                    property real pulse: 1

                                    // centred; once wider than the field, the newest dots stay in view
                                    x: Math.min((parent.width - width) / 2, parent.width - width)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8
                                    opacity: Session.checking ? pulse : 1

                                    Behavior on x {
                                        NumberAnimation {
                                            duration: Theme.hoverDuration
                                            easing.type: Theme.easing
                                        }
                                    }

                                    SequentialAnimation on pulse {
                                        running: Session.checking
                                        loops: Animation.Infinite

                                        NumberAnimation {
                                            to: 0.35
                                            duration: 500
                                            easing.type: Theme.easing
                                        }
                                        NumberAnimation {
                                            to: 1
                                            duration: 500
                                            easing.type: Theme.easing
                                        }
                                    }

                                    Repeater {
                                        model: typed

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 8
                                            height: 8
                                            radius: 4
                                            color: Theme.textBright

                                            NumberAnimation on scale {
                                                from: 0.3
                                                to: 1
                                                duration: Theme.motionDuration
                                                easing.type: Theme.easing
                                            }
                                            NumberAnimation on opacity {
                                                from: 0
                                                to: 1
                                                duration: Theme.hoverDuration
                                                easing.type: Theme.easing
                                            }
                                        }
                                    }

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 2
                                        height: 22
                                        radius: 1
                                        color: Theme.pistachio
                                        opacity: blink.on && !Session.checking ? 1 : 0
                                    }
                                }
                            }

                            Timer {
                                id: blink

                                property bool on: true

                                running: field.activeFocus
                                interval: 530
                                repeat: true
                                onTriggered: on = !on
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Session.checking ? "Checking…" : Session.error || "Enter to unlock"
                            color: Session.error ? Theme.terracotta : Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }
                }

                // what's playing, above the status capsule; fades as a player comes and goes
                MediaCard {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: capsule.top
                    anchors.bottomMargin: 16
                    width: 360
                    color: Theme.bgAlt
                    border.width: 1
                    border.color: Theme.overlay2
                    opacity: player ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.motionDuration
                            easing.type: Theme.easing
                        }
                    }

                    Shadow {
                        z: -1
                        kind: Theme.shadowSmall
                        anchors.fill: parent
                        radius: parent.radius
                    }
                }

                // status capsule
                Rectangle {
                    id: capsule

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 24
                    width: 54
                    height: 40
                    radius: 20
                    color: Theme.bgAlt
                    border.width: 1
                    border.color: Theme.overlay2

                    Icon {
                        anchors.centerIn: parent
                        color: Network.connected ? Theme.text : Theme.subtext
                        paths: Network.connected ? Icons.ethernet : Icons.ethernet.concat(Icons.slash)
                    }
                }
            }
        }
    }

    // For a keybind: qs -c pistachio ipc call lock lock
    IpcHandler {
        target: "lock"

        function lock(): void {
            Session.lock();
        }
    }
}
