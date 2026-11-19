pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import QtQuick

// Lock state, the unlock password check, and the power actions.
Singleton {
    id: root

    property bool locked
    property bool secure // the compositor confirmed the lock covers the screen (set by the lock screen)
    property bool suspending // waiting for the lock before suspending
    readonly property bool checking: pam.active
    property string error // why the last unlock failed, "" otherwise
    property string password // held only until PAM asks for it

    function lock() {
        error = "";
        locked = true;
    }

    // PAM's "login" stack, as other lockers use: three wrong passwords lock the account for a while
    // (pam_faillock), the TTY included.
    function unlock(text: string) {
        if (pam.active)
            return;
        error = "";
        password = text;
        pam.start();
    }

    function logout() {
        Compositor.exit();
    }

    // Locks first, so the machine wakes up locked: suspends once the lock is confirmed, or after 2 s
    // if it never is (e.g. another locker holds the screen).
    function suspend() {
        if (secure) {
            Quickshell.execDetached(["systemctl", "suspend"]);
            return;
        }
        suspending = true;
        lock();
        lockWait.restart();
    }

    function suspendNow() {
        if (!suspending)
            return;
        suspending = false;
        lockWait.stop();
        Quickshell.execDetached(["systemctl", "suspend"]);
    }

    onSecureChanged: if (secure) suspendNow()

    Timer {
        id: lockWait
        interval: 2000
        onTriggered: root.suspendNow()
    }

    function reboot() {
        Quickshell.execDetached(["systemctl", "reboot"]);
    }

    function shutdown() {
        Quickshell.execDetached(["systemctl", "poweroff"]);
    }

    // Restart into another boot entry (owner's call, 14 November 2026). Limine (12.9) publishes its
    // entries in the boot loader interface's EFI variables (LoaderEntries, LoaderEntrySelected), which
    // anyone can read. logind's own reboot-to-entry, which needs no password, only knows entries it finds
    // on /boot (it refused Limine's "Windows"), so the one-shot entry is set with `bootctl set-oneshot`
    // as root: pkexec, so the shell's polkit dialog asks for the password; then a normal reboot. Firmware
    // setup goes through logind and needs no password (allowed for the active session, checked).
    property var bootEntries: [] // [{ id, name }], the entry booted now left out
    property bool firmwareSetup // UEFI, so the firmware's setup can be asked for
    property bool bootBusy // waiting for the password or bootctl

    function refreshBootEntries() {
        if (!bootList.running)
            bootList.running = true;
    }

    function rebootInto(id: string) {
        if (bootBusy || !id)
            return;
        bootBusy = true;
        oneShot.command = ["pkexec", "bootctl", "set-oneshot", id];
        oneShot.running = true;
    }

    function rebootToFirmware() {
        Quickshell.execDetached(["systemctl", "reboot", "--firmware-setup"]);
    }

    Process {
        id: bootList
        command: [Quickshell.env("HOME") + "/.local/bin/psc", "boot-entries"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const got = JSON.parse(text);
                    root.bootEntries = got.entries;
                    root.firmwareSetup = got.efi;
                } catch (e) {
                    root.bootEntries = [];
                }
            }
        }
    }

    Process {
        id: oneShot
        // 0: set, so reboot; anything else (Cancel in the password dialog, a wrong password, bootctl
        // refusing) leaves the system as it is
        onExited: code => {
            root.bootBusy = false;
            if (code === 0)
                root.reboot();
            else
                console.warn(`Session: restart into another entry stopped (exit ${code})`);
        }
    }

    PamContext {
        id: pam

        onPamMessage: {
            if (responseRequired) {
                respond(root.password);
                root.password = "";
            }
        }

        onCompleted: result => {
            root.password = "";
            if (result === PamResult.Success)
                root.locked = false;
            else // e.g. faillock's "The account is locked due to 3 failed logins."
                root.error = messageIsError && message ? message : "Wrong password";
        }
    }
}
