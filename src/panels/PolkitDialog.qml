import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland // layer-shell layer and keyboard focus (Wayland protocols, not a compositor module)
import QtQuick

// Polkit password dialog (polkit-prompt, polkit-details and polkit-wrong-password boards): an app asks
// for admin rights. Centred over the dimmed screen; Enter authenticates, Esc cancels. A click beside it
// does nothing, so a stray one can't dismiss the request. Requests queue in Polkit; one at a time.
PanelWindow {
    id: root

    readonly property var request: Polkit.request
    // the request on screen, kept while the dialog fades out
    property var shown: null
    property bool details // the Details section is open
    readonly property var detailRows: [
        { label: "Requested by", value: shown?.requester ?? "" },
        { label: "Action", value: shown?.action ?? "" },
        { label: "Vendor", value: shown?.vendor ?? "" }
    ].filter(r => r.value)

    // the password field on screen: Classic's or TUI's card (Appearance → Style)
    readonly property var input: Theme.tui ? tuiField : field

    function submit() {
        if (input.text !== "")
            Polkit.submit(input.text);
    }

    onRequestChanged: {
        if (!request)
            return;
        shown = request;
        details = false;
        field.text = "";
        tuiField.text = "";
        input.forceActiveFocus();
    }

    visible: reveal.shown
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay // above fullscreen windows
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Reveal {
        id: reveal
        open: !!root.request
    }

    // a try is over (wrong password, or PAM asks something else): start again from empty
    Connections {
        target: Polkit

        function onCheckingChanged() {
            if (!Polkit.checking) {
                field.text = "";
                tuiField.text = "";
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        opacity: (Theme.tui ? 0 : 0.66) * reveal.progress // the TUI board leaves the screen as it is

        MouseArea {
            anchors.fill: parent
        }
    }

    Rectangle {
        id: card

        visible: !Theme.tui
        anchors.centerIn: parent
        // fades in rising 12 px, and back
        anchors.verticalCenterOffset: 12 * (1 - reveal.progress)
        opacity: reveal.progress
        width: 440
        height: body.implicitHeight + 56
        radius: Theme.panelRadius
        color: Theme.bgAlt
        border.width: 1
        border.color: Theme.overlay2
        Accessible.role: Accessible.Dialog
        Accessible.name: "Authentication required"

        Shadow {
            z: -1 // beneath the card, fading and rising with it
            kind: Theme.shadowModal
            anchors.fill: parent
            radius: parent.radius
        }

        Column {
            id: body

            x: 28
            y: 28
            width: parent.width - 56
            spacing: 18

            Row {
                width: parent.width
                spacing: 16

                Rectangle {
                    width: 48
                    height: 48
                    radius: 24
                    color: Theme.overlay

                    Icon {
                        anchors.centerIn: parent
                        size: 24
                        paths: Icons.shieldAlert
                        color: Theme.gold
                    }
                }

                Column {
                    width: parent.width - 64
                    spacing: 4

                    Text {
                        width: parent.width
                        text: "Authentication required"
                        color: Theme.textBright
                        font.family: Theme.fontUi
                        font.pixelSize: 18
                        font.weight: Font.ExtraBold
                        lineHeight: 24
                        lineHeightMode: Text.FixedHeight
                    }

                    Text {
                        readonly property string message: root.shown?.message ?? ""

                        width: parent.width
                        text: (/[.!?]$/.test(message) ? message : message + ".") + " Enter your password to allow this."
                        wrapMode: Text.Wrap
                        color: Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        lineHeight: 19
                        lineHeightMode: Text.FixedHeight
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 10

                Rectangle {
                    width: toggle.implicitWidth + 22
                    height: 32
                    radius: 16
                    color: toggleArea.containsMouse ? Theme.overlay2 : Theme.overlay
                    Accessible.role: Accessible.Button
                    Accessible.name: root.details ? "Hide details" : "Details"

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.hoverDuration
                            easing.type: Theme.easing
                        }
                    }

                    Row {
                        id: toggle

                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Details"
                            color: Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            size: 14
                            paths: root.details ? Icons.chevronUp : Icons.chevronDown
                            color: Theme.subtext
                        }
                    }

                    MouseArea {
                        id: toggleArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.details = !root.details
                    }
                }

                Rectangle {
                    visible: root.details
                    width: parent.width
                    height: info.implicitHeight + 28
                    radius: Theme.tileRadius
                    color: Theme.bg

                    Column {
                        id: info

                        x: 16
                        y: 14
                        width: parent.width - 32
                        spacing: 12

                        Repeater {
                            model: root.detailRows

                            Column {
                                required property var modelData

                                width: parent.width
                                spacing: 2

                                Text {
                                    text: modelData.label
                                    color: Theme.subtext
                                    font.family: Theme.fontUi
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.88
                                    font.capitalization: Font.AllUppercase
                                }

                                Text {
                                    width: parent.width
                                    text: modelData.value
                                    wrapMode: Text.WrapAnywhere
                                    color: Theme.text
                                    font.family: Theme.fontMono
                                    font.pixelSize: 12
                                    lineHeight: 17
                                    lineHeightMode: Text.FixedHeight
                                }
                            }
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 10

                Row {
                    leftPadding: 4
                    spacing: 8

                    Rectangle {
                        width: 24
                        height: 24
                        radius: 12
                        color: Theme.overlay

                        Icon {
                            anchors.centerIn: parent
                            size: 14
                            paths: Icons.user
                            color: Theme.subtext
                        }
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Text {
                            text: "Authenticating as"
                            color: Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: root.shown?.user ?? ""
                            color: Theme.textBright
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 52
                    radius: 26
                    color: Theme.bg
                    border.width: 1
                    border.color: Theme.overlay2

                    Text {
                        anchors.centerIn: parent
                        visible: field.text === ""
                        text: Polkit.prompt || "Password"
                        color: Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: 17
                        font.weight: Font.Bold
                        font.letterSpacing: 0.34
                    }

                    TextInput {
                        id: field

                        anchors.fill: parent
                        anchors.leftMargin: 22
                        anchors.rightMargin: 22
                        verticalAlignment: TextInput.AlignVCenter
                        horizontalAlignment: TextInput.AlignHCenter
                        echoMode: Polkit.prompt && Polkit.promptVisible ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "•"
                        readOnly: Polkit.checking
                        color: Theme.textBright
                        font.family: Theme.fontUi
                        font.pixelSize: 17
                        font.weight: Font.Bold
                        font.letterSpacing: 3.4
                        focus: true
                        clip: true
                        Accessible.role: Accessible.EditableText
                        Accessible.passwordEdit: echoMode === TextInput.Password
                        Accessible.name: Polkit.prompt || "Password"
                        onAccepted: root.submit()
                        Keys.onEscapePressed: Polkit.cancel()

                        cursorDelegate: Rectangle {
                            width: 2
                            color: Theme.pistachio
                        }
                    }
                }

                Text {
                    visible: Polkit.error !== ""
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Polkit.error
                    wrapMode: Text.Wrap
                    color: Theme.terracotta
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    Accessible.role: Accessible.AlertMessage
                    Accessible.name: text
                }
            }

            Item {
                width: parent.width
                height: 44

                Row {
                    anchors.right: parent.right
                    spacing: 10

                    Rectangle {
                        width: cancelLabel.implicitWidth + 44
                        height: 44
                        radius: 22
                        color: cancelArea.containsMouse ? Theme.overlay2 : Theme.overlay
                        Accessible.role: Accessible.Button
                        Accessible.name: "Cancel"

                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.hoverDuration
                                easing.type: Theme.easing
                            }
                        }

                        Text {
                            id: cancelLabel

                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Theme.text
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            id: cancelArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Polkit.cancel()
                        }
                    }

                    Rectangle {
                        width: authenticate.implicitWidth + 30
                        height: 44
                        radius: 22
                        color: Theme.pistachio
                        Accessible.role: Accessible.Button
                        Accessible.name: "Authenticate"

                        Row {
                            id: authenticate

                            x: 22
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Polkit.checking ? "Checking…" : "Authenticate"
                                color: Theme.bg
                                font.family: Theme.fontUi
                                font.pixelSize: 13
                                font.weight: Font.ExtraBold
                            }

                            Rectangle {
                                width: 28
                                height: 28
                                radius: 14
                                color: Theme.bg

                                Text {
                                    anchors.centerIn: parent
                                    text: "↵"
                                    color: Theme.pistachio
                                    font.family: Theme.fontUi
                                    font.pixelSize: 12
                                    font.weight: Font.ExtraBold
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.submit()
                        }
                    }
                }
            }
        }
    }

    // The TUI card (board pistachio-shell-design/TUI/launcher-and-shell/PolkitDetails.html): a framed box under the top
    // bar, "[!] authentication required", the message, action and user, "[-] details" opening the
    // vendor and the app that asked, the password with a block cursor, and Cancel / Authenticate.
    PanelFrame {
        id: tuiCard

        visible: Theme.tui
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.tuiBarHeight + 72 + 8 * (1 - reveal.progress)
        opacity: reveal.progress
        width: 520
        height: tuiBody.implicitHeight + 40
        title: "polkit"
        detail: (root.shown?.vendor ?? "").split(" ").filter(w => !/^the$|^project$/i.test(w)).join("").toLowerCase()
        Accessible.role: Accessible.Dialog
        Accessible.name: "Authentication required"

        Column {
            id: tuiBody
            x: 16
            y: 20
            width: parent.width - 32
            spacing: 6

            Row {
                spacing: 8
                Text { text: "[!]"; color: Theme.gold; font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize; font.weight: Font.Bold }
                Text { text: "authentication required"; color: Theme.textBright; font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize; font.weight: Font.Bold }
            }

            Text {
                width: parent.width
                bottomPadding: 6
                wrapMode: Text.Wrap
                text: { const m = root.shown?.message ?? ""; return /[.!?]$/.test(m) ? m : m + "."; }
                color: Theme.text
                font.family: Theme.fontTui
                font.pixelSize: Theme.tuiTextSize
            }

            Repeater {
                model: [["action", root.shown?.action ?? ""], ["user", root.shown?.user ?? ""]].filter(r => r[1])
                Row {
                    required property var modelData
                    Text { width: 64; text: modelData[0]; color: Theme.subtext; font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize }
                    Text { width: tuiBody.width - 64; elide: Text.ElideRight; text: modelData[1]; color: Theme.text; font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize }
                }
            }

            // [-] details / [+] details
            Text {
                visible: root.detailRows.length > 0
                text: (root.details ? "[-]" : "[+]") + " details"
                color: detailsMouse.containsMouse ? Theme.textBright : Theme.text
                font.family: Theme.fontTui
                font.pixelSize: Theme.tuiTextSize
                font.weight: Font.Bold
                MouseArea {
                    id: detailsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.details = !root.details
                }
            }

            Rectangle {
                visible: root.details && root.detailRows.length > 0
                x: 16
                width: parent.width - 16
                height: detailsColumn.implicitHeight + 16
                color: Theme.bgAlt

                Column {
                    id: detailsColumn
                    x: 12
                    y: 8
                    width: parent.width - 24
                    Repeater {
                        model: root.detailRows
                        Row {
                            required property var modelData
                            Text { width: 96; text: modelData.label === "Requested by" ? "requested" : modelData.label.toLowerCase(); color: Theme.subtext; font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize }
                            Text { width: detailsColumn.width - 96; elide: Text.ElideRight; text: modelData.value; color: Theme.text; font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize }
                        }
                    }
                }
            }

            // password ••••••••▌
            Row {
                topPadding: 14
                spacing: 12
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (Polkit.prompt || "password").replace(/:\s*$/, "").toLowerCase()
                    color: Theme.subtext
                    font.family: Theme.fontTui
                    font.pixelSize: Theme.tuiTextSize
                }
                TextInput {
                    id: tuiField
                    width: tuiBody.width - 120
                    echoMode: Polkit.prompt && Polkit.promptVisible ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "•"
                    readOnly: Polkit.checking
                    color: Theme.textBright
                    selectionColor: Theme.overlay2
                    font.family: Theme.fontTui
                    font.pixelSize: Theme.tuiTextSize
                    Accessible.name: Polkit.prompt || "Password"
                    onAccepted: root.submit()
                    Keys.onEscapePressed: Polkit.cancel()
                    cursorDelegate: Rectangle {
                        width: 8
                        height: Theme.tuiLineHeight - 2
                        color: Theme.pistachio
                        visible: tuiField.activeFocus && !tuiField.readOnly
                    }
                }
            }

            Text {
                visible: Polkit.error !== ""
                width: parent.width
                wrapMode: Text.Wrap
                text: Polkit.error.toLowerCase()
                color: Theme.terracotta
                font.family: Theme.fontTui
                font.pixelSize: Theme.tuiTextSize
            }

            Item {
                width: parent.width
                height: Theme.tuiButtonHeight + 22

                Row {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    spacing: 8

                    ActionButton {
                        height: Theme.tuiButtonHeight + 12
                        text: "Cancel"
                        base: Theme.overlay
                        onClicked: Polkit.cancel()
                    }
                    ActionButton {
                        height: Theme.tuiButtonHeight + 12
                        primary: true
                        text: Polkit.checking ? "Checking…" : "Authenticate"
                        onClicked: root.submit()
                    }
                }
            }
        }
    }
}
