import qs
import QtQuick

Rectangle {
    id: root
    property string text
    property string value
    property color tint: Theme.textBright
    property bool centered
    property bool active
    property real maximumWidth: Infinity
    property int padding: 8
    signal clicked(int button)
    signal scrolled(real delta)
    implicitWidth: nameLabel.implicitWidth + valueLabel.implicitWidth + (text && value ? 6 : 0) + padding * 2
    width: Math.min(maximumWidth, implicitWidth)
    height: Theme.tuiBarCellHeight
    color: active ? Theme.pistachio : mouse.containsMouse ? Theme.overlay : "transparent"
    Accessible.role: Accessible.Button
    Accessible.name: text + (value ? ", " + value : "")
    Row {
        id: labels
        x: root.centered ? (root.width-root.implicitWidth+root.padding*2)/2 : root.padding; width:root.width-root.padding*2; anchors.verticalCenter: parent.verticalCenter; spacing: root.text && root.value ? 6 : 0
        Text { id:nameLabel;width:Math.min(implicitWidth,labels.width);elide:Text.ElideRight;text:root.text;textFormat:Text.PlainText;color:root.active?Theme.bg:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize }
        Text { id:valueLabel;width:Math.min(implicitWidth,Math.max(0,labels.width-nameLabel.width-labels.spacing));elide:Text.ElideRight;text:root.value;textFormat:Text.PlainText;color:root.active?Theme.bg:root.tint;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize;font.weight:Font.Bold }
    }
    // Clip long titles without making the other readouts move.
    clip: true
    MouseArea {
        id: mouse; anchors.fill:parent;hoverEnabled:true;acceptedButtons:Qt.LeftButton|Qt.MiddleButton|Qt.RightButton
        cursorShape:Qt.PointingHandCursor
        onClicked:event=>root.clicked(event.button)
        onWheel:event=>root.scrolled(event.angleDelta.y)
    }
}
