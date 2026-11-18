import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland
import QtQuick

Scope {
    PanelWindow {
        id: popup
        visible: popupReveal.shown
        Reveal { id:popupReveal; open:FocusMode.phoneOpen && FocusMode.session !== null }
        anchors.top:true; anchors.bottom:true; anchors.left:true; anchors.right:true
        exclusionMode: ExclusionMode.Ignore
        color:"transparent"
        WlrLayershell.layer:WlrLayer.Overlay
        WlrLayershell.namespace:"pistachio-panel"
        WlrLayershell.keyboardFocus:FocusMode.phoneOpen?WlrKeyboardFocus.Exclusive:WlrKeyboardFocus.None
        MouseArea { anchors.fill:parent; onClicked:FocusMode.phoneOpen=false }
        PanelFrame {
            id: card
            opacity:popupReveal.progress
            anchors.centerIn:parent
            width:360; height:FocusMode.phoneQr ? 350 : 170
            title:Theme.tui?"view on phone":""; active:true
            color:Theme.surface
            focus:popup.visible
            Keys.onEscapePressed:FocusMode.phoneOpen=false
            MouseArea { anchors.fill:parent }
            Text { x:20; y:20; width:parent.width-40; text:"View timer on your phone"; color:Theme.textBright; font.family:Theme.fontUi; font.pixelSize:16; font.bold:true }
            Image { id:qr; visible:FocusMode.phoneQr!==""; anchors.horizontalCenter:parent.horizontalCenter; y:52; width:208; height:208; source:FocusMode.phoneQr?"file://"+FocusMode.phoneQr:""; asynchronous:true; fillMode:Image.PreserveAspectFit }
            Text {
                x:20; y:qr.visible?270:64; width:parent.width-40
                text:FocusMode.phoneError || (FocusMode.phoneUrl ? (FocusMode.phoneQrError ? FocusMode.phoneQrError + "\n" : "") + FocusMode.phoneUrl : "Starting phone preview…")
                color:FocusMode.phoneError?Theme.terracotta:Theme.text; font.family:Theme.fontMono; font.pixelSize:13; wrapMode:Text.WrapAnywhere
                textFormat:Text.PlainText
            }
            ActionButton { anchors.right:parent.right; anchors.rightMargin:20; anchors.bottom:parent.bottom; anchors.bottomMargin:16; height:32; text:"Close"; onClicked:FocusMode.phoneOpen=false }
        }
    }
}
