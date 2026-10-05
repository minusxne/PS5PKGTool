import QtQuick
import QtQuick.Shapes

// Circular progress ring (top bar task indicator).
Item {
    id: root
    property real value: 0
    property real thickness: 3
    property color color: Theme.accentBright
    property color track: Qt.rgba(1, 1, 1, 0.16)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.track
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: root.width / 2 - root.thickness; radiusY: root.height / 2 - root.thickness
                startAngle: 0; sweepAngle: 360
            }
        }
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: root.width / 2 - root.thickness; radiusY: root.height / 2 - root.thickness
                startAngle: -90; sweepAngle: 360 * Math.max(0, Math.min(1, root.value))
            }
        }
    }
}
