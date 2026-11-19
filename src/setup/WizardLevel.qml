import qs
import qs.components
import QtQuick
import QtQuick.Layouts

// A level card on Sound and display: a slider in [0, 1], and the device it belongs to.
Rectangle {
    id: card
    required property var wizard
    required property string settingKey
    required property string heading
    required property string detail
    property string deviceKey
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.preferredWidth: 0
    radius: Classic.tileRadius
    color: Theme.overlay
    implicitHeight: levelContent.implicitHeight + 28

    ColumnLayout {
        id: levelContent
        anchors.fill: parent; anchors.margins: 14
        spacing: 5
        RowLayout {
            Layout.fillWidth: true
            SetupText { Layout.fillWidth: true; text: card.heading }
            SetupText {
                text: level.enabled ? Math.round(level.shownValue * 100) + "%" : "—"
                font.family: Classic.fontMono
                secondary: true
            }
        }
        SetupText { Layout.fillWidth: true; text: card.detail; textFormat: Text.PlainText; secondary: true; elide: Text.ElideRight; wrapMode: Text.NoWrap }
        SetupSlider {
            id: level
            objectName: "setup-" + card.settingKey
            Layout.fillWidth: true
            Accessible.name: card.heading
            from: 0; to: 1
            value: card.wizard.values[card.settingKey] ?? 0
            enabled: card.wizard.hasValue(card.settingKey)
            onMoved: if (!pressed) card.wizard.valueRequested(card.settingKey, value)
            onPressedChanged: if (!pressed && Math.abs(value - (card.wizard.values[card.settingKey] ?? 0)) > 0.001)
                card.wizard.valueRequested(card.settingKey, value)
        }
        WizardChoice {
            visible: !!card.deviceKey
            Layout.fillWidth: true
            wizard: card.wizard
            settingKey: card.deviceKey || "none"
            label: card.heading + " device"
        }
        Item { Layout.fillHeight: true }
    }
}
