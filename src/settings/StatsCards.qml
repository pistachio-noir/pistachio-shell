import qs
import qs.services
import QtQuick

Row {
    id: root
    objectName: "setting-stats"
    spacing: 14
    Repeater {
        model: [
            {title:"CPU",value:SystemStats.cpu<0?"—":Math.round(SystemStats.cpu*100)+"%",detail:SystemStats.cpuTemp<0?SystemStats.cpuName:SystemStats.cpuTemp+" °C",level:SystemStats.cpu},
            {title:"Memory",value:SystemStats.memUsed.toFixed(1)+" / "+Math.round(SystemStats.memTotal)+" GB",detail:(SystemStats.memTotal-SystemStats.memUsed).toFixed(1)+" GB available",level:SystemStats.memTotal?SystemStats.memUsed/SystemStats.memTotal:0},
            ...(SystemStats.gpuFound?[{title:"Graphics",value:Math.round(SystemStats.gpu*100)+"%",detail:SystemStats.gpuTemp+" °C · "+SystemStats.vramUsed.toFixed(1)+" GB VRAM",level:SystemStats.gpu}]:[])
        ]
        Rectangle {
            required property var modelData
            width:(root.width-14*(stats.count-1))/Math.max(1,stats.count)
            height:156;radius:Theme.tileRadius;color:Theme.overlay
            Column { x:18;y:18;width:parent.width-36;spacing:12
                SettingsText { text:modelData.title }
                SettingsText { width:parent.width;text:modelData.value;font.pixelSize:modelData.title==="Memory"?18:28;font.weight:Font.ExtraBold }
                Rectangle { width:parent.width;height:5;radius:3;color:Theme.overlay2;Rectangle{width:parent.width*Math.max(0,Math.min(1,modelData.level));height:5;radius:3;color:Theme.sageBlue} }
                SettingsText { width:parent.width;text:modelData.detail;secondary:true;font.pixelSize:11;maximumLineCount:1;elide:Text.ElideRight }
            }
        }
        id: stats
    }
}
