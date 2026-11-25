import QtQuick
import qs.Commons

// Text in the plugin's Monocraft, every font pixel on whole device pixels.
// The same file in Batteries, ROG Deck, Server Dashboard and Sonus.
//
// Monocraft is pixel art, patched (scripts/patch-font.py) to ten font pixels
// to the em. Each step draws a font pixel as `cell` device pixels, a whole
// number picked from the window's scale d:
//
//   small = max(1, round(d))              states, hints, captions, headers
//   body  = max(small + 1, round(1.5 d))  names, rows, messages
//   title = max(body + 1, round(2 d))     figures, page titles
//
// and sets the font at 10 * cell / d logical pixels:
//
//   d      small  body  title    font size (logical px)
//   1      1      2     3        10    20    30
//   1.25   1      2     3         8    16    24
//   1.5    2      3     4        13.3  20    26.7
//   2      2      3     4        10    15    20
//
// A line is 11 font pixels (`line`), a character 6 wide (`advance`). It is
// drawn natively without antialiasing from a whole device pixel (snap()), so
// each font pixel covers exactly `cell` device pixels. Qt rounds a font to whole
// logical pixels; where 10 * cell / d is not whole (1.5), the next whole size
// is drawn scaled down to it, a few percent smaller than its box.
//
// Never bold: Monocraft's bold is a fifth of a pixel off the grid. A name and
// its state differ by step and colour (a state mixed 40% toward the
// background: Qt.tint(fg, Qt.rgba(bg.r, bg.g, bg.b, 0.4))), not by weight.
// The window's devicePixelRatio is read, not Screen's: at a 1.25 scale
// Screen.devicePixelRatio says 2.
Text {
  id: mono

  // "small", "body" or "title".
  property string step: "body"
  property string fontFamily: Style.font.family

  readonly property real dpr: Window.window && Window.window.devicePixelRatio > 0 ? Window.window.devicePixelRatio : 1
  readonly property int cell: cellFor(step, dpr)
  // One font pixel, a character's advance and a line, in logical pixels.
  readonly property real pixel: cell / dpr
  readonly property real advance: 6 * pixel
  readonly property real line: 11 * pixel

  readonly property real exactSize: 10 * pixel
  readonly property int setSize: Math.abs(exactSize - Math.round(exactSize)) < 0.01 ? Math.round(exactSize) : Math.ceil(exactSize)
  readonly property real shrink: exactSize / setSize

  function cellFor(step, d) {
    var small = Math.max(1, Math.round(d))
    var body = Math.max(small + 1, Math.round(1.5 * d))
    if (step === "small") return small
    if (step === "title") return Math.max(body + 1, Math.round(2 * d))
    return body
  }

  renderType: Text.NativeRendering
  antialiasing: false
  font.family: fontFamily
  font.pixelSize: setSize
  font.bold: false

  // Where the text starts, moved to a quarter past a whole device pixel.
  // Qt picks a glyph's image by where it falls inside a pixel, and a line
  // starting a hair short of one (8.9999 for 9) got images that lost their
  // first column. A quarter past also absorbs Qt's 1/64 px rounding of the
  // advance at 1.25 for about 60 characters a line. Checked every frame the
  // window draws, since any ancestor can move the text.
  property real snapX: 0
  property real snapY: 0
  function snap() {
    if (!parent) return
    var at = parent.mapToItem(null, x, y)
    var dx = (Math.round(at.x * dpr) + 0.25 - at.x * dpr) / dpr
    var dy = (Math.round(at.y * dpr) + 0.25 - at.y * dpr) / dpr
    if (Math.abs(dx - snapX) > 0.001) snapX = dx
    if (Math.abs(dy - snapY) > 0.001) snapY = dy
  }
  Connections {
    target: mono.Window.window
    enabled: mono.visible
    function onAfterAnimating() { mono.snap() }
  }
  Component.onCompleted: snap()

  transform: [
    Scale {
      xScale: mono.shrink
      yScale: mono.shrink
      origin.x: mono.effectiveHorizontalAlignment === Text.AlignRight ? mono.width
        : mono.effectiveHorizontalAlignment === Text.AlignHCenter ? mono.width / 2 : 0
    },
    Translate { x: mono.snapX; y: mono.snapY }
  ]
}
