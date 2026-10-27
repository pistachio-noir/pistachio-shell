import qs.bar
import qs.launcher
import qs.lock
import qs.panels
import Quickshell

ShellRoot {
    Bar {
        onLauncherRequested: mode => launcher.show(mode)
    }

    Launcher {
        id: launcher
    }
    Lock {}
    PolkitDialog {} // and the polkit agent behind it, which starts with the shell
}
