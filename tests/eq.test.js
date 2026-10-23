// Run with: node tests/eq.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const source = fs.readFileSync(path.join(__dirname, "..", "ui", "Eq.js"), "utf8").replace(/^\.pragma library\s*/, "")
const Eq = new Function(source + "\nreturn { BAND_FREQS, BAND_COUNT, BAND_Q, GAIN_LIMIT, PRESETS, clamp, flat, normalized, isFlat, presetPreamp, snap, gainText, dbText, responseDb }")()

// The panel's copy of the band layout must match the engine's (eq.py).
const engine = fs.readFileSync(path.join(__dirname, "..", "engine", "sonus", "eq.py"), "utf8")
const freqs = engine.match(/BAND_FREQS[^=]*=\s*\(([^)]*)\)/)[1].split(",").map(s => parseFloat(s)).filter(n => !isNaN(n))
assert.deepStrictEqual(Eq.BAND_FREQS, freqs)
assert.strictEqual(Eq.BAND_Q, parseFloat(engine.match(/^BAND_Q = ([\d.]+)/m)[1]))
assert.strictEqual(Eq.GAIN_LIMIT, parseFloat(engine.match(/^GAIN_LIMIT = ([\d.]+)/m)[1]))

// Every preset has one gain per band, inside the limit, and Flat is flat.
for (const p of Eq.PRESETS) {
  assert.strictEqual(p.gains.length, Eq.BAND_COUNT, p.name)
  for (const g of p.gains) assert.ok(Math.abs(g) <= Eq.GAIN_LIMIT, p.name)
}
assert.ok(Eq.isFlat({ preamp: 0, gains: Eq.PRESETS[0].gains }))

// normalized: pads, clamps, and survives junk.
const n = Eq.normalized({ enabled: false, preamp: 40, gains: [30, -30, "x"] })
assert.strictEqual(n.enabled, false)
assert.strictEqual(n.preamp, 18)
assert.deepStrictEqual(n.gains, [18, -18, 0, 0, 0, 0, 0, 0, 0, 0])
assert.deepStrictEqual(Eq.normalized(null), Eq.flat())
assert.strictEqual(Eq.normalized({}).enabled, true)

// Make-up gain takes back half the peak boost, never boosts.
assert.strictEqual(Eq.presetPreamp([5, 4, 0]), -2.5)
assert.strictEqual(Eq.presetPreamp([-3, -1]), 0)

// Fader snapping: a detent at 0, half-dB steps.
assert.strictEqual(Eq.snap(0.3), 0)
assert.strictEqual(Eq.snap(1.26), 1.5)
assert.strictEqual(Eq.snap(-2.74), -2.5)
assert.strictEqual(Eq.gainText(0), "0")
assert.strictEqual(Eq.gainText(3), "+3")
assert.strictEqual(Eq.gainText(-1.5), "-1.5")
assert.strictEqual(Eq.dbText(-2), "-2.0 dB")

// The drawn response: flat is 0 dB everywhere, a boost peaks at its band,
// and the preamp shifts the whole curve.
const flatGains = new Array(10).fill(0)
assert.ok(Math.abs(Eq.responseDb(1000, flatGains, 0)) < 1e-9)
const boosted = flatGains.slice(); boosted[5] = 6
assert.ok(Math.abs(Eq.responseDb(1000, boosted, 0) - 6) < 0.3)
assert.ok(Eq.responseDb(8000, boosted, 0) < 1)
assert.ok(Math.abs(Eq.responseDb(1000, flatGains, -3) + 3) < 1e-9)

console.log("eq tests passed")
