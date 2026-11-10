import qs
import QtQuick

Text {
    property bool secondary

    color: secondary ? Theme.subtext : Theme.textBright
    font.family: Theme.fontUi
    font.pixelSize: secondary ? 12 : 13
    font.weight: secondary ? Font.Medium : Font.Bold
    wrapMode: Text.Wrap
}
