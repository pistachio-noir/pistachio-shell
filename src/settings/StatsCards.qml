import qs
import qs.components
import qs.services
import QtQuick

Grid {
    id: root
    objectName: "setting-stats"
    columns: Theme.tui ? 1 : (SystemStats.gpuFound ? 3 : 2)
    spacing: Theme.tui ? 0 : 14
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
            width:Theme.tui ? root.width : (root.width-14*(stats.count-1))/Math.max(1,stats.count)
            height:Theme.tui ? 64 : 156;radius: Theme.tui ? 0 : (Theme.tileRadius);color:Theme.tui?"transparent":Theme.overlay
            Rectangle { visible:Theme.tui;width:parent.width;height:1;color:Theme.tuiRule }
            SettingsText { visible:Theme.tui;x:32;y:8;text:reading.title }
            SettingsText { visible:Theme.tui;x:32;y:30;width:parent.width*0.45-32;text:reading.detail;secondary:true;maximumLineCount:1;elide:Text.ElideRight }
            Slider { visible:Theme.tui;x:parent.width*0.48;y:10;width:parent.width*0.27;value:reading.level;enabled:false }
            SettingsText { visible:Theme.tui;anchors.right:parent.right;anchors.rightMargin:8;y:18;text:reading.title==="Memory" ? Math.round(reading.level*100)+"%" : reading.value;secondary:true }
            Column { visible:!Theme.tui;x:18;y:18;width:parent.width-36;spacing:12
                SettingsText { text:reading.title }
                SettingsText { width:parent.width;text:reading.value;font.pixelSize:reading.title==="Memory"?18:28;font.weight:Font.ExtraBold }
                Rectangle { width:parent.width;height:5;radius: Theme.tui ? 0 : (3);color:Theme.overlay2;Rectangle{width:parent.width*Math.max(0,Math.min(1,reading.level));height:5;radius: Theme.tui ? 0 : (3);color:Theme.sageBlue} }
                SettingsText { width:parent.width;text:reading.detail;secondary:true;font.pixelSize: Theme.tui ? Theme.tuiTextSize : 11;maximumLineCount:1;elide:Text.ElideRight }
            }
        }
        id: stats
    }
}
