pragma Singleton

import Quickshell
import QtQuick

// The only place with colours and sizes. Values from design/*.dc.html.
Singleton {
    readonly property color bg: "#15170F"
    readonly property color bgAlt: "#1D2016"
    readonly property color overlay: "#2A2F1F"
    readonly property color overlay2: "#39412A"
    readonly property color muted: "#626F51" // ~3.4:1 on bg: never for small text
    readonly property color subtext: "#A3B08F"
    readonly property color text: "#E5E9D8"
    readonly property color textBright: "#F6F8EF"
    readonly property color pistachio: "#9FD88A" // active state only
    readonly property color terracotta: "#DB8267"
    readonly property color gold: "#E0B15E"
    readonly property color sageBlue: "#7DA3B3"
    readonly property color teal: "#7FC9A8"
    readonly property color lavender: "#AC8ED0"
    readonly property color clay: "#D9975A"

    // Frosted panels (owner's request, 31 October 2026): how opaque the bar's and the panels' own
    // background is, 1 unless the Shell setting is on (shell.qml binds it to ShellSettings.frost);
    // Hyprland blurs what's behind them (a layer rule in the owner's config, README)
    property real frost: 1
    readonly property color surface: glass(bgAlt)

    function glass(c: color): color {
        return Qt.rgba(c.r, c.g, c.b, c.a * frost);
    }

    readonly property int barWidth: 640
    readonly property int barHeight: 56
    readonly property int barRadius: 28
    readonly property int barMargin: 16
    readonly property int chipHeight: 40
    readonly property int chipRadius: 20
    readonly property int tileRadius: 20
    readonly property int panelRadius: 28
    readonly property int lensPromptWidth: 560
    readonly property int lensAnswerWidth: 480

    // Drop shadows from the boards (CSS box-shadow: 0 <y> <blur> black at <alpha>), for panels and
    // popups; the bar and the tray pill stay flat (owner's call).
    readonly property color shadow: "#000000"
    readonly property var shadowPanel: ({ y: 18, blur: 44, alpha: 0.6 }) // quick settings, centre, calendar
    readonly property var shadowSmall: ({ y: 14, blur: 36, alpha: 0.55 }) // toasts, OSD
    readonly property var shadowModal: ({ y: 24, blur: 60, alpha: 0.65 }) // launcher, polkit, power menu

    readonly property string fontUi: "Manrope"
    readonly property string fontMono: "JetBrains Mono" // code-like text
    readonly property string fontEmoji: "Noto Color Emoji" // the launcher's emoji picker

    // One easing curve for everything; CSS ease-out is close to OutCubic.
    readonly property int easing: Easing.OutCubic
    readonly property int hoverDuration: 120
    readonly property int motionDuration: 200
    readonly property int growDuration: 300 // the bar growing out of its handle, a touch slower (owner's request)
    readonly property int introDuration: 600 // the wallpaper fading in as the shell starts (owner's request)
    readonly property int settleDuration: 1200 // the wallpaper settling as showoff mode starts
    readonly property int dimDuration: 1500 // the wallpaper dimming as night light comes on
}
