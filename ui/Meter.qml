import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui
import "Model.js" as Model

// A volume drawn as Batteries draws a battery: an outlined body split into
// cells (Model.meterCells), each filled to the full height of the body, a
// tenth of the level each. It fills in from empty when the panel opens and
// slides to a new level after that. The pointer presses the cells under it
// down a little, and `press` sends a ripple out from a point, as Weave's pad
// does. An input's meter also lights the cells it hears.
//
// It is the fader too: press or drag across it to set the level, in 5%
// steps, with a tick where the pointer would set it. Right-click mutes.
Item {
  id: meter

  required property var host
  // 0..100.
  property real level: 0
  property bool known: true
  property int segments: 10
  property color tone: "white"
  property color foreground: "white"
  // How long after the panel opens this one starts filling, in ms, so the
  // panel fills from the top down.
  property int delay: 0
  // Small meters (an app's) draw a thinner body.
  property bool small: false
  // Muted: drawn quieter, its level kept so unmuting brings it back.
  property bool dimmed: false
  // What an input hears right now, 0..1.
  property real peak: 0
  property bool interactive: true
  property real step: 0.05
  property string tipText: ""

  signal moved(real value)
  signal rightClicked()

  // What is drawn: the level while it fills in, else the level.
  property real shown: 0
  property var dent: null
  property var ripples: []
  readonly property bool dragging: area.pressed && area.pressedButtons & Qt.LeftButton
  readonly property bool hot: area.containsMouse || dragging
  readonly property real pointerValue: area.containsMouse || dragging
    ? Model.faderValue(area.mouseX - cellRow.x, cellRow.width, step) : -1

  // Everything inside is laid out in whole device pixels, as the spectrum
  // is: on a 1.25 screen fractional cells and gaps blur together, and a thin
  // app meter's cells merge into one bar.
  readonly property real dpr: Window.window && Window.window.devicePixelRatio > 0 ? Window.window.devicePixelRatio : 1
  readonly property real line: Math.max(1, Math.round(Style.space(1) * dpr)) / dpr
  readonly property real inset: small ? Math.max(1, Style.space(1)) : Math.max(2, Style.space(2))
  readonly property real gap: small ? Math.max(1, Style.space(1)) : Math.max(2, Style.space(2))

  implicitHeight: small ? Style.space(11) : Style.space(18)

  readonly property var cells: Model.meterCells({
    segments: segments,
    level: known ? shown : 0,
    dent: dent,
    peak: dimmed ? 0 : peak,
    ripples: ripples.map(function(r) { return { x: r.x, age: meter.host.clock - r.at } })
  })

  // Old ripples go once they have run out.
  Connections {
    target: meter.host
    enabled: meter.ripples.length > 0
    function onClockChanged() {
      var left = meter.ripples.filter(function(r) { return meter.host.clock - r.at < Model.METER.RIPPLE_MS })
      if (left.length !== meter.ripples.length) meter.ripples = left
    }
  }

  Connections {
    target: meter.host
    function onEntryChanged() { meter.enter() }
  }

  function enter() {
    fillIn.stop()
    settle.stop()
    if (Style.reduceMotion || !known) { shown = known ? level : 0; return }
    shown = 0
    fillIn.start()
  }

  // A point in the meter's own coordinates. Only near the body presses.
  function hover(x, y) {
    if (x < 0 || x > body.width || y < -height * 0.6 || y > height * 1.6) { dent = null; return }
    dent = x / body.width
  }

  function press(x, y) {
    if (Style.reduceMotion) return
    var next = ripples.slice(-3)
    next.push({ x: Math.max(0, Math.min(1, x / body.width)), at: host.clock })
    ripples = next
  }

  function setFrom(x) {
    var v = Model.faderValue(x - cellRow.x, cellRow.width, step)
    fillIn.stop()
    settle.stop()
    shown = v * 100
    moved(v)
  }

  Component.onCompleted: { shown = known ? level : 0; snap() }

  // How far the cells move to start on a whole device pixel, checked after
  // each frame the window draws, as PixelIcon does.
  property real snapX: 0
  property real snapY: 0

  function snap() {
    if (!visible) return
    var p = body.mapToItem(null, 0, 0)
    var dx = Math.round(p.x * dpr) / dpr - p.x
    var dy = Math.round(p.y * dpr) / dpr - p.y
    if (Math.abs(dx - snapX) > 0.001) snapX = dx
    if (Math.abs(dy - snapY) > 0.001) snapY = dy
  }

  Connections {
    target: meter.Window.window
    ignoreUnknownSignals: true
    function onAfterAnimating() { meter.snap() }
  }

  // Slides to the level as it is now. The target is set here rather than
  // bound: this runs from onLevelChanged, which can come before a binding on
  // `level` has updated, and the slide would then head for the level before.
  // On the wheel that drew every step one behind, so a turn the other way
  // first went one more step the old way.
  function slide() {
    settle.stop()
    settle.to = level
    settle.start()
  }

  onLevelChanged: {
    if (fillIn.running || dragging) return
    if (Style.reduceMotion || !host.opened) { shown = level; return }
    slide()
  }

  SequentialAnimation {
    id: fillIn
    PauseAnimation { duration: Style.duration(meter.delay) }
    NumberAnimation { target: meter; property: "shown"; to: meter.level; duration: Style.duration(680); easing.type: Easing.OutCubic }
    // The level may have moved on while it filled in.
    ScriptAction { script: if (meter.shown !== meter.level) meter.slide() }
  }

  NumberAnimation {
    id: settle
    target: meter
    property: "shown"
    duration: Style.duration(420)
    easing.type: Easing.OutCubic
  }

  Rectangle {
    id: body
    width: parent.width
    height: parent.height
    color: "transparent"
    radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, 3) : 0
    border.width: meter.line
    border.color: Qt.rgba(meter.tone.r, meter.tone.g, meter.tone.b, meter.known && !meter.dimmed ? (meter.hot ? 0.85 : 0.6) : 0.3)
    opacity: meter.dimmed ? 0.5 : 1

    Item {
      id: cellRow
      readonly property real dpr: meter.dpr
      readonly property int edgePx: Math.round((meter.line + meter.inset) * dpr)
      readonly property int gapPx: Math.max(1, Math.round(meter.gap * dpr))
      readonly property int innerPx: Math.max(0, Math.floor(body.width * dpr) - edgePx * 2)
      readonly property int cellPx: Math.max(1, Math.floor((innerPx - gapPx * (meter.segments - 1)) / meter.segments))
      // The pixels the cells do not divide evenly go one each to the first cells.
      readonly property int extraPx: Math.max(0, innerPx - cellPx * meter.segments - gapPx * (meter.segments - 1))
      readonly property real cellWidth: cellPx / dpr
      // Plus whatever puts the row on a whole device pixel of the window: the
      // meter itself sits wherever the room's layout puts it.
      x: edgePx / dpr + meter.snapX
      y: edgePx / dpr + meter.snapY
      width: innerPx / dpr
      height: Math.max(0, Math.floor(body.height * dpr) - edgePx * 2) / dpr

      function cellX(i) { return (i * (cellPx + gapPx) + Math.min(i, extraPx)) / dpr }
      function cellPxOf(i) { return cellPx + (i < extraPx ? 1 : 0) }
      function cellW(i) { return cellPxOf(i) / dpr }

      Repeater {
        model: meter.segments

        Item {
          id: cell
          required property int index
          readonly property var c: meter.cells[index] || ({ fill: 0, glow: 0, press: 0 })

          x: cellRow.cellX(index)
          width: cellRow.cellW(index)
          height: cellRow.height
          // A cell gives under the pointer, as Weave's tiles do.
          scale: 1 - cell.c.press * 0.14

          Rectangle {
            anchors.fill: parent
            color: Qt.rgba(meter.tone.r, meter.tone.g, meter.tone.b, 0.12)
            antialiasing: false
          }

          Rectangle {
            readonly property int px: Math.round(cellRow.cellPxOf(cell.index) * cell.c.fill)
            visible: px > 0
            width: px / cellRow.dpr
            height: parent.height
            color: meter.tone
            antialiasing: false
          }

          Rectangle {
            visible: cell.c.glow > 0.01
            anchors.fill: parent
            color: Qt.rgba(meter.foreground.r, meter.foreground.g, meter.foreground.b, cell.c.glow * 0.55)
            antialiasing: false
          }
        }
      }
    }
  }

  // Where a press would set it: a tick through the body, poking out above
  // and below, as Batteries marks a charge limit.
  Rectangle {
    visible: meter.interactive && meter.pointerValue >= 0
    x: Math.round(cellRow.x + cellRow.width * meter.pointerValue - width / 2)
    y: -Math.max(2, Style.space(3))
    width: meter.line
    height: parent.height - y * 2
    color: meter.foreground
    opacity: 0.55
    antialiasing: false
  }

  MouseArea {
    id: area
    enabled: meter.interactive
    // A little taller than the body, so a thin meter is easy to catch.
    x: 0
    y: -Style.space(4)
    width: parent.width
    height: parent.height + Style.space(8)
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    preventStealing: true
    cursorShape: Qt.PointingHandCursor

    onPositionChanged: function(mouse) {
      meter.hover(mouse.x, mouse.y + y)
      if (meter.dragging) meter.setFrom(mouse.x)
    }
    onExited: meter.dent = null
    onPressed: function(mouse) {
      if (mouse.button === Qt.RightButton) { meter.rightClicked(); return }
      // The clock first: a ripple is stamped with it.
      meter.host.wake(Model.METER.RIPPLE_MS + 200)
      meter.press(mouse.x, mouse.y)
      meter.setFrom(mouse.x)
    }
    onReleased: if (meter.shown !== meter.level) meter.slide()
  }

  PanelToolTip {
    visible: area.containsMouse && !meter.dragging && meter.tipText !== ""
    text: meter.tipText
    fontFamily: meter.host.fontFamily
  }
}
