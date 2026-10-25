import qs.bar
import qs.launcher
import qs.lock
import Quickshell

ShellRoot {
    Bar {
        onLauncherRequested: mode => launcher.show(mode)
    }

    Launcher {
        id: launcher
    }
    Lock {}
}
