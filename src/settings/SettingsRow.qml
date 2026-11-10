import qs
import qs.components
import qs.services
import QtQuick
import QtQuick.Controls.Basic as Basic

Rectangle {
    id: root
    required property var spec
    objectName: "setting-" + spec.id
    property bool divided
    property real horizontalPadding: 18
    readonly property string kind: spec.kind || "read"
    readonly property bool level: kind === "slider" || kind === "audio"
    readonly property bool monoSubtitle: ["chats", "wallpapers", "folder", "storage"].includes(spec.id)
    implicitHeight: Math.max(level ? 112 : 64, titleColumn.implicitHeight + 24)
    radius: Theme.tileRadius
    color: SettingsHub.target === spec.id ? Theme.overlay2 : "transparent"

    Rectangle { visible: root.divided; x: root.horizontalPadding; width: parent.width - root.horizontalPadding * 2; height: 1; color: Theme.overlay2 }
    Column {
        id: titleColumn
        x: root.horizontalPadding; y: root.level ? 14 : (root.height - height) / 2
        width: Math.max(50, root.width - root.horizontalPadding * 2 - (control.visible ? control.width + 12 : 0) - (forget.visible ? forget.width + 12 : 0))
        spacing: 3
        SettingsText { objectName: "label-" + root.spec.id; width: parent.width; text: root.spec.title || "" }
        SettingsText { width: parent.width; text: root.spec.subtitle ? root.spec.subtitle() : ""; visible: text !== ""; secondary: true; font.family: root.monoSubtitle ? Theme.fontMono : Theme.fontUi; font.pixelSize: root.monoSubtitle ? 11 : 12 }
    }
    SettingsButton {
        id: forget
        visible: root.spec.forget !== undefined
        anchors.right: control.left; anchors.rightMargin: 12; anchors.verticalCenter: control.verticalCenter
        text: "Forget"; quiet: true; danger: true
        onClicked: root.spec.forget()
        Accessible.name: "Forget " + root.spec.title
    }
    Item {
        id: control
        anchors.right: parent.right; anchors.rightMargin: root.horizontalPadding
        y: root.level ? 12 : (root.height - height) / 2
        width: root.kind === "toggle" ? 52 : choice.visible ? choice.width : action.visible ? action.width : timePair.visible ? 234 : timeField.visible ? 112 : reading.implicitWidth
        height: 44
        visible: root.kind !== "slider"

        Basic.Switch {
            id: toggle
            objectName: "toggle-" + root.spec.id
            visible: root.kind === "toggle"
            width: 52; height: 44; padding: 0
            checked: visible && root.spec.checked ? root.spec.checked() : false
            onClicked: root.spec.toggle()
            Accessible.name: root.spec.title
            background: Rectangle { anchors.centerIn: parent; width: 48; height: 28; radius: 14; color: toggle.checked ? Theme.pistachio : Theme.overlay2; border.width: toggle.visualFocus ? 1 : 0; border.color: Theme.subtext
                Rectangle { x: toggle.checked ? 24 : 4; y: 4; width: 20; height: 20; radius: 10; color: toggle.checked ? Theme.bg : Theme.subtext; Behavior on x { NumberAnimation { duration: Theme.hoverDuration; easing.type: Theme.easing } } }
            }
            indicator: null
            contentItem: null
        }
        SettingsChoice {
            id: choice
            objectName: "choice-" + root.spec.id
            visible: root.kind === "choice" || root.kind === "audio"
            width: root.kind === "audio" ? Math.min(285, root.width * 0.5) : 170
            choices: visible && root.spec.choices ? root.spec.choices() : []
            selected: visible && root.spec.value ? root.spec.value() : ""
            onChosen: value => root.spec.set(value)
            Accessible.name: root.spec.title
        }
        SettingsButton {
            id: action
            objectName: "action-" + root.spec.id
            visible: root.kind === "action"
            text: root.spec.button || "Open"
            danger: root.spec.danger || false
            enabled: root.spec.enabled ? root.spec.enabled() : true
            onClicked: root.spec.run()
            Accessible.name: root.spec.title + ": " + text
        }
        SettingsTime {
            id: timeField
            objectName: "time-" + root.spec.id
            visible: root.kind === "time"
            minutes: visible && root.spec.value ? root.spec.value() : 0
            onModified: value => root.spec.set(value)
            Accessible.name: root.spec.title
        }
        Row {
            id: timePair
            visible: root.kind === "times"
            spacing: 10
            SettingsTime { objectName: timePair.visible ? "time-from" : ""; minutes: timePair.visible ? root.spec.start() : 0; onModified: value => root.spec.setStart(value); Accessible.name: root.spec.title + ": from" }
            SettingsTime { objectName: timePair.visible ? "time-to" : ""; minutes: timePair.visible ? root.spec.end() : 0; onModified: value => root.spec.setEnd(value); Accessible.name: root.spec.title + ": until" }
        }
        SettingsText { id: reading; visible: root.kind === "read"; anchors.verticalCenter: parent.verticalCenter; text: visible && root.spec.value ? root.spec.value() : ""; font.pixelSize: 12 }
    }
    Row {
        visible: root.level
        x: root.horizontalPadding; y: root.height - 50; width: root.width - root.horizontalPadding * 2; height: 44; spacing: 12
        SettingsButton {
            visible: root.spec.mute !== undefined
            width: 44; padding: 0
            text: root.spec.muted && root.spec.muted() ? "×" : "♪"
            glyph: root.spec.id === "input" ? root.spec.muted && root.spec.muted() ? Icons.micOff : Icons.mic : root.spec.muted && root.spec.muted() ? Icons.volumeMuted : Icons.volume
            onClicked: root.spec.mute()
            Accessible.name: root.spec.title + (root.spec.muted && root.spec.muted() ? ": unmute" : ": mute")
        }
        Slider {
            id: levelSlider
            trackColor: Theme.overlay2
            objectName: "level-" + root.spec.id
            width: parent.width - valueLabel.width - 12 - (root.spec.mute !== undefined ? 56 : 0)
            from: root.spec.from === undefined ? 0 : root.spec.from
            to: root.spec.to === undefined ? 1 : root.spec.to
            value: root.level && root.spec.level ? root.spec.level() : 0
            onMoved: root.spec.adjust(value)
            Accessible.name: root.spec.title
        }
        SettingsText { id: valueLabel; width: root.spec.to > 1 ? 70 : 44; height: 44; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; text: root.spec.format ? root.spec.format(levelSlider.shownValue) : root.spec.to > 1 ? Math.round(levelSlider.shownValue) + " K" : Math.round(levelSlider.shownValue * 100) + "%"; font.pixelSize: 12 }
    }
}
