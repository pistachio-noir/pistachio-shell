import qs
import qs.services
import QtQuick

// A confirmation inside the existing Lens card; no additional keyboard-grabbing window.
FocusScope {
    id: root
    visible: reveal.shown
    property bool useCoding: false
    Reveal { id: reveal; open: Lens.upgradePrompt }
    opacity: reveal.progress

    Connections {
        target: Lens
        function onUpgradePromptChanged() {
            if (Lens.upgradePrompt) {
                root.useCoding = false;
                Qt.callLater(() => root.forceActiveFocus());
            }
        }
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) Lens.respondCodingUpgrade(false);
        else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Tab) root.useCoding = !root.useCoding;
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) Lens.respondCodingUpgrade(root.useCoding);
        else return;
        event.accepted = true;
    }
    Rectangle { anchors.fill: parent; radius: Theme.panelRadius; color: Theme.bg; opacity: 0.9 }
    MouseArea { anchors.fill: parent }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(440, parent.width - 32)
        height: content.implicitHeight + 40
        radius: Theme.panelRadius
        color: Theme.bgAlt
        border.width: 1; border.color: Theme.overlay2
        Accessible.role: Accessible.Dialog
        Accessible.name: "Use coding model for this code?"
        Column {
            id: content
            x: 20; y: 20; width: parent.width - 40; spacing: 14
            Row {
                spacing: 10
                Rectangle {
                    width: 36; height: 36; radius: 18; color: Theme.overlay
                    Icon { anchors.centerIn: parent; size: 18; paths: Icons.fileCode; color: Theme.clay }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Use coding model?"; color: Theme.textBright
                    font.family: Theme.fontUi; font.pixelSize: 15; font.weight: Font.ExtraBold
                }
            }
            Text {
                width: parent.width
                text: "Code detected. Retry with " + Lens.codingLabel + "?"
                wrapMode: Text.Wrap; textFormat: Text.PlainText
                color: Theme.text; font.family: Theme.fontUi; font.pixelSize: 13; font.weight: Font.Medium
            }
            Text {
                width: parent.width
                text: "May take longer and use more of your allowance. Only coding questions in this chat use this preset; translations and other tasks keep your normal model."
                wrapMode: Text.Wrap
                color: Theme.subtext; font.family: Theme.fontUi; font.pixelSize: 12
            }
            Flow {
                width: parent.width; spacing: 8
                ActionButton { objectName: "lens-keep-model"; height: 44; text: "Keep current answer"; primary: !root.useCoding; onClicked: Lens.respondCodingUpgrade(false) }
                ActionButton { objectName: "lens-use-coding"; height: 44; text: "Use coding model"; primary: root.useCoding; onClicked: Lens.respondCodingUpgrade(true) }
            }
        }
    }
}
