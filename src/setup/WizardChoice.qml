import qs
import QtQuick

// A drop-down for one setting, its choices from `wizard.options[settingKey]`.
SetupChoice {
    id: root
    required property var wizard
    required property string settingKey
    required property string label
    objectName: "setup-" + settingKey
    Accessible.name: label
    choices: wizard.options[settingKey] || []
    selected: wizard.values[settingKey]
    enabled: choices.length > 0 && wizard.available[settingKey] !== false
    onChosen: value => wizard.valueRequested(settingKey, value)
}
