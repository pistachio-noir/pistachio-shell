import qs
import QtQuick

Rectangle {
    id: root
    property string text
    property string detail
    property string kind: "action"
    property bool checked
    property bool selected
    property bool muted
    property real value
    property real from: 0
    property real to: 1
    property var format: v=>Math.round(v*100)+"%"
    signal activated
    signal alternate
    signal moved(real value)
    signal picked
    readonly property bool stacked: kind==="level" && text.length>5
    implicitHeight: stacked ? 52 : 32
    color: selected ? (kind==="level"?Theme.bgAlt:Theme.pistachio) : hover.hovered ? Theme.bgAlt : "transparent"
    readonly property color foreground: selected && kind!=="level" ? Theme.bg : Theme.text
    Accessible.role: kind==="toggle"?Accessible.CheckBox:Accessible.Button
    Accessible.name: text+(detail?", "+detail:"")
    Accessible.checkable: kind==="toggle"
    Accessible.checked: checked
    HoverHandler { id:hover }
    MouseArea { anchors.fill:parent;acceptedButtons:Qt.LeftButton|Qt.RightButton;cursorShape:Qt.PointingHandCursor;onClicked:e=>{root.picked();if(e.button===Qt.RightButton)root.alternate();else root.activated();} }
    Text {
        objectName:"control-label"
        x:0;y:root.stacked?0:(parent.height-height)/2;width:root.stacked?parent.width:40;elide:Text.ElideRight
        text:root.kind==="level"?root.text:root.kind==="read"?"   ":root.kind==="action"?"[>]":root.checked?"[x]":"[ ]"
        color:root.kind==="toggle"&&root.checked&&!root.selected?Theme.pistachio:root.foreground
        font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize
    }
    Text {
        visible:root.kind!=="level";x:32;anchors.verticalCenter:parent.verticalCenter;width:parent.width-x-(meta.visible?meta.width+8:0)
        text:root.text;textFormat:Text.PlainText;elide:Text.ElideRight;color:root.foreground;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize
    }
    Text {
        id:meta;visible:root.kind!=="level"&&text!=="";anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter
        width:Math.min(implicitWidth,parent.width*0.52);text:root.detail;textFormat:Text.PlainText;elide:Text.ElideRight
        color:root.selected?Theme.bg:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize
    }
    Slider {
        id:slider;objectName:"control-slider";visible:root.kind==="level";x:root.stacked?0:40;y:root.stacked?20:0;width:Math.min(Theme.tuiControlMeterWidth,parent.width-x-78);height:32
        from:root.from;to:root.to;value:root.value
        onMoved:{root.picked();root.moved(value);}
        Accessible.name:root.text
    }
    Text {
        visible:root.kind==="level";x:slider.x+slider.width+20;y:root.stacked?20+(32-height)/2:(parent.height-height)/2
        text:root.muted?"muted":root.format(slider.shownValue);color:root.muted?Theme.terracotta:Theme.textBright;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize
    }
}
