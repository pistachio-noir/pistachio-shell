import QtQuick
import QtQuick.Window

// Shows the SDDM theme without SDDM: stand-ins for what the greeter provides (sddm, userModel,
// sessionModel, keyboard, config, primaryScreen), which Main.qml finds through this file's ids.
// The password "test" logs in; anything else fails. Power buttons only print.
// Run integrations/sddm/preview.sh; with `shot <file.png> [wrong|menu]` it saves a picture and quits.
Window {
    id: window

    readonly property var args: Qt.application.arguments
    readonly property int shot: args.indexOf("shot")

    width: 1920
    height: 1080
    visible: true
    color: "black"
    title: "Pistachio Noir SDDM preview"

    QtObject {
        id: sddm

        property string hostName: "arch"
        property bool canPowerOff: true
        property bool canReboot: true
        property bool canSuspend: true
        property bool canHibernate: false
        property bool canHybridSleep: false

        signal loginFailed
        signal loginSucceeded
        signal informationMessage(string message)

        function login(user, password, session) {
            console.log("preview: login as", user, "into session", session);
            answer.ok = password === "test";
            answer.restart();
        }
        function powerOff() { console.log("preview: shut down"); }
        function reboot() { console.log("preview: reboot"); }
        function suspend() { console.log("preview: suspend"); }
    }

    Timer {
        id: answer
        property bool ok
        interval: 400
        onTriggered: ok ? sddm.loginSucceeded() : sddm.loginFailed()
    }

    ListModel {
        id: userModel

        property int lastIndex: 0
        property string lastUser: "sx"

        ListElement { name: "sx"; realName: "sxnvte"; icon: ""; needsPassword: true }
    }

    ListModel {
        id: sessionModel

        property int lastIndex: 0

        ListElement { name: "Hyprland"; type: 2; comment: "" }
        ListElement { name: "Plasma"; type: 2; comment: "" }
        ListElement { name: "Plasma"; type: 1; comment: "" }
    }

    QtObject {
        id: keyboard

        property bool enabled: true
        property bool capsLock: false
        property bool numLock: false
        property int currentLayout: 0
        property var layouts: [{ shortName: "pl", longName: "Polish" }, { shortName: "us", longName: "English (US)" }]
    }

    QtObject {
        id: config

        property string background: ""
        property string clockFormat: "hh:mm"
    }

    QtObject {
        id: primaryScreen // truthy, like SDDM's `true` on the primary screen
    }

    Loader {
        id: theme
        anchors.fill: parent
        focus: true
        source: "../pistachio-noir/Main.qml"
    }

    Timer {
        running: window.shot >= 0
        interval: 1500
        onTriggered: {
            const state = window.args[window.shot + 2] ?? "";
            if (state === "wrong")
                sddm.loginFailed();
            if (state === "menu")
                theme.item.menuOpen = true;
            capture.start();
        }
    }

    Timer {
        id: capture
        interval: 600
        onTriggered: theme.item.grabToImage(r => {
            console.log("preview: saved", r.saveToFile(window.args[window.shot + 1]));
            Qt.quit();
        })
    }
}
