import qs
import qs.components
import QtQuick

// Owner's board: compact capture modes, Lens, then optional utilities, with a delayed help card.
Item {
    id: root
    property bool open
    property var choices: []
    property string output: "save"
    signal outputChosen(string value)
    property int current
    signal highlighted(int index)
    signal chosen(int index)
    property bool tipOpen
    property var tipChoice: null
    property Item tipAnchor: null
    readonly property bool shown: reveal.shown

    function scheduleTip() {
        tipOpen = false;
        if (open) tipDelay.restart();
        else tipDelay.stop();
        Qt.callLater(() => {
            const item = delegates.itemAt(current);
            if (!item) return;
            if (item.x < viewport.contentX) viewport.contentX = item.x;
            else if (item.x + item.width > viewport.contentX + viewport.width)
                viewport.contentX = Math.min(viewport.contentWidth - viewport.width, item.x + item.width - viewport.width);
        });
    }
    property point pointerPosition
    property bool pointerKnown
    onOpenChanged: { pointerKnown = false; scheduleTip(); }
    onCurrentChanged: scheduleTip()
    onChoicesChanged: scheduleTip()
    Reveal { id: reveal; open: root.open }
    Timer {
        id: tipDelay
        interval: 500
        onTriggered: {
            root.tipAnchor = delegates.itemAt(root.current);
            root.tipChoice = root.choices[root.current] || null;
            root.tipOpen = root.open && root.tipChoice !== null;
        }
    }

    Rectangle {
        id: bar
        objectName: "screenshot-toolbar"
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.min(Theme.screenshotMenuTop, Math.max(16, root.height - height - tip.height - 30)) + 12 * (1 - reveal.progress)
        width: Math.min(buttons.implicitWidth + 18, root.width - 32)
        height: 62
        radius: Theme.panelRadius
        color: Theme.bgAlt
        border.width: 1; border.color: Theme.overlay2
        opacity: reveal.progress
        visible: reveal.shown
        enabled: root.open
        Accessible.role: Accessible.Grouping
        Accessible.name: "Screenshot"
        Shadow { anchors.fill: parent; z: -1; radius: parent.radius; kind: Theme.shadowPanel }
        MouseArea { anchors.fill: parent }
        Flickable {
            id: viewport
            x: 9; y: 9; width: parent.width - 18; height: 44
            contentWidth: buttons.implicitWidth; contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            Row {
                id: buttons
                spacing: 2
                Repeater {
                    id: delegates
                    model: root.choices
                    Item {
                        id: slot
                        required property var modelData
                        required property int index
                        readonly property bool divided: modelData.name === "Lens" || index === 5
                        readonly property real buttonOffset: divided ? 19 : 0
                        width: button.width + buttonOffset; height: 44
                        Item {
                            visible: slot.divided
                            width: 17; height: 44
                            Rectangle { x: 8; y: 8; width: 1; height: 28; color: Theme.overlay2 }
                        }
                        Rectangle {
                            id: button
                            objectName: "screenshot-choice-" + slot.modelData.name.toLowerCase()
                            readonly property bool selected: root.current === slot.index
                            x: slot.buttonOffset
                            width: labelRow.implicitWidth + 30; height: 44; radius: 22
                            color: selected ? Theme.pistachio : mouse.containsMouse ? Theme.overlay : "transparent"
                            Accessible.role: Accessible.Button
                            Accessible.name: `${slot.modelData.name}, key ${String.fromCharCode(slot.modelData.key)}`
                            Accessible.description: slot.modelData.description
                            Behavior on color { ColorAnimation { duration: Theme.hoverDuration; easing.type: Theme.easing } }
                            Row {
                                id: labelRow
                                x: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                                Item {
                                    width: 18; height: 18; anchors.verticalCenter: parent.verticalCenter
                                    Icon { anchors.fill: parent; size: 18; paths: slot.modelData.icon; color: button.selected ? Theme.bg : Theme.text }
                                    Rectangle {
                                        visible: slot.modelData.name === "Record"
                                        anchors.centerIn: parent; width: 6; height: 6; radius: 3
                                        color: button.selected ? Theme.bg : Theme.text
                                    }
                                }
                                Text {
                                    text: slot.modelData.name; textFormat: Text.PlainText
                                    color: button.selected ? Theme.bg : Theme.text
                                    font.family: Theme.fontUi; font.pixelSize: 13; font.weight: button.selected ? Font.ExtraBold : Font.Bold
                                }
                                Text {
                                    visible: slot.index < 5
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String.fromCharCode(slot.modelData.key)
                                    opacity: 0.7
                                    color: button.selected ? Theme.bg : Theme.text
                                    font.family: Theme.fontUi; font.pixelSize: 11; font.weight: Font.Bold
                                }
                            }
                            MouseArea {
                                id: mouse
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                // A still pointer must not replace a keyboard selection when this maps.
                                onEntered: {
                                    if (reveal.progress >= 1) root.highlighted(slot.index);
                                    if (root.current === slot.index) root.scheduleTip();
                                }
                                onExited: if (root.current === slot.index) { root.tipOpen = false; tipDelay.stop(); }
                                onPositionChanged: event => {
                                    const at = mouse.mapToItem(root, event.x, event.y);
                                    const moved = root.pointerKnown && (Math.abs(at.x-root.pointerPosition.x) > 0.5 || Math.abs(at.y-root.pointerPosition.y) > 0.5);
                                    root.pointerKnown = true; root.pointerPosition = at;
                                    if (containsMouse && root.open && moved) root.highlighted(slot.index);
                                }
                                onClicked: root.chosen(slot.index)
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        objectName: "screenshot-output"
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(8, bar.y - 48)
        width: outputRow.implicitWidth + 8; height: 40; radius: 20
        color: Theme.bgAlt; border.width: 1; border.color: Theme.overlay2
        visible: reveal.shown; opacity: reveal.progress; enabled: root.open
        Row {
            id: outputRow; x: 4; y: 4; spacing: 2
            Repeater {
                model: [{value:"save",label:"Save"},{value:"copy",label:"Copy"},{value:"both",label:"Both"}]
                CaptureButton {
                    required property var modelData
                    objectName: "capture-output-" + modelData.value
                    text: modelData.label; selected: root.output === modelData.value
                    height: 32
                    onClicked: root.outputChosen(modelData.value)
                }
            }
        }
    }

    Rectangle {
        id: tip
        objectName: "screenshot-tooltip"
        readonly property real centre: root.tipAnchor ? bar.x + 9 + root.tipAnchor.x + root.tipAnchor.buttonOffset + (root.tipAnchor.width - root.tipAnchor.buttonOffset) / 2 - viewport.contentX : bar.x
        x: Math.max(16, Math.min(root.width - width - 16, centre - 96))
        y: bar.y + bar.height + 14 + 6 * (1 - tipReveal.progress)
        width: Math.min(Theme.screenshotTipWidth, root.width - 32)
        height: tipText.implicitHeight + 30
        radius: Theme.tileRadius
        color: Theme.bgAlt
        border.width: 1; border.color: Theme.overlay2
        visible: tipReveal.shown
        opacity: tipReveal.progress * reveal.progress
        Accessible.role: Accessible.ToolTip
        Accessible.name: root.tipChoice ? root.tipChoice.name + ". " + root.tipChoice.description : ""
        Reveal { id: tipReveal; open: root.open && root.tipOpen }
        Shadow { anchors.fill: parent; z: -1; radius: parent.radius; kind: Theme.shadowSmall }
        MouseArea { anchors.fill: parent }
        Column {
            id: tipText
            x: 17; y: 15; width: parent.width - 34; spacing: 4
            Text { text: root.tipChoice?.name ?? ""; color: Theme.textBright; font.family: Theme.fontUi; font.pixelSize: 13; font.weight: Font.Bold }
            Text {
                width: parent.width; text: root.tipChoice?.description ?? ""; textFormat: Text.PlainText
                wrapMode: Text.Wrap; lineHeightMode: Text.FixedHeight; lineHeight: 18
                color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 12; font.weight: Font.Medium
            }
            Item {
                width: parent.width; height: command.implicitHeight + 4
                Text {
                    id: command
                    y: 4; width: parent.width; wrapMode: Text.Wrap
                    text: root.tipChoice?.command || (root.tipChoice ? "Press " + String.fromCharCode(root.tipChoice.key) : "")
                    color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 11
                }
            }
        }
    }
}
