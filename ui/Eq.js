.pragma library

// The EQ model the panel needs on the click itself. engine/sonus/eq.py owns
// the same layout; keep the two in step.

var BAND_FREQS = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
var BAND_LABELS = ["32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]
var BAND_COUNT = 10
var BAND_Q = 1.8
var GAIN_LIMIT = 18
var PREAMP_LIMIT = 18

// Assertive enough to hear, short of a "gamer EQ" that clips.
var PRESETS = [
  { name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
  { name: "Bass", gains: [5, 4, 2.5, 1, 0, 0, 0, 0, 0, 0] },
  { name: "Voice", gains: [-2, -1.5, 0, 0.5, 2, 3, 3, 2.5, 1, 0] },
  { name: "Treble", gains: [0, 0, 0, 0, 0, 0.5, 2, 3, 4, 4.5] },
  { name: "Steps", gains: [-3, -2.5, -0.5, 0, 0.5, 2.5, 3.5, 3.5, 2, 0.5] }
]

function clamp(value, limit) {
  return Math.max(-limit, Math.min(limit, Number(value) || 0))
}

function flat() {
  return { enabled: true, preamp: 0, gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] }
}

function normalized(state) {
  var out = flat()
  if (!state || typeof state !== "object") return out
  out.enabled = state.enabled !== false
  out.preamp = clamp(state.preamp, PREAMP_LIMIT)
  var gains = Array.isArray(state.gains) ? state.gains : []
  for (var i = 0; i < BAND_COUNT; i++) out.gains[i] = clamp(gains[i], GAIN_LIMIT)
  return out
}

function isFlat(state) {
  if (!state) return true
  if (Math.abs(state.preamp) >= 0.05) return false
  for (var i = 0; i < state.gains.length; i++) if (Math.abs(state.gains[i]) >= 0.05) return false
  return true
}

// Partial make-up gain: pull the preamp down by half the peak boost. Full
// compensation made a Bass preset quieter than flat, which read as "the EQ
// does nothing".
function presetPreamp(gains) {
  var peak = 0
  for (var i = 0; i < gains.length; i++) peak = Math.max(peak, gains[i])
  return clamp(-peak * 0.5, PREAMP_LIMIT)
}

// Fader position to dB: half-dB steps, with a detent at 0 so flat is easy
// to hit.
function snap(raw) {
  return Math.abs(raw) < 0.35 ? 0 : Math.round(raw * 2) / 2
}

function gainText(value) {
  if (!value) return "0"
  var text = (value > 0 ? "+" : "") + value.toFixed(1)
  return text.replace(/\.0$/, "")
}

function dbText(value) {
  return (value >= 0 ? "+" : "") + value.toFixed(1) + " dB"
}

// Magnitude response of one RBJ peaking biquad, in dB, at `freq`.
function peakingDb(freq, f0, gain, q, fs) {
  if (Math.abs(gain) < 0.01) return 0
  var A = Math.pow(10, gain / 40)
  var w0 = 2 * Math.PI * f0 / fs
  var alpha = Math.sin(w0) / (2 * q)
  var cw = Math.cos(w0)
  var b0 = 1 + alpha * A, b1 = -2 * cw, b2 = 1 - alpha * A
  var a0 = 1 + alpha / A, a1 = -2 * cw, a2 = 1 - alpha / A
  var s = Math.sin(Math.PI * freq / fs)
  var phi = s * s
  function mag(c0, c1, c2) {
    return (c0 + c1 + c2) * (c0 + c1 + c2) - 4 * (c0 * c1 + 4 * c0 * c2 + c1 * c2) * phi + 16 * c0 * c2 * phi * phi
  }
  return 10 * Math.log(mag(b0, b1, b2) / mag(a0, a1, a2)) / Math.LN10
}

// The whole chain: preamp plus every band, as the filter-chain runs it.
function responseDb(freq, gains, preamp) {
  var total = preamp
  for (var i = 0; i < BAND_COUNT; i++) total += peakingDb(freq, BAND_FREQS[i], gains[i] || 0, BAND_Q, 48000)
  return total
}

function _gains(gains) {
  var out = []
  for (var i = 0; i < BAND_COUNT; i++) out.push(Number(gains && gains[i]) || 0)
  return out
}

// Fritsch–Carlson slopes. A plain cubic through the faders overshoots, which
// is the rollercoaster between two bands; these slopes are flattened wherever
// that would happen, so the line stays between the points it joins.
function _slopes(gains) {
  var d = []
  for (var i = 0; i < BAND_COUNT - 1; i++) d.push(gains[i + 1] - gains[i])
  var m = []
  m[0] = d[0]
  m[BAND_COUNT - 1] = d[BAND_COUNT - 2]
  for (var j = 1; j < BAND_COUNT - 1; j++) {
    if (d[j - 1] * d[j] <= 0) m[j] = 0
    else m[j] = (d[j - 1] + d[j]) / 2
  }
  for (var k = 0; k < BAND_COUNT - 1; k++) {
    if (Math.abs(d[k]) < 1e-9) {
      m[k] = 0
      m[k + 1] = 0
      continue
    }
    var a = m[k] / d[k]
    var b = m[k + 1] / d[k]
    var h = a * a + b * b
    if (h > 9) {
      var scale = 3 / Math.sqrt(h)
      m[k] = scale * a * d[k]
      m[k + 1] = scale * b * d[k]
    }
  }
  return m
}

function _sample(index, gains, slopes) {
  if (index <= 0) return gains[0]
  if (index >= BAND_COUNT - 1) return gains[BAND_COUNT - 1]
  var i = Math.floor(index)
  var t = index - i
  var t2 = t * t
  var t3 = t2 * t
  var h00 = 2 * t3 - 3 * t2 + 1
  var h10 = t3 - 2 * t2 + t
  var h01 = -2 * t3 + 3 * t2
  var h11 = t3 - t2
  return h00 * gains[i] + h10 * slopes[i] + h01 * gains[i + 1] + h11 * slopes[i + 1]
}

// Gain of the drawn curve at a band position. 0 is the first knob, 9 the
// last. It passes through every fader and does not dip or peak between them.
function curveAt(index, gains) {
  var values = _gains(gains)
  return _sample(index, values, _slopes(values))
}

function curveSeries(gains, steps) {
  var values = _gains(gains)
  var slopes = _slopes(values)
  var count = Math.max(1, steps)
  var series = []
  for (var k = 0; k <= count; k++) series.push(_sample(-0.5 + BAND_COUNT * k / count, values, slopes))
  return series
}
