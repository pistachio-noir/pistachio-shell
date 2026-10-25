pragma Singleton

import Quickshell
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
