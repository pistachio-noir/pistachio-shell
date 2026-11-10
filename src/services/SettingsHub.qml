pragma Singleton

import Quickshell
import qs
import QtQuick

// Navigation and validated text edits for the normal Settings window. UI never starts processes.
Singleton {
    id: root
    property bool opened
    property string page: "appearance"
    property string target: ""
    signal present
    signal wallpapersRequested
    signal showoffRequested
    property string placedAddress
    readonly property var window: Compositor.windows.find(w => w.title === "Pistachio Settings" && w.pid === Quickshell.processId) ?? null
    onWindowChanged: {
        if (opened && window && window.bounds.width > 0 && window.address !== placedAddress) {
            placedAddress = window.address;
            Compositor.placeSettingsWindow(window, Theme.settingsWidth, Theme.settingsHeight);
        }
        if (!window) placedAddress = "";
    }

    function openPage(section: string, control: string) {
        page = section || "appearance";
        target = control || "";
        opened = true;
        present();
    }

    property string editKey
    property string editError
    property bool editBusy
    property int editGeneration
    property var forgetDevice: null

    function beginEdit(key: string) {
        cancelEdit();
        editKey = key;
    }

    function cancelEdit() {
        editGeneration++;
        editKey = "";
        editError = "";
        editBusy = false;
    }

    function saveEdit(input: string) {
        if (!editKey || editBusy) return;
        const value = input.trim();
        if (!value) { editError = "Enter a value first."; return; }
        const key = editKey, generation = ++editGeneration;
        editBusy = true;
        editError = "";
        const done = (result, problem) => {
            if (generation !== editGeneration || key !== editKey) return;
            editBusy = false;
            if (problem) { editError = problem; return; }
            if (key === "weather") Weather.setCity(result.name);
            else if (key === "cider") Cider.setToken(result);
            else if (key === "name") LocalSend.setName(result);
            cancelEdit();
        };
        if (key === "weather") Weather.lookup(value, done);
        else if (key === "cider") Cider.check(value, done);
        else if (key === "name") done(value, "");
        else { editBusy = false; editError = "Unknown setting."; }
    }

    function openChats() {
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && xdg-open "$1"', "sh", Quickshell.env("HOME") + "/lens-chats"]);
    }

    function openSource() {
        if (/^https:\/\//.test(About.repo)) Quickshell.execDetached(["xdg-open", About.repo]);
    }
}
