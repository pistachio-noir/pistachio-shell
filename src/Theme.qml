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

    // OLED black (owner, 22 November 2026; Experimental, Noir only: "it doesn't look good in pistachio
    // noir"; preview pistachio-shell-design/oled-tones.html): the background fully off, every surface a
    // step down and everything on it about a fifth darker, so nothing glows against the black. Panels
    // keep their 1 px overlay2 outline, which is what separates them from the black; drop shadows go.
    // shell.qml binds it to ShellSettings.oledLive (the switch and Noir); ignored in Pistachio Noir.
    property bool oled: false
    // one colour per look: Pistachio Noir, Noir, OLED Noir
    function tone(pistachio: color, grey: color, oledGrey: color): color {
        return !noir ? pistachio : oled ? oledGrey : grey;
    }

    readonly property color bg: tone("#15170F", "#111111", "#000000")
    readonly property color bgAlt: tone("#1D2016", "#1A1A1A", "#0A0A0A")
    readonly property color overlay: tone("#2A2F1F", "#262626", "#161616")
    readonly property color overlay2: tone("#39412A", "#333333", "#242424")
    readonly property color muted: tone("#626F51", "#5E5E5E", "#4A4A4A") // ~3.4:1 on bg: never for small text
    readonly property color subtext: tone("#A3B08F", "#A6A6A6", "#858585")
    readonly property color text: tone("#E5E9D8", "#E6E6E6", "#BABABA")
    readonly property color textBright: tone("#F6F8EF", "#F7F7F7", "#D0D0D0")
    readonly property color pistachio: tone("#9FD88A", "#BDBDBD", "#969696") // active state only (Noir: light grey)
    readonly property color terracotta: tone("#DB8267", "#C9675C", "#A5544B") // Noir's one colour: errors and danger
    // the other accents are light greys in Noir, a little apart so readings still differ in weight
    readonly property color gold: tone("#E0B15E", "#D2D2D2", "#A8A8A8")
    readonly property color sageBlue: tone("#7DA3B3", "#B4B4B4", "#8F8F8F")
    readonly property color teal: tone("#7FC9A8", "#C8C8C8", "#A0A0A0")
    readonly property color lavender: tone("#AC8ED0", "#BEBEBE", "#989898")
    readonly property color clay: tone("#D9975A", "#C4C4C4", "#9D9D9D")
    readonly property color deep: tone("#0D0F09", "#0B0B0B", "#000000") // under bg: the Overview's backdrop tint and workspace cards (Overview boards)

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
        plain: text.toString(), keyword: textBright.toString(), string: oled ? "#939393" : "#B8B8B8", number: gold.toString(),
        comment: oled ? "#707070" : "#8C8C8C", function: textBright.toString(), type: subtext.toString(), variable: text.toString(),
        flag: subtext.toString(), key: subtext.toString(), meta: subtext.toString(), add: gold.toString(),
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
