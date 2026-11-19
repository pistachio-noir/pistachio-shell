import qs
import qs.components
import qs.services
import qs.setup
import Quickshell
import Quickshell.Widgets
import QtQuick

// The first-run setup as a normal window like Settings (owner's call, 19 November 2026): about
// 880 px, the steps on the left, floated and centred by FirstRun. No layer-shell keyboard grab.
FloatingWindow {
    id: root
    title: "Pistachio Setup"
    implicitWidth: Theme.setupWidth
    implicitHeight: Theme.setupHeight
    minimumSize: Qt.size(760, 540)
    color: "transparent"
    visible: reveal.shown
    readonly property alias wizard: view
    // closed from outside (Super+Q, the compositor): the same as Skip, so it never nags
    onClosed: if (FirstRun.opened) FirstRun.finish("skip")
    onWindowConnected: {
        const window = contentItem.Window.window;
        if (window) window.flags = Qt.Window | Qt.FramelessWindowHint;
    }
    // made as setup opens (shell.qml loads it lazily): start closed, so it fades in
    property bool started
    Component.onCompleted: { Qt.callLater(() => root.started = true); focusLater.restart(); }
    Reveal { id: reveal; open: root.started && FirstRun.opened }

    Connections {
        target: FirstRun
        function onPresent() { focusLater.restart(); }
    }
    Timer { id: focusLater; interval: Classic.motionDuration + 40; onTriggered: if (FirstRun.opened) root.contentItem.Window.window?.requestActivate() }

    ClippingRectangle {
        id: surface
        objectName: "setup-surface"
        anchors.fill: parent
        radius: Classic.panelRadius
        color: Theme.bgAlt
        border.width: 1; border.color: Theme.overlay2
        contentInsideBorder: true
        opacity: reveal.progress
        scale: 0.98 + reveal.progress * 0.02

        FirstRunWizard {
            id: view
            anchors.fill: parent
            open: FirstRun.opened
            onMoveRequested: root.startSystemMove()
        }
        SetupController { wizard: view }
    }
}
