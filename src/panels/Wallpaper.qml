import qs
import qs.components
import qs.panels
import qs.services
import Quickshell
import Quickshell.Io
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
    // from the desktop icons: shell.qml has the launcher ask for a name, or opens the switcher
    signal renameRequested(var item)
    signal newFolderRequested(var cell)
    signal wallpapersRequested

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
    // Ctrl+click on the desktop icons needs to know Ctrl is down, which only the surface with the
    // keyboard is told: the desktop takes it on a click, but only on a workspace without windows. An
    // on-demand layer may take the keyboard on hover too, and the desktop shows in the gaps between
    // windows, so a pointer resting there could pull typing away from a window.
    WlrLayershell.keyboardFocus: !Theme.tui && Desktop.enabled && !(Compositor.workspaces.find(w => w.active)?.occupied ?? true) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Theme.tui && !Showoff.active ? catRegion : null
    Region { id: catRegion; item: desktopCat.visible ? desktopCat : null }

    // Showoff mode: the wallpaper settles in from a little closer as it starts, and a click on it (the
    // desktop between the panels) ends it.
    Connections {
        target: Showoff

        function onActiveChanged() {
            if (Showoff.active)
                settle.restart();
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: Showoff.active
        onClicked: Showoff.stop()
    }

    WallpaperView {
        id: view
        anchors.fill: parent
        path: Wallpapers.current
        loadSize: Qt.size(root.screen.width * root.screen.devicePixelRatio, root.screen.height * root.screen.devicePixelRatio)
        fadeDuration: root.intro ? Theme.introDuration : Theme.growDuration
        onFaded: path => {
            if (path)
                root.endIntro();
        }
    }

    DesktopCat {
        id: desktopCat
        interactive: true
        skin: ShellSettings.catSkin
        anchors.right: parent.right
        anchors.rightMargin: 80
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 100
        active: ShellSettings.desktopCat && Compositor.workspaces.some(w => w.active) && !Compositor.fullscreen && !Compositor.windows.some(w => w.workspace === Compositor.activeWorkspace && !w.floating && !w.hidden && !w.minimized)
    }

    // The wallpaper dims a little while night light is on (owner's pick, 31 October 2026), so the
    // desktop isn't the brightest thing on screen late at night; the icons stay as they are
    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        opacity: NightLight.enabled ? 0.5 : 0 // 0.3 was too little (owner, 1 November)

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.dimDuration
                easing.type: Theme.easing
            }
        }
    }

    // desktop widgets (Experimental, 20 November 2026): over the wallpaper, under the icons
    DesktopWidgetLayer {
        anchors.fill: parent
    }

    NumberAnimation {
        id: settle
        target: view
        property: "scale"
        from: 1.06
        to: 1
        duration: Theme.settleDuration
        easing.type: Theme.easing
    }

    // the Desktop folder's files and folders (owner's request, after phase 8)
    Loader {
        anchors.fill: parent
        active: !Theme.tui
        focus: active
        sourceComponent: DesktopIcons {
            id: desktop
            onCatHover: (position, inside) => desktopCat.hovered = inside && desktopCat.visible && desktopCat.contains(desktopCat.mapFromItem(desktop, position.x, position.y))
            onCatClick: position => { if (desktopCat.visible && desktopCat.contains(desktopCat.mapFromItem(desktop, position.x, position.y))) desktopCat.pet(); }
            onRenameRequested: item => root.renameRequested(item)
            onNewFolderRequested: cell => root.newFolderRequested(cell)
            onWallpapersRequested: root.wallpapersRequested()

            FocusGrab {
                windows: [root]
                active: desktop.menuOpen
                onCleared: desktop.menu = null
            }
        }
    }

    // For a keybind (owner's request, 29 October): qs -c pistachio ipc call desktop toggle (or on, off;
    // not show and hide: `qs ipc call desktop show` printed the target's functions); the OSD says which
    IpcHandler {
        target: "desktop"

        function toggle(): void {
            Desktop.setEnabled(!Desktop.enabled);
        }
        function on(): void {
            Desktop.setEnabled(true);
        }
        function off(): void {
            Desktop.setEnabled(false);
        }
    }

    // TUI and Zen give the cat its own target because the desktop handler is inactive.
    MouseArea {
        anchors.fill: desktopCat
        enabled: (Theme.tui || FocusMode.zen) && !Showoff.active && desktopCat.visible
        visible: enabled
        hoverEnabled: true
        onEntered: desktopCat.hovered = true
        onExited: desktopCat.hovered = false
        onEnabledChanged: if (!enabled) desktopCat.hovered = false
        onClicked: desktopCat.pet()
    }

    Timer {
        id: introLimit
        interval: Theme.introDuration + 900
        onTriggered: root.endIntro()
    }
}
