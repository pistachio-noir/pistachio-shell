import qs
import qs.components
import qs.services
import QtQuick
import "calendar.js" as Cal

Item {
    id: view
    objectName:"tui-calendar"
    required property var controller
    implicitHeight:196+(Events.enabled?220:0)
    Text {x:12;y:16;width:parent.width-24;horizontalAlignment:Text.AlignHCenter;text:Qt.formatDate(new Date(view.controller.year,view.controller.month,1),"MMMM yyyy").toLowerCase();color:Theme.text;font.family:Theme.fontTui;font.pixelSize:Theme.tuiTextSize}
    Repeater {
        model:[-1,1]
        ActionButton {required property int modelData;x:modelData===-1?4:view.width-width-4;y:6;width:32;height:32;horizontalPadding:0;base:"transparent";text:modelData===-1?"‹":"›";onClicked:view.controller.step(modelData,false);Accessible.name:modelData===-1?"Previous month":"Next month"}
    }
    MouseArea {x:40;y:6;width:parent.width-80;height:32;cursorShape:Qt.PointingHandCursor;onClicked:{view.controller.showToday(false);view.controller.selectToday();}onWheel:e=>view.controller.step(e.angleDelta.y>0?-1:1,true)}
    Row {x:12;y:40
        Repeater {model:["mo","tu","we","th","fr","sa","su"]
            Text {required property string modelData;width:(view.width-24)/7;height:20;horizontalAlignment:Text.AlignHCenter;text:modelData;color:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:12}
        }
    }
    Grid {x:12;y:60;columns:7
        Repeater {model:Cal.days(view.controller.year,view.controller.month)
            Rectangle {
                id:day
                required property var modelData
                readonly property bool today:Cal.sameDay(modelData,new Date())
                readonly property bool selected:Events.enabled&&Cal.sameDay(modelData,view.controller.selected)
                width:(view.width-24)/7;height:20
                color:today?Theme.pistachio:selected?Theme.overlay:"transparent"
                Text {anchors.centerIn:parent;text:day.modelData.getDate();color:day.today?Theme.bg:day.modelData.getMonth()===view.controller.month?Theme.text:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:12}
                Rectangle {visible:Events.enabled&&(Events.byDay[Events.key(day.modelData)]??[]).length>0;width:3;height:3;x:parent.width/2;y:17;color:day.today?Theme.bg:Theme.subtext}
                MouseArea {anchors.fill:parent;enabled:Events.enabled;cursorShape:Qt.PointingHandCursor;onClicked:view.controller.selected=day.modelData;Accessible.role:Accessible.Button;Accessible.name:Qt.formatDate(day.modelData,"dddd d MMMM yyyy")}
            }
        }
    }
    Column {
        visible:Events.enabled;x:12;y:196;width:parent.width-24;spacing:8
        Rectangle {width:parent.width;height:1;color:Theme.tuiRule}
        Text {text:Qt.formatDate(view.controller.selected,"ddd d MMM").toLowerCase();color:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:12}
        Text {visible:view.controller.dayEvents.length===0;text:"No events";color:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:12}
        Repeater {model:view.controller.dayEvents.slice(0,4)
            Rectangle {
                required property var modelData
                width:parent.width;height:32;color:hover.hovered?Theme.bgAlt:"transparent"
                HoverHandler {id:hover}
                Rectangle {width:2;height:24;y:4;color:Events.colourFor(parent.modelData.calendar)}
                Text {x:8;width:parent.width-8;text:parent.modelData.title;elide:Text.ElideRight;color:Theme.text;font.family:Theme.fontTui;font.pixelSize:12}
                Text {x:8;y:16;text:parent.modelData.allDay?"all day":Qt.formatTime(new Date(parent.modelData.start),"HH:mm");color:Theme.subtext;font.family:Theme.fontTui;font.pixelSize:11}
                MouseArea {anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:Events.open()}
            }
        }
        ActionButton {height:28;horizontalPadding:0;base:"transparent";maximumWidth:parent.width;text:view.controller.dayEvents.length>4?`${view.controller.dayEvents.length-4} more in Calendar`:"Open Calendar";onClicked:Events.open()}
    }
}
