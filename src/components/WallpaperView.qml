import qs
import qs.services
import QtQuick

// A wallpaper filling this item, in its fit (Wallpapers.fitOf), cross-fading to the next: each new one
// fades in over whatever shows, and the ones under it go once it covers them, so stepping through
// quickly stays smooth. For the desktop (panels/Wallpaper.qml) and the switcher's live preview.
Item {
    id: root

    property string path // "" fades to nothing
    property int fadeDuration: Theme.growDuration
    // The size to decode pictures at, in device pixels (the screen's): a 3840 × 2160 picture on a
    // 1920 × 1080 screen otherwise sits in memory four times as large as anything it can show
    // (measured 12 November: about 50 MiB for the desktop alone). Only for the fits that scale the
    // picture ("fill" and "fit"); "center" and "tile" need its own size. Unset: never scaled.
    property size loadSize
    property var layers: [] // the pictures, bottom first
    property bool ready // the first picture is made once, as it's created
    // the newest picture's own size, once it's in (only without a loadSize, as in the switcher's preview)
    readonly property size imageSize: layers.length > 0 ? layers[layers.length - 1].sourceSize : Qt.size(0, 0)

    signal faded(string path) // a picture has fully faded in

    function fillMode(fit: string): int {
        return fit === "fit" ? Image.PreserveAspectFit : fit === "center" ? Image.Pad : fit === "tile" ? Image.Tile : Image.PreserveAspectCrop;
    }

    function scales(fit: string): bool {
        return fit !== "center" && fit !== "tile";
    }

    function covered(top) {
        const i = layers.indexOf(top);
        for (const below of layers.slice(0, i))
            below.destroy();
        layers = layers.slice(i);
    }

    onPathChanged: {
        if (ready)
            layers = layers.concat([layer.createObject(root, { path: path })]);
    }
    Component.onCompleted: {
        layers = [layer.createObject(root, { path: path })];
        ready = true;
    }

    Component {
        id: layer

        Image {
            id: picture

            required property string path

            function appear() {
                if (status !== Image.Loading && !fade.running && opacity < 1)
                    fade.start();
            }

            anchors.fill: parent
            source: path ? `file://${path}` : ""
            fillMode: root.fillMode(Wallpapers.fitOf(path))
            sourceSize: root.loadSize.width > 0 && root.scales(Wallpapers.fitOf(path)) ? root.loadSize : undefined
            asynchronous: true
            opacity: 0
            onStatusChanged: appear()
            Component.onCompleted: appear()

            NumberAnimation {
                id: fade
                target: picture
                property: "opacity"
                to: 1
                duration: root.fadeDuration
                easing.type: Theme.easing
                onFinished: {
                    root.covered(picture);
                    root.faded(picture.path);
                }
            }
        }
    }
}
