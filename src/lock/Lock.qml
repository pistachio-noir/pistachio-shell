import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland // the session-lock protocol (Wayland, not a compositor module)
import QtQuick

// Lock screen (Lock board). The password goes to PAM through Session. If the shell dies while locked,
// the screen stays locked; from a TTY: hyprctl --instance 0 eval 'hl.clear_crashed_lockscreen()'
Scope {
    // A live reload recreates Session (singletons keep nothing) while the screen stays locked, so
    // carry the lock state over; otherwise the right password would find nothing to unlock.
    PersistentProperties {
        id: persist
        reloadableId: "lock"
        property bool locked
        onReloaded: if (locked) Session.lock()
    }

    Connections {
        target: Session

        function onLockedChanged() {
            persist.locked = Session.locked;
        }
    }

    WlSessionLock {
        locked: Session.locked
        onSecureChanged: Session.secure = secure

        WlSessionLockSurface {
            id: surface

            color: Theme.bg

            // the clock and password field fade in over the plain background
            // (target set once: contentItem can't be bound to)
            Component.onCompleted: {
                fadeIn.target = contentItem;
                fadeIn.start();
            }

            NumberAnimation {
                id: fadeIn
                property: "opacity"
                from: 0
                to: 1
                duration: Theme.motionDuration
                easing.type: Theme.easing
            }

            SystemClock {
                id: clock
                precision: SystemClock.Minutes
            }

            Column {
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

                        TextInput {
                            id: field

                            anchors.fill: parent
                            anchors.leftMargin: 24
                            anchors.rightMargin: 24
                            verticalAlignment: TextInput.AlignVCenter
                            horizontalAlignment: TextInput.AlignHCenter
                            echoMode: TextInput.Password
                            passwordCharacter: "•"
                            readOnly: Session.checking
                            color: Theme.textBright
                            font.family: Theme.fontUi
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            font.letterSpacing: 3.6
                            focus: true
                            clip: true
                            Accessible.role: Accessible.EditableText
                            Accessible.passwordEdit: true
                            Accessible.name: "Password"
                            onAccepted: {
                                Session.unlock(text);
                                text = "";
                            }
                            Keys.onEscapePressed: text = ""

                            cursorDelegate: Rectangle {
                                width: 2
                                color: Theme.pistachio
                            }
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

            // status capsule
            Rectangle {
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

    // For a keybind: qs -c pistachio ipc call lock lock
    IpcHandler {
        target: "lock"

        function lock(): void {
            Session.lock();
        }
    }
}
