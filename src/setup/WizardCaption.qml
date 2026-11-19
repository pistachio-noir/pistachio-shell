import qs
import QtQuick
import QtQuick.Layouts

// A small section label: capitals in Classic, lower case in TUI.
SetupText {
    property string label
    Layout.topMargin: 4
    text: label.toUpperCase()
    secondary: true
    font.pixelSize: 11; font.letterSpacing: 0.7
}
