import qs
import QtQuick
import QtQuick.Shapes

// A dashed rounded outline (the Overview boards' New card, empty slot and empty workspace), as the
// launcher's empty workspace cards draw theirs.
Shape {
    id: root

    property real radius: 20
    property color color: Theme.muted
    property real lineWidth: 1.5

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeColor: root.color
        strokeWidth: root.lineWidth
        strokeStyle: ShapePath.DashLine
        dashPattern: [3, 3]
        fillColor: "transparent"

        PathRectangle {
            x: root.lineWidth / 2
            y: root.lineWidth / 2
            width: root.width - root.lineWidth
            height: root.height - root.lineWidth
            radius: root.radius
        }
    }
}
