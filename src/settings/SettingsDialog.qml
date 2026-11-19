import qs
import qs.components
import qs.services
import QtQuick
import QtQuick.Controls.Basic as Basic

Basic.Popup {
    id: root
    objectName: "settings-dialog"
    parent: Basic.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(440, parent ? parent.width - 48 : 440)
    padding: Theme.tui ? 16 : 28
    modal: true
    focus: true
    closePolicy: Basic.Popup.NoAutoClose
    visible: SettingsHub.opened && (SettingsHub.editKey !== "" || Bluetooth.request !== null || SettingsHub.forgetDevice !== null || SettingsHub.restartMode !== "" || AppTheming.conflict !== null)
    readonly property var request: Bluetooth.request
    readonly property bool pairing: request !== null
    readonly property bool forgetting: !pairing && SettingsHub.forgetDevice !== null
    readonly property bool restarting: !pairing && !forgetting && SettingsHub.restartMode !== ""
    // theming integration: an app with its own theme, asked once Settings is open (the lowest priority)
    readonly property var themingApp: !pairing && !forgetting && !restarting && SettingsHub.editKey === "" ? AppTheming.conflict : null
    readonly property bool theming: themingApp !== null
    readonly property bool needsCode: pairing && (request.kind === "pin" || request.kind === "passkey")
    readonly property bool displayCode: pairing && request.kind.startsWith("display")
    readonly property string code: pairing ? request.code : ""
    readonly property bool valid: pairing ? !needsCode || (request.kind === "pin" ? /^[A-Za-z0-9]{1,16}$/.test(field.text) : /^\d{1,6}$/.test(field.text)) : field.text.trim() !== "" || SettingsHub.editKey === "games"
    readonly property string title: pairing ? (request.kind === "service" ? `Let ${Bluetooth.requestName} use ${Bluetooth.serviceName(request.uuid)}?` : `${displayCode ? "Pairing" : "Pair"} with ${Bluetooth.requestName}${displayCode ? "" : "?"}`)
        : forgetting ? `Forget ${Bluetooth.name(SettingsHub.forgetDevice)}?` : restarting ? (SettingsHub.restartMode === "force-restart" ? "Force restart shell?" : "Restart shell?") : theming ? `${themingApp.name} has its own theme` : ({weather:"Weather location",cider:"Cider token",name:"Device name",games:"Extra game windows"})[SettingsHub.editKey] || "Change setting"
    readonly property string description: pairing ? request.kind === "confirm" ? "Pair only if the device shows the same code."
        : request.kind === "service" ? "The device is paired but not trusted, so it asks each time."
        : displayCode ? "Type this code on the device, then press Enter on it."
        : needsCode ? "Enter the code shown on your device or in its manual."
        : "The device asks to pair with this computer."
        : forgetting ? "You will need to pair this device again to reconnect."
        : restarting ? "Active timers and transfers will end."
        : theming ? "Use Pistachio Noir and Noir? Your config is backed up first."
        : SettingsHub.editKey === "games" ? "Window classes, separated by commas. Find one with hyprctl activewindow."
        : SettingsHub.editKey === "weather" ? "Choose a city. We’ll check it before saving."
        : SettingsHub.editKey === "cider" ? "Open Cider and paste its API token. It is checked before saving." : "The name other devices see when you share files."

    function cancel() {
        if (pairing) Bluetooth.answer(false, "");
        else if (forgetting) SettingsHub.forgetDevice = null;
        else if (restarting) SettingsHub.restartMode = "";
        else if (theming) AppTheming.keep(themingApp.id);
        else SettingsHub.cancelEdit();
    }
    function submit() {
        if (forgetting) { Bluetooth.forget(SettingsHub.forgetDevice); SettingsHub.forgetDevice = null; }
        else if (restarting) { const mode = SettingsHub.restartMode; SettingsHub.restartMode = ""; SettingsHub.restartShell(mode); }
        else if (theming) AppTheming.use(themingApp.id);
        else if (!valid || SettingsHub.editBusy || displayCode) return;
        else if (pairing) Bluetooth.answer(true, field.text);
        else SettingsHub.saveEdit(field.text);
    }
    function fill() {
        field.text = pairing ? "" : SettingsHub.editKey === "weather" ? Weather.city : SettingsHub.editKey === "name" ? LocalSend.name : SettingsHub.editKey === "games" ? ShellSettings.gameClasses.join(", ") : "";
        if (needsCode || !pairing && !forgetting && !restarting && !theming) { field.forceActiveFocus(); field.selectAll(); }
        else cancelButton.forceActiveFocus();
    }
    onOpened: fill()
    onTitleChanged: if (visible) fill()
    background: PanelFrame { title: root.pairing ? "pair" : root.forgetting ? "forget" : SettingsHub.editKey; detail: root.pairing ? "bluetooth" : "setting"; radius: Theme.tui ? 0 : (Theme.panelRadius); color: Theme.bgAlt; border.width: 1; border.color: Theme.overlay2; Shadow { anchors.fill: parent; z: -1; radius: Theme.tui ? 0 : (Theme.panelRadius); kind: Theme.shadowModal } }
    Basic.Overlay.modal: Rectangle { color: Qt.rgba(Theme.bg.r,Theme.bg.g,Theme.bg.b,0.66) }
    contentItem: Column {
        spacing: 14
        Keys.onEscapePressed: root.cancel()
        Rectangle { visible:!Theme.tui;width: 48; height:48; radius: Theme.tui ? 0 : (24); color:Theme.overlay; Icon { anchors.centerIn:parent;size:22;paths:root.pairing?Icons.bluetooth:root.forgetting?Icons.trash:Icons.pencil;color:Theme.clay } }
        SettingsText { width:parent.width;text:root.title;font.pixelSize: Theme.tui ? Theme.tuiTextSize : 18;font.weight:Font.ExtraBold }
        SettingsText { width:parent.width;text:root.description;secondary:true }
        Rectangle {
            visible: root.code !== ""; width:parent.width;height:80;radius: Theme.tui ? 0 : (20);color:Theme.overlay
            Column { anchors.centerIn:parent; spacing:4
                SettingsText { text:root.code;font.family:Theme.fontMono;font.pixelSize: Theme.tui ? Theme.tuiCodeSize : 30;font.weight:Font.Medium }
                SettingsText { visible:root.displayCode && root.request.entered >= 0;text:root.pairing?root.request.entered+" digits entered":"";secondary:true;font.pixelSize: Theme.tui ? Theme.tuiTextSize : 11 }
            }
        }
        Basic.TextField {
            id: field
            objectName: "settings-edit-field"
            visible: root.needsCode || !root.pairing && !root.forgetting && !root.restarting && !root.theming
            width:parent.width;height:52;leftPadding:16;rightPadding:16
            color:Theme.textBright;selectionColor:Theme.overlay2;selectedTextColor:Theme.textBright
            placeholderText:root.needsCode?"Code":SettingsHub.editKey==="weather"?"City":"Enter a value…"
            placeholderTextColor:Theme.subtext
            echoMode:SettingsHub.editKey==="cider"?TextInput.Password:TextInput.Normal
            maximumLength:root.needsCode?(root.request.kind==="pin"?16:6):1024
            font.family:root.needsCode?Theme.fontMono:Theme.fontUi;font.pixelSize: Theme.tui ? Theme.tuiTextSize : 13
            selectByMouse:true
            onAccepted:root.submit()
            onTextEdited:SettingsHub.editError=""
            background:Rectangle { radius: Theme.tui ? 0 : (26);color:Theme.bg;border.width:1;border.color:field.activeFocus?Theme.subtext:Theme.overlay2 }
            Accessible.name:root.title
        }
        SettingsText { visible:text!=="";width:parent.width;text:SettingsHub.editError;color:Theme.terracotta;font.pixelSize: Theme.tui ? Theme.tuiTextSize : 12 }
        Row {
            anchors.right:parent.right;spacing:10
            SettingsButton { id:cancelButton;text:root.theming?"Keep mine":root.pairing&&root.request.kind==="service"?"Decline":"Cancel";onClicked:root.cancel() }
            SettingsButton { visible:!root.displayCode;text:root.theming?"Use Pistachio":root.restarting?"Restart":root.forgetting?"Forget":SettingsHub.editBusy?"Checking…":root.pairing?root.request.kind==="service"?"Allow":"Pair":"Save";active:!root.forgetting&&!root.restarting;danger:root.forgetting||root.restarting;enabled:(root.theming||root.restarting||root.forgetting||root.valid)&&!SettingsHub.editBusy;onClicked:root.submit() }
        }
    }
}
