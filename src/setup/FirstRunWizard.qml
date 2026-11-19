import qs
import qs.components
import qs.setup
import QtQuick
import QtQuick.Controls.Basic as Basic
import QtQuick.Effects
import QtQuick.Layouts

// The first-run setup view (boards design/FirstRun/; contract docs/first-run-frontend.md). It only
// shows its inputs and sends signals: SetupController.qml wires it to the shell's services.
FocusScope {
    id: root

    property bool open
    property bool reducedMotion
    property string checkState: "idle"
    property var checks: []
    property int checkTotal: checks.length
    property string checkNote
    property var values: ({})
    property var options: ({})
    property var details: ({})
    property var available: ({})
    property var devices: []
    property var summary: []
    property var shortcuts: []
    property var commands: []
    // Restore my settings: { state: idle|busy|reviewing|missing|error, path, message, changes: [{title, from, to}], skipped }
    property var restore: ({ state: "idle", changes: [] })
    property string errorMessage

    signal checkRequested()
    signal valueRequested(string key, var value)
    signal actionRequested(string action, var payload)
    signal finished(string destination)

    // "full" walks every page; "restore" brings back a Settings export, checks, and is done
    readonly property string mode: navigation.mode
    readonly property var flow: mode === "restore" ? ["welcome", "restore", "check", "done"]
        : ["welcome", "check", "look", "sound", "notifications", "connections", "lens", "places", "done"]
    readonly property int page: navigation.index
    readonly property string pageId: flow[page] ?? "welcome"
    readonly property var titles: ({ restore: "Restore", check: "Check", look: "Look", sound: "Sound & display",
        notifications: "Notifications", connections: "Connections", lens: "Lens", places: "Places", done: "All set" })
    readonly property var steps: flow.slice(1).map(id => titles[id])
    readonly property bool confirmingSkip: skipDialog.visible
    readonly property bool shown: open || reveal > 0
    readonly property bool awaitingCheck: pageId === "check" && (checkState === "idle" || checkState === "checking")
    readonly property bool restoreReady: restore.state === "reviewing"
    readonly property string heading: pageId === "check"
        ? checkState === "clear" ? "Everything is installed" : checkState === "attention" ? "Almost there" : "Checking your system"
        : pageId === "restore" ? (restoreReady ? "Review your settings" : "Restore my settings")
        : ({ look: "Pick your look", sound: "Sound and display", notifications: "Notifications", connections: "Connections",
             lens: "Pistachio Lens", places: "Apps and places", done: "You are all set" })[pageId] ?? ""
    readonly property string description: pageId === "check"
        ? checkState === "clear" ? "Your system has what the shell needs. Nothing was changed."
            : checkState === "attention" ? "The shell starts without these, but a few features stay off."
            : "Looking for the programs the shell talks to. Nothing is changed."
        : pageId === "restore" ? "Bring back what you saved with Settings → About → Export. You see every change before it applies."
        : ({ look: "These apply at once, so the desktop behind this window changes as you choose.",
             sound: "Choose where sound goes and how bright the screen is. The shell remembers it.",
             notifications: "The shell shows its own notifications, so you can pick when they stay quiet.",
             connections: "Turn on what you use. Both can wait until later.",
             lens: "Ask about anything on your screen. It uses a command-line tool you already have.",
             places: "Where the shell opens things and finds your pictures.",
             done: mode === "restore" ? "Your settings are back. Everything else keeps its defaults." : "The shell is ready. Your choices are saved." })[pageId] ?? ""

    property real reveal: open ? 1 : 0
    property real panelReveal: page > 0 ? 1 : 0
    visible: shown
    opacity: reveal
    focus: true
    Keys.enabled: open && !confirmingSkip

    QtObject { id: navigation; property int index; property int direction: 1; property string mode: "full" }
    function hasValue(key) {
        return available[key] !== false && values[key] !== undefined && values[key] !== null;
    }
    function goTo(next) {
        if (next < 0 || next >= flow.length || next === page) return;
        navigation.direction = next > page ? 1 : -1;
        navigation.index = next;
        Qt.callLater(focusPage);
    }
    function goToPage(id) { goTo(flow.indexOf(id)); }
    function startChecks() {
        navigation.mode = "full";
        goToPage("check");
        checkRequested();
    }
    function startRestore() {
        navigation.mode = "restore";
        goToPage("restore");
        actionRequested("restoreReview", null);
    }
    function back() {
        if (pageId === "restore") {
            actionRequested("restoreCancel", null);
            goTo(0);
            navigation.mode = "full";
        } else {
            goTo(page - 1);
        }
    }
    // Continue: the footer's main button and Enter
    function advance() {
        if (pageId === "done") finished("shell");
        else if (pageId === "check" && checkState === "attention") checkRequested();
        else if (pageId === "restore") {
            if (!restoreReady) return;
            if (restore.changes.length) actionRequested("restoreApply", null);
            goToPage("check");
            checkRequested();
        } else if (!awaitingCheck) goTo(page + 1);
    }
    function focusPage() {
        if (!open || confirmingSkip) return;
        if (page === 0) welcome.forceActiveFocus();
        else pageFocus.forceActiveFocus();
    }
    function showSkip() {
        if (open) skipDialog.open();
    }
    Keys.onEscapePressed: showSkip()
    Keys.onReturnPressed: event => {
        if (page === 0) startChecks();
        else if (pageId !== "done" && !(pageId === "check" && checkState === "attention")) advance();
        else event.accepted = false;
    }

    onOpenChanged: {
        if (open) {
            navigation.index = 0;
            navigation.mode = "full";
            Qt.callLater(focusPage);
        } else {
            skipDialog.close();
        }
    }
    Behavior on reveal {
        enabled: !root.reducedMotion
        NumberAnimation { duration: Classic.motionDuration; easing.type: Theme.easing }
    }
    Behavior on panelReveal {
        enabled: !root.reducedMotion
        NumberAnimation { duration: Classic.motionDuration * 1.5; easing.type: Theme.easing }
    }

    WizardBackdrop {
        anchors.fill: parent
        visible: root.panelReveal < 1
        opacity: 1 - root.panelReveal
        welcome: true
        activeMotion: root.open && !root.reducedMotion && root.page === 0
    }

    WizardWelcome {
        id: welcome
        anchors.fill: parent
        visible: root.panelReveal < 1
        enabled: root.page === 0
        opacity: 1 - root.panelReveal
        scale: 1 - root.panelReveal * 0.03
        wizard: root
    }

    // the welcome page moves the window from its top edge
    MouseArea {
        visible: root.page === 0
        width: parent.width; height: 56
        onPressed: root.moveRequested()
    }

    Item {
        id: panel
        objectName: "setup-panel"
        anchors.fill: parent
        visible: root.page > 0 || root.panelReveal > 0
        enabled: root.page > 0
        opacity: root.panelReveal
        scale: 0.98 + root.panelReveal * 0.02

        Rectangle { anchors.fill: parent; color: Theme.bgAlt }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                id: sidebar
                visible: panel.width >= 620
                Layout.preferredWidth: 231
                Layout.fillHeight: true
                color: Theme.bg
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.overlay2 }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16; anchors.rightMargin: 16
                    anchors.topMargin: 23; anchors.bottomMargin: 20
                    spacing: Math.min(6, Math.max(0, (sidebar.height - 385) / 11))

                    RowLayout {
                        Layout.leftMargin: 4; Layout.bottomMargin: 12
                        spacing: 12
                        ShellLogo { size: 36 }
                        Column {
                            SetupText { text: "Pistachio Noir"; font.weight: Font.ExtraBold }
                            SetupText { text: root.mode === "restore" ? "Restore settings" : "First-run setup"; secondary: true; font.pixelSize: 11 }
                        }
                    }

                    Repeater {
                        model: root.steps
                        Rectangle {
                            id: step
                            required property string modelData
                            required property int index
                            readonly property bool selected: root.page === index + 1
                            readonly property bool completed: root.page > index + 1
                            readonly property bool last: index === root.steps.length - 1
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(40, Math.max(22, (sidebar.height - 119) / 8))
                            radius: Classic.tileRadius
                            color: selected ? Theme.overlay : "transparent"
                            Behavior on color { ColorAnimation { duration: root.reducedMotion ? 0 : Classic.hoverDuration; easing.type: Theme.easing } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                spacing: 10
                                Rectangle {
                                    Layout.preferredWidth: 22; Layout.preferredHeight: 22
                                    color: step.selected ? Theme.pistachio : Theme.overlay
                                    radius: 11
                                    scale: step.selected ? 1 : 0.92
                                    Behavior on color { ColorAnimation { duration: root.reducedMotion ? 0 : Classic.motionDuration; easing.type: Theme.easing } }
                                    Behavior on scale { NumberAnimation { duration: root.reducedMotion ? 0 : Classic.motionDuration; easing.type: Easing.OutBack } }
                                    Icon {
                                        anchors.centerIn: parent; size: 12; paths: Icons.check
                                        visible: step.completed || (step.last && !step.selected); color: step.selected ? Theme.bg : Theme.subtext
                                    }
                                    SetupText {
                                        anchors.centerIn: parent
                                        visible: !step.completed && !(step.last && !step.selected)
                                        text: step.last ? "✓" : String(step.index + 1)
                                        color: step.selected ? Theme.bg : Theme.subtext
                                        font.pixelSize: 10
                                    }
                                }
                                SetupText {
                                    Layout.fillWidth: true
                                    text: step.modelData
                                    secondary: !step.selected
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                    SetupText {
                        Layout.fillWidth: true
                        visible: sidebar.height >= 445
                        text: "About two minutes. Skip anything you like."
                        secondary: true; font.pixelSize: 11
                    }
                }
            }

            FocusScope {
                id: pageFocus
                Layout.fillWidth: true; Layout.fillHeight: true
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(header.implicitHeight + 24, 96)
                        // the window moves from its header, as Settings does
                        MouseArea { anchors.fill: parent; onPressed: root.moveRequested() }
                        ColumnLayout {
                            id: header
                            anchors.top: parent.top; anchors.topMargin: 23
                            anchors.left: parent.left; anchors.leftMargin: 27
                            anchors.right: parent.right; anchors.rightMargin: skip.width + 38
                            spacing: 2
                            SetupText {
                                text: root.pageId === "done" ? "ALL DONE" : "STEP " + root.page + " OF " + (root.flow.length - 2)
                                secondary: true
                                font.pixelSize: 11; font.letterSpacing: 0.7
                            }
                            SetupText {
                                Layout.fillWidth: true
                                text: root.heading; font.pixelSize: 22; font.weight: Font.ExtraBold
                                Accessible.role: Accessible.Heading
                            }
                            SetupText {
                                Layout.fillWidth: true
                                text: root.description; secondary: true
                            }
                        }
                        SetupButton {
                            id: skip
                            objectName: "setup-skip"
                            visible: root.pageId !== "done"
                            anchors.top: parent.top; anchors.topMargin: 18
                            anchors.right: parent.right; anchors.rightMargin: 18
                            text: "Skip setup"; quiet: true
                            onClicked: root.showSkip()
                        }
                    }

                    Basic.ScrollView {
                        id: scroller
                        Layout.fillWidth: true; Layout.fillHeight: true
                        Layout.topMargin: 13
                        Layout.bottomMargin: 8
                        Layout.leftMargin: 27; Layout.rightMargin: 27
                        clip: true
                        contentWidth: availableWidth
                        Flickable {
                            id: scroll
                            contentWidth: width
                            contentHeight: pages.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            WizardPages {
                                id: pages
                                width: scroll.width
                                wizard: root
                                transform: Translate { id: pageOffset }
                            }
                        }
                    }

                    SetupText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 27; Layout.rightMargin: 27; Layout.bottomMargin: 6
                        visible: text !== ""
                        text: root.errorMessage; textFormat: Text.PlainText
                        color: Theme.terracotta; font.pixelSize: 11
                        Accessible.role: Accessible.AlertMessage
                    }

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.overlay2 }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 71
                        Layout.leftMargin: 19; Layout.rightMargin: 19
                        spacing: 8
                        SetupButton { text: "Back"; objectName: "setup-back"; onClicked: root.back() }
                        SetupText {
                            Layout.fillWidth: true
                            secondary: true
                            textFormat: Text.PlainText
                            elide: Text.ElideRight; wrapMode: Text.NoWrap
                            text: root.awaitingCheck ? "This takes a few seconds" :
                                root.pageId === "check" && root.checkState === "clear" ? root.checkNote : ""
                        }
                        SetupButton {
                            visible: root.pageId === "check" && root.checkState === "attention"
                            text: "Continue anyway"
                            objectName: "setup-continue-anyway"
                            onClicked: root.goTo(root.page + 1)
                        }
                        SetupButton {
                            visible: root.pageId === "done"
                            text: "Open settings"
                            objectName: "setup-open-settings"
                            onClicked: root.finished("settings")
                        }
                        SetupButton {
                            objectName: root.pageId === "check" && root.checkState === "attention" ? "setup-retry" : "setup-continue"
                            text: root.pageId === "done" ? "Open the shell"
                                : root.pageId === "check" && root.checkState === "attention" ? "Check again"
                                : root.pageId === "restore" && root.restoreReady && root.restore.changes.length
                                    ? "Apply " + root.restore.changes.length + (root.restore.changes.length === 1 ? " setting" : " settings")
                                : "Continue"
                            active: enabled
                            enabled: !root.awaitingCheck && (root.pageId !== "restore" || root.restoreReady)
                            onClicked: root.advance()
                        }
                    }
                }
            }
        }
    }

    signal moveRequested()

    ParallelAnimation {
        id: pageEntry
        NumberAnimation { target: pages; property: "opacity"; from: 0; to: 1; duration: Classic.motionDuration; easing.type: Theme.easing }
        NumberAnimation {
            target: pageOffset; property: "x"; from: navigation.direction * 24; to: 0
            duration: Classic.motionDuration * 1.2; easing.type: Theme.easing
        }
    }
    onPageChanged: {
        scroll.contentY = 0;
        if (!reducedMotion && page > 0) pageEntry.restart();
    }
    onReducedMotionChanged: {
        if (!reducedMotion) return;
        pageEntry.stop();
        pages.opacity = 1;
        pageOffset.x = 0;
    }

    Basic.Popup {
        id: skipDialog
        parent: root
        anchors.centerIn: parent
        width: Math.min(440, root.width - 32)
        padding: 24
        modal: true
        focus: true
        closePolicy: Basic.Popup.CloseOnEscape
        Basic.Overlay.modal: Rectangle { color: Qt.rgba(Theme.deep.r, Theme.deep.g, Theme.deep.b, 0.66) }
        onOpened: keepSettingUp.forceActiveFocus()
        onClosed: Qt.callLater(root.focusPage)
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: root.reducedMotion ? 0 : Classic.motionDuration; easing.type: Theme.easing }
                NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: root.reducedMotion ? 0 : Classic.motionDuration; easing.type: Theme.easing }
            }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: root.reducedMotion ? 0 : Classic.hoverDuration; easing.type: Theme.easing }
        }
        background: Rectangle { radius: Classic.panelRadius; color: Theme.bgAlt; border.color: Theme.overlay2 }
        contentItem: ColumnLayout {
            spacing: 12
            RowLayout {
                spacing: 10
                Icon { paths: Icons.info; color: Theme.gold; size: 20 }
                SetupText { text: "Skip setup?"; font.pixelSize: 20; font.weight: Font.ExtraBold }
            }
            SetupText {
                Layout.fillWidth: true
                secondary: true
                text: "The shell works with its defaults. You can run setup again from the terminal with psc setup, or change anything in Settings."
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                Layout.topMargin: 5
                SetupButton {
                    text: "Skip for now"
                    objectName: "setup-confirm-skip"
                    onClicked: { skipDialog.close(); root.finished("skip"); }
                }
                SetupButton {
                    id: keepSettingUp
                    text: "Keep setting up"
                    objectName: "setup-cancel-skip"
                    active: true
                    onClicked: skipDialog.close()
                }
            }
        }
    }
}
