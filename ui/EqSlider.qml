import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Eq.js" as Eq

// One vertical dB fader, drawn the way PanelSlider draws a horizontal one:
// a selected-fill track, a foreground fill growing from 0 dB, a round knob.
//
// `value` is the target; `shown` is what is drawn and eases toward it, so a
// preset or a reset glides instead of snapping. Double-click zeroes the band,
// the wheel moves it in half-dB steps.
Item {
  id: slider

  property color foreground: Commons.Color.foreground
  property color background: Commons.Color.background
  property color trackColor: Style.selectedFillFor(foreground, Commons.Color.accent)
  property real limit: Eq.GAIN_LIMIT
  property real value: 0
  property bool dimmed: false
  property bool hasCursor: false
  signal moved(real value)

  property bool dragging: false
  property bool instant: false
  property real shown: 0
  property real wheelAcc: 0

  onValueChanged: shown = value
  Component.onCompleted: shown = value
  Behavior on shown {
    enabled: !slider.instant && !slider.dragging
    NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
  }

  // Spread out from the 0 dB line into the saved curve.
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

  readonly property real knob: Math.max(12, Math.round(Style.spacing.controlHeight * 0.38))
  readonly property real pad: knob / 2
  readonly property real span: height - pad * 2
  readonly property real frac: (Math.max(-limit, Math.min(limit, shown)) + limit) / (2 * limit)
  readonly property real pos: pad + span * (1 - frac)
  readonly property real centre: pad + span / 2
  readonly property real trackW: Math.max(4, Math.round(Style.spacing.controlHeight * 0.11))
  readonly property bool hot: mouse.containsMouse || dragging || hasCursor

  function valueAt(y) {
    var f = 1 - (y - pad) / Math.max(1, span)
    return Eq.snap((Math.max(0, Math.min(1, f)) * 2 - 1) * limit)
  }

  opacity: dimmed ? 0.45 : 1

  Rectangle {
    x: (slider.width - width) / 2
    y: slider.pad
    width: slider.trackW
    height: slider.span
    radius: width / 2
    color: slider.trackColor
  }

  Rectangle {
    readonly property real y0: Math.min(slider.centre, slider.pos)
    visible: Math.abs(slider.pos - slider.centre) > 0.5
    x: (slider.width - width) / 2
    y: y0
    width: slider.trackW
    height: Math.abs(slider.pos - slider.centre)
    radius: width / 2
    color: slider.foreground
  }

  Rectangle {
    width: slider.knob
    height: slider.knob
    radius: width / 2
    x: (slider.width - width) / 2
    y: slider.pos - height / 2
    color: slider.foreground
    border.width: Math.max(1, Style.space(2))
    border.color: slider.background
    scale: slider.hot ? 1.15 : 1
    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onPressed: function(event) {
      slider.dragging = true
      slider.set(slider.valueAt(event.y))
      slider.shown = slider.value
    }
    onPositionChanged: function(event) {
      if (!slider.dragging) return
      slider.set(slider.valueAt(event.y))
      slider.shown = slider.value
    }
    onReleased: slider.dragging = false
    onCanceled: slider.dragging = false
    onDoubleClicked: slider.set(0)
    onWheel: function(event) {
      slider.wheelAcc += event.angleDelta.y
      var steps = slider.wheelAcc > 0 ? Math.floor(slider.wheelAcc / 120) : Math.ceil(slider.wheelAcc / 120)
      if (steps === 0) return
      slider.wheelAcc -= steps * 120
      slider.set(slider.value + steps * 0.5)
    }
  }
}
