import qs
import qs.components
import qs.services
import QtQuick

Rectangle {
    height: 124; radius: Theme.tileRadius; color: Theme.bg; clip: true
    Image { anchors.fill: parent; source: Wallpapers.current ? "file://"+Wallpapers.current : ""; fillMode: Image.PreserveAspectCrop; opacity: 0.35 }
    SettingsText { x:16; y:14; text:"Panel preview"; secondary:true; font.pixelSize:11 }
    Rectangle {
        anchors.right: parent.right; anchors.rightMargin:24; y:15; width:148; height:83; radius:20; color:Theme.surface; border.color:Theme.overlay2
        Column { x:12;y:12;spacing:9; Repeater { model:[68,106,86]; Rectangle { required property int modelData; width:modelData;height:7;radius:4;color:Theme.overlay2 } } }
        Rectangle { x:110;y:12;width:26;height:16;radius:8;color:Theme.pistachio; Rectangle{x:13;y:3;width:10;height:10;radius:5;color:Theme.bg} }
    }
    Rectangle {
        anchors.horizontalCenter:parent.horizontalCenter; y:84;width:238;height:27;radius:14;color:Theme.surface
        Row { x:10;anchors.verticalCenter:parent.verticalCenter;spacing:5; Repeater{ model:3;Rectangle{required property int index;width:index===1?16:4;height:4;radius:2;color:index===1?Theme.pistachio:Theme.muted}} }
        SettingsText { anchors.right:parent.right;anchors.rightMargin:12;anchors.verticalCenter:parent.verticalCenter;text:Qt.formatTime(new Date(),"hh:mm");secondary:true;font.pixelSize:11 }
    }
}
