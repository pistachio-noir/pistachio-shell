pragma Singleton
import Quickshell
import QtQuick

// Explicit allowlist of shell preferences. No credentials, pairings, OS device selections,
// device levels/mutes, known senders, app launch history or user content is ever reset.
Singleton {
    id: root
    property string reviewing
    readonly property var defaults: ({
        experimental: {appearanceStyle:"classic",colourScheme:"pistachio",tuiTrayOpen:false,phonePreview:false},
        appearance: {frosted:false,frostStyle:"subtle",shadows:true,desktopIcons:true,workspaceOsd:true,tabbedOsd:true},
        display: {nightSchedule:false,nightFrom:1200,nightTo:420},
        sound: {headphonesTakeOver:true,volumeTick:true},
        notifications: {dnd:false,dndSchedule:false,dndFollowsNight:false,dndFrom:1320,dndTo:420,quietFullscreen:true,quietCalls:true,notificationSound:true,notificationRules:{}},
        lens: {lensProvider:"claude",lensClaudeModel:"claude-haiku-5-5",lensClaudeEffort:"medium",lensCodexModel:"gpt-6-luna",lensCodexEffort:"low",lensClaudeFallback:false,lensCodexFallback:false,lensSuggestCoding:true,lensClaudeCodingModel:"sonnet",lensClaudeCodingEffort:"high",lensCodexCodingModel:"gpt-6.1-sol",lensCodexCodingEffort:"high",quickChatTile:true},
        apps: {terminal:"",weatherCity:""},
        localsend: {localsendName:"",localsendFolder:"",localsendAcceptKnown:false}
    })
    readonly property var names: ({
        phonePreview:"Phone timer preview",appearanceStyle:"Style",colourScheme:"Colours",tuiTrayOpen:"Tray icons shown (TUI)",nightSchedule:"Night light schedule",nightFrom:"Night light start",nightTo:"Night light end",frosted:"Frosted panels",frostStyle:"Frost style",shadows:"Drop shadows",desktopIcons:"Desktop icons",workspaceOsd:"Workspace OSD",tabbedOsd:"Tabbed OSD",headphonesTakeOver:"Headphones take over",volumeTick:"Volume tick",dnd:"Do not disturb",dndSchedule:"Quiet schedule",dndFollowsNight:"Follow night light",dndFrom:"Quiet start",dndTo:"Quiet end",quietFullscreen:"Quiet in fullscreen",quietCalls:"Quiet during calls",notificationSound:"Notification sound",notificationRules:"App notification rules",lensProvider:"Preferred provider",lensClaudeModel:"Claude model",lensClaudeEffort:"Claude effort",lensCodexModel:"Codex model",lensCodexEffort:"Codex effort",lensClaudeFallback:"Claude fallback",lensCodexFallback:"Codex fallback",lensSuggestCoding:"Coding suggestions",lensClaudeCodingModel:"Claude coding model",lensClaudeCodingEffort:"Claude coding effort",lensCodexCodingModel:"Codex coding model",lensCodexCodingEffort:"Codex coding effort",quickChatTile:"Quick chat in quick settings",terminal:"Terminal",weatherCity:"Weather location",localsendName:"Device name",localsendFolder:"Receive folder",localsendAcceptKnown:"Accept known devices"
    })
    function available(page: string): bool { return defaults[page] !== undefined; }
    function changes(page: string): var {
        return Object.keys(defaults[page] || {}).filter(key => JSON.stringify(Store.saved[key]) !== JSON.stringify(defaults[page][key])).map(key => ({key:key,title:names[key],value:defaults[page][key]}));
    }
    function shown(value): string {
        if (typeof value === "boolean") return value ? "On" : "Off";
        if (typeof value === "object") return "Default rules";
        return value === "" ? "Automatic / default" : String(value);
    }
    function review(page: string) { reviewing = available(page) ? page : ""; }
    function cancel() { reviewing = ""; }
    function apply(page: string) {
        if (!Store.ready || page !== reviewing || !available(page)) return;
        for (const item of changes(page)) Store.saved[item.key] = item.value;
        cancel();
    }
}
