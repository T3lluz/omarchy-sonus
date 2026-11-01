import QtQuick
import QtQuick.Shapes
import "Drawings.js" as Drawings

// A drawing from Drawings.js, as Batteries draws its devices: one solid
// silhouette with fine details cut out of it. Fitted inside the item by what
// it draws, not by its grid, and centred.
Item {
  id: root

  property string name: "laptop"
  property color color: "white"

  readonly property var glyph: Drawings.drawings[name] || null
  readonly property var ink: glyph ? glyph.ink : [0, 0, 48, 48]
  readonly property real fit: Math.min(width / (ink[2] - ink[0]), height / (ink[3] - ink[1]))

  Shape {
    width: 48
    height: 48
    // Ink origin to zero, then scale about zero, then centre: applied in
    // list order.
    transform: [
      Translate { x: -root.ink[0]; y: -root.ink[1] },
      Scale { xScale: root.fit; yScale: root.fit },
      Translate {
        x: (root.width - (root.ink[2] - root.ink[0]) * root.fit) / 2
        y: (root.height - (root.ink[3] - root.ink[1]) * root.fit) / 2
      }
    ]
    preferredRendererType: Shape.CurveRenderer
    // Sampled down from three times the painted size, so the hairline cuts
    // stay whole at row size.
    layer.enabled: true
    layer.smooth: true
    layer.textureSize: Qt.size(width * root.fit * 3, height * root.fit * 3)

    ShapePath {
      fillColor: root.color
      // Negative, not zero: zero still strokes.
      strokeWidth: -1
      fillRule: ShapePath.OddEvenFill
      PathSvg { path: root.glyph ? root.glyph.path : "" }
    }
  }
}
