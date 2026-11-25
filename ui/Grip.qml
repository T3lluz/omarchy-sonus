import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Commons as Commons

// Three rows of two dots: the usual sign for "drag me". Square dots on whole
// device pixels, as the pixel icons are drawn, and big enough to notice.
Grid {
  id: grip

  property color color: Commons.Color.foreground

  readonly property real dpr: Window.window && Window.window.devicePixelRatio > 0 ? Window.window.devicePixelRatio : 1
  readonly property real dot: Math.max(2, Math.round(Style.space(2) * dpr)) / dpr

  columns: 2
  spacing: grip.dot

  Repeater {
    model: 6

    Rectangle {
      width: grip.dot
      height: grip.dot
      color: grip.color
      antialiasing: false
    }
  }
}
