import qs
import QtQuick

Canvas {
    id: root
    required property bool welcome
    property bool activeMotion
    property real orbit: 0

    onWelcomeChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Connections { target: Theme; function onNoirChanged() { root.requestPaint(); } }

    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        ctx.fillStyle = Qt.rgba(Theme.deep.r, Theme.deep.g, Theme.deep.b, welcome ? 1 : 0.84);
        ctx.fillRect(0, 0, width, height);
        const glows = [[0.78, 0.18, Theme.pistachio, 0.10], [0.12, 0.96, Theme.teal, 0.05]];
        for (const [x, y, color, alpha] of glows) {
            const glow = ctx.createRadialGradient(width * x, height * y, 0, width * x, height * y, width * 0.45);
            glow.addColorStop(0, Qt.rgba(color.r, color.g, color.b, alpha));
            glow.addColorStop(1, "transparent");
            ctx.fillStyle = glow;
            ctx.fillRect(0, 0, width, height);
        }
        if (welcome) {
            ctx.strokeStyle = Theme.overlay2;
            for (const [radius, alpha] of [[150, 0.55], [230, 0.42], [320, 0.32], [420, 0.22]]) {
                ctx.globalAlpha = alpha;
                ctx.beginPath();
                ctx.arc(width / 2, height * 5 / 12, radius, 0, 2 * Math.PI);
                ctx.stroke();
            }
            ctx.globalAlpha = 1;
        }
    }

    NumberAnimation on orbit {
        from: 0; to: 2 * Math.PI
        duration: 85000
        loops: Animation.Infinite
        running: root.welcome && root.activeMotion
    }

    Repeater {
        model: root.welcome ? [[150, 3.5], [230, -0.52], [320, 1.05], [420, 2.45], [320, -1.92]] : []
        Rectangle {
            required property var modelData
            width: 7; height: 7; radius: 4
            color: Theme.muted
            x: root.width / 2 + modelData[0] * Math.cos(modelData[1] + root.orbit) - width / 2
            y: root.height * 5 / 12 + modelData[0] * Math.sin(modelData[1] + root.orbit) - height / 2
        }
    }
}
