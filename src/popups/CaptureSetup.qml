import qs
import qs.components
import qs.services
import QtQuick

// Approved controls have no board: use the existing panel and pill language.
Rectangle {
    id: root
    signal selectArea
    signal selectScreen
    width: 480; height: content.implicitHeight + 48
    radius: Theme.panelRadius; color: Theme.surface
    border.width: 1; border.color: Theme.overlay2
    Shadow { anchors.fill: parent; z: -1; radius: parent.radius; kind: Theme.shadowPanel }
    MouseArea { anchors.fill: parent }
    Column {
        id: content; x: 24; y: 24; width: parent.width - 48; spacing: 16
        Text { text: "Record screen"; color: Theme.textBright; font.family: Theme.fontUi; font.pixelSize: 20; font.weight: Font.ExtraBold }
        Text { text: "Audio"; color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: Theme.tui ? Theme.tuiTextSize : 12; font.weight: Font.Bold }
        Row {
            spacing: 6
            Repeater {
                model: [{value:"off",label:"Off"},{value:"system",label:"System"},{value:"mic",label:"Mic"},{value:"both",label:"Both"}]
                CaptureButton {
                    required property var modelData
                    objectName: "capture-audio-" + modelData.value
                    text: modelData.label; selected: ShellSettings.recordingAudio === modelData.value
                    onClicked: ShellSettings.setRecordingAudio(modelData.value)
                }
            }
        }
        Text { text: "Mic follows the current input in Sound settings."; color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 12 }
        Text { text: "Countdown"; color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: Theme.tui ? Theme.tuiTextSize : 12; font.weight: Font.Bold }
        Row {
            spacing: 6
            Repeater {
                model: [0,3,5,10]
                CaptureButton {
                    required property int modelData
                    objectName: "capture-countdown-" + modelData
                    text: modelData ? modelData + " s" : "Off"; selected: ShellSettings.recordingCountdown === modelData
                    onClicked: ShellSettings.setRecordingCountdown(modelData)
                }
            }
        }
        Row {
            spacing: 8
            CaptureButton { objectName: "capture-select-area"; text: "Select area"; onClicked: root.selectArea() }
            CaptureButton { objectName: "capture-full-screen"; text: "Full screen"; onClicked: root.selectScreen() }
        }
        Text { text: "Esc cancel"; color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 11 }
    }
}
