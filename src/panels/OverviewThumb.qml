import qs
import qs.components
import qs.services
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick

// A window in the Overview (boards Overview*.html): its live picture in a rounded card of the
// window's own shape, fitted inside this item (a fixed 16:10 card filled by the picture cut tall
// windows down to a strip, owner's report, 12 November), with the board's shadow. The picture is
// drawn solid (shaders/opaque.frag: a see-through window shows as it would opaque). A tabbed group
// shows its tabs as chips along the top. The ✕ in the corner closes it; `dimmed` is a search's
// non-match. Recompile the shader after editing it:
//   /usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o opaque.frag.qsb opaque.frag
Item {
    id: root

    property var w: null // a Compositor.windows entry: the one showing, for a group
    property var tabs: [] // a tabbed group's windows, in order; [] for a lone window
    property bool live: true
    property bool selected
    property bool hovered
    property bool closable: selected || hovered
    property bool dimmed
    property real radius: 16
    property string badge // a workspace's name, top right (search, all windows)
    // the window's shape, from its size on screen (known before the picture comes), else 16:10
    property bool atTop // the card at the top of this item (a column), else at its bottom, just above its label
    readonly property rect cardRect: Qt.rect(card.x, card.y, card.width, card.height) // where the card is drawn
    readonly property real aspect: w && w.bounds.width > 0 && w.bounds.height > 0 ? w.bounds.width / w.bounds.height : 1.6

    signal closeClicked

    opacity: dimmed ? 0.35 : 1
    // a slight lift under the pointer
    scale: hovered && !dimmed ? 1.025 : 1

    Behavior on scale {
        NumberAnimation {
            duration: Theme.hoverDuration
            easing.type: Theme.easing
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.motionDuration
            easing.type: Theme.easing
        }
    }

    Shadow {
        kind: Theme.shadowSmall
        anchors.fill: card
        radius: card.radius
    }

    ClippingRectangle {
        id: card

        anchors.horizontalCenter: parent.horizontalCenter
        y: root.atTop ? 0 : root.height - height
        width: Math.min(root.width, root.height * root.aspect)
        height: Math.min(root.height, root.width / root.aspect)
        radius: root.radius
        color: Theme.bg
        border.width: 1
        border.color: Theme.overlay2

        ScreencopyView {
            anchors.fill: parent
            layer.enabled: hasContent
            layer.effect: ShaderEffect {
                fragmentShader: Qt.resolvedUrl("../shaders/opaque.frag.qsb")
            }
            captureSource: root.visible ? root.w?.toplevel ?? null : null // only while the Overview shows (the cards stay while it's closed)
            live: root.live
            opacity: hasContent ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.motionDuration
                    easing.type: Theme.easing
                }
            }
        }

        // no picture yet (or none to be had): the app's icon
        Image {
            anchors.centerIn: parent
            width: 40
            height: 40
            sourceSize: Qt.size(80, 80)
            source: Apps.iconFor(root.w?.appId ?? "")
            // like every other app icon in the shell: loaded here on the main thread while the chips'
            // copy of the same icon loaded on the image thread, the shell aborted ("pure virtual
            // method called" in QPixmap::load), at startup or as the Overview opened (12 November)
            asynchronous: true
            visible: status === Image.Ready
            opacity: 0.5
            z: -1
        }

        // the card's own edge over the picture
        Rectangle {
            anchors.fill: parent
            radius: card.radius
            color: "transparent"
            border.width: 1
            border.color: Theme.overlay2
        }

        // a tabbed group's tabs, the showing one in pistachio (cut short of the workspace badge)
        Item {
            visible: root.tabs.length > 1
            x: 8
            y: 8
            width: card.width - 16 - (root.badge !== "" ? badgeBox.width + 8 : 0)
            height: 24
            clip: true

        Row {
            spacing: 4

            Repeater {
                model: root.tabs

                Rectangle {
                    required property var modelData
                    readonly property bool showing: modelData.address === root.w?.address

                    height: 24
                    width: Math.min(110, tabName.implicitWidth + 20)
                    radius: 12
                    color: showing ? Theme.pistachio : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.9)

                    Text {
                        id: tabName
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 20)
                        elide: Text.ElideRight
                        text: Apps.nameFor(parent.modelData.appId) || parent.modelData.appId || "Window"
                        color: parent.showing ? Theme.bg : Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                        font.weight: parent.showing ? Font.ExtraBold : Font.Bold
                    }
                }
            }
        }
        }

        // the workspace it's on
        Rectangle {
            id: badgeBox
            visible: root.badge !== ""
            anchors.right: parent.right
            anchors.rightMargin: 10
            y: 10
            height: 24
            width: badgeText.implicitWidth + 20
            radius: 12
            color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.85)
            border.width: 1
            border.color: Theme.overlay2

            Text {
                id: badgeText
                anchors.centerIn: parent
                text: root.badge
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: 11
                font.weight: Font.Bold
            }
        }
    }

    // ✕ in the top-left corner, half outside the card
    Item {
        x: card.x - 14
        y: card.y - 14
        width: 44
        height: 44
        visible: root.closable
        z: 2

        Rectangle {
            anchors.centerIn: parent
            width: 28
            height: 28
            radius: 14
            color: closeMouse.containsMouse ? Theme.overlay : Theme.bgAlt
            border.width: 1
            border.color: Theme.overlay2

            Icon {
                anchors.centerIn: parent
                size: 14
                paths: Icons.close
                color: closeMouse.containsMouse ? Theme.textBright : Theme.text
            }
        }

        MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.closeClicked()
            Accessible.role: Accessible.Button
            Accessible.name: "Close window"
        }
    }
}
