import QtQuick
import "Eq.js" as Eq

// One dB fader: vertical for a band, horizontal for the preamp.
//
// `value` is the target; `shown` is what is drawn and eases toward it, so
// presets, resets and the page entrance glide instead of snapping. Dragging
// writes both directly.
Item {
  id: slider

  required property var theme
  property color accent: theme.accent
  property bool horizontal: false
  property real limit: Eq.GAIN_LIMIT
  property real value: 0
  property bool dimmed: false
  signal moved(real value)

  property bool dragging: false
  property bool instant: false
  property real shown: 0
  property real wheelAcc: 0

  onValueChanged: shown = value
  Component.onCompleted: shown = value
  Behavior on shown {
    enabled: !slider.instant && !slider.dragging
    NumberAnimation { duration: 340; easing.type: Easing.OutCubic }
  }

  function replay() {
    instant = true
    shown = 0
    instant = false
    shown = value
  }

  function set(v) {
    v = Eq.clamp(v, limit)
    if (Math.abs(v - value) < 0.001) return
    value = v
    moved(v)
  }

  readonly property real pad: theme.s(8)
  readonly property real span: (horizontal ? width : height) - pad * 2
  readonly property real frac: (Math.max(-limit, Math.min(limit, shown)) + limit) / (2 * limit)
  readonly property real pos: horizontal ? pad + span * frac : pad + span * (1 - frac)
  readonly property real centre: pad + span / 2
  readonly property real trackW: theme.s(5)
  readonly property color fillColor: dimmed ? theme.faint : accent

  function valueAt(x, y) {
    var c = horizontal ? x : y
    var f = (c - pad) / Math.max(1, span)
    if (!horizontal) f = 1 - f
    return Eq.snap((Math.max(0, Math.min(1, f)) * 2 - 1) * limit)
  }

  Rectangle {
    x: slider.horizontal ? slider.pad : (slider.width - width) / 2
    y: slider.horizontal ? (slider.height - height) / 2 : slider.pad
    width: slider.horizontal ? slider.span : slider.trackW
    height: slider.horizontal ? slider.trackW : slider.span
    radius: slider.trackW / 2
    color: theme.track
  }

  Rectangle {
    readonly property real a: Math.min(slider.centre, slider.pos)
    readonly property real len: Math.abs(slider.pos - slider.centre)
    visible: len > 0.5
    x: slider.horizontal ? a : (slider.width - width) / 2
    y: slider.horizontal ? (slider.height - height) / 2 : a
    width: slider.horizontal ? len : slider.trackW
    height: slider.horizontal ? slider.trackW : len
    radius: slider.trackW / 2
    color: slider.fillColor
  }

  Rectangle {
    readonly property real w: slider.horizontal ? theme.s(13) : theme.s(24)
    readonly property real h: slider.horizontal ? theme.s(24) : theme.s(13)
    readonly property real grow: slider.dragging || mouse.containsMouse ? theme.s(2) : 0
    width: w + grow
    height: h + grow
    x: slider.horizontal ? slider.pos - width / 2 : (slider.width - width) / 2
    y: slider.horizontal ? (slider.height - height) / 2 : slider.pos - height / 2
    radius: theme.s(5)
    color: theme.thumb
    Behavior on width { NumberAnimation { duration: 110 } }
    Behavior on height { NumberAnimation { duration: 110 } }

    Rectangle {
      anchors.centerIn: parent
      width: slider.horizontal ? Math.max(2, theme.s(2.5)) : theme.s(10)
      height: slider.horizontal ? theme.s(10) : Math.max(2, theme.s(2.5))
      radius: Math.min(width, height) / 2
      color: slider.fillColor
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onPressed: function(event) {
      slider.dragging = true
      slider.set(slider.valueAt(event.x, event.y))
      slider.shown = slider.value
    }
    onPositionChanged: function(event) {
      if (!slider.dragging) return
      slider.set(slider.valueAt(event.x, event.y))
      slider.shown = slider.value
    }
    onReleased: slider.dragging = false
    onCanceled: slider.dragging = false
    onDoubleClicked: slider.set(0)
    onWheel: function(event) {
      slider.wheelAcc += event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x
      var steps = slider.wheelAcc > 0 ? Math.floor(slider.wheelAcc / 120) : Math.ceil(slider.wheelAcc / 120)
      if (steps === 0) return
      slider.wheelAcc -= steps * 120
      slider.set(slider.value + steps * 0.5)
    }
  }
}
