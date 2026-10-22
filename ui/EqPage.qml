import QtQuick
import "Eq.js" as Eq
import "Glyphs.js" as Glyphs

// Full-page equaliser for one category: presets and preamp on the left, ten
// bands spread wide with the live response of the whole chain drawn behind
// them. One page serves every category; load() points it at one.
Rectangle {
  id: page

  required property var theme
  property string channelKey: ""
  property string label: ""
  property color accent: theme.accent
  property bool eqEnabled: true

  signal edited(string key, var state)
  signal back()

  radius: theme.cardRadius
  color: theme.card

  readonly property real pad: theme.s(18)
  readonly property real leftW: theme.s(190)
  readonly property real bandsX: pad + leftW + theme.s(48)
  readonly property real bandsR: width - pad
  readonly property real col: (bandsR - bandsX) / Eq.BAND_COUNT
  readonly property real sliderTop: theme.s(84)
  readonly property real sliderBot: height - theme.s(36)

  property bool loading: false
  property var gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  property real preamp: 0

  function state() {
    return { enabled: eqEnabled, preamp: preamp, gains: gains.slice() }
  }

  function emitEdit() {
    if (!loading && channelKey !== "") edited(channelKey, state())
    curve.requestPaint()
  }

  // `entrance`: faders spread out from the 0 dB line into the saved curve.
  function load(key, text, color, saved, entrance) {
    loading = true
    var st = Eq.normalized(saved)
    channelKey = key
    label = text
    accent = color
    eqEnabled = st.enabled
    gains = st.gains.slice()
    preamp = st.preamp
    for (var i = 0; i < Eq.BAND_COUNT; i++) {
      var s = bands.itemAt(i)
      if (!s) continue
      s.value = st.gains[i]
      if (entrance) s.replay()
    }
    preampSlider.value = st.preamp
    if (entrance) preampSlider.replay()
    loading = false
    curve.requestPaint()
  }

  function setBand(index, value) {
    var next = gains.slice()
    next[index] = value
    gains = next
    emitEdit()
  }

  function applyPreset(preset) {
    var next = preset.gains.slice()
    for (var i = 0; i < Eq.BAND_COUNT; i++) {
      var s = bands.itemAt(i)
      if (s) s.value = next[i]
    }
    gains = next
    preamp = Eq.presetPreamp(next)
    preampSlider.value = preamp
    eqEnabled = true
    emitEdit()
  }

  function reset() {
    applyPresetValues([0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 0)
  }

  function applyPresetValues(values, pre) {
    for (var i = 0; i < Eq.BAND_COUNT; i++) {
      var s = bands.itemAt(i)
      if (s) s.value = values[i]
    }
    gains = values.slice()
    preamp = pre
    preampSlider.value = pre
    emitEdit()
  }

  function presetMatches(preset) {
    for (var i = 0; i < Eq.BAND_COUNT; i++) if (Math.abs(preset.gains[i] - gains[i]) > 0.01) return false
    return true
  }

  // ---- header ---------------------------------------------------------------

  Chip {
    id: backChip
    theme: page.theme
    x: page.pad
    y: theme.s(14)
    glyph: Glyphs.back
    text: "Back"
    onClicked: page.back()
  }

  Rectangle {
    x: backChip.x + backChip.width + theme.s(18)
    anchors.verticalCenter: backChip.verticalCenter
    width: theme.s(10)
    height: width
    radius: width / 2
    color: page.accent
  }

  Text {
    x: backChip.x + backChip.width + theme.s(36)
    anchors.verticalCenter: backChip.verticalCenter
    textFormat: Text.PlainText
    text: page.label + " EQUALIZER"
    color: theme.fg
    font.family: theme.font
    font.pixelSize: theme.s(14)
    font.weight: Font.Bold
    font.letterSpacing: theme.s(1)
  }

  Row {
    anchors.right: parent.right
    anchors.rightMargin: page.pad
    y: theme.s(14)
    height: backChip.height
    spacing: theme.s(12)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "EQ enabled"
      color: theme.fg
      font.family: theme.font
      font.pixelSize: theme.s(11)
      font.weight: Font.DemiBold
    }

    Switch {
      theme: page.theme
      anchors.verticalCenter: parent.verticalCenter
      tint: page.accent
      checked: page.eqEnabled
      onToggled: function(value) {
        page.eqEnabled = value
        page.emitEdit()
      }
    }

    Item { width: theme.s(4); height: 1 }

    Chip {
      theme: page.theme
      anchors.verticalCenter: parent.verticalCenter
      text: "Reset"
      onClicked: page.reset()
    }
  }

  // ---- presets and preamp ---------------------------------------------------

  Text {
    x: page.pad + theme.s(2)
    y: theme.s(60)
    text: "PRESETS"
    color: theme.dim
    font.family: theme.font
    font.pixelSize: theme.s(10)
    font.weight: Font.Bold
    font.letterSpacing: theme.s(1)
  }

  Column {
    x: page.pad
    y: theme.s(80)
    spacing: theme.s(6)

    Repeater {
      model: Eq.PRESETS

      Chip {
        required property var modelData
        theme: page.theme
        width: page.leftW
        height: theme.s(26)
        text: modelData.name
        tint: page.accent
        active: page.presetMatches(modelData)
        onClicked: page.applyPreset(modelData)
      }
    }
  }

  Text {
    id: preampCaption
    x: page.pad + theme.s(2)
    y: theme.s(80) + 5 * theme.s(26) + 4 * theme.s(6) + theme.s(18)
    text: "PREAMP"
    color: theme.dim
    font.family: theme.font
    font.pixelSize: theme.s(10)
    font.weight: Font.Bold
    font.letterSpacing: theme.s(1)
  }

  EqSlider {
    id: preampSlider
    theme: page.theme
    horizontal: true
    limit: Eq.PREAMP_LIMIT
    accent: page.accent
    dimmed: !page.eqEnabled
    x: page.pad - theme.s(6)
    y: preampCaption.y + theme.s(16)
    width: page.leftW - theme.s(58)
    height: theme.s(28)
    onMoved: function(v) {
      page.preamp = v
      page.emitEdit()
    }
  }

  Text {
    anchors.verticalCenter: preampSlider.verticalCenter
    x: page.pad + page.leftW - width
    text: Eq.dbText(page.preamp)
    color: page.preamp !== 0 ? page.accent : theme.fg
    font.family: theme.font
    font.pixelSize: theme.s(11)
  }

  Text {
    x: page.pad + theme.s(2)
    y: preampSlider.y + preampSlider.height + theme.s(12)
    width: page.leftW
    wrapMode: Text.WordWrap
    text: "Double-click a band to zero it, scroll for 0.5 dB steps. Stacking big boosts? Pull the preamp down."
    color: theme.faint
    font.family: theme.font
    font.pixelSize: theme.s(10)
    lineHeight: 1.15
  }

  Rectangle {
    x: page.pad + page.leftW + theme.s(18)
    y: theme.s(64)
    width: Math.max(1, theme.s(1))
    height: page.height - theme.s(92)
    color: theme.rule
  }

  // ---- bands ----------------------------------------------------------------

  // dB guides and the summed response curve, aligned to the fader travel.
  Canvas {
    id: curve
    x: page.bandsX
    y: page.sliderTop
    width: page.bandsR - page.bandsX
    height: page.sliderBot - page.sliderTop
    renderStrategy: Canvas.Cooperative

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var pad = theme.s(8)
      var top = pad, bottom = height - pad, mid = (top + bottom) / 2
      function yFor(db) {
        var f = (Math.max(-Eq.GAIN_LIMIT, Math.min(Eq.GAIN_LIMIT, db)) + Eq.GAIN_LIMIT) / (2 * Eq.GAIN_LIMIT)
        return bottom - (bottom - top) * f
      }
      ctx.lineWidth = 1
      ctx.strokeStyle = theme.rule
      var lines = [-18, -9, 9, 18]
      for (var l = 0; l < lines.length; l++) {
        ctx.beginPath()
        ctx.moveTo(0, Math.round(yFor(lines[l])) + 0.5)
        ctx.lineTo(width, Math.round(yFor(lines[l])) + 0.5)
        ctx.stroke()
      }
      ctx.strokeStyle = theme.track
      ctx.lineWidth = 1.5
      ctx.beginPath()
      ctx.moveTo(0, mid)
      ctx.lineTo(width, mid)
      ctx.stroke()

      var shown = []
      for (var i = 0; i < Eq.BAND_COUNT; i++) {
        var s = bands.itemAt(i)
        shown.push(s ? s.shown : 0)
      }
      var pre = page.eqEnabled ? preampSlider.shown : 0
      var col = width / Eq.BAND_COUNT
      var points = []
      var steps = 96
      for (var k = 0; k <= steps; k++) {
        // Bands sit one octave apart in equal columns, so the x axis is
        // log2 frequency with band i centred in column i.
        var octave = -0.5 + (Eq.BAND_COUNT) * k / steps
        var freq = 32 * Math.pow(2, octave)
        var db = page.eqEnabled ? Eq.responseDb(freq, shown, pre) : 0
        points.push([col * (octave + 0.5), yFor(db)])
      }
      var tone = page.eqEnabled ? page.accent : theme.faint
      ctx.beginPath()
      ctx.moveTo(points[0][0], mid)
      for (var p = 0; p < points.length; p++) ctx.lineTo(points[p][0], points[p][1])
      ctx.lineTo(points[points.length - 1][0], mid)
      ctx.closePath()
      ctx.fillStyle = Qt.rgba(tone.r, tone.g, tone.b, 0.12)
      ctx.fill()
      ctx.beginPath()
      for (var q = 0; q < points.length; q++) {
        if (q === 0) ctx.moveTo(points[q][0], points[q][1])
        else ctx.lineTo(points[q][0], points[q][1])
      }
      ctx.lineWidth = Math.max(1.5, theme.s(2))
      ctx.strokeStyle = Qt.rgba(tone.r, tone.g, tone.b, 0.85)
      ctx.lineJoin = "round"
      ctx.stroke()
    }
  }

  Repeater {
    model: [["+18", -18], ["0", 0], ["-18", 18]]

    Text {
      required property var modelData
      x: page.bandsX - width - theme.s(10)
      y: page.sliderTop + theme.s(8) + (page.sliderBot - page.sliderTop - theme.s(16)) * (modelData[1] + 18) / 36 - height / 2
      text: modelData[0]
      color: theme.faint
      font.family: theme.font
      font.pixelSize: theme.s(9)
    }
  }

  Repeater {
    id: bands
    model: Eq.BAND_COUNT

    EqSlider {
      required property int index
      theme: page.theme
      accent: page.accent
      dimmed: !page.eqEnabled
      width: theme.s(30)
      x: page.bandsX + page.col * index + page.col / 2 - width / 2
      y: page.sliderTop
      height: page.sliderBot - page.sliderTop
      onShownChanged: curve.requestPaint()
      onMoved: function(v) { page.setBand(index, v) }
    }
  }

  Repeater {
    model: Eq.BAND_COUNT

    Text {
      required property int index
      readonly property real gain: page.gains[index] || 0
      width: page.col
      x: page.bandsX + page.col * index
      y: page.sliderTop - theme.s(22)
      horizontalAlignment: Text.AlignHCenter
      text: Eq.gainText(gain)
      color: gain !== 0 && page.eqEnabled ? page.accent : theme.dim
      font.family: theme.font
      font.pixelSize: theme.s(10)
      font.weight: gain !== 0 ? Font.DemiBold : Font.Normal
    }
  }

  Repeater {
    model: Eq.BAND_LABELS

    Text {
      required property int index
      required property var modelData
      width: page.col
      x: page.bandsX + page.col * index
      y: page.sliderBot + theme.s(8)
      horizontalAlignment: Text.AlignHCenter
      text: modelData
      color: theme.dim
      font.family: theme.font
      font.pixelSize: theme.s(10)
      font.weight: Font.DemiBold
    }
  }

  Connections {
    target: preampSlider
    function onShownChanged() { curve.requestPaint() }
  }
  onEqEnabledChanged: curve.requestPaint()
  onAccentChanged: curve.requestPaint()
}
