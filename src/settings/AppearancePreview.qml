import qs
import qs.components
import qs.services
import QtQuick

Rectangle {
    height: 124; radius: Theme.tui ? 0 : (Theme.tileRadius); color: Theme.bg; clip: true
    Rectangle {
        visible:Theme.tui;anchors.fill:parent;color:Theme.deep;border.width:1;border.color:Theme.tuiBorder
        Rectangle { x:24;y:16;width:300;height:92;color:Theme.bgAlt;border.width:1;border.color:Theme.tuiBorder
            Column { x:12;y:10;width:276;spacing:0
                SettingsText { text:"panel";secondary:true }
                SettingsText { text:"[x] do not disturb";color:Theme.pistachio }
                SettingsText { width:parent.width;wrapMode:Text.NoWrap;textFormat:Text.RichText;text:"vol [<font color=\""+Theme.pistachio+"\">██████████</font>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;]" }
            }
        }
        SettingsText { anchors.right:parent.right;anchors.rightMargin:12;anchors.bottom:parent.bottom;anchors.bottomMargin:8;text:"preview";secondary:true }
    }
    Image { visible:!Theme.tui;anchors.fill: parent; source: Wallpapers.current ? "file://"+Wallpapers.current : ""; fillMode: Image.PreserveAspectCrop; opacity: 0.35 }
    SettingsText { visible:!Theme.tui;x:16; y:14; text:"Panel preview"; secondary:true; font.pixelSize: Theme.tui ? Theme.tuiTextSize : 11 }
    Rectangle {
        visible:!Theme.tui
        anchors.right: parent.right; anchors.rightMargin:24; y:15; width:148; height:83; radius: Theme.tui ? 0 : (20); color:Theme.surface; border.color:Theme.overlay2
        Column { x:12;y:12;spacing:9; Repeater { model:[68,106,86]; Rectangle { required property int modelData; width:modelData;height:7;radius: Theme.tui ? 0 : (4);color:Theme.overlay2 } } }
        Rectangle { x:110;y:12;width:26;height:16;radius: Theme.tui ? 0 : (8);color:Theme.pistachio; Rectangle{x:13;y:3;width:10;height:10;radius: Theme.tui ? 0 : (5);color:Theme.bg} }
    }
    Rectangle {
        visible:!Theme.tui
        anchors.horizontalCenter:parent.horizontalCenter; y:84;width:238;height:27;radius: Theme.tui ? 0 : (14);color:Theme.surface
        Row { x:10;anchors.verticalCenter:parent.verticalCenter;spacing:5; Repeater{ model:3;Rectangle{required property int index;width:index===1?16:4;height:4;radius: Theme.tui ? 0 : (2);color:index===1?Theme.pistachio:Theme.muted}} }
        SettingsText { anchors.right:parent.right;anchors.rightMargin:12;anchors.verticalCenter:parent.verticalCenter;text:Qt.formatTime(new Date(),"hh:mm");secondary:true;font.pixelSize: Theme.tui ? Theme.tuiTextSize : 11 }
    }
}
