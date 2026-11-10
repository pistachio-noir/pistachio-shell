import qs
import qs.services
import QtQuick
import QtQuick.Controls.Basic as Basic

Basic.TextField {
    id: root
    property int minutes
    signal modified(int value)
    width: 112
    height: 44
    text: NightLight.timeText(minutes)
    inputMask: "99:99"
    horizontalAlignment: TextInput.AlignHCenter
    font.family: Theme.fontMono
    font.pixelSize: 13
    color: Theme.textBright
    selectByMouse: true
    background: Rectangle {
        radius: 22
        color: Theme.bgAlt
        border.width: root.activeFocus ? 1 : 0
        border.color: Theme.subtext
    }
    onEditingFinished: {
        const parts = text.split(":").map(Number);
        if (/^\d{2}:\d{2}$/.test(text) && parts[0] < 24 && parts[1] < 60)
            modified(parts[0] * 60 + parts[1]);
        text = Qt.binding(() => NightLight.timeText(root.minutes));
    }
}
