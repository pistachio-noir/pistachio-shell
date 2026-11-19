import qs
import QtQuick

Row {
    id: root
    required property var choices
    property var selected
    signal chosen(var value)

    spacing: 2
    Repeater {
        model: root.choices
        SetupButton {
            required property var modelData
            objectName: "setup-option-" + modelData.value
            text: modelData.title
            active: root.selected === modelData.value
            quiet: !active
            enabled: !modelData.disabled
            leftPadding: 12
            rightPadding: 12
            implicitWidth: Math.max(44, contentItem.implicitWidth + leftPadding + rightPadding)
            onClicked: root.chosen(modelData.value)
            Accessible.role: Accessible.RadioButton
            Accessible.checked: active
        }
    }
}
