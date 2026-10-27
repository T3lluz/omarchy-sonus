import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Eq.js" as Eq
import "Glyphs.js" as Glyphs

// A category's 10-band equalizer: presets, the bands over the live response
// of the whole chain, and the preamp. load() points it at a category.
Column {
  id: view

  required property var host
  property string key: ""
  property string title: ""
  property bool eqEnabled: true
  property var gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  property real preamp: 0
  property bool loading: false
  property int band: -1

  spacing: Style.space(12)

  function state() { return { enabled: eqEnabled, preamp: preamp, gains: gains.slice() } }

  function commit() {
    if (!loading && key !== "") host.service.setEq(key, state())
    curve.requestPaint()
  }

  function load(k, t, saved, entrance) {
    loading = true
    var st = Eq.normalized(saved)
    key = k
    title = t
    eqEnabled = st.enabled
    gains = st.gains.slice()
    preamp = st.preamp
    for (var i = 0; i < Eq.BAND_COUNT; i++) {
      var s = bands.itemAt(i)
      if (!s) continue
      s.value = st.gains[i]
      if (entrance) s.replay()
    }
    band = -1
    loading = false
    curve.requestPaint()
  }

  function setBand(i, v) {
    var next = gains.slice()
    next[i] = Eq.clamp(v, Eq.GAIN_LIMIT)
    var s = bands.itemAt(i)
    if (s) s.value = next[i]
    gains = next
    commit()
  }

  function applyValues(values, pre) {
    for (var i = 0; i < Eq.BAND_COUNT; i++) {
      var s = bands.itemAt(i)
      if (s) s.value = values[i]
    }
    gains = values.slice()
    preamp = pre
    commit()
  }

  // Presets pull the preamp down by half their peak boost, and switch the
  // EQ on: picking a curve means wanting to hear it.
  function applyPreset(name) {
    for (var i = 0; i < Eq.PRESETS.length; i++) {
      if (Eq.PRESETS[i].name !== name) continue
      eqEnabled = true
      applyValues(Eq.PRESETS[i].gains, Eq.presetPreamp(Eq.PRESETS[i].gains))
    }
  }

  readonly property string presetName: {
    for (var i = 0; i < Eq.PRESETS.length; i++) {
      var p = Eq.PRESETS[i]
      var same = true
      for (var j = 0; j < Eq.BAND_COUNT; j++) if (Math.abs(p.gains[j] - gains[j]) > 0.01) same = false
      if (same) return p.name
    }
    return ""
  }

  // Keyboard: h/l pick a band, j/k move it, 0 zeroes it, p cycles presets.
  function handleMove(dx, dy) {
    if (dx !== 0) band = band < 0 ? 0 : Math.max(0, Math.min(Eq.BAND_COUNT - 1, band + dx))
    else if (dy !== 0 && band >= 0) setBand(band, gains[band] - dy * 0.5)
    else if (dy !== 0) band = 0
  }

  function handleText(t) {
    if (t === "0" && band >= 0) setBand(band, 0)
    else if (t === " ") { eqEnabled = !eqEnabled; commit() }
    else if (t === "p") {
      var names = Eq.PRESETS.map(function(p) { return p.name })
      applyPreset(names[(names.indexOf(presetName) + 1) % names.length])
    } else if (t === "r") applyValues([0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 0)
    else return false
    return true
  }

  // ---- header -----------------------------------------------------------------

  Item {
    width: parent.width
    implicitHeight: Math.max(backButton.height, toggle.implicitHeight)

    PanelActionButton {
      id: backButton
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      iconText: Glyphs.back
      tooltipText: "Back (esc)"
      foreground: view.host.fg
      fontFamily: view.host.fontFamily
      onClicked: view.host.setView("mixer")
    }

    Column {
      anchors.left: backButton.right
      anchors.leftMargin: Style.space(10)
      anchors.right: toggle.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        text: view.title + " equalizer"
        color: view.host.fg
        font.family: view.host.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        textFormat: Text.PlainText
        text: (view.eqEnabled ? (view.presetName || "Custom") : "Bypassed").toUpperCase()
          + "  ·  PREAMP " + Eq.dbText(view.preamp).toUpperCase()
        color: view.host.dim
        font.family: view.host.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
        elide: Text.ElideRight
        width: parent.width
      }
    }

    ToggleSwitch {
      id: toggle
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: view.eqEnabled
      foreground: view.host.fg
      onToggled: {
        view.eqEnabled = !view.eqEnabled
        view.commit()
      }

      PanelToolTip {
        visible: toggle.containsMouse
        text: view.eqEnabled ? "Bypass the EQ (space)" : "Enable the EQ (space)"
        fontFamily: view.host.fontFamily
      }
    }
  }

  PanelSeparator { foreground: view.host.fg }

  PanelSectionHeader {
    text: "PRESETS"
    foreground: view.host.fg
    fontFamily: view.host.fontFamily
  }

  ButtonGroup {
    options: Eq.PRESETS.map(function(p) { return p.name })
    value: view.presetName
    foreground: view.host.fg
    fontFamily: view.host.fontFamily
    fontSize: Style.font.caption
    onChanged: function(value) { view.applyPreset(value) }
  }

  // ---- bands ----------------------------------------------------------------

  Item {
    id: bandArea
    width: parent.width
    height: Style.space(228)

    readonly property real labelW: Style.space(26)
    readonly property real x0: labelW
    readonly property real col: (width - x0) / Eq.BAND_COUNT
    readonly property real topY: Style.space(18)
    readonly property real bottomY: height - Style.space(20)

    Canvas {
      id: curve
      x: bandArea.x0
      y: bandArea.topY
      width: bandArea.width - bandArea.x0
      height: bandArea.bottomY - bandArea.topY
      renderStrategy: Canvas.Cooperative
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var fg = view.host.fg
        var knob = Math.max(12, Math.round(Style.spacing.controlHeight * 0.38))
        var top = knob / 2, bottom = height - knob / 2, mid = (top + bottom) / 2
        function yFor(db) {
          var f = (Math.max(-Eq.GAIN_LIMIT, Math.min(Eq.GAIN_LIMIT, db)) + Eq.GAIN_LIMIT) / (2 * Eq.GAIN_LIMIT)
          return bottom - (bottom - top) * f
        }
        ctx.lineWidth = 1
        ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.08)
        var lines = [-18, -9, 9, 18]
        for (var l = 0; l < lines.length; l++) {
          var ly = Math.round(yFor(lines[l])) + 0.5
          ctx.beginPath(); ctx.moveTo(0, ly); ctx.lineTo(width, ly); ctx.stroke()
        }
        ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.18)
        ctx.beginPath(); ctx.moveTo(0, Math.round(mid) + 0.5); ctx.lineTo(width, Math.round(mid) + 0.5); ctx.stroke()

        var shown = []
        for (var i = 0; i < Eq.BAND_COUNT; i++) {
          var s = bands.itemAt(i)
          shown.push(s ? s.shown : 0)
        }
        var col = width / Eq.BAND_COUNT
        var pts = []
        var steps = 80
        // A smooth line through the faders. The real bells dip and peak
        // between bands; this stays on the points instead.
        var series = view.eqEnabled ? Eq.curveSeries(shown, steps) : null
        for (var k = 0; k <= steps; k++) {
          var octave = -0.5 + Eq.BAND_COUNT * k / steps
          var db = series ? series[k] : 0
          pts.push([col * (octave + 0.5), yFor(db)])
        }
        var tone = view.eqEnabled ? Commons.Color.accent : fg
        ctx.beginPath()
        ctx.moveTo(pts[0][0], mid)
        for (var p = 0; p < pts.length; p++) ctx.lineTo(pts[p][0], pts[p][1])
        ctx.lineTo(pts[pts.length - 1][0], mid)
        ctx.closePath()
        ctx.fillStyle = Qt.rgba(tone.r, tone.g, tone.b, view.eqEnabled ? 0.14 : 0.05)
        ctx.fill()
        ctx.beginPath()
        for (var q = 0; q < pts.length; q++) {
          if (q === 0) ctx.moveTo(pts[q][0], pts[q][1])
          else ctx.lineTo(pts[q][0], pts[q][1])
        }
        ctx.lineWidth = Math.max(1.5, Style.space(2))
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        ctx.strokeStyle = Qt.rgba(tone.r, tone.g, tone.b, view.eqEnabled ? 0.9 : 0.3)
        ctx.stroke()
      }
    }

    Repeater {
      model: [["+18", -18], ["0", 0], ["-18", 18]]

      Text {
        required property var modelData
        readonly property real knob: Math.max(12, Math.round(Style.spacing.controlHeight * 0.38))
        x: 0
        width: bandArea.labelW - Style.space(6)
        horizontalAlignment: Text.AlignRight
        y: bandArea.topY + knob / 2 + (bandArea.bottomY - bandArea.topY - knob) * (modelData[1] + 18) / 36 - height / 2
        text: modelData[0]
        color: view.host.dim
        font.family: view.host.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Repeater {
      id: bands
      model: Eq.BAND_COUNT

      EqSlider {
        required property int index
        x: bandArea.x0 + bandArea.col * index + (bandArea.col - width) / 2
        y: bandArea.topY
        width: Math.min(bandArea.col, Style.space(30))
        height: bandArea.bottomY - bandArea.topY
        foreground: view.host.fg
        background: Commons.Color.popups.background
        dimmed: !view.eqEnabled
        hasCursor: view.band === index
        onShownChanged: curve.requestPaint()
        onMoved: function(v) {
          var next = view.gains.slice()
          next[index] = v
          view.gains = next
          view.commit()
        }
      }
    }

    Repeater {
      model: Eq.BAND_COUNT

      Text {
        required property int index
        readonly property real gain: view.gains[index] || 0
        x: bandArea.x0 + bandArea.col * index
        width: bandArea.col
        y: 0
        horizontalAlignment: Text.AlignHCenter
        text: Eq.gainText(gain)
        color: gain !== 0 && view.eqEnabled ? view.host.fg : view.host.dim
        font.family: view.host.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: gain !== 0 || view.band === index
      }
    }

    Repeater {
      model: Eq.BAND_LABELS

      Text {
        required property int index
        required property var modelData
        x: bandArea.x0 + bandArea.col * index
        width: bandArea.col
        y: bandArea.bottomY + Style.space(4)
        horizontalAlignment: Text.AlignHCenter
        text: modelData
        color: view.band === index ? view.host.fg : view.host.dim
        font.family: view.host.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }

  // ---- preamp -----------------------------------------------------------------

  Item {
    width: parent.width
    implicitHeight: Math.max(preHeader.implicitHeight, preValue.implicitHeight)

    PanelSectionHeader {
      id: preHeader
      text: "PREAMP"
      foreground: view.host.fg
      fontFamily: view.host.fontFamily
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: preValue
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: Eq.dbText(preSlider.dragging ? preSlider.liveValue : view.preamp)
      color: view.host.dim
      font.family: view.host.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  PanelSlider {
    id: preSlider
    bar: view.host.bar
    width: parent.width
    minimum: -Eq.PREAMP_LIMIT
    maximum: Eq.PREAMP_LIMIT
    step: 0.5
    tickCount: 3
    value: view.preamp
    opacity: view.eqEnabled ? 1 : 0.45
    onMoved: function(v) {
      view.preamp = Eq.snap(v)
      view.commit()
    }
    onRightClicked: {
      view.preamp = 0
      view.commit()
    }
  }

  PanelSeparator { foreground: view.host.fg }

  Item {
    width: parent.width
    implicitHeight: Math.max(hint.implicitHeight, resetButton.implicitHeight)

    Text {
      id: hint
      anchors.left: parent.left
      anchors.right: resetButton.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      wrapMode: Text.WordWrap
      text: "Double-click a band to zero it, scroll for 0.5 dB. Big boosts? Pull the preamp down."
      color: view.host.dim
      font.family: view.host.fontFamily
      font.pixelSize: Style.font.caption
    }

    Button {
      id: resetButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "Reset"
      tooltipText: "Flatten every band and the preamp (r)"
      bordered: true
      foreground: view.host.fg
      fontFamily: view.host.fontFamily
      fontSize: Style.font.caption
      onClicked: view.applyValues([0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 0)
    }
  }

  onEqEnabledChanged: curve.requestPaint()
  onPreampChanged: curve.requestPaint()
}
