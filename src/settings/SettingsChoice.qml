import qs
import qs.components
import QtQuick
import QtQuick.Controls.Basic as Basic

Basic.ComboBox {
    id: root
    property var choices: []
    property var selected
    signal chosen(var value)
    property string filterText
    readonly property bool filterable: Theme.tui && Accessible.name.toLowerCase().includes("model")
    readonly property var shownChoices: filterable && filterText.trim() ? choices.filter(c => (c.title + " " + (c.subtitle || "")).toLowerCase().includes(filterText.trim().toLowerCase())) : choices
    model: shownChoices
    textRole: "title"
    valueRole: "value"
    currentIndex: shownChoices.findIndex(c => c.value === selected)
    onActivated: index => { if (shownChoices[index]) chosen(shownChoices[index].value); }
    implicitHeight: 44
    implicitWidth: 152
    leftPadding: 14
    rightPadding: 34
    font.family: Theme.fontUi
    font.pixelSize: Theme.tui ? Theme.tuiTextSize : 12
    font.weight: Font.Bold
    background: Rectangle {
        y: Theme.tui ? (root.height-Theme.tuiButtonHeight)/2 : 0
        height: Theme.tui ? Theme.tuiButtonHeight : root.height
        radius: Theme.tui ? 0 : (Theme.tileRadius)
        color: Theme.tui ? Theme.overlay : root.hovered ? Theme.overlay2 : Theme.bgAlt
        border.width: Theme.tui ? 0 : 1
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
        id: option
        required property var modelData
        required property int index
        width: root.popup.width - 14
        height: Theme.tui ? (modelData.subtitle ? 52 : 44) : modelData.subtitle ? 60 : 48
        enabled: !modelData.disabled
        highlighted: Theme.tui && options.activeFocus ? options.currentIndex === index : root.highlightedIndex === index
        background: Rectangle { radius: Theme.tui ? 0 : (16); color: Theme.tui ? (parent.highlighted ? Theme.pistachio : "transparent") : parent.highlighted || root.selected === modelData.value ? Theme.overlay : "transparent" }
        contentItem: Item {
            Column {
                anchors.left: parent.left; anchors.right: check.left; anchors.verticalCenter: parent.verticalCenter
                SettingsText { width: parent.width; text: modelData.title; font.pixelSize: Theme.tui ? Theme.tuiTextSize : 12; color: Theme.tui && option.highlighted ? Theme.bg : modelData.disabled ? Theme.subtext : Theme.textBright; elide: Text.ElideRight; maximumLineCount: 1 }
                SettingsText { width: parent.width; visible: text !== ""; text: modelData.subtitle || ""; secondary: true; color: Theme.tui && option.highlighted ? Theme.bg : Theme.subtext; font.pixelSize: Theme.tui ? Theme.tuiTextSize : 11; maximumLineCount: 1; elide: Text.ElideRight }
            }
            Icon { id: check; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; size: 16; paths: Icons.check; color: Theme.tui && option.highlighted ? Theme.bg : Theme.pistachio; visible: root.selected === modelData.value }
        }
    }
    popup: Basic.Popup {
        onClosed: root.filterText = ""
        x: Math.min(0, root.width - width)
        y: root.height + 6
        margins: 8
        width: Math.max(root.width, 230)
        height: Math.min(contentItem.implicitHeight + 14, 320)
        padding: 7
        contentItem: Item {
            implicitHeight: (filter.visible ? filter.height : 0) + Math.min(options.contentHeight, Theme.tui ? 270 : 306)
            Basic.TextField {
                id: filter
                objectName: "choice-filter"
                visible: root.filterable
                width: parent.width; height: 36
                placeholderText: "/ filter models"
                color: Theme.text; placeholderTextColor: Theme.subtext
                font.family: Theme.fontTui; font.pixelSize: Theme.tuiTextSize
                text: root.filterText
                onTextEdited: { root.filterText = text; options.currentIndex = root.shownChoices.length ? 0 : -1; }
                background: Rectangle { color: Theme.bg }
                Keys.onDownPressed: { options.forceActiveFocus(); options.currentIndex = root.shownChoices.length ? 0 : -1; }
            }
            ListView {
            id: options
            y: filter.visible ? filter.height : 0
            width: parent.width
            height: Math.min(contentHeight, root.popup.height - (filter.visible ? filter.height : 0) - 14)
            clip: true
            implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            Keys.onDownPressed: event => { if (Theme.tui) currentIndex = Math.min(count-1,currentIndex+1); else event.accepted=false; }
            Keys.onUpPressed: event => { if (Theme.tui) currentIndex = Math.max(0,currentIndex-1); else event.accepted=false; }
            Keys.onReturnPressed: event => {
                if (Theme.tui && root.shownChoices[currentIndex]) {
                    root.chosen(root.shownChoices[currentIndex].value);
                    root.popup.close();
                } else event.accepted=false;
            }
            Basic.ScrollIndicator.vertical: Basic.ScrollIndicator {}
            }
        }
        background: Rectangle { radius: Theme.tui ? 0 : (Theme.tileRadius); color: Theme.tui ? Theme.bg : Theme.bgAlt; border.width: 1; border.color: Theme.overlay2 }
    }
}
