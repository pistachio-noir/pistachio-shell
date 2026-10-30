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

    // unmount, then power the drive off, so it's safe to pull out; a notification says how it went
    function eject(drive) {
        Quickshell.execDetached(["sh", "-c", 'if udisksctl unmount -b "$1" >/dev/null 2>&1; then udisksctl power-off -b "$2" >/dev/null 2>&1; '
            + 'notify-send --app-name=Drives --icon=drive-removable-media "$3 can be removed"; '
            + 'else notify-send --app-name=Drives --icon=drive-removable-media "Couldn\'t eject $3" "A program may still be using it"; fi',
            "sh", drive.path, drive.disk, drive.name]);
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
