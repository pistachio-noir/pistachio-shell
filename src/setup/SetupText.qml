import qs
import QtQuick

// SettingsText in the Classic look only (Classic.qml).
Text {
    property bool secondary

    color: secondary ? Theme.subtext : Theme.textBright
    font.family: Classic.fontUi
    font.pixelSize: secondary ? 12 : 13
    font.weight: secondary ? Font.Medium : Font.Bold
    wrapMode: Text.Wrap
}
