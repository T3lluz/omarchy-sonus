import QtQuick
import qs.Commons
import "Model.js" as Model

// A room's volume in the block face (Model.bigDigits), with a small % and
// the mark beside it, a pixel icon (Model.markFor): muted, or an equalizer
// shaping the sound. The mark's column is there either way, so nothing moves
// when one appears. The blocks are laid out on the font's character grid but
// drawn as rectangles, since typed block characters leave hairline seams.
// `value` follows the room's meter while it fills in, so the number counts
// up with it.
Item {
  id: figure

  property var value: null
  // The level it is counting up to. Its width is kept from the start, so the
  // room does not widen as the count passes 9 and 99.
  property var target: value
  property color tone: "white"
  property color foreground: "white"
  property string mark: ""
  property int markPlay: 0
  // A muted level reads quieter, as an unknown one does.
  property bool dimmed: false
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.bodySmall
  // The most it may take across. Where the room is short (a narrow screen),
  // the face steps down a size rather than push the name into breaking.
  property real maxWidth: Infinity
  // The size it draws at: `fontSize`, or the largest below it that fits.
  readonly property int faceSize: {
    var base = Math.round(fontSize)
    var charW = baseGrid.implicitWidth / 10
    for (var s = base; s > 7; s--) {
      var w = reserveCols * charW * s / base + Style.space(3) + Math.max(pct.implicitWidth, Math.round(s * 1.1))
      if (w <= maxWidth) return s
    }
    return 7
  }
  readonly property real markSize: Math.round(faceSize * 1.1)

  readonly property bool known: Model.hasLevel(value)
  readonly property var rows: Model.bigDigits(known ? String(Math.round(value)) : "--")
  readonly property int cols: rows[0].length
  readonly property int reserveCols: Math.max(cols,
    Model.hasLevel(target) ? Model.bigDigits(String(Math.round(target)))[0].length : 0)
  readonly property real cellW: grid.implicitWidth / 10
  readonly property real cellH: Math.round(metrics.height * 0.9)
  readonly property real digitsWidth: Math.round(reserveCols * cellW)
  // Fewer digits than kept room for sit at the right, next to the %.
  readonly property real digitsShift: Math.round((reserveCols - cols) * cellW)
  // Quiet text, from the panel (a tint toward the background).
  property color dimColor: Qt.darker(foreground, 1.5)
  readonly property color faceColor: known && !dimmed ? tone : dimColor
  // Every block of every row, as [col, row, "full" | "top" | "bottom"].
  readonly property var blocks: {
    var out = []
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        var ch = rows[r].charAt(c)
        if (ch === "█") out.push([c, r, "full"])
        else if (ch === "▀") out.push([c, r, "top"])
        else if (ch === "▄") out.push([c, r, "bottom"])
      }
    }
    return out
  }

  implicitWidth: digitsWidth + Style.space(3) + side.implicitWidth
  // The face sits two and a half rows tall: nothing hangs below the bottom bar.
  implicitHeight: Math.round(cellH * 2.5)

  FontMetrics {
    id: metrics
    font.family: figure.fontFamily
    font.pixelSize: figure.faceSize
  }

  // The width of the font's own characters, measured as drawn, at the size
  // it draws and at the size it would like.
  Text {
    id: grid
    visible: false
    text: "0000000000"
    font.family: figure.fontFamily
    font.pixelSize: figure.faceSize
  }

  Text {
    id: baseGrid
    visible: false
    text: "0000000000"
    font.family: figure.fontFamily
    font.pixelSize: figure.fontSize
  }

  Repeater {
    model: figure.blocks

    Rectangle {
      required property var modelData
      readonly property real from: modelData[1] * figure.cellH + (modelData[2] === "bottom" ? figure.cellH / 2 : 0)
      x: figure.digitsShift + Math.round(modelData[0] * figure.cellW)
      y: Math.round(from)
      width: Math.round((modelData[0] + 1) * figure.cellW) - x
      height: Math.round(from + (modelData[2] === "full" ? figure.cellH : figure.cellH / 2)) - y
      color: figure.faceColor
      antialiasing: false
    }
  }

  // The mark over the %, in one column as wide as the wider of the two.
  Item {
    id: side
    x: figure.digitsWidth + Style.space(3)
    implicitWidth: Math.max(pct.implicitWidth, markIcon.implicitWidth)
    height: figure.implicitHeight

    PixelIcon {
      id: markIcon
      visible: figure.mark !== ""
      anchors.horizontalCenter: parent.horizontalCenter
      name: figure.mark
      size: figure.markSize
      color: figure.dimmed ? figure.dimColor : figure.tone
      play: figure.markPlay
      playDelay: 220
    }

    PixelText {
      id: pct
      visible: figure.known
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      text: "%"
      size: Style.font.caption * 0.75
      color: figure.dimColor
    }
  }
}
