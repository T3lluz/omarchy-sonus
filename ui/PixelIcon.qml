import QtQuick
import QtQuick.Window
import "Pixels.js" as Pixels

// A pixel icon from Pixels.js, drawn as rectangles on whole device pixels so
// it stays sharp at any scale. The icon comes out as close to `size` as the
// grid allows: the 24-unit grid where a unit gets whole device pixels, the
// same grid halved (12 cells) where it would not. On a 1.25 scale a 14 px
// request draws 12 device pixels; a 20 px one draws 24.
// Never scaled: a fractional scale only ever picks the nearest sharp size.
Item {
  id: icon

  property string name: ""
  // Art drawn elsewhere ({ g12, g24 }, as Pixels.js keeps it), in place of a
  // named icon: the Sonus mark, whose knobs move.
  property var custom: null
  property real size: 16
  property color color: "white"
  // Device pixels per cell of the halved grid, to match other pixel art
  // (PixelText) stroke for stroke; 0 picks it from `size`.
  property int unit: 0

  readonly property var art: custom || Pixels.icons[name] || null
  readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
  // Device pixels across, in twelfths: odd counts take the halved grid. Its
  // strokes are this many device pixels thick either way.
  readonly property int twelfths: unit > 0 ? unit : Math.max(1, Math.round(size * dpr / 12))
  readonly property bool fine: twelfths % 2 === 0
  readonly property real cell: (fine ? twelfths / 2 : twelfths) / dpr
  readonly property var rects: art ? (fine ? art.g24 : art.g12) : []

  implicitWidth: twelfths * 12 / dpr
  implicitHeight: implicitWidth

  Repeater {
    model: icon.rects

    Rectangle {
      required property var modelData
      x: modelData[0] * icon.cell
      y: modelData[1] * icon.cell
      width: modelData[2] * icon.cell
      height: modelData[3] * icon.cell
      color: icon.color
      antialiasing: false
    }
  }
}
