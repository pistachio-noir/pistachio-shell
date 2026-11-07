import QtQuick

// Inside a Text that may be cut short: while it's hovered and cut ("…"), HoverTip shows it whole.
HoverHandler {
    onHoveredChanged: {
        if (hovered && parent.truncated)
            HoverTip.show(parent, parent.text);
        else
            HoverTip.hide(parent);
    }
}
