import qs
import qs.components
import Quickshell
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var wizard
    readonly property bool checking: wizard.checkState === "idle" || wizard.checkState === "checking"
    readonly property bool attention: wizard.checkState === "attention"
    readonly property int passed: wizard.checks.filter(item => item.status === "pass").length
    readonly property int checked: wizard.checks.filter(item => item.status !== "pending").length
    readonly property int total: Math.max(checked, wizard.checkTotal)
    spacing: 8
    function rank(item) { return ({conflict: 0, warning: 1, optional: 2})[item.status] ?? 3; }

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        visible: !root.attention
        spacing: 12
        Icon {
            paths: root.checking ? Icons.loader : Icons.check
            color: root.checking ? Theme.subtext : Theme.pistachio
            size: 16
            NumberAnimation on rotation {
                from: 0; to: 360; duration: 1300
                loops: Animation.Infinite
                running: root.checking && root.wizard.open && !root.wizard.reducedMotion
            }
        }
        SetupText {
            text: root.checking ? (root.total ? "Checking " + root.checked + " of " + root.total : "Checking…")
                                : root.passed + " of " + root.total + " passed"
        }
        Rectangle {
            visible: root.checking
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            radius: 3
            color: Theme.overlay
            Rectangle {
                width: root.total ? parent.width * root.checked / root.total : 0
                height: parent.height
                radius: parent.radius
                color: Theme.pistachio
                Behavior on width { NumberAnimation { duration: root.wizard.reducedMotion ? 0 : Classic.motionDuration; easing.type: Theme.easing } }
            }
        }
    }

    GridLayout {
        visible: !root.attention
        Layout.fillWidth: true
        columns: width >= 440 ? 2 : 1
        columnSpacing: 5
        rowSpacing: 5
        Repeater {
            // keyed, so a row that arrives fades in once and the rows before it stay put
            model: ScriptModel { values: root.wizard.checks; objectProp: "title" }
            Rectangle {
                id: checkRow
                required property var modelData
                opacity: root.wizard.reducedMotion ? 1 : 0
                scale: root.wizard.reducedMotion ? 1 : 0.97
                Component.onCompleted: if (!root.wizard.reducedMotion) arrive.start()
                ParallelAnimation {
                    id: arrive
                    NumberAnimation { target: checkRow; property: "opacity"; to: 1; duration: Classic.motionDuration; easing.type: Theme.easing }
                    NumberAnimation { target: checkRow; property: "scale"; to: 1; duration: Classic.motionDuration; easing.type: Theme.easing }
                }
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                Layout.preferredHeight: 38
                radius: 12
                color: Theme.overlay
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                    spacing: 7
                    Icon {
                        size: 14
                        paths: modelData.status === "pass" ? Icons.check : modelData.status === "pending" ? Icons.clock : Icons.info
                        color: modelData.status === "pass" ? Theme.pistachio : Theme.subtext
                    }
                    SetupText {
                        Layout.fillWidth: true
                        text: modelData.title
                        textFormat: Text.PlainText
                        wrapMode: Text.NoWrap; elide: Text.ElideRight
                        font.pixelSize: 11
                    }
                    SetupText {
                        Layout.maximumWidth: parent.width * 0.54
                        text: modelData.detail || ""
                        textFormat: Text.PlainText
                        wrapMode: Text.NoWrap; elide: Text.ElideRight
                        secondary: true; font.pixelSize: 11
                    }
                }
            }
        }
    }

    Repeater {
        // conflicts first, then what is required, then optional tools; installs show the package name only
        model: root.attention ? root.wizard.checks.filter(item => item.status !== "pass" && item.status !== "pending")
            .sort((a, b) => root.rank(a) - root.rank(b)) : []
        Rectangle {
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: report.implicitHeight + 24
            radius: Classic.tileRadius
            color: Theme.overlay
            RowLayout {
                id: report
                anchors.fill: parent; anchors.margins: 12
                spacing: 12
                Icon {
                    Layout.alignment: Qt.AlignTop
                    size: 20; paths: Icons.triangleAlert
                    color: modelData.status === "conflict" ? Theme.terracotta : Theme.gold
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    RowLayout {
                        Layout.fillWidth: true
                        SetupText { text: modelData.title; textFormat: Text.PlainText; Layout.fillWidth: true }
                        SetupText {
                            text: modelData.status === "conflict" ? "Conflict" : modelData.status === "optional" ? "Optional" : "Required"
                            color: modelData.status === "conflict" ? Theme.terracotta : Theme.gold
                            font.pixelSize: 11
                        }
                    }
                    SetupText { text: modelData.detail || ""; textFormat: Text.PlainText; secondary: true; Layout.fillWidth: true }
                    SetupText {
                        Layout.fillWidth: true
                        visible: !!modelData.command || !!modelData.package
                        text: modelData.command ? "$ " + modelData.command : modelData.package ? "Package: " + modelData.package : ""
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAnywhere
                        font.family: Classic.fontMono; font.pixelSize: 11
                    }
                }
                SetupButton {
                    objectName: "setup-copy-command"
                    visible: !!modelData.command || !!modelData.package
                    Layout.preferredWidth: 44
                    glyph: Icons.copy
                    Accessible.name: modelData.command ? "Copy command" : "Copy package name"
                    onClicked: root.wizard.actionRequested("copyCommand", modelData.command || modelData.package)
                }
            }
        }
    }
    WizardRow {
        visible: root.attention
        Layout.fillWidth: true
        title: root.passed + " checks passed"
        detail: root.wizard.checkNote
        glyph: Icons.check
        surface: Theme.bgAlt
        border.color: Theme.overlay2
    }
}
