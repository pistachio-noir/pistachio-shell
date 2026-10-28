import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland // the background layer (a Wayland protocol, not a compositor module)
import QtQuick

// The desktop's wallpaper (owner's request, after phase 8; it replaces hyprpaper): Wallpapers.current
// on the background layer, cross-fading when it changes; Theme.bg where a fit leaves room.
PanelWindow {
    id: root

    // The startup animation (shell.qml): the first wallpaper fades in from the background colour over
    // Theme.introDuration, then introDone() lets the bar grow. Without a wallpaper, or one slow to
    // load, the bar waits no more than a moment.
    property bool intro
    signal introDone

    function startIntro() {
        intro = true;
        introLimit.restart();
    }

    function endIntro() {
        if (!intro)
            return;
        intro = false;
        introLimit.stop();
        introDone();
    }

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: Theme.bg
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "pistachio-wallpaper"

    WallpaperView {
        anchors.fill: parent
        path: Wallpapers.current
        fadeDuration: root.intro ? Theme.introDuration : Theme.growDuration
        onFaded: path => {
            if (path)
                root.endIntro();
        }
    }

    Timer {
        id: introLimit
        interval: Theme.introDuration + 900
        onTriggered: root.endIntro()
    }
}
