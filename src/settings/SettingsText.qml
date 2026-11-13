import qs
import QtQuick

Text {
    property bool secondary

    color: secondary ? Theme.subtext : Theme.textBright
    font.family: Theme.fontUi
    font.pixelSize: Theme.tui ? Theme.tuiTextSize : secondary ? 12 : 13
    font.weight: secondary ? Font.Medium : Font.Bold
    lineHeightMode: Theme.tui ? Text.FixedHeight : Text.ProportionalHeight
    lineHeight: Theme.tui ? Theme.tuiLineHeight : 1
    wrapMode: Text.Wrap
}
