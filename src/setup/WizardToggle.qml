import qs
import qs.components
import QtQuick
import QtQuick.Layouts

// A wizard row with a switch for one boolean setting: the view sends the request, the controller
// answers with the new value in `wizard.values`.
WizardRow {
    id: root
    required property var wizard
    required property string settingKey
    Layout.fillWidth: true
    control: SetupSwitch {
        objectName: "setup-" + root.settingKey
        checked: !!root.wizard.values[root.settingKey]
        enabled: root.wizard.hasValue(root.settingKey)
        opacity: enabled ? 1 : 0.5
        activeFocusOnTab: true
        Accessible.name: root.title
        onToggled: root.wizard.valueRequested(root.settingKey, !checked)
        Keys.onSpacePressed: toggled()
        Accessible.onPressAction: toggled()
        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            radius: Classic.tileRadius
            visible: parent.activeFocus
            color: "transparent"
            border.color: Theme.subtext
        }
    }
}
