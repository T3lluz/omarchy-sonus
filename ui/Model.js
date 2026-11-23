.pragma library

// The Rooms look's pure logic, kept free of QML so tests/model.test.js can run
// it under node. Room tones, the block face and the pixel type, the cells of a
// meter, the icon stories and the decode come from Batteries 2.8, which set
// the look; the icon maps and the hover card's rows are Sonus's own. Icons are
// names in Pixels.js (pixel art). The panel kit is handed Nerd Font glyphs,
// which Glyph.qml swaps for their pixel icons through PIXEL_GLYPHS.

function hasLevel(level) {
  return level !== null && level !== undefined && !isNaN(level)
}

// A 0..1 volume as a whole percent.
function percentOf(volume) {
  return Math.round(Math.max(0, Math.min(1, Number(volume) || 0)) * 100)
}

// ------------------------------------------------------------------ icons

// What plays where: each channel has an icon of its own, and none of them
// looks like a device, or the channel rooms would read as hardware.
var CHANNEL_PIXELS = {
  game: "gamepad",
  chat: "message-text",
  media: "music",
  aux: "audio-waveform",
  "": "cancel"
}

function channelPixel(key) {
  return CHANNEL_PIXELS[key] || CHANNEL_PIXELS[""]
}

// The engine's coarse device shapes (profiles.device_form).
var DEVICE_PIXELS = {
  laptop: "laptop",
  headphones: "headphone",
  headset: "headphone",
  earbuds: "airpods",
  bluetooth: "volume-2",
  hdmi: "monitor",
  tv: "tv",
  speaker: "volume-2",
  mic: "mic",
  camera: "webcam"
}

function devicePixel(form, section) {
  return DEVICE_PIXELS[form] || (section === "src" ? "mic" : "volume-2")
}

// The mute button: the level as Omarchy's own volume icon, the microphone
// for an input.
function levelPixel(muted, volume, mic) {
  if (mic) return muted ? "mic-off" : "mic"
  if (muted || !(volume > 0)) return "volume-x"
  if (volume >= 0.67) return "volume-3"
  if (volume >= 0.34) return "volume-2"
  return "volume-1"
}

// The mark in a figure's fixed column: muted first, then an equalizer that
// shapes the sound. Empty otherwise; the column stays either way.
function markFor(muted, mic, eqShaping) {
  if (muted) return mic ? "mic-off" : "volume-x"
  if (eqShaping) return "sliders-horizontal"
  return ""
}

// Every pixel icon the QML and this file name, for the test that checks they
// all exist in Pixels.js.
var UI_PIXELS = ["chevron-down", "settings-cog", "arrow-left", "check", "sliders-horizontal",
  "volume-x", "volume-1", "volume-2", "volume-3", "mic", "mic-off", "app-windows"]

// The Nerd Font glyphs the panel kit is handed (Glyphs.js), each with its
// pixel icon. Glyph.qml draws the pixel icon for any glyph listed here, so
// the kit's icons match the rooms'. Code points, because a Nerd Font
// character is invisible in most editors.
var GLYPH_PIXELS = [
  [0xF04C3, "volume-2"],      // speaker
  [0xF057E, "volume-3"],      // volume high
  [0xF0580, "volume-2"],      // volume mid
  [0xF057F, "volume-1"],      // volume low
  [0xF0581, "volume-x"],      // volume off
  [0xF02CB, "headphone"],
  [0xF184F, "airpods"],       // earbuds
  [0xF0322, "laptop"],
  [0xF00AF, "volume-2"],      // bluetooth
  [0xF09A2, "volume-2"],      // bluetooth speaker
  [0xF0379, "monitor"],
  [0xF0F5F, "monitor"],       // monitor speaker
  [0xF0502, "tv"],
  [0xF036C, "mic"],
  [0xF036D, "mic-off"],
  [0xF0100, "webcam"],        // camera
  [0xF02B4, "gamepad"],
  [0xF02CE, "headphone"],     // headset
  [0xF075A, "music"],
  [0xF1394, "audio-waveform"],// aux
  [0xF028C, "message-text"],  // chat
  [0xF073A, "cancel"],        // no channel
  [0xF066A, "sliders-horizontal"],
  [0xF0493, "settings-cog"],
  [0xF0156, "close"],
  [0xF004D, "arrow-left"],
  [0xF003B, "app-windows"],
  [0xF012C, "check"],
  [0xF0140, "chevron-down"],
  [0xF0143, "chevron-up"],
  [0xF04E6, "reload"],        // sync
  [0xF01DA, "download"],
  [0xF0026, "warning-diamond"],
  [0xF02FD, "circle-info"],
  [0xF030C, "keyboard"],
  [0xF06B0, "download"]       // update
]

var PIXEL_GLYPHS = {}
;(function() {
  for (var i = 0; i < GLYPH_PIXELS.length; i++) PIXEL_GLYPHS[String.fromCodePoint(GLYPH_PIXELS[i][0])] = GLYPH_PIXELS[i][1]
})()

function pixelFor(glyph) {
  return PIXEL_GLYPHS[glyph] || ""
}

// ------------------------------------------------------------- the mark

// The Sonus mark, after its app icon: three faders, each a knob on a track,
// the track lit below the knob and dim above it. Drawn on the icons' 12-cell
// grid in their weight (one-cell tracks, knobs three by two), the 24-unit
// grid being the same drawing doubled. `knobs` are the rows the knobs' tops
// sit on, 1 at the top to 9 at the bottom: the faders down is the mark
// muted. `part` is "lit" (knobs and the tracks under them) or "track" (the
// tracks over them), so the two can take different colours.
var LOGO_KNOBS = [6, 2, 4]
var LOGO_DOWN = [9, 9, 9]
var LOGO_TOP = 1
var LOGO_BOTTOM = 10

function logoGrid(knobs, part) {
  var g = []
  for (var r = 0; r < 12; r++) { g.push([]); for (var c = 0; c < 12; c++) g[r].push(false) }
  for (var i = 0; i < 3; i++) {
    var k = Math.max(LOGO_TOP, Math.min(LOGO_BOTTOM - 1, Math.round(knobs && knobs[i] !== undefined ? knobs[i] : LOGO_KNOBS[i])))
    var col = 1 + i * 4
    for (var row = LOGO_TOP; row <= LOGO_BOTTOM; row++) {
      if (row >= k && row <= k + 1) {
        if (part === "lit") for (var dx = -1; dx <= 1; dx++) g[row][col + dx] = true
      } else if (row > k + 1) {
        if (part === "lit") g[row][col] = true
      } else if (part === "track") g[row][col] = true
    }
  }
  return g
}

// Runs along each row, merged down where the next rows repeat them, as
// [x, y, w, h]: the shape Pixels.js keeps its icons in.
function gridRects(grid) {
  var runs = []
  for (var r = 0; r < grid.length; r++) {
    var c = 0
    while (c < grid[r].length) {
      if (!grid[r][c]) { c++; continue }
      var s = c
      while (c < grid[r].length && grid[r][c]) c++
      runs.push([s, r, c - s, 1])
    }
  }
  var merged = []
  runs.forEach(function(run) {
    for (var m = 0; m < merged.length; m++) {
      var x = merged[m]
      if (x[0] === run[0] && x[2] === run[2] && x[1] + x[3] === run[1]) { x[3]++; return }
    }
    merged.push(run.slice())
  })
  return merged
}

// The mark as a pixel icon's art: { g12, g24 }.
function sonusLogo(knobs, part) {
  var g12 = gridRects(logoGrid(knobs, part || "lit"))
  return { g12: g12, g24: g12.map(function(q) { return [q[0] * 2, q[1] * 2, q[2] * 2, q[3] * 2] }) }
}

// Where the knobs are `k` of the way (0..1) from `from` to `to`: each fader a
// little after the one before, easing out, in whole rows so the art never
// smears. The mark's story: the faders rise into place when the panel
// opens, and drop when the output is muted.
function logoKnobs(from, to, k) {
  var out = []
  for (var i = 0; i < 3; i++) {
    var p = Math.max(0, Math.min(1, (k - i * 0.12) / 0.76))
    var e = 1 - Math.pow(1 - p, 3)
    out.push(Math.round(from[i] + (to[i] - from[i]) * e))
  }
  return out
}

// ------------------------------------------------------------ room tones

// Each room takes a tone from the theme's terminal palette, by what it is,
// the way DailyDash gives each category one colour and the plugins agree on
// them: the devices are the machine (blue), Game is play (green), Chat is a
// connection (cyan), Media is media (magenta), Aux is the rest (yellow). The
// apps that skip the channels have no tone of their own.
var KEY_TONES = {
  master: "blue",
  input: "blue",
  game: "green",
  chat: "cyan",
  media: "magenta",
  aux: "yellow"
}

function toneName(key) {
  return KEY_TONES[key] || ""
}

// The named colours in a theme's colors.toml: { red: "#565d60", ... }.
function parsePalette(text) {
  var out = {}
  String(text || "").split("\n").forEach(function(line) {
    var m = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (m) out[m[1]] = m[2]
  })
  return out
}

// Contrast between two colours ({r, g, b}, 0 to 1), by the WCAG formula.
function contrast(a, b) {
  function lum(c) {
    function ch(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
  }
  var la = lum(a), lb = lum(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

// Each tone's own hue, DailyDash's, for themes whose palette is all greys.
var TONE_HUES = {
  blue: "#5ab4f5",
  magenta: "#c38af0",
  cyan: "#4fc9d9",
  green: "#5cc98a",
  yellow: "#f1b467"
}

function hexRgb(hex) {
  var m = String(hex || "").match(/^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i)
  return m ? { r: parseInt(m[1], 16) / 255, g: parseInt(m[2], 16) / 255, b: parseInt(m[3], 16) / 255 } : null
}

function rgbHex(c) {
  function h(v) { var s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16); return s.length < 2 ? "0" + s : s }
  return "#" + h(c.r) + h(c.g) + h(c.b)
}

// HSL saturation, 0 to 1.
function saturation(c) {
  var max = Math.max(c.r, c.g, c.b), min = Math.min(c.r, c.g, c.b)
  var l = (max + min) / 2
  if (max === min) return 0
  return (max - min) / (1 - Math.abs(2 * l - 1))
}

// A room's tone: the theme's colour of that name when it is a colour, else
// the tone's own hue, either way softened toward the theme's text colour so
// it sits quietly in the theme. No name is the text colour itself.
function roomToneHex(name, palette, foreground) {
  var fg = hexRgb(foreground) || { r: 0.8, g: 0.8, b: 0.8 }
  if (!name) return rgbHex(fg)
  var own = hexRgb(palette ? palette[name] : null)
  var base = own && saturation(own) >= 0.3 ? own : hexRgb(TONE_HUES[name] || TONE_HUES.green)
  var k = 0.3
  return rgbHex({ r: base.r + (fg.r - base.r) * k, g: base.g + (fg.g - base.g) * k, b: base.b + (fg.b - base.b) * k })
}

// ------------------------------------------------------------ block face

// Levels in a three-row block face, as seven segments: the top and the middle
// bar ride the upper half of their row, so the digit sits two and a half rows
// tall. Returns the three rows; anything unknown is a dash.
var SEGMENTS = {
  "0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fbgc",
  "5": "afgcd", "6": "afgecd", "7": "abc", "8": "abcdefg", "9": "abcdfg", "-": "g"
}

// A one on the right-hand segments alone reads as a stray bar beside its
// neighbour, so it stands in the middle on a foot.
var BIG_ONE = ["▀█ ", " █ ", "▀▀▀"]

function bigDigits(text) {
  var rows = ["", "", ""]
  String(text).split("").forEach(function(ch, i) {
    var gap = i > 0 ? " " : ""
    if (ch === "1") {
      for (var r = 0; r < 3; r++) rows[r] += gap + BIG_ONE[r]
      return
    }
    var s = SEGMENTS[ch] === undefined ? SEGMENTS["-"] : SEGMENTS[ch]
    function on(seg) { return s.indexOf(seg) !== -1 }
    rows[0] += gap + (on("f") ? "█" : on("a") ? "▀" : " ") + (on("a") ? "▀" : " ") + (on("b") ? "█" : on("a") ? "▀" : " ")
    rows[1] += gap + (on("e") ? "█" : on("g") ? "▀" : " ") + (on("g") ? "▀" : " ") + (on("c") ? "█" : on("g") ? "▀" : " ")
    // Without a bottom bar (4, 7) the sides still reach the baseline.
    rows[2] += gap + (on("d") ? "▀▀▀" : (on("e") ? "▀" : " ") + " " + (on("c") ? "▀" : " "))
  })
  return rows
}

// ------------------------------------------------------------- pixel type

// Small numbers in the block face, as pixels: each digit is the face's
// columns by five half rows (bigDigits) with its middle column doubled, four
// wide, so the inside of a 0 or an 8 is two pixels and reads at bar size. The
// one keeps a single stem. The % is drawn to match. Rows top to bottom, "#" on.
var PIXEL_FONT = {
  "1": [".##.", "..#.", "..#.", "..#.", ".###"],
  "%": ["##..#", "##.#.", "..#..", ".#.##", "#..##"],
  " ": ["..", "..", "..", "..", ".."],
  ".": [".", ".", ".", ".", "#"]
}
;(function() {
  "023456789-".split("").forEach(function(ch) {
    var rows = bigDigits(ch)
    var half = []
    rows.forEach(function(row) {
      var top = "", bottom = ""
      for (var i = 0; i < row.length; i++) {
        var c = row.charAt(i)
        var t = c === "█" || c === "▀" ? "#" : "."
        var u = c === "█" || c === "▄" ? "#" : "."
        // The middle column twice.
        top += i === 1 ? t + t : t
        bottom += i === 1 ? u + u : u
      }
      half.push(top, bottom)
    })
    PIXEL_FONT[ch] = half.slice(0, 5)
  })
})()

// A line in the pixel type: { width, height, rects }, in cells, rects as
// [x, y, w, h] merged along each row. A cell between letters; anything the
// type lacks is skipped.
function pixelText(text) {
  var rects = [], x = 0
  String(text || "").split("").forEach(function(ch) {
    var glyph = PIXEL_FONT[ch]
    if (!glyph) return
    if (x > 0) x += 1
    for (var r = 0; r < glyph.length; r++) {
      var row = glyph[r], c = 0
      while (c < row.length) {
        if (row.charAt(c) !== "#") { c++; continue }
        var start = c
        while (c < row.length && row.charAt(c) === "#") c++
        rects.push([x + start, r, c - start, 1])
      }
    }
    x += glyph[0].length
  })
  return { width: x, height: 5, rects: rects }
}

// Whether the pixel type can draw all of `text`.
function drawable(text) {
  return String(text).split("").every(function(ch) { return PIXEL_FONT[ch] !== undefined })
}

// --------------------------------------------------------------- meters

// A volume drawn as a meter of cells, the way Batteries draws a battery: ten
// cells for a tenth each, so the level can be counted at a glance. For each
// cell, how full it is (0..1), how lit (`glow`, 0..1: a ripple passing, or
// the microphone hearing something), how far the pointer presses it
// (`press`, 0..1).
//
// opts: segments, level (0..100, fractional while it fills in), dent (0..1
// across the body, where the pointer is), ripples ([{ x, age }], x 0..1
// across, age in ms) and peak (0..1, what an input hears right now).
var METER = {
  RIPPLE_MS: 760,      // Weave's ripple
  RIPPLE_CELLS: 14,    // how far it travels, in cells
  DENT_CELLS: 1.6      // how wide the pointer presses, in cells
}

function meterCells(opts) {
  var n = Math.max(1, Math.floor(opts.segments || 10))
  var level = hasLevel(opts.level) ? Math.max(0, Math.min(100, opts.level)) : 0
  var full = level / 100 * n
  var ripples = opts.ripples || []
  // What an input hears lights the cells it reaches, inside the filled part:
  // the level a fader lets through.
  var heard = Math.max(0, Math.min(1, Number(opts.peak) || 0)) * full
  var out = []
  for (var i = 0; i < n; i++) {
    var fill = Math.max(0, Math.min(1, full - i))
    var glow = Math.max(0, Math.min(1, heard - i)) * 0.45
    for (var j = 0; j < ripples.length; j++) {
      var k = ripples[j].age / METER.RIPPLE_MS
      if (k < 0 || k >= 1) continue
      var d = Math.abs(i + 0.5 - ripples[j].x * n)
      var ring = 1 - Math.abs(d - k * METER.RIPPLE_CELLS) / 1.1
      if (ring > 0) glow = Math.max(glow, ring * (1 - k))
    }
    var press = 0
    if (opts.dent !== null && opts.dent !== undefined)
      press = Math.max(0, 1 - Math.abs(i + 0.5 - opts.dent * n) / METER.DENT_CELLS)
    out.push({ fill: fill, glow: glow, press: press })
  }
  return out
}

// Where a press on a fader lands: 0..1 across the meter, snapped to `step`.
function faderValue(x, width, step) {
  if (!(width > 0)) return 0
  var v = Math.max(0, Math.min(1, x / width))
  var s = step > 0 ? step : 0.05
  return Math.round(v / s) * s
}

// ------------------------------------------------------------------ type

// Monocraft draws each glyph on a grid nine of its pixels tall, every glyph
// two thirds of that wide. Text lands on the screen's pixels only at a whole
// multiple of nine, so the panel's text comes in two sizes: running text at
// the multiple nearest the shell's body size, titles at twice that.
var MONO_EM = 9

function monoSize(body) {
  return MONO_EM * Math.max(1, Math.round((Number(body) || MONO_EM) / MONO_EM))
}

// How many characters of Monocraft at `size` fit across `width`.
function monoColumns(width, size) {
  return Math.max(1, Math.floor((Number(width) || 0) / (size * 2 / 3) + 0.001))
}

// `text` broken into lines of at most `cols` characters for a monospaced
// column: at spaces, and inside a long name (alsa_output.usb-Focusrite_...)
// after one of _ . - / : or between the humps of a camelCase run, so a raw
// name breaks where it has joints, never in the middle of a word. Only a run
// with no joint longer than a line is cut.
function wrapName(text, cols) {
  text = String(text || "")
  if (!(cols >= 2) || text.length <= cols) return text
  var lines = []
  var line = ""
  function put(word) {
    if (line === "") line = word
    else if (line.length + 1 + word.length <= cols) line += " " + word
    else { lines.push(line); line = word }
  }
  var words = text.split(/\s+/).filter(function(w) { return w !== "" })
  for (var i = 0; i < words.length; i++) {
    var word = words[i]
    if (word.length <= cols) { put(word); continue }
    if (line !== "") { lines.push(line); line = "" }
    while (word.length > cols) {
      var cut = -1
      // A separator first; a camelCase hump only where there is none.
      for (var j = cols; j >= 1 && cut < 0; j--) if ("_.-/:".indexOf(word.charAt(j - 1)) >= 0) cut = j
      for (var k = cols; k >= 1 && cut < 0; k--) if (/[a-z0-9]/.test(word.charAt(k - 1)) && /[A-Z]/.test(word.charAt(k))) cut = k
      if (cut < 0) cut = cols
      lines.push(word.substring(0, cut))
      word = word.substring(cut)
    }
    line = word
  }
  if (line !== "") lines.push(line)
  return lines.join("\n")
}

// ---------------------------------------------------------------- prompt

function escapeHtml(text) {
  return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

// The prompt line `typed` characters in, as styled text that always lays out
// the whole line plus a cursor cell, the part not typed yet drawn clear, so a
// word never wraps differently while it types. The cursor stands in for the
// next character, except a space, which it would glue to the next word; once
// typed, it blinks in the cell kept for it at the end. An underscore, the
// terminal's own cursor, because Monocraft has no block characters: a glyph
// it lacks comes from a fallback font with taller lines, and the row would
// grow and shrink as the cursor moved between lines.
var CURSOR = "_"
var CLEAR = "<font color=\"#00000000\">"

function revealLine(line, typed, cursorOn) {
  line = String(line || "")
  var n = Math.max(0, Math.min(line.length, Math.floor(typed) || 0))
  var shown = escapeHtml(line.substring(0, n))
  var rest
  if (n < line.length) {
    var next = line.charAt(n)
    shown += next === " " ? " " : CURSOR
    rest = line.substring(n + 1) + CURSOR
  } else if (cursorOn) {
    shown += CURSOR
    rest = ""
  } else {
    rest = CURSOR
  }
  return rest === "" ? shown : shown + CLEAR + escapeHtml(rest) + "</font>"
}

// Text arriving the way a terminal decodes it: the first `progress` of it
// is real, the rest cycles through glyphs. Spaces and separators stay put so
// the line keeps its shape. `seed` varies the noise between runs.
var GLITCH = "#%&*+=<>/\\|~:;?!$@"

function scramble(text, progress, seed) {
  text = String(text || "")
  var keep = Math.floor(Math.max(0, Math.min(1, progress)) * text.length)
  var tick = Math.floor(progress * 14)
  var out = ""
  for (var i = 0; i < text.length; i++) {
    var ch = text.charAt(i)
    if (i < keep || ch === " " || ch === "·") { out += ch; continue }
    var h = (((i + 1) * 73856093) ^ (((seed || 0) + 1) * 19349663) ^ ((tick + 1) * 83492791)) >>> 0
    out += GLITCH.charAt(h % GLITCH.length)
  }
  return out
}

// ------------------------------------------------------------ hover card

// The card that opens when the pointer rests on the bar item: the output,
// the input and each running channel, a line each. { key, name, icon, tone
// (a KEY_TONES name), volume (0..1), muted, mark }.
// state: { output: { label, form }, input: { label, form } | null,
//          volumes: { key: v }, muted: { key: bool }, channels: [{ key, title }] }
function hoverRows(state) {
  var rows = []
  if (!state) return rows
  var volumes = state.volumes || {}
  var muted = state.muted || {}
  if (state.output) {
    rows.push({ key: "master", name: state.output.label || "Output", icon: devicePixel(state.output.form, "sink"),
                tone: toneName("master"), volume: volumes.master, muted: !!muted.master,
                mark: markFor(!!muted.master, false, false) })
  }
  if (state.input) {
    rows.push({ key: "input", name: state.input.label || "Input", icon: devicePixel(state.input.form, "src"),
                tone: toneName("input"), volume: volumes.input, muted: !!muted.input,
                mark: markFor(!!muted.input, true, false) })
  }
  ;(state.channels || []).forEach(function(c) {
    rows.push({ key: c.key, name: c.title, icon: channelPixel(c.key), tone: toneName(c.key),
                volume: volumes[c.key], muted: !!muted[c.key], mark: markFor(!!muted[c.key], false, !!c.eq) })
  })
  return rows
}
