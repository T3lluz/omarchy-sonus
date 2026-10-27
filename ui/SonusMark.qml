import QtQuick
import QtQuick.Shapes

// A center dot with two sound-waves on each side, tilted 45 degrees so the
// sound travels corner to corner. Two waves instead of three keep the gaps
// open at bar size. Muted drops the outer waves and dims the rest. Drawn as
// vectors: a canvas buffer at bar size came out as noise.
Item {
  id: mark

  property color color: "white"
  property bool muted: false

  readonly property real s: Math.min(width, height)
  readonly property real cx: width / 2
  readonly property real cy: height / 2
  readonly property real stroke: Math.max(1.5, s * 0.1)
  readonly property real tilt: -45
  readonly property real sweep: 96

  opacity: muted ? 0.45 : 1

  Rectangle {
    anchors.centerIn: parent
    width: mark.s * 0.2
    height: width
    radius: width / 2
    color: mark.color
  }

  Shape {
    anchors.fill: parent
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer

    Wave { radius: mark.s * 0.25; facing: 0 }
    Wave { radius: mark.s * 0.25; facing: 180 }
    Wave { radius: mark.s * 0.42; facing: 0; visible: !mark.muted }
    Wave { radius: mark.s * 0.42; facing: 180; visible: !mark.muted }
  }

  // One arc centred on `facing`, measured from the tilted axis.
  component Wave: ShapePath {
    id: wave
    property real radius: 8
    property real facing: 0
    property bool visible: true
    readonly property real start: mark.tilt + facing - mark.sweep / 2
    readonly property real rad: start * Math.PI / 180

    strokeColor: visible ? mark.color : "transparent"
    fillColor: "transparent"
    strokeWidth: mark.stroke
    capStyle: ShapePath.RoundCap
    joinStyle: ShapePath.RoundJoin
    startX: mark.cx + radius * Math.cos(rad)
    startY: mark.cy + radius * Math.sin(rad)

    PathAngleArc {
      centerX: mark.cx
      centerY: mark.cy
      radiusX: wave.radius
      radiusY: wave.radius
      startAngle: wave.start
      sweepAngle: mark.sweep
    }
  }
}
