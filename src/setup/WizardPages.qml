import qs
import qs.components
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts

// The content of each stepped page (boards design/FirstRun/). Everything shown comes from the
// wizard's inputs; every change goes out through its signals.
Loader {
    id: root
    required property var wizard
    sourceComponent: ({
        restore: restorePage, check: checksPage, look: lookPage, sound: soundPage,
        notifications: notificationsPage, connections: connectionsPage, lens: lensPage,
        places: placesPage, done: donePage
    })[wizard.pageId] ?? null

    Component { id: checksPage; WizardCheck { wizard: root.wizard } }

    Component {
        id: restorePage
        ColumnLayout {
            readonly property var restore: root.wizard.restore
            spacing: 8
            WizardRow {
                Layout.fillWidth: true
                visible: restore.state === "busy"
                title: "Reading your settings"
                detail: restore.path || ""
                glyph: Icons.loader
            }
            WizardRow {
                Layout.fillWidth: true
                visible: restore.state === "missing" || restore.state === "error"
                title: restore.state === "missing" ? "No saved settings here" : "This file can't be restored"
                detail: restore.message || ""
                glyph: Icons.info
                control: SetupButton {
                    objectName: "setup-restore-choose"
                    text: "Choose file…"
                    enabled: root.wizard.available.restoreChoose !== false
                    onClicked: root.wizard.actionRequested("restoreChoose", null)
                }
            }
            WizardRow {
                Layout.fillWidth: true
                visible: restore.state === "reviewing"
                title: restore.changes.length ? restore.changes.length + (restore.changes.length === 1 ? " setting changes" : " settings change")
                                              : "Your settings already match"
                detail: (restore.path || "") + (restore.skipped ? " · " + restore.skipped + " left out" : "")
                glyph: Icons.download
                control: SetupButton {
                    objectName: "setup-restore-other"
                    text: "Other file…"; quiet: true
                    enabled: root.wizard.available.restoreChoose !== false
                    onClicked: root.wizard.actionRequested("restoreChoose", null)
                }
            }
            WizardCaption {
                visible: restore.state === "reviewing" && restore.changes.length > 0
                label: "Review before applying"
            }
            Repeater {
                model: restore.state === "reviewing" ? restore.changes : []
                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: 12
                    color: Theme.overlay
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                        spacing: 8
                        SetupText { Layout.fillWidth: true; text: modelData.title; textFormat: Text.PlainText; font.pixelSize: 11; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                        SetupText {
                            Layout.maximumWidth: parent.width * 0.6
                            text: modelData.from + "  →  " + modelData.to
                            textFormat: Text.PlainText; secondary: true
                            font.pixelSize: 11; elide: Text.ElideMiddle; wrapMode: Text.NoWrap
                        }
                    }
                }
            }
            SetupText {
                Layout.fillWidth: true
                visible: restore.state === "reviewing"
                secondary: true
                text: "Nothing changes until you apply. The Cider token, histories and the wallpaper never travel in this file."
            }
        }
    }

    Component {
        id: lookPage
        ColumnLayout {
            spacing: 8
            WizardRow {
                Layout.fillWidth: true
                title: "Colours"; detail: "Pistachio Noir, or Noir in greys with one red"; glyph: Icons.pipette
                control: WizardSegment {
                    objectName: "setup-colourScheme"
                    enabled: root.wizard.hasValue("colourScheme")
                    choices: [{value:"pistachio",title:"Pistachio Noir"}, {value:"noir",title:"Noir"}]
                    selected: root.wizard.values.colourScheme
                    onChosen: value => root.wizard.valueRequested("colourScheme", value)
                }
            }
            WizardRow {
                Layout.fillWidth: true
                title: "Frosted panels"; detail: "How see-through panels look"; glyph: Icons.layers
                control: WizardSegment {
                    objectName: "setup-frostStyle"
                    enabled: root.wizard.hasValue("frostStyle")
                    choices: [{value:"off",title:"Off"}, {value:"subtle",title:"Subtle"}, {value:"glassy",title:"Glassy"}]
                    selected: root.wizard.values.frostStyle
                    onChosen: value => root.wizard.valueRequested("frostStyle", value)
                }
            }
            WizardToggle { wizard: root.wizard; settingKey: "shadows"; title: "Drop shadows"; detail: "Soft shadows under panels"; glyph: Icons.layers }
            WizardToggle {
                visible: root.wizard.available.desktopIcons !== false
                wizard: root.wizard; settingKey: "desktopIcons"; title: "Desktop icons"; detail: "Show your Desktop folder on the wallpaper"; glyph: Icons.grid
            }
            WizardCaption { label: "Wallpaper" }
            SetupText {
                visible: !wallpapers.count
                Layout.fillWidth: true
                text: root.wizard.details.wallpaperEmpty || "No wallpapers available"; textFormat: Text.PlainText
                secondary: true
            }
            GridLayout {
                id: wallpaperGrid
                Layout.fillWidth: true
                columns: Math.max(1, Math.min(4, Math.floor(width / 126)))
                columnSpacing: 10
                rowSpacing: 8
                Repeater {
                    id: wallpapers
                    model: root.wizard.options.wallpaper || []
                    SetupButton {
                        id: tile
                        required property var modelData
                        objectName: "setup-wallpaper-" + index
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        Layout.preferredHeight: 96
                        active: root.wizard.values.wallpaper === modelData.value
                        padding: 0
                        enabled: root.wizard.available.wallpaper !== false && !modelData.disabled
                        text: modelData.title
                        Accessible.role: Accessible.RadioButton
                        Accessible.checked: active
                        onClicked: root.wizard.valueRequested("wallpaper", modelData.value)
                        background: Item {}
                        contentItem: ClippingRectangle {
                            radius: Math.max(0, Classic.tileRadius - 4)
                            color: tile.hovered ? Theme.overlay2 : Theme.overlay
                            border.width: tile.active || tile.visualFocus ? 2 : 1
                            border.color: tile.active ? Theme.textBright : tile.visualFocus ? Theme.subtext : Theme.overlay2
                            contentInsideBorder: true
                            Image {
                                anchors.fill: parent
                                source: tile.modelData.source || ""
                                asynchronous: true
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(270, 140)
                                opacity: status === Image.Ready ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Classic.motionDuration; easing.type: Theme.easing } }
                            }
                            Icon {
                                anchors.centerIn: parent
                                visible: !tile.modelData.source
                                size: 20; paths: Icons.image; color: Theme.subtext
                            }
                            Rectangle {
                                visible: tile.active
                                anchors.right: parent.right; anchors.rightMargin: 7
                                anchors.top: parent.top; anchors.topMargin: 7
                                width: 20; height: 20; radius: 10
                                color: Theme.pistachio
                                Icon { anchors.centerIn: parent; paths: Icons.check; size: 12; color: Theme.bg }
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom; width: parent.width; height: 25
                                color: Qt.rgba(Theme.deep.r, Theme.deep.g, Theme.deep.b, 0.88)
                                SetupText {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8; anchors.rightMargin: 8
                                    verticalAlignment: Text.AlignVCenter
                                    text: tile.text; textFormat: Text.PlainText
                                    wrapMode: Text.NoWrap; elide: Text.ElideRight
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: soundPage
        GridLayout {
            columns: width >= 452 ? 2 : 1
            columnSpacing: 8
            rowSpacing: 8
            WizardLevel {
                wizard: root.wizard
                settingKey: "outputLevel"; heading: "Output"; deviceKey: "outputDevice"
                detail: root.wizard.details.outputDevice || "No output device found"
            }
            WizardLevel {
                wizard: root.wizard
                settingKey: "inputLevel"; heading: "Input"; deviceKey: "inputDevice"
                detail: root.wizard.details.inputDevice || "No input device found"
            }
            WizardLevel {
                wizard: root.wizard
                settingKey: "brightness"; heading: "Brightness"
                detail: root.wizard.details.brightness || "Brightness unavailable"
            }
            WizardToggle {
                Layout.fillHeight: true
                Layout.preferredWidth: 0
                wizard: root.wizard
                settingKey: "nightLight"; title: "Night light"; glyph: Icons.moon
                detail: root.wizard.details.nightLight || ""
            }
        }
    }

    Component {
        id: notificationsPage
        ColumnLayout {
            spacing: 8
            WizardToggle { wizard: root.wizard; settingKey: "quietFullscreen"; title: "Quiet in fullscreen"; detail: "Toasts wait while a game or video is fullscreen"; glyph: Icons.monitor }
            WizardToggle { wizard: root.wizard; settingKey: "quietCalls"; title: "Quiet during calls"; detail: "No toast or sound while an app records your microphone"; glyph: Icons.mic }
            WizardToggle { wizard: root.wizard; settingKey: "notificationSound"; title: "Notification sound"; detail: "A short sound with each toast"; glyph: Icons.bell }
            WizardCaption { Layout.topMargin: 8; label: "Preview" }
            WizardRow {
                Layout.fillWidth: true
                title: "Pistachio Noir"; detail: "This is how a notification looks."; glyph: Icons.bell
                control: SetupButton {
                    objectName: "setup-play-sound"; text: "Play sound"
                    enabled: root.wizard.available.playNotificationSound !== false
                    onClicked: root.wizard.actionRequested("playNotificationSound", null)
                }
            }
        }
    }

    Component {
        id: connectionsPage
        ColumnLayout {
            spacing: 8
            WizardToggle {
                wizard: root.wizard; settingKey: "bluetooth"; title: "Bluetooth"
                detail: root.wizard.details.bluetooth || "Pair headphones, keyboards and speakers"; glyph: Icons.bluetooth
            }
            Repeater {
                model: root.wizard.devices
                WizardRow {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    implicitHeight: 42
                    title: modelData.title; detail: modelData.detail || ""
                    surface: Theme.bg
                    glyph: Icons.headphones
                }
            }
            WizardToggle {
                visible: root.wizard.available.localSend !== false
                wizard: root.wizard; settingKey: "localSend"; title: "LocalSend"
                detail: "Receive files from phones and computers. Off until you switch it on."; glyph: Icons.share
            }
            WizardRow {
                visible: root.wizard.available.localSend !== false && !!root.wizard.details.localSendName
                Layout.fillWidth: true
                implicitHeight: 44
                title: "Others see this computer as " + (root.wizard.details.localSendName || "")
                surface: Theme.bgAlt; border.color: Theme.overlay2
            }
            WizardRow {
                Layout.fillWidth: true
                title: "Ethernet"; detail: root.wizard.details.ethernet || "Wired status unavailable"; glyph: Icons.ethernet
            }
        }
    }

    Component {
        id: lensPage
        ColumnLayout {
            readonly property bool none: root.wizard.available.lensProvider === false
            spacing: 8
            WizardRow {
                objectName: "setup-lens-none"
                visible: none
                Layout.fillWidth: true
                title: "No assistant found"
                detail: root.wizard.details.lensNone || "Lens and the quick chat use Claude Code or Codex CLI. Neither is installed, so there is nothing to pick yet. Once one is, choose it in Settings → Lens and AI."
                glyph: Icons.info
            }
            WizardRow {
                visible: !none
                Layout.fillWidth: true
                title: "Preferred provider"; detail: "Pistachio Lens asks this one first"; glyph: Icons.sparkles
                control: WizardSegment {
                    objectName: "setup-lensProvider"
                    choices: root.wizard.options.lensProvider || []
                    selected: root.wizard.values.lensProvider
                    onChosen: value => root.wizard.valueRequested("lensProvider", value)
                }
            }
            RowLayout {
                visible: !none
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: root.wizard.options.lensProvider || []
                    WizardRow {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        implicitHeight: 52
                        title: modelData.value === "codex" ? "Codex CLI" : "Claude Code"
                        detail: modelData.subtitle || ""
                        glyph: modelData.disabled ? Icons.info : Icons.check
                        surface: Theme.bgAlt; border.color: Theme.overlay2
                    }
                }
            }
            RowLayout {
                visible: !none
                Layout.fillWidth: true
                spacing: 8
                WizardRow {
                    Layout.fillWidth: true; Layout.preferredWidth: 0
                    title: "Model"
                    control: WizardChoice { wizard: root.wizard; settingKey: "lensModel"; label: "Model"; width: 140 }
                }
                WizardRow {
                    Layout.fillWidth: true; Layout.preferredWidth: 0
                    title: "Effort"
                    control: WizardChoice { wizard: root.wizard; settingKey: "lensEffort"; label: "Effort"; width: 112 }
                }
            }
            WizardToggle {
                visible: !none
                wizard: root.wizard
                settingKey: "lensFallback"
                title: root.wizard.values.lensProvider === "codex" ? "Fall back to Claude" : "Fall back to ChatGPT"
                detail: root.wizard.details.lensFallback || ""
                glyph: Icons.layers
            }
            SetupText {
                Layout.fillWidth: true
                visible: !none && text !== ""
                text: root.wizard.details.lensArchive || ""; textFormat: Text.PlainText; secondary: true
            }
        }
    }

    Component {
        id: placesPage
        ColumnLayout {
            spacing: 8
            WizardRow {
                Layout.fillWidth: true
                title: "Terminal"; detail: root.wizard.details.terminal || ""; glyph: Icons.terminal
                control: WizardChoice { wizard: root.wizard; settingKey: "terminal"; label: "Terminal" }
            }
            WizardRow {
                Layout.fillWidth: true
                title: "Weather location"
                detail: root.wizard.details.weather || "Only the city’s coordinates are sent, every 30 minutes."
                glyph: Icons.mapPin
                control: Basic.TextField {
                    id: city
                    objectName: "setup-weatherLocation"
                    width: 170; height: 44
                    topPadding: 3; bottomPadding: 3; leftPadding: 12; rightPadding: 12
                    text: root.wizard.values.weatherLocation || ""
                    placeholderText: "City"
                    placeholderTextColor: Theme.subtext
                    selectByMouse: true
                    enabled: root.wizard.hasValue("weatherLocation")
                    color: Theme.textBright
                    font.family: Classic.fontUi; font.pixelSize: 12
                    Accessible.name: "Weather location"
                    function submit() {
                        if (text.trim()) root.wizard.valueRequested("weatherLocation", text.trim());
                    }
                    Keys.onReturnPressed: event => { event.accepted = true; submit(); }
                    Keys.onEnterPressed: event => { event.accepted = true; submit(); }
                    background: Rectangle {
                        color: Theme.bgAlt; radius: Classic.tileRadius
                        border.color: parent.activeFocus ? Theme.subtext : Theme.overlay2
                    }
                }
            }
            // fixed folders, shown as text (owner's call, 19 November 2026)
            WizardRow {
                Layout.fillWidth: true
                title: "Wallpapers"; detail: root.wizard.details.wallpaperFolder || ""; glyph: Icons.folder
            }
            WizardRow {
                Layout.fillWidth: true
                title: "Screenshots"; detail: root.wizard.details.screenshotFolder || ""; glyph: Icons.crop
            }
        }
    }

    Component {
        id: donePage
        ColumnLayout {
            spacing: 8
            GridLayout {
                Layout.fillWidth: true
                columns: width >= 450 ? 2 : 1
                columnSpacing: 8
                rowSpacing: 8
                WizardRecap { heading: "You chose"; items: root.wizard.summary }
                WizardRecap {
                    objectName: "setup-keys"
                    heading: "Bind keys to psc"
                    items: root.wizard.shortcuts
                    mono: true
                    footnote: root.wizard.details.bindTip || ""
                }
            }
            Rectangle {
                objectName: "setup-psc-guide"
                visible: root.wizard.commands.length > 0
                Layout.fillWidth: true
                implicitHeight: guide.implicitHeight + 24
                color: Theme.overlay; radius: Classic.tileRadius
                ColumnLayout {
                    id: guide
                    anchors.fill: parent; anchors.margins: 12
                    spacing: 6
                    SetupText { text: "psc in a terminal"; font.weight: Font.ExtraBold }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: width >= 560 ? 3 : width >= 360 ? 2 : 1
                        columnSpacing: 12
                        rowSpacing: 6
                        Repeater {
                            model: root.wizard.commands
                            ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                spacing: 0
                                SetupText { Layout.fillWidth: true; text: modelData.command; textFormat: Text.PlainText; font.family: Classic.fontMono; font.pixelSize: 11; wrapMode: Text.NoWrap; elide: Text.ElideRight }
                                SetupText { Layout.fillWidth: true; text: modelData.detail; textFormat: Text.PlainText; secondary: true; font.pixelSize: 10; wrapMode: Text.NoWrap; elide: Text.ElideRight }
                            }
                        }
                    }
                }
            }
        }
    }
}
