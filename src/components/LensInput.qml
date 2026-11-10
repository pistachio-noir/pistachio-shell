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
    implicitHeight: Math.min(136, Math.max(52, field.contentHeight + 22))
    radius: 26
    color: Theme.bg
    border.width: 1
    border.color: Theme.overlay2

    function focusInput() { field.forceActiveFocus(); }
    Icon {
        visible: root.initial
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        paths: Icons.sparkles
        color: Theme.clay
        size: 18
    }
    Flickable {
        id: scroll
        objectName: "lensInputScroll"
        x: root.initial ? 44 : 18
        y: 11
        width: parent.width - x - 56
        height: parent.height - 22
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
            placeholderText: root.placeholder
            placeholderTextColor: Theme.subtext
            readOnly: root.reading
            wrapMode: TextEdit.Wrap
            color: root.reading ? Theme.subtext : Theme.textBright
            selectionColor: Theme.overlay2
            selectedTextColor: Theme.textBright
            font.family: Theme.fontUi
            font.pixelSize: root.initial ? 14 : 13
            font.weight: Font.DemiBold
            background: null
            cursorDelegate: Rectangle {
                width: 2
                height: field.font.pixelSize + 6
                radius: 1
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
