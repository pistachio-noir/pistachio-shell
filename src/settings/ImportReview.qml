import qs
import qs.services
import QtQuick

// The import's review on About (owner's call, 15 November 2026), like the page reset's: what the file
// would change (old → new), what it skipped and why, then Apply or Cancel. Nothing changes before Apply.
Rectangle {
    id: root
    objectName: "settings-import-review"
    height: body.implicitHeight + 36
    radius: Theme.tui ? 0 : Theme.tileRadius
    color: Theme.overlay

    Column {
        id: body
        x: 18
        y: 18
        width: parent.width - 36
        spacing: 10

        SettingsText { text: "Review import"; font.weight: Font.Bold }
        SettingsText {
            width: parent.width
            secondary: true
            text: Preferences.changes.length ? `From ${Preferences.shownPath}, these settings would change:` : "Your settings already match the file."
        }
        Repeater {
            model: Preferences.changes
            SettingsText {
                required property var modelData
                width: body.width
                text: `${modelData.title}: ${modelData.from} → ${modelData.to}`
                font.pixelSize: Theme.tui ? Theme.tuiTextSize : 12
            }
        }
        SettingsText {
            visible: Preferences.skipped.length > 0
            width: parent.width
            text: "Skipped (left as they are):"
            secondary: true
        }
        Repeater {
            model: Preferences.skipped
            SettingsText {
                required property var modelData
                width: body.width
                text: `${modelData.key}: ${modelData.reason}`
                secondary: true
                font.pixelSize: Theme.tui ? Theme.tuiTextSize : 12
            }
        }
        SettingsText {
            width: parent.width
            text: "Tokens, pairings, known devices and history aren't in the file and stay as they are."
            secondary: true
            font.pixelSize: Theme.tui ? Theme.tuiTextSize : 11
        }
        Row {
            spacing: 8
            SettingsButton { objectName: "import-cancel"; text: "Cancel"; onClicked: Preferences.cancel() }
            SettingsButton { objectName: "import-apply"; text: "Apply"; enabled: Preferences.changes.length > 0 && Store.ready; onClicked: Preferences.apply() }
        }
    }
}
