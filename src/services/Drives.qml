pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Removable drives (owner's request, 30 October 2026): udiskie (owner's call) mounts a USB drive the
// moment it's plugged in, and the ones already in at startup, and its notifications say so (with
// Browse); the shell runs it without its tray icon, so don't start another one from Hyprland's config.
// `mounted` lists the removable drives that are mounted, read with lsblk whenever udisks reports a
// change (udisksctl monitor), for the launcher's Eject rows. Without udiskie nothing mounts by itself.
Singleton {
    id: root

    // [{ path, disk, name, mountpoint, size }]: the filesystem's device, the drive it's on (to power
    // off), its label or device name
    property var mounted: []

    property var result: null
    property var pending: null
    readonly property bool busy: ejector.running
    function eject(drive) {
        if (busy) return;
        pending = drive;
        result = null;
        ejector.command = ["python3", "-I", Quickshell.shellPath("services/system-tools.py"), "eject", drive.path, drive.disk, drive.name, drive.mountpoint];
        ejector.running = true;
    }
    function returnToApp(pid: int) {
        const window = Compositor.windows.find(w => Number(w.pid) === pid);
        if (window) { SettingsHub.opened = false; Compositor.focus(window.address); }
    }
    function canReturn(pid: int): bool { return Compositor.windows.some(w => Number(w.pid) === pid); }
    Process {
        id: ejector
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.result = JSON.parse(text); } catch(e) { root.result = {ok:false,name:root.pending?.name || "Drive",holders:[],message:"Could not read eject result."}; }
                if (!root.result.ok) SettingsHub.openPage("system", "eject-result");
                Quickshell.execDetached(["notify-send", "--app-name=Drives", "--icon=drive-removable-media", root.result.name, root.result.message]);
            }
        }
        onExited: code => { if (code !== 0) { root.result = {ok:false,name:root.pending?.name || "Drive",holders:[],message:"Eject helper could not start."}; SettingsHub.openPage("system", "eject-result"); } }
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v udiskie >/dev/null || exit 0; exec setpriv --pdeathsig TERM udiskie --automount --notify --no-tray"]
    }

    // a line for each change udisks makes (setpriv: it would outlive a killed shell, as pactl did)
    Process {
        running: true
        command: ["setpriv", "--pdeathsig", "TERM", "udisksctl", "monitor"]
        stdout: SplitParser {
            onRead: reading.restart()
        }
    }

    // one reading per burst of changes (a drive brings several)
    Timer {
        id: reading
        interval: 400
        onTriggered: lsblk.running = true
    }

    Process {
        id: lsblk
        running: true
        command: ["lsblk", "-J", "-l", "-o", "PATH,PKNAME,LABEL,MOUNTPOINT,HOTPLUG,RM,SIZE"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.mounted = JSON.parse(text).blockdevices.filter(d => d.mountpoint && (d.hotplug || d.rm)).map(d => ({
                        path: d.path,
                        disk: d.pkname ? `/dev/${d.pkname}` : d.path,
                        name: d.label || d.path.split("/").pop(),
                        mountpoint: d.mountpoint,
                        size: d.size
                    }));
                } catch (e) {
                    console.warn("drives: can't read lsblk:", e);
                }
            }
        }
    }
}
