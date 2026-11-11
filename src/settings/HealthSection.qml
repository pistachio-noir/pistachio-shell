import qs
import qs.services
import QtQuick

Column {
    spacing:14
    SettingsGroup {
        width:parent.width;title:"Local checks"
        rows:[
            {id:"health-check",kind:"action",title:"Shell & helpers",subtitle:()=>"Check dependencies and recent shell error count. No model request is sent.",button:SystemHealth.busy?"Checking…":"Check installed",enabled:()=>!SystemHealth.busy,run:()=>SystemHealth.check(false)},
            {id:"health-auth",kind:"action",title:"CLI sign-in status",subtitle:()=>"Runs Claude auth status and Codex login status only.",button:"Check sign-in",enabled:()=>!SystemHealth.busy,run:()=>SystemHealth.check(true)},
            {id:"diagnostics",kind:"action",title:"Redacted diagnostics",subtitle:()=>"Status labels only: no logs, paths, addresses, identities or tokens.",button:"Copy",enabled:()=>SystemHealth.checked,run:SystemHealth.copyDiagnostics}
        ]
    }
    SettingsText { visible:!!SystemHealth.error;width:parent.width;text:SystemHealth.error;color:Theme.terracotta }
    SettingsGroup { width:parent.width;title:"Results";visible:SystemHealth.checked;rows:SystemHealth.rows.map(r=>({id:"health-"+r.id,title:r.title,subtitle:()=>r.detail,value:()=>r.status})) }
}
