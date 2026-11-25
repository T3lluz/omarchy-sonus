import QtQuick
import qs.Commons

// What is playing, as cava hears it, as the title room's background: square
// pixel cells, one column a band from the lows on the left to the highs on
// the right, lit from the bottom up. Each row up is fainter than the one
// under it, until the top is only a shade over the room's own wash, so the
// mark, the title and the prompt read over it at any level. Nothing plays,
// nothing lights.
//
// Cells and gaps are whole device pixels from the room's corner, so every
// edge is sharp. `columns` and `rows` are what fits; the service runs cava
// with that many bars and scales them to `rows`.
Item {
  id: spectrum

  required property var host
  // One level a column, 0..rows, from the service.
  property var levels: []
  property color color: host.fg
  // How strong a lit cell is on the bottom row and on the top one. The
  // brightest rows sit behind the prompt and the mark, so even the floor is
  // faint enough for the words to read over it.
  property real floorAlpha: 0.1
  property real ceilingAlpha: 0.03
  // The cells are made once, this many rows and columns at most; a room
  // that grows or shrinks (the device list sliding open under it) only shows
  // or hides rows, never builds them again.
  readonly property int maxRows: 24
  readonly property int maxColumns: 64

  readonly property real dpr: host.dpr
  readonly property int cellPx: Math.max(2, Math.round(Style.space(4) * dpr))
  readonly property int gapPx: Math.max(1, Math.round(Style.space(1) * dpr))
  readonly property real pitch: (cellPx + gapPx) / dpr
  readonly property real cell: cellPx / dpr
  readonly property int columns: Math.min(maxColumns, Math.max(0, Math.floor((width * dpr + gapPx) / (cellPx + gapPx))))
  readonly property int rows: Math.min(maxRows, Math.max(0, Math.floor((height * dpr + gapPx) / (cellPx + gapPx))))
  // The grid sits in the middle of the room's width and on its floor.
  readonly property real startX: Math.round((width * dpr - (columns * (cellPx + gapPx) - gapPx)) / 2) / dpr
  readonly property real baseY: Math.floor(height * dpr) / dpr

  function rowAlpha(row) {
    return rows > 1 ? floorAlpha + (ceilingAlpha - floorAlpha) * row / (rows - 1) : floorAlpha
  }

  Repeater {
    model: spectrum.maxColumns

    Item {
      id: column
      required property int index
      readonly property int level: index < spectrum.columns
        ? Math.min(spectrum.rows, Math.max(0, spectrum.levels[index] || 0)) : 0

      visible: index < spectrum.columns
      x: spectrum.startX + index * spectrum.pitch
      width: spectrum.cell
      height: spectrum.height

      // Every cell is made once and only shown or hidden as the level
      // moves: cava sends 30 frames a second. A cell's colour is fixed by
      // its row, so a frame touches only the visibility of the cells whose
      // column changed.
      Repeater {
        model: spectrum.maxRows

        Rectangle {
          required property int index
          visible: index < column.level
          x: 0
          y: spectrum.baseY - spectrum.cell - index * spectrum.pitch
          width: spectrum.cell
          height: spectrum.cell
          color: Qt.rgba(spectrum.color.r, spectrum.color.g, spectrum.color.b, spectrum.rowAlpha(index))
          antialiasing: false
        }
      }
    }
  }
}
