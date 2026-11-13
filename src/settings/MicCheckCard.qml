import qs
import qs.services
import QtQuick

Column {
    id: root
    objectName: "setting-mic-check"
    spacing: 8
    SettingsText { text: "Microphone check"; secondary: true; font.pixelSize: Theme.tui ? Theme.tuiTextSize : 11; font.weight: Font.Bold }
    Rectangle {
        width: parent.width; height: body.implicitHeight + 36; radius: Theme.tui ? 0 : (Theme.tileRadius); color: Theme.overlay
        Column {
            id: body
            x:18;y:18;width:parent.width-36;spacing:12
            SettingsText { width:parent.width;text:MicCheck.error || (MicCheck.state === "recording" ? "Recording · " + MicCheck.seconds.toFixed(1) + " / 5 s" : MicCheck.state === "metering" ? "Listening · microphone in use" : MicCheck.state === "recorded" ? "Sample ready · microphone closed" : MicCheck.state === "playing" ? "Playing sample · microphone closed" : "Start when you are ready. Nothing is recorded until you choose Record.");secondary:true }
            Rectangle {
                width:parent.width;height:8;radius: Theme.tui ? 0 : (4);color:Theme.overlay2
                Rectangle { width:parent.width*MicCheck.level;height:8;radius: Theme.tui ? 0 : (4);color:Theme.pistachio }
            }
            Flow {
                width:parent.width;spacing:8
                SettingsButton { objectName:"mic-meter";text:"Start meter";enabled:!!MicCheck.input && ["idle","recorded"].includes(MicCheck.state);onClicked:MicCheck.start("meter") }
                SettingsButton { objectName:"mic-record";text:"Record 5 seconds";enabled:!!MicCheck.input && ["idle","metering","recorded"].includes(MicCheck.state);onClicked:MicCheck.start("record") }
                SettingsButton { objectName:"mic-play";text:"Play sample";enabled:MicCheck.state==="recorded";onClicked:MicCheck.start("play") }
                SettingsButton { objectName:"mic-stop";text:"Stop & discard";enabled:MicCheck.state!=="idle";onClicked:MicCheck.stop() }
            }
            SettingsText { width:parent.width;text:"Uses your selected input. The temporary sample is discarded when you leave this page or close Settings.";secondary:true;font.pixelSize: Theme.tui ? Theme.tuiTextSize : 11 }
        }
    }
}
