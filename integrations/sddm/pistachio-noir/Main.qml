import QtQuick
import QtQuick.Effects // RectangularShadow

// Pistachio Noir login screen for SDDM (Qt 6 greeter, theme API 2.0), after pistachio-shell-design/sddm-*.html:
// clock and date, the user, the password field, a session menu and keyboard layout bottom-left, and
// suspend / reboot / shut down bottom-right. SDDM provides sddm, userModel, sessionModel, keyboard,
// config and primaryScreen. The greeter runs as its own user and can't see the shell, so the palette
// and the icon are copies, and Manrope comes with the theme.
Rectangle {
    id: root

    // the shell's Theme.qml palette
    readonly property color bg: "#15170F"
    readonly property color bgAlt: "#1D2016"
    readonly property color overlay: "#2A2F1F"
    readonly property color overlay2: "#39412A"
    readonly property color subtext: "#A3B08F"
    readonly property color text: "#E5E9D8"
    readonly property color textBright: "#F6F8EF"
    readonly property color pistachio: "#9FD88A"
    readonly property color terracotta: "#DB8267"
    readonly property color gold: "#E0B15E"
    readonly property string fontFamily: manrope.status === FontLoader.Ready ? manrope.name : "Manrope"

    // icons (Lucide, as on the boards)
    readonly property var icons: ({
        user: ["M8 8a4 4 0 1 0 8 0a4 4 0 1 0-8 0", "M4 21a8 8 0 0 1 16 0"],
        monitor: ["M2 5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2z", "M8 21h8", "M12 17v4"],
        chevronDown: ["M6 9l6 6 6-6"],
        chevronsUpDown: ["M7 15l5 5 5-5", "M7 9l5-5 5 5"],
        check: ["M20 6 9 17l-5-5"],
        moon: ["M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"],
        reboot: ["M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8", "M21 3v5h-5", "M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16", "M8 16H3v5"],
        power: ["M18.36 6.64a9 9 0 1 1-12.73 0", "M12 2v10"]
    })

    property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    readonly property var user: users.count > 0 ? users.itemAt(Math.min(userIndex, users.count - 1)) : null
    readonly property var session: sessions.count > 0 ? sessions.itemAt(Math.min(sessionIndex, sessions.count - 1)) : null
    property bool busy // waiting for SDDM's answer
    property bool failed
    property string message // a note from PAM, e.g. a password about to expire
    property bool menuOpen // the session menu
    property date now: new Date()

    function login() {
        if (busy || !user)
            return;
        busy = true;
        failed = false;
        message = "";
        sddm.login(user.name, password.text, sessionIndex);
    }

    color: bg
    width: 1920
    height: 1080

    FontLoader {
        id: manrope
        source: "fonts/Manrope-Variable.ttf"
    }

    Connections {
        target: sddm

        function onLoginFailed() {
            root.busy = false;
            root.failed = true;
            password.text = "";
            password.forceActiveFocus();
        }
        function onLoginSucceeded() {
            root.busy = true; // the session starts; nothing more to do here
        }
        function onInformationMessage(text) {
            root.message = text;
        }
    }

    Timer {
        running: true
        repeat: true
        interval: 1000
        onTriggered: root.now = new Date()
    }

    // the models' rows, readable by index
    Item {
        visible: false

        Repeater {
            id: users
            model: userModel

            Item {
                required property string name
                required property string realName
                required property string icon
                required property bool needsPassword
            }
        }

        Repeater {
            id: sessions
            model: sessionModel

            Item {
                required property string name
                required property int type // 1 X11, 2 Wayland
                required property string comment
                readonly property string kind: type === 2 ? "Wayland" : type === 1 ? "X11" : comment
            }
        }
    }

    Image {
        anchors.fill: parent
        source: config.background ? Qt.resolvedUrl(config.background) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: status === Image.Ready
    }

    // the login form, on the primary screen only
    Item {
        anchors.fill: parent
        visible: primaryScreen

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
            spacing: 36

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(root.now, config.clockFormat || "hh:mm")
                    color: root.textBright
                    font.family: root.fontFamily
                    font.pixelSize: 132
                    font.weight: Font.ExtraBold
                    font.letterSpacing: -2.64
                    font.features: { "tnum": 1 }
                    lineHeight: 132
                    lineHeightMode: Text.FixedHeight
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(root.now, "dddd, d MMMM")
                    color: root.subtext
                    font.family: root.fontFamily
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14

                // the user; click the name to switch when there are several
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 64
                        height: 64
                        radius: 32
                        color: root.overlay
                        clip: true

                        Image {
                            id: face
                            anchors.fill: parent
                            // SDDM's generic face is less tidy than the glyph; a user's own picture wins
                            source: root.user && root.user.icon && !root.user.icon.includes("/sddm/faces/") ? root.user.icon : ""
                            sourceSize: Qt.size(128, 128)
                            fillMode: Image.PreserveAspectCrop
                            visible: status === Image.Ready
                        }

                        Icon {
                            anchors.centerIn: parent
                            visible: !face.visible
                            size: 30
                            paths: root.icons.user
                            color: root.subtext
                        }
                    }

                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: nameRow.implicitWidth
                        height: nameRow.implicitHeight
                        Accessible.role: users.count > 1 ? Accessible.Button : Accessible.StaticText
                        Accessible.name: (root.user ? root.user.realName || root.user.name : "") + (users.count > 1 ? ", switch user" : "")

                        Row {
                            id: nameRow
                            spacing: 6

                            Text {
                                text: root.user ? root.user.realName || root.user.name : ""
                                color: root.textBright
                                font.family: root.fontFamily
                                font.pixelSize: 16
                                font.weight: Font.Bold
                            }

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: users.count > 1
                                size: 14
                                paths: root.icons.chevronsUpDown
                                color: root.subtext
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: users.count > 1
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.userIndex = (root.userIndex + 1) % users.count;
                                root.failed = false;
                                password.text = "";
                                password.forceActiveFocus();
                            }
                        }
                    }
                }

                Item {
                    width: 320
                    height: 56

                    RectangularShadow {
                        anchors.fill: field
                        offset.y: 14
                        blur: 36
                        radius: 28
                        color: Qt.rgba(0, 0, 0, 0.55)
                    }

                    Rectangle {
                        id: field

                        anchors.fill: parent
                        radius: 28
                        color: root.bgAlt
                        border.width: 1
                        border.color: root.overlay2

                        TextInput {
                            id: password

                            anchors.fill: parent
                            anchors.leftMargin: 24
                            anchors.rightMargin: 24
                            verticalAlignment: TextInput.AlignVCenter
                            horizontalAlignment: TextInput.AlignHCenter
                            echoMode: TextInput.Password
                            passwordCharacter: "•"
                            readOnly: root.busy
                            color: root.textBright
                            font.family: root.fontFamily
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            font.letterSpacing: 3.6
                            focus: true
                            clip: true
                            Accessible.role: Accessible.EditableText
                            Accessible.passwordEdit: true
                            Accessible.name: "Password"
                            onTextChanged: if (text) root.failed = false

                            // hidden while empty, where it would cut through the placeholder
                            cursorDelegate: Rectangle {
                                width: 2
                                color: root.pistachio
                                opacity: password.text ? 1 : 0
                            }

                            // with the session menu open, ↑↓ pick a session and Enter or Esc close it
                            Keys.onPressed: event => {
                                if (root.menuOpen && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                                    root.sessionIndex = (root.sessionIndex + (event.key === Qt.Key_Down ? 1 : -1) + sessions.count) % sessions.count;
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Escape) {
                                    if (root.menuOpen)
                                        root.menuOpen = false;
                                    else
                                        password.text = "";
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    if (root.menuOpen)
                                        root.menuOpen = false;
                                    else
                                        root.login();
                                    event.accepted = true;
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !password.text
                                text: "Password"
                                color: root.subtext
                                font.family: root.fontFamily
                                font.pixelSize: 18
                                font.weight: Font.Bold
                                font.letterSpacing: 0.36
                            }
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.busy ? "Logging in…"
                        : root.failed ? "Wrong password. Try again."
                        : keyboard.capsLock ? "Caps Lock is on"
                        : root.message || "Enter to log in"
                    color: root.failed ? root.terracotta : keyboard.capsLock && !root.busy ? root.gold : root.subtext
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    font.weight: root.failed || keyboard.capsLock ? Font.Bold : Font.DemiBold
                    Accessible.role: root.failed ? Accessible.AlertMessage : Accessible.StaticText
                }
            }
        }

        // the session menu, above its button
        Rectangle {
            id: menu

            x: 24
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 76
            width: 240
            height: sessionList.implicitHeight + 16
            radius: 28
            color: root.bgAlt
            border.width: 1
            border.color: root.overlay2
            opacity: root.menuOpen ? 1 : 0
            visible: opacity > 0
            Accessible.role: Accessible.List
            Accessible.name: "Session"

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

            RectangularShadow {
                anchors.fill: parent
                z: -1
                offset.y: 24
                blur: 60
                radius: 28
                color: Qt.rgba(0, 0, 0, 0.65)
            }

            Column {
                id: sessionList

                x: 8
                y: 8
                width: parent.width - 16
                spacing: 2

                Repeater {
                    model: sessionModel

                    Rectangle {
                        id: option

                        required property int index
                        required property string name
                        required property int type
                        required property string comment
                        readonly property bool chosen: root.sessionIndex === index

                        width: parent.width
                        height: 52
                        radius: 20
                        color: chosen ? root.overlay2 : optionMouse.containsMouse ? root.overlay : "transparent"
                        Accessible.role: Accessible.ListItem
                        Accessible.name: name
                        Accessible.selected: chosen

                        Column {
                            x: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                text: option.name
                                color: option.chosen ? root.textBright : root.text
                                font.family: root.fontFamily
                                font.pixelSize: 14
                                font.weight: Font.Bold
                            }

                            Text {
                                text: option.type === 2 ? "Wayland" : option.type === 1 ? "X11" : option.comment
                                color: root.subtext
                                font.family: root.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }

                        Rectangle {
                            visible: option.chosen
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22
                            height: 22
                            radius: 11
                            color: root.pistachio

                            Icon {
                                anchors.centerIn: parent
                                size: 13
                                paths: root.icons.check
                                color: root.bg
                            }
                        }

                        MouseArea {
                            id: optionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.sessionIndex = option.index;
                                root.menuOpen = false;
                                password.forceActiveFocus();
                            }
                        }
                    }
                }
            }
        }

        // session and keyboard layout
        Row {
            x: 24
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            spacing: 8

            Rectangle {
                width: sessionRow.implicitWidth + 30
                height: 40
                radius: 20
                color: root.menuOpen ? root.overlay2 : sessionMouse.containsMouse ? root.overlay : root.bgAlt
                border.width: 1
                border.color: root.overlay2
                Accessible.role: Accessible.ComboBox
                Accessible.name: "Session: " + (root.session ? root.session.name : "")

                Row {
                    id: sessionRow
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 16
                        paths: root.icons.monitor
                        color: root.menuOpen ? root.textBright : root.text
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.session ? root.session.name : ""
                        color: root.menuOpen ? root.textBright : root.text
                        font.family: root.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 14
                        paths: root.icons.chevronDown
                        color: root.subtext
                    }
                }

                MouseArea {
                    id: sessionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.menuOpen = !root.menuOpen;
                        password.forceActiveFocus();
                    }
                }
            }

            // the keyboard layout; click for the next one
            Rectangle {
                visible: keyboard.enabled && keyboard.layouts.length > 0
                width: Math.max(48, layoutText.implicitWidth + 28)
                height: 40
                radius: 20
                color: layoutMouse.containsMouse ? root.overlay : root.bgAlt
                border.width: 1
                border.color: root.overlay2
                Accessible.role: Accessible.Button
                Accessible.name: "Keyboard layout: " + (keyboard.layouts[keyboard.currentLayout] ? keyboard.layouts[keyboard.currentLayout].longName : "")

                Text {
                    id: layoutText
                    anchors.centerIn: parent
                    text: keyboard.layouts[keyboard.currentLayout] ? keyboard.layouts[keyboard.currentLayout].shortName.toUpperCase() : ""
                    color: root.text
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 0.52
                }

                MouseArea {
                    id: layoutMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length;
                        password.forceActiveFocus();
                    }
                }
            }
        }

        // suspend, reboot, shut down: only what the machine can do
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            width: powerRow.implicitWidth + 8
            height: 40
            radius: 20
            color: root.bgAlt
            border.width: 1
            border.color: root.overlay2

            Row {
                id: powerRow
                x: 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Repeater {
                    model: [
                        { name: "Suspend", icon: root.icons.moon, can: sddm.canSuspend, run: () => sddm.suspend() },
                        { name: "Reboot", icon: root.icons.reboot, can: sddm.canReboot, run: () => sddm.reboot() },
                        { name: "Shut down", icon: root.icons.power, can: sddm.canPowerOff, run: () => sddm.powerOff(), danger: true }
                    ]

                    Rectangle {
                        id: powerButton

                        required property var modelData

                        visible: modelData.can
                        width: 32
                        height: 32
                        radius: 16
                        color: powerMouse.containsMouse ? root.overlay2 : "transparent"
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.name

                        Icon {
                            anchors.centerIn: parent
                            size: 17
                            paths: powerButton.modelData.icon
                            color: powerButton.modelData.danger ? root.terracotta : root.text
                        }

                        MouseArea {
                            id: powerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: powerButton.modelData.run()
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: password.forceActiveFocus()
}
