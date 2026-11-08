import qs
import qs.bar
import qs.launcher
import qs.lock
import qs.panels
import qs.popups
import qs.services
import Quickshell
import QtQuick

ShellRoot {
    // services that work in the background from the start: a singleton only starts once it's used
    readonly property var background: [Drives, LocalSend]

    // frosted panels: how opaque the bar and panels are
    Binding {
        target: Theme
        property: "frost"
        value: ShellSettings.frost
    }

    Wallpaper { // first: the desktop under everything
        id: wallpaper
        onIntroDone: bar.endIntro()
        onRenameRequested: item => launcher.renameDesktopItem(item)
        onNewFolderRequested: cell => launcher.newDesktopFolder(cell)
        onWallpapersRequested: wallpaperSwitcher.show()
    }
    Bar {
        id: bar
        onLauncherRequested: mode => launcher.show(mode)
        onRenameWorkspaceRequested: ws => {
            launcher.show("workspaces");
            launcher.renameWorkspace(ws);
        }
    }

    Launcher {
        id: launcher
        onWallpapersRequested: wallpaperSwitcher.show()
        onNotificationRequested: n => bar.showNotification(n)
        onRainRequested: rain.start()
    }
    Lock {}
    PolkitDialog {} // and the polkit agent behind it, which starts with the shell
    ScreenshotPicker {}
    PistachioRain {
        id: rain
    }
    WindowSwitcher {}
    WallpaperSwitcher {
        id: wallpaperSwitcher
    }

    // The startup animation (owner's request, after phase 8), on every start but not on a live reload:
    // the wallpaper fades in from the background colour, then the bar grows out of its handle.
    // `started` is carried over a reload, before loaded() comes.
    PersistentProperties {
        reloadableId: "startup"
        property bool started
        onLoaded: {
            if (started)
                return;
            started = true;
            bar.startIntro();
            wallpaper.startIntro();
        }
    }
}
