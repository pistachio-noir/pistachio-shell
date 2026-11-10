import qs
import qs.components
import QtQuick
import QtQuick.Controls.Basic as Basic

Basic.ComboBox {
    id: root
    property var choices: []
    property var selected
    signal chosen(var value)
    model: choices
    textRole: "title"
    valueRole: "value"
    currentIndex: choices.findIndex(c => c.value === selected)
    onActivated: index => chosen(choices[index].value)
    implicitHeight: 44
    implicitWidth: 152
    leftPadding: 14
    rightPadding: 34
    font.family: Theme.fontUi
    font.pixelSize: 12
    font.weight: Font.Bold
    background: Rectangle {
        radius: Theme.tileRadius
        color: root.hovered ? Theme.overlay2 : Theme.bgAlt
        border.width: 1
        border.color: root.visualFocus ? Theme.subtext : Theme.overlay2
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
    }
    delegate: Basic.ItemDelegate {
        required property var modelData
        required property int index
        width: root.popup.width - 14
        height: modelData.subtitle ? 60 : 48
        enabled: !modelData.disabled
        highlighted: root.highlightedIndex === index
        background: Rectangle { radius: 16; color: parent.highlighted || root.selected === modelData.value ? Theme.overlay : "transparent" }
        contentItem: Item {
            Column {
                anchors.left: parent.left; anchors.right: check.left; anchors.verticalCenter: parent.verticalCenter
                SettingsText { width: parent.width; text: modelData.title; font.pixelSize: 12; color: modelData.disabled ? Theme.subtext : Theme.textBright; elide: Text.ElideRight; maximumLineCount: 1 }
                SettingsText { width: parent.width; visible: text !== ""; text: modelData.subtitle || ""; secondary: true; font.pixelSize: 11; maximumLineCount: 1; elide: Text.ElideRight }
            }
            Icon { id: check; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; size: 16; paths: Icons.check; color: Theme.pistachio; visible: root.selected === modelData.value }
        }
    }
    popup: Basic.Popup {
        x: Math.min(0, root.width - width)
        y: root.height + 6
        margins: 8
        width: Math.max(root.width, 230)
        height: Math.min(contentItem.implicitHeight + 14, 320)
        padding: 7
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            Basic.ScrollIndicator.vertical: Basic.ScrollIndicator {}
        }
        background: Rectangle { radius: Theme.tileRadius; color: Theme.bgAlt; border.width: 1; border.color: Theme.overlay2 }
    }
}
