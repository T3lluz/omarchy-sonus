import QtQuick
import QtQuick.Window
import "Model.js" as Model

// A line in the pixel type (Model.pixelText): the panel's block digits and
// the %, drawn as rectangles on whole device pixels. `unit` is device pixels per cell, the same unit a PixelIcon beside
// it takes so their strokes match; 0 picks it from `size`, the height of a
// capital in logical pixels.
Item {
  id: line

  property string text: ""
  property color color: "white"
  property real size: 9
  property int unit: 0

  readonly property real dpr: Window.window && Window.window.devicePixelRatio > 0 ? Window.window.devicePixelRatio : 1
  readonly property int px: unit > 0 ? unit : Math.max(1, Math.round(size * dpr / 5))
  readonly property real cell: px / dpr
  readonly property var shape: Model.pixelText(text)

  implicitWidth: shape.width * cell
  implicitHeight: shape.height * cell

  // Starts on a whole device pixel wherever the layout puts it, checked after
  // each frame the window draws, as PixelIcon does.
  property real snapX: 0
  property real snapY: 0

  function snap() {
    if (!visible) return
    var p = line.mapToItem(null, 0, 0)
    var dx = Math.round(p.x * dpr) / dpr - p.x
    var dy = Math.round(p.y * dpr) / dpr - p.y
    if (Math.abs(dx - snapX) > 0.001) snapX = dx
    if (Math.abs(dy - snapY) > 0.001) snapY = dy
  }

  Component.onCompleted: snap()

  Connections {
    target: line.Window.window
    ignoreUnknownSignals: true
    function onAfterAnimating() { line.snap() }
  }

  Item {
    x: line.snapX
    y: line.snapY

    Repeater {
      model: line.shape.rects.length

      Rectangle {
        required property int index
        readonly property var q: line.shape.rects[index] || [0, 0, 0, 0]
        x: q[0] * line.cell
        y: q[1] * line.cell
        width: q[2] * line.cell
        height: q[3] * line.cell
        color: line.color
        antialiasing: false
      }
    }
  }
}
