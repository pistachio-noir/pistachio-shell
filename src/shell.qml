import qs.bar
import qs.launcher
import qs.lock
import qs.panels
import qs.popups
import Quickshell

ShellRoot {
    Wallpaper { // first: the desktop under everything
        id: wallpaper
        onIntroDone: bar.endIntro()
    }
    Bar {
        id: bar
        onLauncherRequested: mode => launcher.show(mode)
    }

    Launcher {
        id: launcher
        onWallpapersRequested: wallpaperSwitcher.show()
        onNotificationRequested: n => bar.showNotification(n)
    }
    Lock {}
    PolkitDialog {} // and the polkit agent behind it, which starts with the shell
    ScreenshotPicker {}
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
