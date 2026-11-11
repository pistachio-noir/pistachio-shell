import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick

// No input region or keyboard grab: hold/release and wheel shortcuts arrive through IPC.
PanelWindow {
    id:root
    visible:reveal.shown
    screen:Quickshell.screens[0]
    anchors { top:true; bottom:true; left:true; right:true }
    exclusionMode:ExclusionMode.Ignore
    color:"transparent"
    mask:Region {}
    WlrLayershell.namespace:"pistachio-magnifier"
    WlrLayershell.layer:WlrLayer.Overlay
    WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
    Reveal { id:reveal; open:Compositor.magnifierOpen }
    readonly property real sample:200/Compositor.magnifierZoom
    readonly property real px:Compositor.pointerPosition.x-(screen?.x ?? 0)
    readonly property real py:Compositor.pointerPosition.y-(screen?.y ?? 0)
    ScreencopyView {
        id:shot; width:root.width; height:root.height
        captureSource:Compositor.magnifierOpen ? root.screen : null
        live:true; paintCursor:false; visible:false
    }
    ClippingRectangle {
        id:lens
        objectName:"screen-magnifier-lens"
        x:root.px+root.sample/2+24+width<root.width ? root.px+root.sample/2+24 : Math.max(8,root.px-root.sample/2-24-width)
        y:Math.max(8,Math.min(root.height-height-8,root.py-height/2))
        width:208; height:244; radius:Theme.tileRadius
        color:Theme.bgAlt; border.color:Theme.overlay2; border.width:2
        opacity:reveal.progress
        ShaderEffectSource {
            x:4; y:4; width:200; height:200; sourceItem:shot
            sourceRect:Qt.rect(Math.max(0,Math.min(root.width-root.sample,root.px-root.sample/2)),Math.max(0,Math.min(root.height-root.sample,root.py-root.sample/2)),root.sample,root.sample)
            hideSource:true; live:true
        }
        Rectangle { x:99; y:96; width:10; height:1; color:Theme.textBright }
        Rectangle { x:103; y:92; width:1; height:10; color:Theme.textBright }
        Text { anchors.horizontalCenter:parent.horizontalCenter; y:214; text:Compositor.magnifierZoom.toFixed(1)+"×"; color:Theme.text; font.family:Theme.fontMono; font.pixelSize:12 }
    }
}
