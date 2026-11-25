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
  "PIXEL_FONT", "pixelText", "drawable", "meterCells", "METER", "faderValue", "monoCell", "monoAdvance", "monoColumns", "wrapName",
  "scramble", "hoverRows", "LOGO_KNOBS", "LOGO_DOWN", "logoGrid", "gridRects", "sonusLogo", "logoKnobs", "revealLine", "SPECTRUM", "spectrumFrame"])
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

// No Nerd Font glyph is typed straight into the QML or the helpers, past
// the map (as ROG Deck checks): every one has a pixel icon. The one the kit
// types itself, the "Check now" button inside UpdateSection, is exempt.
{
  const files = ["Panel.qml", "Service.qml"].map(f => path.join(__dirname, "..", f))
    .concat(fs.readdirSync(qmlDir).filter(f => /\.(qml|js)$/.test(f) && f !== "UpdateSection.qml" && f !== "Pixels.js")
      .map(f => path.join(qmlDir, f)))
  const exempt = new Set([0xF0453])
  for (const file of files) {
    const text = fs.readFileSync(file, "utf8")
    const found = []
    for (const ch of text) found.push(ch.codePointAt(0))
    for (const m of text.matchAll(/\\u\{?([0-9A-Fa-f]{4,6})\}?|0x(F[0-9A-Fa-f]{4})\b/g)) found.push(parseInt(m[1] || m[2], 16))
    for (const cp of found) {
      if (!((cp >= 0xE000 && cp <= 0xF8FF) || (cp >= 0xF0000 && cp <= 0xFFFFD)) || exempt.has(cp)) continue
      assert.ok(Model.pixelFor(String.fromCodePoint(cp)), "U+" + cp.toString(16).toUpperCase() + " in " + path.basename(file) + " has a pixel icon")
    }
  }
}

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

// A one- or two-letter last word never sits alone.
assert.strictEqual(Model.wrapName("Counter-Strike 2", 14), "Counter-\nStrike 2")
assert.strictEqual(Model.wrapName("Living room TV", 12), "Living\nroom TV")
assert.strictEqual(Model.wrapName("Zen", 14), "Zen")

// The kit's MonoText steps: font pixels a cell, at each window scale
// (the table in ui/MonoText.qml).
for (const [d, small, body, title] of [[1, 1, 2, 3], [1.25, 1, 2, 3], [1.5, 2, 3, 4], [2, 2, 3, 4]]) {
  assert.deepStrictEqual([Model.monoCell("small", d), Model.monoCell("body", d), Model.monoCell("title", d)], [small, body, title], "dpr " + d)
}
assert.strictEqual(Model.monoAdvance("body", 2), 9)
assert.strictEqual(Model.monoAdvance("small", 1.25), 4.8)
assert.strictEqual(Model.monoColumns(60, 6), 10)
assert.strictEqual(Model.monoColumns(59.9, 6), 9)
{
  // And MonoText itself still says so.
  const mono = fs.readFileSync(path.join(qmlDir, "MonoText.qml"), "utf8")
  assert.ok(mono.includes("var small = Math.max(1, Math.round(d))") && mono.includes("var body = Math.max(small + 1, Math.round(1.5 * d))")
    && mono.includes('return Math.max(body + 1, Math.round(2 * d))'), "Model.monoCell mirrors MonoText.cellFor")
}

// Names break at spaces, and long raw names at their joints, never inside a word.
assert.strictEqual(Model.wrapName("Laptop speakers", 20), "Laptop speakers")
assert.strictEqual(Model.wrapName("Bose QuietComfort Ultra Headphones", 18), "Bose QuietComfort\nUltra Headphones")
const raw = Model.wrapName("alsa_output.usb-Focusrite_Scarlett_2i2_USB-00.analog-stereo", 20)
for (const l of raw.split("\n")) assert.ok(l.length <= 20, l)
assert.strictEqual(raw.replace(/\n/g, ""), "alsa_output.usb-Focusrite_Scarlett_2i2_USB-00.analog-stereo")
assert.ok(raw.split("\n").slice(0, -1).every(l => "_.-/:".includes(l.slice(-1))), raw)
assert.strictEqual(Model.wrapName("steam_app_1245620_EldenRingNightreign", 20), "steam_app_1245620_\nEldenRingNightreign")
assert.strictEqual(Model.wrapName("steam_app_1245620_EldenRingNightreign", 14), "steam_app_\n1245620_\nEldenRing\nNightreign")
// A run with no joint longer than a line is the only thing cut.
assert.strictEqual(Model.wrapName("abcdefghij", 4), "abcd\nefgh\nij")
assert.strictEqual(Model.wrapName("Spotify", 3), "Spo\ntif\ny")

// The spectrum's ceiling halves in about a second and a half at cava's frame rate.
{
  const halve = Math.log(0.5) / Math.log(Model.SPECTRUM.DECAY) / Model.SPECTRUM.FPS
  assert.ok(halve > 1.2 && halve < 1.7, "ceiling halves in " + halve.toFixed(2) + " s")
}

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
assert.strictEqual(Model.revealLine("ab", 0, true), "_<font color=\"#00000000\">b_</font>")
assert.strictEqual(Model.revealLine("a b", 1, true), "a <font color=\"#00000000\">b_</font>")
assert.strictEqual(Model.revealLine("ab", 2, true), "ab_")
assert.strictEqual(Model.revealLine("ab", 2, false), "ab<font color=\"#00000000\">_</font>")
assert.ok(Model.revealLine("Tom & Jerry", 11, true).includes("Tom &amp; Jerry"))

// The spectrum: quiet music still fills the room, silence lights nothing,
// and a ceiling falls back a little each frame rather than all at once.
{
  const half = Math.round(Math.pow(0.5, Model.SPECTRUM.CURVE) * 10)
  assert.ok(half > 5 && half < 10)
  const loud = Model.spectrumFrame("1000;500;0;", 3, 10, 0)
  assert.deepStrictEqual(loud.levels, [10, half, 0])
  const quiet = Model.spectrumFrame("200;100;0;", 3, 10, 0)
  assert.deepStrictEqual(quiet.levels, [10, half, 0])
  const after = Model.spectrumFrame("200;100;0;", 3, 10, 1000)
  assert.strictEqual(after.ceiling, 1000 * Model.SPECTRUM.DECAY)
  assert.ok(after.levels[0] < 10)
  let ceiling = 1000
  for (let i = 0; i < 600; i++) ceiling = Model.spectrumFrame("200;100;0;", 3, 10, ceiling).ceiling
  assert.deepStrictEqual(Model.spectrumFrame("200;100;0;", 3, 10, ceiling).levels, [10, half, 0])
  assert.deepStrictEqual(Model.spectrumFrame("0;0;0;", 3, 10, 0).levels, [0, 0, 0])
  // A hiss of 1 in RANGE stays dark; music at the floor fills the room.
  assert.deepStrictEqual(Model.spectrumFrame("1;0;0;", 3, 10, 0).levels, [0, 0, 0])
  assert.deepStrictEqual(Model.spectrumFrame(Model.SPECTRUM.FLOOR + ";0;0;", 3, 10, 0).levels, [10, 0, 0])
  assert.deepStrictEqual(Model.spectrumFrame("0;0;0;", 3, 10, 50).levels, [0, 0, 0])
  assert.deepStrictEqual(Model.spectrumFrame("", 2, 10, 0).levels, [0, 0])
  assert.deepStrictEqual(Model.spectrumFrame("500000;-3;x;", 3, 10, 0).levels, [10, 0, 0])
}

console.log("model ok")
