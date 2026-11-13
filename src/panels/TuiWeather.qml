import qs
import qs.components
import qs.services
import QtQuick

Item {
    id:view
    objectName:"tui-weather"
    required property var controller
    readonly property var forecast:Weather.today?[Object.assign({name:"today",code:Weather.now?.code??0},Weather.today)].concat(Weather.days):Weather.days
    Text {x:12;y:16;width:parent.width-24;elide:Text.ElideRight;text:Showoff.active?"local weather":Weather.place?.name??Weather.city;color:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize}
    Text {x:12;y:36;width:parent.width-24;elide:Text.ElideRight;text:Weather.now?`${Weather.now.temp}° ${Weather.describe(Weather.now.code).text.toLowerCase()}  feels ${Weather.now.feels}°`:"waiting for weather";color:Theme.text;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize}
    Flickable {
        x:12;y:66;width:parent.width-24;height:60;clip:true;contentHeight:days.height;contentWidth:width
        Column {id:days;width:parent.width
            Repeater {model:view.forecast
                Item {
                    required property var modelData
                    width:parent.width;height:20
                    Text {text:parent.modelData.name.toLowerCase();color:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:12}
                    Rectangle {x:52;y:8;width:Math.max(4,Math.min(100,(parent.modelData.max-parent.modelData.min)*10));height:4;color:Theme.clay}
                    Text {anchors.right:parent.right;text:`${parent.modelData.min}°  ${parent.modelData.max}°`;color:Theme.text;font.family:Theme.fontTui;font.pixelSize:12}
                }
            }
        }
    }
    Item {
        visible:view.controller.expanded
        x:12;y:148;width:parent.width-24;height:260
        opacity:view.controller.expanded?1:0
        Behavior on opacity {NumberAnimation {duration:Theme.motionDuration;easing.type:Theme.easing}}
        Rectangle {width:parent.width;height:1;color:Theme.tuiRule}
        Column {y:16;width:parent.width;spacing:4
            Repeater {model:Weather.now&&Weather.today?[["feels like",`${Weather.now.feels}°`],["wind",`${Weather.now.wind} km/h`],["humidity",`${Weather.now.humidity}%`],["sunset",Weather.today.sunset]]:[]
                Item {required property var modelData;width:parent.width;height:20
                    Text {text:parent.modelData[0];color:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:12}
                    Text {anchors.right:parent.right;text:parent.modelData[1];color:Theme.text;font.family:Theme.fontTui;font.pixelSize:12}
                }
            }
        }
        Text {y:126;text:"next hours";color:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:12}
        Flickable {y:152;width:parent.width;height:100;clip:true;contentWidth:width;contentHeight:hours.height
            Column {id:hours;width:parent.width
                Repeater {model:Weather.hours
                    Item {required property var modelData;width:parent.width;height:20
                        Text {text:parent.modelData.label.toLowerCase();color:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:12}
                        Text {x:62;width:90;elide:Text.ElideRight;text:Weather.describe(parent.modelData.code).text.toLowerCase();color:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:11}
                        Text {anchors.right:parent.right;text:`${parent.modelData.temp}° ${parent.modelData.rain}%`;color:Theme.text;font.family:Theme.fontTui;font.pixelSize:12}
                    }
                }
            }
        }
    }
    ActionButton {x:12;y:parent.height-32;width:parent.width-24;height:28;horizontalPadding:0;base:"transparent";text:view.controller.expanded?"[W] hide details":"[W] details";onClicked:view.controller.expanded=!view.controller.expanded;Accessible.name:view.controller.expanded?"Hide weather details":"Show weather details"}
}
