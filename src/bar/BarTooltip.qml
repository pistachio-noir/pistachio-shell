import qs
import qs.components
import Quickshell
import Quickshell.Wayland // layer-shell layer for this window (a Wayland protocol, not a compositor module)
import QtQuick

// The bar's tooltip (owner's request; not on a board): a small card 8 px above the bar naming what
// the pointer rests on, as lines of a label and an optional detail in subtext. Its own click-through
// window in the overlay layer, like the OSD; the bar says what to show and where.
PanelWindow {
    id: root

    property var lines: [] // [[label, detail], …]; plain text
    property real centre // the x it centres on, from the screen's left edge
    property bool open
    property int lift // from the screen's bottom edge to the card's bottom
    // room around the card for its shadow
    readonly property int side: Theme.shadowSmall.blur
    readonly property int above: Theme.shadowSmall.blur - Theme.shadowSmall.y
    readonly property int below: Theme.shadowSmall.blur + Theme.shadowSmall.y

    visible: reveal.shown
    anchors.bottom: true
    anchors.left: true
    // kept 8 px inside the screen's edges
    margins.left: Math.round(Math.max(8, Math.min(screen.width - card.width - 8, centre - card.width / 2))) - side
    margins.bottom: lift - below
    exclusiveZone: 0
    implicitWidth: side + card.width + side
    implicitHeight: above + card.height + below
    color: "transparent"
    WlrLayershell.namespace: "pistachio-panel" // frosted panels: Hyprland blurs the shell's layers by name
    mask: Region {} // clicks go through
    WlrLayershell.layer: WlrLayer.Overlay

    Reveal {
        id: reveal
        open: root.open
    }

    Rectangle {
        id: card

        x: root.side
        // fades in rising 6 px, and back
        y: root.above + 6 * (1 - reveal.progress)
        width: rows.implicitWidth + 28
        height: rows.implicitHeight + 20
        radius: Math.min(height / 2, Theme.tileRadius)
        color: Theme.surface
        border.width: 1
        border.color: Theme.overlay2
        opacity: reveal.progress

        // beneath the card (z -1), so it fades and rises with it
        Shadow {
            frostable: true
            z: -1
            kind: Theme.shadowSmall
            anchors.fill: parent
            radius: parent.radius
        }

        Column {
            id: rows

            anchors.centerIn: parent
            spacing: 4

            Repeater {
                model: root.lines

                Row {
                    required property var modelData

                    spacing: 8

                    Text {
                        text: parent.modelData[0]
                        textFormat: Text.PlainText
                        color: Theme.textBright
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }

                    Text {
                        visible: text !== ""
                        text: parent.modelData[1] ?? ""
                        textFormat: Text.PlainText
                        color: Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        font.features: { "tnum": 1 }
                    }
                }
            }
        }
    }
}
