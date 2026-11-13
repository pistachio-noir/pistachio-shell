import qs
import qs.bar
import qs.launcher
import qs.lock
import qs.panels
import qs.popups
import qs.services
import qs.settings
import Quickshell
import QtQuick

ShellRoot {
    // services that work in the background from the start: a singleton only starts once it's used
    readonly property var background: [Drives, LocalSend, Clocks]

    Binding { target: Theme; property: "tui"; value: ShellSettings.appearanceStyle === "tui" }

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
    Overview { // before the bar: mapped first on the same level, so the bar stays above it
        id: overview
        onLauncherRequested: mode => launcher.show(mode)
    }
    Bar {
        id: bar
        overviewOpen: overview.open
        wallpaperSwitcher: wallpaperSwitcher
        sessionPillWidth: sessionPill.visible ? sessionPill.width : 0
        onLauncherRequested: mode => launcher.show(mode)
        onTimerRequested: launcher.askTimer()
        onAlarmRequested: launcher.askAlarm()
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
        onSettingsRequested: page => settings.showPage(page, "")
    }
    SettingsWindow { id: settings }
    Connections {
        target: SettingsHub
        function onPresent() { launcher.open = false; }
        function onWallpapersRequested() { wallpaperSwitcher.show(); }
        function onShowoffRequested() { SettingsHub.opened = false; Showoff.start(); }
    }
    Connections { target: LauncherTools; function onPresent() { launcher.open = false; } }
    Lock {}
    PolkitDialog {} // and the polkit agent behind it, which starts with the shell
    ScreenshotPicker {}
    RecordingRegion {} // area bounds and an outside Stop pill
    LensCard {}
    QuickChat {} // the quick chat above the bar (Chat, `chat toggle`, the launcher's ask)
    LauncherExtras {}
    RecordingTools {}
    AlarmPopup {} // timers done and Clocks' alarms ringing
    SessionPill { id: sessionPill } // a Pomodoro's time while Zen hides the bar
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
