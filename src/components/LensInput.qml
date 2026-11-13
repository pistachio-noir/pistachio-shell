import qs
import QtQuick
import QtQuick.Controls

Rectangle {
    id: root
    property alias text: field.text
    property string placeholder: "Ask about this…"
    property bool reading
    property bool initial
    signal submitted(string text)
    signal stopped
    // TUI (Lens boards): no box, "> " then the text with a block cursor, "[s] stop" while reading
    implicitHeight: Theme.tui ? Math.min(120, Math.max(Theme.tuiLineHeight, field.contentHeight)) : Math.min(136, Math.max(52, field.contentHeight + 22))
    radius: Theme.tui ? 0 : 26
    color: Theme.tui ? "transparent" : Theme.bg
    border.width: Theme.tui ? 0 : 1
    border.color: Theme.overlay2

    function focusInput() { field.forceActiveFocus(); }
    Text {
        visible: Theme.tui
        y: 0
        text: ">"
        color: Theme.pistachio
        font.family: Theme.fontTui
        font.pixelSize: Theme.tuiTextSize
        font.weight: Font.Bold
    }
    TuiBracket {
        id: tuiStop
        visible: Theme.tui && root.reading
        anchors.right: parent.right
        key: "s"
        label: "stop"
        onClicked: root.stopped()
    }
    Icon {
        visible: root.initial && !Theme.tui
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        paths: Icons.sparkles
        color: Theme.clay
        size: 18
    }
    Flickable {
        id: scroll
        objectName: "lensInputScroll"
        x: Theme.tui ? 16 : root.initial ? 44 : 18
        y: Theme.tui ? 0 : 11
        width: parent.width - x - (Theme.tui ? (tuiStop.visible ? tuiStop.width + 12 : 0) : 56)
        height: parent.height - (Theme.tui ? 0 : 22)
        contentWidth: width
        contentHeight: Math.max(height, field.height)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        function ensureCursor() {
            const top = field.y + field.cursorRectangle.y;
            const bottom = top + field.cursorRectangle.height;
            if (contentY > top) contentY = top;
            else if (contentY + height < bottom) contentY = bottom - height;
            contentY = Math.max(0, Math.min(contentY, contentHeight - height));
        }
        TextArea {
            id: field
            objectName: "lensInputField"
            width: scroll.width
            height: contentHeight
            y: Math.max(0, (scroll.height - height) / 2)
            padding: 0
            // Centre short text explicitly; the attached TextArea.flickable also
            // adjusts margins/contentY and shifted text away from the icon's centre.
            onCursorRectangleChanged: scroll.ensureCursor()
            placeholderText: Theme.tui ? "" : root.placeholder
            placeholderTextColor: Theme.subtext
            readOnly: root.reading
            wrapMode: TextEdit.Wrap
            color: root.reading ? Theme.subtext : Theme.textBright
            selectionColor: Theme.overlay2
            selectedTextColor: Theme.textBright
            font.family: Theme.fontUi
            font.pixelSize: Theme.tui ? Theme.tuiTextSize : root.initial ? 14 : 13
            font.weight: Theme.tui ? Font.Bold : Font.DemiBold
            background: null
            // TUI: the placeholder after the block cursor, as the boards draw it
            Text {
                visible: Theme.tui && field.text === "" && field.preeditText === ""
                x: 12
                text: root.placeholder.replace(/…$/, "").toLowerCase()
                color: Theme.subtext
                font.family: Theme.fontTui
                font.pixelSize: Theme.tuiTextSize
            }
            cursorDelegate: Rectangle {
                width: Theme.tui ? 8 : 2
                height: Theme.tui ? Theme.tuiLineHeight - 2 : field.font.pixelSize + 6
                radius: Theme.tui ? 0 : 1
                color: Theme.pistachio
                visible: field.activeFocus && !field.readOnly
            }
            Keys.onPressed: event => {
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                    event.accepted = true;
                    if (!root.reading && text.trim()) root.submitted(text);
                }
            }
        }
    }
    Rectangle {
        visible: !Theme.tui
        width: 44; height: 44; radius: 22
        anchors.right: parent.right; anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        color: !root.reading && root.text.trim() ? Theme.pistachio : Theme.overlay
        Accessible.role: Accessible.Button
        Accessible.name: root.reading ? "Stop request" : "Send question"
        Icon {
            anchors.centerIn: parent
            paths: root.reading ? Icons.stop : Icons.arrowUp
            size: root.reading ? 16 : 20
            color: !root.reading && root.text.trim() ? Theme.bg : Theme.text
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.reading) root.stopped(); else if (root.text.trim()) root.submitted(root.text)
        }
    }
}
