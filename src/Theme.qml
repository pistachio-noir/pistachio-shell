pragma Singleton

import Quickshell
import QtQuick

// The only place with colours and sizes. Values from design/*.dc.html.
Singleton {
    property bool tui: false
    readonly property real tuiTextSize: 13.3333
    readonly property int tuiLineHeight: 20
    readonly property int tuiButtonHeight: 32
    readonly property int tuiButtonPadding: 14
    readonly property int tuiBarHeight: 41
    readonly property int tuiBarCell: 40
    readonly property int tuiControlMeterWidth: 140
    readonly property int tuiLauncherWidth: 576
    readonly property int tuiLauncherTop: 104
    readonly property int tuiLauncherRowHeight: 32
    readonly property int tuiLauncherMeterWidth: 176
    readonly property int tuiSwitcherWidth: 520
    readonly property int tuiSwitcherTop: 90
    readonly property int tuiPanelWidth: 384
    readonly property int tuiPanelGap: 15
    readonly property int tuiPanelMargin: 12
    readonly property int tuiCodeSize: 24
    readonly property int tuiRowHeight: 52
    readonly property int tuiSidebarWidth: 224
    readonly property int tuiHeaderHeight: 52
    readonly property color tuiSurface: bg
    readonly property color tuiBorder: overlay2
    readonly property color tuiRule: overlay
    readonly property color tuiHover: bgAlt
    readonly property string fontTui: "JetBrainsMono Nerd Font"

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
    readonly property color deep: "#0D0F09" // under bg: the Overview's backdrop tint and workspace cards (Overview boards)

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
    readonly property int barRadius: tui ? 0 : 28
    readonly property int barMargin: 16
    readonly property int chipHeight: 40
    readonly property int chipRadius: tui ? 0 : 20
    readonly property int tileRadius: tui ? 0 : 20
    readonly property int panelRadius: tui ? 0 : 28
    readonly property int lensPromptWidth: 560
    readonly property int lensAnswerWidth: 480
    readonly property int screenshotMenuTop: 96
    readonly property int screenshotTipWidth: 334
    readonly property int settingsWidth: 1040
    readonly property int settingsHeight: tui ? 800 : 760

    // Drop shadows from the boards (CSS box-shadow: 0 <y> <blur> black at <alpha>), for panels and
    // popups; the bar and the tray pill stay flat (owner's call).
    readonly property color shadow: "#000000"
    readonly property var shadowPanel: ({ y: 18, blur: 44, alpha: 0.6 }) // quick settings, centre, calendar
    readonly property var shadowSmall: ({ y: 14, blur: 36, alpha: 0.55 }) // toasts, OSD
    readonly property var shadowModal: ({ y: 24, blur: 60, alpha: 0.65 }) // launcher, polkit, power menu

    readonly property string fontUi: tui ? fontTui : "Manrope"
    readonly property string fontMono: tui ? fontTui : "JetBrains Mono" // code-like text
    // code blocks' colours (components/highlight.js, owner's request, 13 November 2026), as text for
    // its rich text; on the code block's bg
    readonly property var codeColours: ({
        plain: textBright.toString(), keyword: lavender.toString(), string: teal.toString(), number: clay.toString(),
        comment: subtext.toString(), function: gold.toString(), type: sageBlue.toString(), variable: clay.toString(),
        flag: sageBlue.toString(), key: sageBlue.toString(), meta: terracotta.toString(), add: teal.toString(),
        remove: terracotta.toString(), font: fontMono
    })
    readonly property string fontEmoji: "Noto Color Emoji" // the launcher's emoji picker

    // One easing curve for everything; CSS ease-out is close to OutCubic.
    readonly property int easing: Easing.OutCubic
    readonly property int hoverDuration: tui ? 80 : 120
    readonly property int motionDuration: tui ? 80 : 200
    readonly property int growDuration: 300 // the bar growing out of its handle, a touch slower (owner's request)
    readonly property int introDuration: 600 // the wallpaper fading in as the shell starts (owner's request)
    readonly property int settleDuration: 1200 // the wallpaper settling as showoff mode starts
    readonly property int dimDuration: 1500 // the wallpaper dimming as night light comes on
}
