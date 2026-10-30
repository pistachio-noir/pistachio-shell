import qs
import qs.services
import QtQuick

// Focused window: title over app id. Empty when nothing has focus. In showoff mode only the app id: a
// title can say what's open (a chat, a file).
Column {
    Text {
        width: parent.width
        text: (Showoff.active ? Compositor.focusedWindow?.appId : Compositor.focusedWindow?.title) ?? ""
        elide: Text.ElideRight
        color: Theme.textBright
        font.family: Theme.fontUi
        font.pixelSize: 13
        font.weight: Font.Bold
        lineHeight: 17
        lineHeightMode: Text.FixedHeight
    }

    Text {
        width: parent.width
        visible: !Showoff.active
        text: Compositor.focusedWindow?.appId ?? ""
        elide: Text.ElideRight
        color: Theme.subtext
        font.family: Theme.fontUi
        font.pixelSize: 11
        font.weight: Font.DemiBold
        lineHeight: 14
        lineHeightMode: Text.FixedHeight
    }
}
