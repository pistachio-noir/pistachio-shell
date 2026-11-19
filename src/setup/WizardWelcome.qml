import qs
import qs.components
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Flickable {
    id: root
    required property var wizard
    contentWidth: width
    contentHeight: content.y + content.height + 20
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    ColumnLayout {
        id: content
        width: Math.min(root.width - 32, 736)
        x: (root.width - width) / 2
        y: Math.max(20, (root.height - height) * 0.42)
        spacing: 0

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 92
            Layout.preferredHeight: 92
            RectangularShadow {
                anchors.fill: emblem; anchors.margins: 8 * emblem.k
                radius: 56 * emblem.k; blur: 44; offset.y: 18
                color: Qt.rgba(Theme.shadow.r, Theme.shadow.g, Theme.shadow.b, Theme.shadowPanel.alpha)
            }
            ShellLogo { id: emblem; anchors.fill: parent; size: 92 }
        }

        SetupText {
            Layout.topMargin: 20
            Layout.alignment: Qt.AlignHCenter
            text: "FIRST RUN"; secondary: true
            font.pixelSize: 11; font.letterSpacing: 0.7
        }
        SetupText {
            Layout.fillWidth: true
            Layout.topMargin: 4
            text: "Welcome to Pistachio Noir"
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: root.width < 680 ? 32 : root.width < 1000 ? 40 : 46
            lineHeightMode: Text.ProportionalHeight; lineHeight: 1 // TUI's fixed 20 px lines are for body text
            font.weight: Font.ExtraBold
        }
        SetupText {
            Layout.topMargin: 10
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(content.width, 470)
            text: "A calm, dark desktop shell for Hyprland. We will check what is installed, then set up the basics together."
            horizontalAlignment: Text.AlignHCenter
            secondary: true
            font.pixelSize: 15
            lineHeightMode: Text.ProportionalHeight; lineHeight: 1.35
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.topMargin: 30
            columns: content.width >= 560 ? 3 : 1
            columnSpacing: 14
            rowSpacing: 8
            Repeater {
                model: [
                    {title: "Check", detail: "Make sure everything the shell needs is installed.", icon: Icons.check},
                    {title: "Make it yours", detail: "Pick a look, sound and notification habits.", icon: Icons.sliders},
                    {title: "Connect", detail: "Bluetooth, LocalSend and Pistachio Lens.", icon: Icons.share}
                ]
                WizardRow {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.minimumHeight: content.width >= 560 ? 92 : 56
                    title: modelData.title
                    detail: modelData.detail
                    glyph: modelData.icon
                    surface: Theme.bgAlt
                    border.color: Theme.overlay2
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 30
            spacing: 10
            SetupButton { objectName: "setup-start"; text: "Get started"; active: true; onClicked: root.wizard.startChecks() }
            SetupButton {
                objectName: "setup-restore"
                visible: root.wizard.available.restore !== false
                text: "Restore my settings"
                onClicked: root.wizard.startRestore()
            }
            SetupButton { objectName: "setup-welcome-skip"; text: "Skip setup"; quiet: true; onClicked: root.wizard.showSkip() }
        }
        SetupText {
            Layout.fillWidth: true
            Layout.topMargin: 14
            text: "About two minutes. You can change everything later in Settings."
            horizontalAlignment: Text.AlignHCenter
            secondary: true
        }
    }
}
