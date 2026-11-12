import qs
import qs.services
import QtQuick

Row {
    id: root
    objectName: "setting-stats"
    spacing: 14
    // the cards are made once (the model changes only if a graphics card is found) and read the
    // readings themselves: a model rebuilt on each reading remade them every 1.5 s
    function card(title: string): var {
        if (title === "CPU")
            return {title:"CPU",value:SystemStats.cpu<0?"—":Math.round(SystemStats.cpu*100)+"%",detail:SystemStats.cpuTemp<0?SystemStats.cpuName:SystemStats.cpuTemp+" °C",level:SystemStats.cpu};
        if (title === "Memory")
            return {title:"Memory",value:SystemStats.memUsed.toFixed(1)+" / "+Math.round(SystemStats.memTotal)+" GB",detail:(SystemStats.memTotal-SystemStats.memUsed).toFixed(1)+" GB available",level:SystemStats.memTotal?SystemStats.memUsed/SystemStats.memTotal:0};
        return {title:"Graphics",value:Math.round(SystemStats.gpu*100)+"%",detail:SystemStats.gpuTemp+" °C · "+SystemStats.vramUsed.toFixed(1)+" GB VRAM",level:SystemStats.gpu};
    }
    Repeater {
        model: SystemStats.gpuFound ? ["CPU", "Memory", "Graphics"] : ["CPU", "Memory"]
        Rectangle {
            required property string modelData
            readonly property var reading: root.card(modelData)
            width:(root.width-14*(stats.count-1))/Math.max(1,stats.count)
            height:156;radius:Theme.tileRadius;color:Theme.overlay
            Column { x:18;y:18;width:parent.width-36;spacing:12
                SettingsText { text:reading.title }
                SettingsText { width:parent.width;text:reading.value;font.pixelSize:reading.title==="Memory"?18:28;font.weight:Font.ExtraBold }
                Rectangle { width:parent.width;height:5;radius:3;color:Theme.overlay2;Rectangle{width:parent.width*Math.max(0,Math.min(1,reading.level));height:5;radius:3;color:Theme.sageBlue} }
                SettingsText { width:parent.width;text:reading.detail;secondary:true;font.pixelSize:11;maximumLineCount:1;elide:Text.ElideRight }
            }
        }
        id: stats
    }
}
