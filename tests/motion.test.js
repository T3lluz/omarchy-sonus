// Run with: node tests/motion.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

function load(file, names) {
  const source = fs.readFileSync(path.join(__dirname, "..", "ui", file), "utf8").replace(/^\.pragma library\s*/, "")
  return new Function(source + "\nreturn { " + names.join(", ") + " }")()
}

const Motion = load("Motion.js", ["SPECS", "specFor", "frame", "cells", "fillRows", "eqHeights", "eqArt",
  "TICK_MS", "LOOP_TICKS", "FRAME_MS", "EQ_PERIODS", "EQ_TALLEST", "EQ_BOTTOM"])
const { icons } = load("Pixels.js", ["icons"])

// The cells a list of rectangles covers, as a sorted list of "x,y".
function covered(rects) {
  const out = new Set()
  for (const [x, y, w, h] of rects)
    for (let r = y; r < y + h; r++)
      for (let c = x; c < x + w; c++) out.add(c + "," + r)
  return [...out].sort()
}

const steps = []
for (let t = 0; t <= 1.0001; t += 0.01) steps.push(Math.min(1, t))

for (const [name, spec] of Object.entries(Motion.SPECS)) {
  const art = icons[name]
  assert.ok(art, name + " has art")
  assert.ok(spec.ms > 0 && spec.ms <= 1200, name + " plays briefly")
  const named = new Set(Object.keys(art.parts || { base: 1 }).concat(Object.keys(art.layers || {})))
  for (const fine of [true, false]) {
    const grid = fine ? "g24" : "g12"
    const rest = covered(art[grid])
    // The parts together are the icon, so it rests exactly as drawn.
    assert.deepStrictEqual(covered(Motion.frame(art, null, 1, false, fine, 0)), rest, name + " at rest")
    // Played again it starts and ends at rest, so nothing jumps.
    assert.deepStrictEqual(covered(Motion.frame(art, spec, 0, false, fine, 0)), rest, name + " starts at rest")
    assert.deepStrictEqual(covered(Motion.frame(art, spec, 1, false, fine, 0)), rest, name + " ends at rest")
    assert.deepStrictEqual(covered(Motion.frame(art, spec, 1, true, fine, 0)), rest, name + " ends at rest entering")
    for (const entering of [false, true]) {
      for (const t of steps) {
        for (const part of Object.keys(spec.pose(t, entering))) assert.ok(named.has(part), name + " has " + part)
        for (const q of Motion.frame(art, spec, t, entering, fine, 0))
          assert.ok(q.every(Number.isInteger), name + " moves in whole cells at " + t)
      }
    }
  }
}

// What is not named in SPECS rests.
assert.strictEqual(Motion.specFor("chevron-down"), null)

// The microphone's capsule fills a row at a time, inside the capsule.
assert.strictEqual(Motion.fillRows(0), 0)
assert.strictEqual(Motion.fillRows(0.01), 0)
assert.strictEqual(Motion.fillRows(1), 5)
for (let l = 0.03; l <= 1; l += 0.05) {
  const rows = Motion.fillRows(l)
  assert.ok(rows >= 1 && rows <= 5)
  assert.ok(rows >= Motion.fillRows(l - 0.03))
}
const mic = icons.mic
const capsule = covered(mic.parts.capsule.g12)
const full = covered(Motion.frame(mic, null, 1, false, false, 5))
for (const cell of full) assert.ok(covered(mic.g12).includes(cell) || inside(cell), "fill stays in the capsule")
function inside(cell) {
  const [x, y] = cell.split(",").map(Number)
  const xs = capsule.map(c => Number(c.split(",")[0]))
  const ys = capsule.map(c => Number(c.split(",")[1]))
  return x > Math.min(...xs) && x < Math.max(...xs) && y > Math.min(...ys) && y < Math.max(...ys)
}

// The loops: every bar's period divides the clock's, so the bars come round
// with it, and they stand on the bottom row inside the grid.
for (const p of Motion.EQ_PERIODS) assert.strictEqual(Motion.LOOP_TICKS % p, 0, "period " + p)
for (let tick = 0; tick < Motion.LOOP_TICKS; tick++) {
  assert.deepStrictEqual(Motion.eqHeights(tick, true), Motion.eqHeights(tick + Motion.LOOP_TICKS, true))
  for (const h of Motion.eqHeights(tick, true)) assert.ok(Number.isInteger(h) && h >= 1 && h <= Motion.EQ_TALLEST)
  for (const [x, y, w, h] of Motion.eqArt(tick, true).g12) {
    assert.strictEqual(y + h, Motion.EQ_BOTTOM + 1)
    assert.ok(x >= 0 && x < 12 && y >= 0)
  }
}
// Paused, they hold still.
assert.deepStrictEqual(Motion.eqHeights(3, false), Motion.eqHeights(17, false))
// And they move while playing.
assert.ok(new Set(Array.from({ length: Motion.LOOP_TICKS }, (_, i) => Motion.eqHeights(i, true).join())).size > 4)

console.log("motion ok")
