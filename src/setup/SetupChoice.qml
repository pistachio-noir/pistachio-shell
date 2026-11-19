import qs
import qs.components
import QtQuick
import QtQuick.Controls.Basic as Basic

// SettingsChoice in the Classic look only (Classic.qml): a drop-down of {value, title, subtitle?, disabled?}.
Basic.ComboBox {
    id: root
    property var choices: []
    property var selected
    signal chosen(var value)
    model: choices
    textRole: "title"
    valueRole: "value"
    currentIndex: choices.findIndex(c => c.value === selected)
    onActivated: index => { if (choices[index]) chosen(choices[index].value); }
    implicitHeight: 44
    implicitWidth: 152
    leftPadding: 14
    rightPadding: 34
    font.family: Classic.fontUi
    font.pixelSize: 12
    font.weight: Font.Bold
    background: Rectangle {
        radius: Classic.tileRadius
        color: root.hovered ? Theme.overlay2 : Theme.bgAlt
        border.width: 1
        border.color: root.visualFocus ? Theme.subtext : Theme.overlay2
        Behavior on color { ColorAnimation { duration: Classic.hoverDuration; easing.type: Theme.easing } }
    }
    contentItem: Text {
        text: root.displayText || "None available"
        font: root.font
        color: Theme.textBright
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Icon {
        x: root.width - width - 12
        y: (root.height - height) / 2
        size: 16
        paths: Icons.chevronDown
        color: Theme.subtext
        rotation: root.popup.visible ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: Classic.motionDuration; easing.type: Theme.easing } }
    }
    delegate: Basic.ItemDelegate {
        id: option
        required property var modelData
        required property int index
        width: root.popup.width - 14
        height: modelData.subtitle ? 60 : 48
        enabled: !modelData.disabled
        highlighted: root.highlightedIndex === index
        background: Rectangle { radius: 16; color: parent.highlighted || root.selected === option.modelData.value ? Theme.overlay : "transparent" }
        contentItem: Item {
            Column {
                anchors.left: parent.left; anchors.right: check.left; anchors.verticalCenter: parent.verticalCenter
                SetupText { width: parent.width; text: option.modelData.title; font.pixelSize: 12; color: option.modelData.disabled ? Theme.subtext : Theme.textBright; elide: Text.ElideRight; maximumLineCount: 1 }
                SetupText { width: parent.width; visible: text !== ""; text: option.modelData.subtitle || ""; secondary: true; font.pixelSize: 11; maximumLineCount: 1; elide: Text.ElideRight }
            }
            Icon { id: check; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; size: 16; paths: Icons.check; color: Theme.pistachio; visible: root.selected === option.modelData.value }
        }
    }
    popup: Basic.Popup {
        x: Math.min(0, root.width - width)
        y: root.height + 6
        margins: 8
        width: Math.max(root.width, 230)
        height: Math.min(contentItem.implicitHeight + 14, 320)
        padding: 7
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Classic.motionDuration; easing.type: Theme.easing } }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Classic.hoverDuration; easing.type: Theme.easing } }
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            Basic.ScrollIndicator.vertical: Basic.ScrollIndicator {}
        }
        background: Rectangle { radius: Classic.tileRadius; color: Theme.bgAlt; border.width: 1; border.color: Theme.overlay2 }
    }
}
