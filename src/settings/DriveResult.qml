import qs
import qs.services
import QtQuick

Column {
    visible:Drives.result !== null
    spacing:8
    objectName:"setting-eject-result"
    SettingsText { text:Drives.result?.name || "Drive";font.weight:Font.Bold }
    SettingsText { width:parent.width;text:Drives.result?.message || "";secondary:true }
    SettingsGroup {
        width:parent.width;title:"Applications using this drive"
        visible:!!Drives.result && !Drives.result.ok && Drives.result.holders.length>0
        rows:(Drives.result?.holders || []).map(h=>({id:"holder-"+h.pid,title:h.name,subtitle:()=>"Process "+h.pid,kind:"action",button:"Return to app",enabled:()=>Drives.canReturn(h.pid),run:()=>Drives.returnToApp(h.pid)}))
    }
    Row { spacing:8
        SettingsButton { text:"Try eject again";visible:!!Drives.result && !Drives.result.ok;enabled:!Drives.busy && !!Drives.pending;onClicked:Drives.eject(Drives.pending) }
        SettingsButton { text:"Dismiss";quiet:true;onClicked:Drives.result=null }
    }
}
