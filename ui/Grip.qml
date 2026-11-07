import QtQuick
import qs.Commons
import qs.Commons as Commons

// Three rows of two dots: the usual sign for "drag me". Drawn rather than a
// font glyph, which at this size comes out too faint to notice.
Grid {
  id: grip

  property color color: Commons.Color.foreground

  columns: 2
  spacing: Style.space(2)

  Repeater {
    model: 6

    Rectangle {
      width: Math.max(2, Style.space(2))
      height: width
      radius: width / 2
      color: grip.color
    }
  }
}
