import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// What opens when the pointer rests on the bar item, in place of the shell's
// plain tooltip: the panel's look in a line per room (Model.hoverRows), a
// tinted row with its pixel icon, name, a small meter of cells and the volume
// in the pixel type. Placed and framed the way the shell places and frames
// its own tooltip, so it opens where one would.
PopupWindow {
  id: card

  property Item target: null
  property var bar: null
  property bool shown: false
  property var rows: []
  // A line under the rows: an update waiting, something the engine says.
  property string note: ""
  // The panel's room colours (Model.roomToneHex) and the bar's figures' unit.
  property var palette: ({})
  property int unit: 2
  property string fontFamily: Style.font.family
  // The card takes the width its longest name needs on one line, between
  // the shell tooltip's 280 and 380, so a device name does not stack a word
  // a line; a longer one wraps at its words.
  readonly property var longestRow: rows.reduce(function(a, r) {
    return String(r && r.name || "").length > String(a && a.name || "").length ? r : a
  }, rows.length ? rows[0] : ({}))

  readonly property color foreground: Commons.Color.tooltip.text
  readonly property color background: Commons.Color.tooltip.background
  readonly property color dim: Qt.tint(foreground, Qt.rgba(background.r, background.g, background.b, 0.4))
  readonly property real gap: 6
  readonly property var barWindow: target ? target.QsWindow.window : null

  visible: shown && !!target && rows.length > 0
  color: "transparent"
  implicitWidth: Math.ceil(frame.implicitWidth)
  implicitHeight: Math.ceil(frame.implicitHeight)

  // A fresh surface maps at a whole-number scale before it learns the
  // output's fractional one; stay clear until it matches the bar, as the
  // shell's tooltip does.
  readonly property bool scaleReady: visible && !!barWindow && Math.round(devicePixelRatio * 120) === Math.round(barWindow.devicePixelRatio * 120)
  property bool revealed: false
  onVisibleChanged: if (!visible) revealed = false
  // Each time the card shows, its icons play, a row after another.
  property int plays: 0
  onRevealedChanged: if (revealed) plays++
  onScaleReadyChanged: if (scaleReady) Qt.callLater(function() { if (card.scaleReady) card.revealed = true })

  function toneOf(name) {
    return Qt.color(Model.roomToneHex(name, palette, String(foreground)))
  }

  anchor {
    id: cardAnchor
    window: card.barWindow
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1

    onAnchoring: {
      if (!card.target || !card.barWindow) return
      var t = card.target
      var x = t.width / 2 - card.implicitWidth / 2
      var y = t.height + card.gap
      var edge = card.bar ? card.bar.position : "top"
      if (edge === "bottom") y = -card.implicitHeight - card.gap
      else if (edge === "left") { x = t.width + card.gap; y = t.height / 2 - card.implicitHeight / 2 }
      else if (edge === "right") { x = -card.implicitWidth - card.gap; y = t.height / 2 - card.implicitHeight / 2 }
      var point = card.barWindow.contentItem.mapFromItem(t, x, y)
      cardAnchor.rect.x = Math.round(point.x)
      cardAnchor.rect.y = Math.round(point.y)
    }
  }

  BorderSurface {
    id: frame
    opacity: card.revealed ? 1 : 0
    implicitWidth: Math.round(Math.max(Style.space(280), Math.min(Style.space(380), probe.needWidth + Style.space(8) * 2)))
    implicitHeight: list.implicitHeight + Style.space(8) * 2
    color: Commons.Color.tooltip.background
    borderSpec: Border.surfaceSpec("tooltip", "border", Commons.Color.tooltip.border, 1)
    radius: Style.cornerRadius

    Column {
      id: list
      x: Style.space(8)
      y: Style.space(8)
      width: parent.width - x * 2
      spacing: Style.space(3)

      Repeater {
        model: card.rows

        HoverRow {
          required property var modelData
          required property int index
          width: list.width
          play: card.plays
          playDelay: index * 70
          entry: modelData
          tone: card.toneOf(modelData.tone)
          foreground: card.foreground
          dimColor: card.dim
          unit: card.unit
          fontFamily: card.fontFamily
        }
      }

      MonoText {
        step: "small"
        fontFamily: card.fontFamily
        visible: card.note !== ""
        width: list.width
        topPadding: Style.space(3)
        leftPadding: Style.space(6)
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: card.note
        color: card.dim
      }

      // What the bar item does, since the card stands where its tooltip would.
      MonoText {
        step: "small"
        fontFamily: card.fontFamily
        width: list.width
        topPadding: Style.space(3)
        leftPadding: Style.space(6)
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: "Click opens · right-click settings · middle-click mutes · scroll sets volume"
        color: card.dim
      }
    }
  }

  // Measures the longest row, for the card's width.
  HoverRow {
    id: probe
    visible: false
    width: 1
    entry: ({ name: card.longestRow.name || "", icon: card.longestRow.icon || "", mark: "sliders-horizontal", volume: 1 })
    unit: card.unit
    fontFamily: card.fontFamily
  }
}
