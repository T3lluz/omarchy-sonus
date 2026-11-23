.pragma library

// How each pixel icon acts out what it is, after DailyDash's island glyphs:
// only the part that should move moves (Pixels.js keeps an icon's parts and
// the layers it shows only while moving), in whole strokes of its own grid,
// so the art never smears. A speaker's waves ripple out while the cone stays,
// a headphone's cups tap a beat, a slash draws across, a controller's buttons
// press, a chat types its lines. Every play ends exactly where it began.
//
// PixelIcon plays these: once when its room comes in or is clicked, and when
// the state the icon shows changes (it then plays "entering": what draws in
// starts from nothing, the way the state before it had nothing there). The
// loops that run while something is live (an app's equaliser bars) run off
// one clock of LOOP_TICKS ticks, and every loop's period divides it, so
// nothing jumps when the clock comes round.

var TICK_MS = 100
var LOOP_TICKS = 24
// One-shots step at most this often, as pixel animation does.
var FRAME_MS = 40

// The value of the last frame at or before `t`: [[from, value], ...].
function step(t, frames) {
  var v = frames[0][1]
  for (var i = 0; i < frames.length; i++) if (t >= frames[i][0]) v = frames[i][1]
  return v
}

function clamp01(x) {
  return Math.max(0, Math.min(1, x))
}

// How much of a line is drawn at `t`: entering, it draws in from nothing;
// played again, it rubs out the way it was drawn and draws in once more.
function redraw(t, entering, from, to) {
  if (from === undefined) from = 0
  if (to === undefined) to = 0.8
  if (entering) return clamp01((t - from) / (to - from))
  if (t < 0.3) return 1 - clamp01(t / 0.25)
  return clamp01((t - 0.35) / (to - 0.35))
}

// How many of a speaker's `n` waves show: played again they fold in to the
// cone and ripple out; entering (the sound back on) they ripple out from it.
function ripple(t, entering, n) {
  if (entering) return Math.min(n, Math.floor(clamp01(t / 0.75) * (n + 1)))
  if (t < 0.3) return n - Math.min(n, Math.floor(t / 0.3 * (n + 1)))
  return Math.min(n, Math.floor(clamp01((t - 0.3) / 0.5) * (n + 1)))
}

function waves(n) {
  return {
    ms: 640 + n * 120,
    pose: function(t, entering) {
      var shown = ripple(t, entering, n)
      var out = {}
      for (var i = 1; i <= n; i++) out["wave-" + i] = { hide: i > shown }
      return out
    }
  }
}

// Beats on and off: [[from, to], ...] within 0..1.
function within(t, spans) {
  for (var i = 0; i < spans.length; i++) if (t >= spans[i][0] && t < spans[i][1]) return true
  return false
}

// Each icon: how long it plays, and its parts' poses at `t` (0..1). A pose is
// { dx, dy } in strokes, `hide`, or `reveal` (0..1 of the part drawn, in the
// order `by` names). Parts left out sit at rest; layers left out are hidden.
var SPECS = {
  // A line typed out on the screen, then cleared.
  laptop: { ms: 1100, pose: function(t) {
    if (t < 0.08 || t >= 0.86) return {}
    return { text: { reveal: clamp01((t - 0.08) / 0.5), by: "rows" } }
  } },
  // The cups tap a beat, left, right, left, right.
  headphone: { ms: 900, pose: function(t) {
    return {
      "cup-left": { dy: within(t, [[0.06, 0.2], [0.5, 0.64]]) ? 1 : 0 },
      "cup-right": { dy: within(t, [[0.28, 0.42], [0.72, 0.86]]) ? 1 : 0 }
    }
  } },
  airpods: { ms: 900, pose: function(t) {
    return {
      "bud-left": { dy: within(t, [[0.06, 0.2], [0.5, 0.64]]) ? -1 : 0 },
      "bud-right": { dy: within(t, [[0.28, 0.42], [0.72, 0.86]]) ? -1 : 0 }
    }
  } },
  "volume-1": waves(1),
  "volume-2": waves(2),
  "volume-3": waves(3),
  // Muted: the cross draws over the cone, top to bottom.
  "volume-x": { ms: 560, pose: function(t, entering) {
    return { cross: { reveal: redraw(t, entering), by: "rows" } }
  } },
  // The capsule lifts as if picked up. What it hears fills it (`fill`).
  mic: { ms: 640, pose: function(t) {
    return { capsule: { dy: within(t, [[0.12, 0.5]]) ? -1 : 0 } }
  } },
  "mic-off": { ms: 600, pose: function(t, entering) {
    return { slash: { reveal: redraw(t, entering), by: "x" } }
  } },
  // The lens looks left, then right.
  webcam: { ms: 1000, pose: function(t) {
    return { lens: { dx: step(t, [[0, 0], [0.1, -1], [0.42, 1], [0.76, 0]]) } }
  } },
  // A line sweeps the screen top to bottom as it wakes.
  monitor: { ms: 720, pose: function(t) {
    if (t < 0.06 || t >= 0.9) return {}
    return { scan: { dy: Math.min(5, Math.floor((t - 0.06) / 0.84 * 6)) } }
  } },
  // A tube coming on: a dot, a line across, then the picture.
  tv: { ms: 640, pose: function(t) {
    if (within(t, [[0.06, 0.3]])) return { dot: {} }
    if (within(t, [[0.3, 0.62]])) return { line: {} }
    if (within(t, [[0.62, 0.74]])) return { dot: {} }
    return {}
  } },
  // The pad presses down, then the buttons, one and the other.
  gamepad: { ms: 900, pose: function(t) {
    return {
      dpad: { dy: within(t, [[0.06, 0.24]]) ? 1 : 0 },
      "button-a": { hide: within(t, [[0.32, 0.44], [0.72, 0.82]]) },
      "button-b": { hide: within(t, [[0.52, 0.64]]) }
    }
  } },
  // The message types itself out, line by line.
  "message-text": { ms: 1000, pose: function(t, entering) {
    if (!entering && t < 0.3) {
      var gone = clamp01(t / 0.25)
      return { "line-1": { reveal: 1 - gone, by: "x" }, "line-2": { reveal: 1 - gone, by: "x" } }
    }
    var from = entering ? 0 : 0.35
    return {
      "line-1": { reveal: clamp01((t - from) / 0.3), by: "x" },
      "line-2": { reveal: clamp01((t - from - 0.32) / 0.16), by: "x" }
    }
  } },
  // The notes bob to a beat, and the beam rocks between them.
  music: { ms: 1000, pose: function(t) {
    return {
      "note-left": { dy: within(t, [[0.06, 0.2], [0.5, 0.64]]) ? -1 : 0 },
      "note-right": { dy: within(t, [[0.28, 0.42], [0.72, 0.86]]) ? -1 : 0 }
    }
  } },
  // The signal comes in, drawn from the left.
  "audio-waveform": { ms: 900, pose: function(t, entering) {
    return { base: { reveal: redraw(t, entering), by: "x" } }
  } },
  "cancel": { ms: 600, pose: function(t, entering) {
    return { slash: { reveal: redraw(t, entering), by: "-x" } }
  } },
  // Each knob slides a step and back, top to bottom.
  "sliders-horizontal": { ms: 1000, pose: function(t) {
    return {
      "knob-1": { dx: within(t, [[0.06, 0.28]]) ? -1 : 0 },
      "knob-2": { dx: within(t, [[0.34, 0.56]]) ? 1 : 0 },
      "knob-3": { dx: within(t, [[0.62, 0.84]]) ? -1 : 0 }
    }
  } },
  check: { ms: 420, pose: function(t, entering) {
    return { base: { reveal: redraw(t, entering), by: "x" } }
  } },
  close: { ms: 420, pose: function(t, entering) {
    return { base: { reveal: redraw(t, entering), by: "rows" } }
  } },
  // The arrow drops into the tray, and the next comes down from above.
  download: { ms: 1000, pose: function(t) {
    var y = step(t, [[0, 0], [0.1, 1], [0.24, 2], [0.38, null], [0.5, -2], [0.64, -1], [0.8, 0]])
    return { arrow: y === null ? { hide: true } : { dy: y } }
  } },
  "warning-diamond": { ms: 1000, pose: function(t) {
    return { mark: { hide: within(t, [[0.14, 0.3], [0.46, 0.62]]) } }
  } },
  "circle-info": { ms: 640, pose: function(t) {
    return { dot: { dy: within(t, [[0.1, 0.4]]) ? -1 : 0 } }
  } },
  // A few keys go down, as if typed on.
  keyboard: { ms: 1000, pose: function(t) {
    return {
      "key-1": { hide: within(t, [[0.04, 0.16]]) },
      "key-3": { hide: within(t, [[0.2, 0.32]]) },
      "key-2": { hide: within(t, [[0.36, 0.48]]) },
      space: { hide: within(t, [[0.56, 0.74]]) }
    }
  } },
  // The window's buttons blink as it comes up.
  "app-windows": { ms: 800, pose: function(t) {
    return {
      "button-1": { hide: within(t, [[0.1, 0.3]]) },
      "button-2": { hide: within(t, [[0.36, 0.56]]) }
    }
  } },
  // Back: a step the way it points.
  "arrow-left": { ms: 480, pose: function(t) {
    return { base: { dx: within(t, [[0.12, 0.56]]) ? -1 : 0 } }
  } }
}

function specFor(name) {
  return SPECS[name] || null
}

// Every cell of `rects` ([x, y, w, h]) one by one, in the order `by` names.
function cells(rects, by) {
  var out = []
  for (var i = 0; i < rects.length; i++) {
    var q = rects[i]
    for (var y = q[1]; y < q[1] + q[3]; y++)
      for (var x = q[0]; x < q[0] + q[2]; x++) out.push([x, y, 1, 1])
  }
  out.sort(function(a, b) {
    if (by === "x") return a[0] - b[0] || a[1] - b[1]
    if (by === "-x") return b[0] - a[0] || a[1] - b[1]
    return a[1] - b[1] || a[0] - b[0]
  })
  return out
}

// How many rows of the microphone's capsule light for a peak of `level`
// (0..1): speech sits low, so the scale opens up the quiet end.
function fillRows(level) {
  if (!(level > 0.02)) return 0
  return Math.max(1, Math.min(5, Math.ceil(Math.sqrt(level) * 5)))
}

// The rectangles to draw for `art` (a Pixels.js icon) at `t` of `spec`'s
// play, on the fine grid or the halved one. A stroke is two cells of the fine
// grid and one of the halved. `fill` lights that many of the mic's rows.
function frame(art, spec, t, entering, fine, fill) {
  var grid = fine ? "g24" : "g12"
  var stroke = fine ? 2 : 1
  var poses = spec && t < 1 ? spec.pose(t, entering) : {}
  var parts = art.parts || { base: art }
  var out = []
  function draw(rects, pose) {
    if (pose.hide) return
    var dx = (pose.dx || 0) * stroke
    var dy = (pose.dy || 0) * stroke
    var list = rects
    if (pose.reveal !== undefined) {
      var all = cells(rects, pose.by)
      list = all.slice(0, Math.round(clamp01(pose.reveal) * all.length))
    }
    for (var i = 0; i < list.length; i++) {
      var q = list[i]
      out.push([q[0] + dx, q[1] + dy, q[2], q[3]])
    }
  }
  for (var name in parts) draw(parts[name][grid], poses[name] || {})
  var layers = art.layers || {}
  for (var layer in layers) {
    var pose = poses[layer]
    var m = /^fill-(\d)$/.exec(layer)
    // The mic's fill rides with its capsule.
    if (m && Number(m[1]) <= fill) pose = poses.capsule || {}
    if (pose) draw(layers[layer][grid], pose)
  }
  return out
}

// ------------------------------------------------------------ equaliser

// An app's little equaliser: four bars on the 12 grid, each a cell wide,
// standing on the bottom row. Playing, each rises and falls on a beat of its
// own; paused, they hold still at rest heights.
var EQ_X = [3, 5, 7, 9]
var EQ_PERIODS = [6, 8, 12, 24]
var EQ_OFFSETS = [0, 3, 7, 13]
var EQ_REST = [3, 5, 2, 4]
var EQ_BOTTOM = 10
var EQ_TALLEST = 8

function eqHeights(tick, playing) {
  if (!playing) return EQ_REST.slice()
  var out = []
  for (var i = 0; i < 4; i++) {
    var p = EQ_PERIODS[i]
    var e = ((tick + EQ_OFFSETS[i]) % p) / p
    var tri = e < 0.5 ? e * 2 : 2 - e * 2
    out.push(2 + Math.round(tri * (EQ_TALLEST - 2)))
  }
  return out
}

// The bars as a pixel icon's art, { g12, g24 }.
function eqArt(tick, playing) {
  var h = eqHeights(tick, playing)
  var g12 = []
  for (var i = 0; i < 4; i++) g12.push([EQ_X[i], EQ_BOTTOM + 1 - h[i], 1, h[i]])
  return { g12: g12, g24: g12.map(function(q) { return [q[0] * 2, q[1] * 2, q[2] * 2, q[3] * 2] }) }
}
