// Run with: node tests/model.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

function load(file, names) {
  const source = fs.readFileSync(path.join(__dirname, "..", "ui", file), "utf8").replace(/^\.pragma library\s*/, "")
  return new Function(source + "\nreturn { " + names.join(", ") + " }")()
}

const Model = load("Model.js", ["hasLevel", "percentOf", "CHANNEL_PIXELS", "channelPixel", "DEVICE_PIXELS", "devicePixel",
  "levelPixel", "markFor", "UI_PIXELS", "GLYPH_PIXELS", "PIXEL_GLYPHS", "pixelFor",
  "KEY_TONES", "toneName", "parsePalette", "contrast", "TONE_HUES", "hexRgb", "roomToneHex", "bigDigits",
  "PIXEL_FONT", "pixelText", "drawable", "meterCells", "METER", "faderValue", "STORIES", "storyOf", "storyPose",
  "scramble", "hoverRows", "LOGO_KNOBS", "LOGO_DOWN", "logoGrid", "gridRects", "sonusLogo", "logoKnobs", "revealLine"])
const { icons } = load("Pixels.js", ["icons"])
const Glyphs = load("Glyphs.js", ["deviceGlyph", "channel", "levelIcon"])

// Every pixel icon the model and the QML name is in Pixels.js, on both grids.
const named = new Set([].concat(
  Object.values(Model.CHANNEL_PIXELS), Object.values(Model.DEVICE_PIXELS),
  Model.UI_PIXELS, Model.GLYPH_PIXELS.map(p => p[1])))
const qmlDir = path.join(__dirname, "..", "ui")
const qml = ["Panel.qml"].map(f => path.join(__dirname, "..", f))
  .concat(fs.readdirSync(qmlDir).filter(f => f.endsWith(".qml")).map(f => path.join(qmlDir, f)))
for (const file of qml) {
  const text = fs.readFileSync(file, "utf8")
  for (const m of text.matchAll(/\b(?:name|icon|mark):\s*"([a-z0-9-]+)"/g)) named.add(m[1])
  for (const row of text.split("\n").filter(l => /^\s*(name|icon|mark):/.test(l)))
    for (const m of row.matchAll(/"([a-z0-9-]+)"/g)) named.add(m[1])
}
for (const name of named) {
  assert.ok(icons[name], "missing pixel icon " + name)
  assert.ok(icons[name].g24.length > 0 && icons[name].g12.length > 0, "empty icon " + name)
}
// The rects stay on their grids.
for (const [name, art] of Object.entries(icons)) {
  for (const [x, y, w, h] of art.g24) assert.ok(x >= 0 && y >= 0 && x + w <= 24 && y + h <= 24, name)
  for (const [x, y, w, h] of art.g12) assert.ok(x >= 0 && y >= 0 && x + w <= 12 && y + h <= 12, name)
}
// The mark: three faders on the 12-cell grid, lit and track never overlapping,
// a knob three wide on each, and the same drawing doubled on the 24 grid.
const cellsOf = art => { const s = new Set(); for (const [x, y, w, h] of art) for (let i = x; i < x + w; i++) for (let j = y; j < y + h; j++) s.add(i + "," + j); return s }
for (const knobs of [Model.LOGO_KNOBS, Model.LOGO_DOWN, [1, 1, 1], [5, 9, 3]]) {
  const lit = Model.sonusLogo(knobs, "lit"), track = Model.sonusLogo(knobs, "track")
  const litCells = cellsOf(lit.g12), trackCells = cellsOf(track.g12)
  for (const c of trackCells) assert.ok(!litCells.has(c), "overlap " + c)
  for (const [x, y, w, h] of lit.g12.concat(track.g12)) assert.ok(x >= 0 && y >= 0 && x + w <= 12 && y + h <= 12)
  assert.strictEqual(cellsOf(lit.g24).size, litCells.size * 4)
  // Every fader has its knob: three cells wide on two rows.
  for (let i = 0; i < 3; i++) {
    const col = 1 + i * 4, k = knobs[i]
    for (const dy of [0, 1]) for (const dx of [-1, 0, 1]) assert.ok(litCells.has((col + dx) + "," + (k + dy)), knobs.join())
  }
}
// Muted is the faders all the way down, with nothing lit under them.
assert.strictEqual(cellsOf(Model.sonusLogo(Model.LOGO_DOWN, "lit").g12).size, 3 * 3 * 2)
// The story moves in whole rows and ends where it was going.
assert.deepStrictEqual(Model.logoKnobs(Model.LOGO_DOWN, Model.LOGO_KNOBS, 0), Model.LOGO_DOWN)
assert.deepStrictEqual(Model.logoKnobs(Model.LOGO_DOWN, Model.LOGO_KNOBS, 1), Model.LOGO_KNOBS)
for (let k = 0; k <= 1; k += 0.05) for (const v of Model.logoKnobs(Model.LOGO_DOWN, Model.LOGO_KNOBS, k)) assert.ok(Number.isInteger(v))

// Every glyph the panel hands the kit (Glyphs.js) has a pixel icon, so no
// Nerd Font glyph ends up beside the pixel art.
const glyphSource = fs.readFileSync(path.join(qmlDir, "Glyphs.js"), "utf8")
for (const m of glyphSource.matchAll(/^var (\w+) = g\((0x[0-9A-F]+)\)/gm))
  assert.ok(Model.pixelFor(String.fromCodePoint(parseInt(m[2], 16))), "no pixel icon for Glyphs." + m[1])
for (const form of ["laptop", "headphones", "earbuds", "hdmi", "mic", "camera", ""])
  assert.ok(Model.pixelFor(Glyphs.deviceGlyph(form)), "notice icon for " + form)
assert.strictEqual(Model.pixelFor("x"), "")

// A channel's icon never looks like a device, and each channel has its own.
const channelIcons = ["game", "chat", "media", "aux", ""].map(Model.channelPixel)
assert.strictEqual(new Set(channelIcons).size, channelIcons.length)
const forms = ["laptop", "headphones", "headset", "earbuds", "bluetooth", "hdmi", "tv", "speaker", "mic", "camera", "", undefined]
for (const form of forms) assert.ok(!channelIcons.includes(Model.devicePixel(form, "sink")), String(form))
assert.notStrictEqual(Model.devicePixel("earbuds"), Model.devicePixel("headphones"))
assert.strictEqual(Model.devicePixel("", "src"), "mic")

// Levels and marks.
assert.strictEqual(Model.levelPixel(false, 1), "volume-3")
assert.strictEqual(Model.levelPixel(false, 0.5), "volume-2")
assert.strictEqual(Model.levelPixel(false, 0.1), "volume-1")
assert.strictEqual(Model.levelPixel(false, 0), "volume-x")
assert.strictEqual(Model.levelPixel(true, 1), "volume-x")
assert.strictEqual(Model.levelPixel(true, 1, true), "mic-off")
assert.strictEqual(Model.markFor(true, false, true), "volume-x")
assert.strictEqual(Model.markFor(false, false, true), "sliders-horizontal")
assert.strictEqual(Model.markFor(false, true, false), "")

// Tones: every room has a valid hex, a grey theme falls back to the tone's own
// hue, and no tone is the text colour.
const grey = Model.parsePalette('color1 = "#565d60"\nblue = "#808080"\ngreen = "#7a7a7a"\nmagenta = "#999999"\ncyan = "#666666"\nyellow = "#aaaaaa"\n')
assert.strictEqual(grey.blue, "#808080")
const tokyo = Model.parsePalette("blue = '#7aa2f7'\ngreen = \"#9ece6a\"\n")
for (const key of ["master", "input", "game", "chat", "media", "aux", ""]) {
  for (const palette of [grey, tokyo, {}]) {
    const hex = Model.roomToneHex(Model.toneName(key), palette, "#c0caf5")
    assert.match(hex, /^#[0-9a-f]{6}$/, key)
    if (key) assert.notStrictEqual(hex, "#c0caf5", key)
  }
}
assert.strictEqual(Model.roomToneHex("", {}, "#c0caf5"), "#c0caf5")
// A grey theme colour is not used; the hue is.
assert.strictEqual(Model.roomToneHex("blue", grey, "#ffffff"), Model.roomToneHex("blue", {}, "#ffffff"))
// Each channel its own tone.
assert.strictEqual(new Set(["game", "chat", "media", "aux"].map(Model.toneName)).size, 4)
assert.ok(Model.contrast({ r: 1, g: 1, b: 1 }, { r: 0, g: 0, b: 0 }) > 20)

// The block face: three rows, every digit the same width, unknown as a dash.
for (const n of ["0", "7", "18", "100", "--"]) {
  const rows = Model.bigDigits(n)
  assert.strictEqual(rows.length, 3)
  assert.ok(rows.every(r => r.length === rows[0].length))
  assert.strictEqual(rows[0].length, n.length * 4 - 1)
}

// Every string the pixel type writes can be drawn: volumes as percents.
for (let v = 0; v <= 100; v++) assert.ok(Model.drawable(v + "%"), String(v))
assert.ok(Model.drawable("--"))
assert.ok(Model.drawable("%"))
assert.strictEqual(Model.pixelText("100%").height, 5)
assert.strictEqual(Model.percentOf(0.456), 46)
assert.strictEqual(Model.percentOf(3), 100)
assert.strictEqual(Model.percentOf(null), 0)

// Meter cells: a tenth a cell, peak lights only what the level lets through,
// a ripple runs out and is gone.
const half = Model.meterCells({ segments: 10, level: 45 })
assert.strictEqual(half.length, 10)
assert.deepStrictEqual(half.map(c => c.fill), [1, 1, 1, 1, 0.5, 0, 0, 0, 0, 0])
assert.ok(half.every(c => c.glow === 0 && c.press === 0))
const heard = Model.meterCells({ segments: 10, level: 50, peak: 1 })
assert.ok(heard[0].glow > 0 && heard[4].glow > 0 && heard[5].glow === 0)
const ring = Model.meterCells({ segments: 10, level: 50, ripples: [{ x: 0.5, age: 100 }] })
assert.ok(ring.some(c => c.glow > 0))
const gone = Model.meterCells({ segments: 10, level: 50, ripples: [{ x: 0.5, age: Model.METER.RIPPLE_MS }] })
assert.ok(gone.every(c => c.glow === 0))
const pressed = Model.meterCells({ segments: 10, level: 50, dent: 0.05 })
assert.ok(pressed[0].press > 0.9 && pressed[5].press === 0)

// The fader: where a press lands, in 5% steps, clamped.
assert.strictEqual(Model.faderValue(50, 100, 0.05), 0.5)
assert.strictEqual(Model.faderValue(52, 100, 0.05), 0.5)
assert.strictEqual(Model.faderValue(53, 100, 0.05), 0.55)
assert.strictEqual(Model.faderValue(-10, 100, 0.05), 0)
assert.strictEqual(Model.faderValue(140, 100, 0.05), 1)
assert.strictEqual(Model.faderValue(10, 0, 0.05), 0)

// Every story ends where it began, in whole pixels the whole way.
for (const story of new Set(Object.values(Model.STORIES).concat(["pop", "press"]))) {
  assert.deepStrictEqual(Model.storyPose(story, 0), { x: 0, y: 0 }, story)
  assert.deepStrictEqual(Model.storyPose(story, 1), { x: 0, y: 0 }, story)
  for (let k = 0; k <= 1; k += 0.05) {
    const p = Model.storyPose(story, k)
    assert.ok(Number.isInteger(p.x) && Number.isInteger(p.y), story)
  }
}
assert.strictEqual(Model.storyOf("game"), "shake")
assert.strictEqual(Model.storyOf("unknown"), "pop")

// The decode keeps the line's shape and ends on the line.
const line = "Output · 2 more"
const mid = Model.scramble(line, 0.3, 1)
assert.strictEqual(mid.length, line.length)
assert.strictEqual(mid.charAt(6), " ")
assert.strictEqual(mid.charAt(7), "·")
assert.strictEqual(Model.scramble(line, 1, 1), line)

// The hover card: output, input, then the running channels, marks in place.
const rows = Model.hoverRows({
  output: { label: "AirPods Pro", form: "earbuds" },
  input: { label: "ALC285 Analog", form: "mic" },
  volumes: { master: 1, input: 0.94, game: 0.36, chat: 0.4 },
  muted: { chat: true },
  channels: [{ key: "game", title: "Game", eq: true }, { key: "chat", title: "Chat", eq: false }]
})
assert.deepStrictEqual(rows.map(r => r.key), ["master", "input", "game", "chat"])
assert.strictEqual(rows[0].icon, "airpods")
assert.strictEqual(rows[1].icon, "mic")
assert.strictEqual(rows[2].mark, "sliders-horizontal")
assert.strictEqual(rows[3].mark, "volume-x")
assert.strictEqual(rows[2].tone, "green")
for (const r of rows) assert.ok(icons[r.icon], r.icon)
assert.deepStrictEqual(Model.hoverRows(null), [])

// The prompt always lays out the whole line and a cursor cell, so a word
// never wraps differently while it types: strip the markup and the text is
// the same length at every step.
const plain = t => t.replace(/<[^>]+>/g, "").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
const sentence = "Move Tom & Jerry <3> to Game"
for (let n = 0; n <= sentence.length; n++)
  for (const on of [true, false]) assert.strictEqual(plain(Model.revealLine(sentence, n, on)).length, sentence.length + 1, n + " " + on)
assert.strictEqual(Model.revealLine("ab", 0, true), "\u258C<font color=\"#00000000\">b\u258C</font>")
assert.strictEqual(Model.revealLine("a b", 1, true), "a <font color=\"#00000000\">b\u258C</font>")
assert.strictEqual(Model.revealLine("ab", 2, true), "ab\u258C")
assert.strictEqual(Model.revealLine("ab", 2, false), "ab<font color=\"#00000000\">\u258C</font>")
assert.ok(Model.revealLine("Tom & Jerry", 11, true).includes("Tom &amp; Jerry"))

console.log("model ok")
