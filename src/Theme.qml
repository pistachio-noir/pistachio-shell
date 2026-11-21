pragma Singleton

import Quickshell
import QtQuick

// The only place with colours and sizes. Values from pistachio-shell-design/*.dc.html.
Singleton {
    property bool tui: false
    // Colour scheme (owner's call, 14 November 2026; board pistachio-shell-design/noir-tones.html, "Pure neutral"):
    // Pistachio Noir, or Noir: neutral greys, light grey for what's active and one red for errors and
    // danger. The accents' names stay, so every file follows without change. shell.qml binds it.
    property bool noir: false
    readonly property real tuiTextSize: 13.3333
    readonly property int tuiLineHeight: 20
    readonly property int tuiButtonHeight: 32
    readonly property int tuiButtonPadding: 14
    readonly property int tuiBarHeight: 35
    readonly property int tuiBarCellHeight: tuiBarHeight - 1
    readonly property int tuiBarCellWidth: 40
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

    // The cat's coats keep their colours across shell palettes.
    readonly property var catSkins: [
        {value: "cream", title: "Cream", outline: "#A3B08F", fur: "#E5E9D8", eyes: "#15170F", cheeks: "#D9975A"},
        {value: "ginger", title: "Ginger", outline: "#895032", fur: "#E1A369", eyes: "#342417", cheeks: "#F0C996", stripes: "#AC653D"},
        {value: "midnight", title: "Midnight", outline: "#798195", fur: "#333848", eyes: "#DDE5A9", cheeks: "#BB92AF"}
    ]

    readonly property color bg: noir ? "#111111" : "#15170F"
    readonly property color bgAlt: noir ? "#1A1A1A" : "#1D2016"
    readonly property color overlay: noir ? "#262626" : "#2A2F1F"
    readonly property color overlay2: noir ? "#333333" : "#39412A"
    readonly property color muted: noir ? "#5E5E5E" : "#626F51" // ~3.4:1 on bg: never for small text
    readonly property color subtext: noir ? "#A6A6A6" : "#A3B08F"
    readonly property color text: noir ? "#E6E6E6" : "#E5E9D8"
    readonly property color textBright: noir ? "#F7F7F7" : "#F6F8EF"
    readonly property color pistachio: noir ? "#BDBDBD" : "#9FD88A" // active state only (Noir: light grey)
    readonly property color terracotta: noir ? "#C9675C" : "#DB8267" // Noir's one colour: errors and danger
    // the other accents are light greys in Noir, a little apart so readings still differ in weight
    readonly property color gold: noir ? "#D2D2D2" : "#E0B15E"
    readonly property color sageBlue: noir ? "#B4B4B4" : "#7DA3B3"
    readonly property color teal: noir ? "#C8C8C8" : "#7FC9A8"
    readonly property color lavender: noir ? "#BEBEBE" : "#AC8ED0"
    readonly property color clay: noir ? "#C4C4C4" : "#D9975A"
    readonly property color deep: noir ? "#0B0B0B" : "#0D0F09" // under bg: the Overview's backdrop tint and workspace cards (Overview boards)

    // Frosted panels (owner's request, 31 October 2026): how opaque the bar's and the panels' own
    // background is, 1 unless the Shell setting is on (shell.qml binds it to ShellSettings.frost);
    // Hyprland blurs what's behind them (a layer rule in the owner's config, docs/frosted-panels.md)
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
    readonly property int setupWidth: 880 // the first-run setup window (boards pistachio-shell-design/FirstRun/)
    readonly property int setupHeight: 600

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
    // Noir: shades of grey, keywords and functions brightest, comments quietest (still readable)
    readonly property var codeColours: noir ? ({
        plain: text.toString(), keyword: textBright.toString(), string: "#B8B8B8", number: "#D2D2D2",
        comment: "#8C8C8C", function: textBright.toString(), type: subtext.toString(), variable: text.toString(),
        flag: subtext.toString(), key: subtext.toString(), meta: subtext.toString(), add: "#D2D2D2",
        remove: terracotta.toString(), font: fontMono
    }) : ({
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
