// Run with: node tests/audio.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const source = fs.readFileSync(path.join(__dirname, "..", "ui", "Audio.js"), "utf8").replace(/^\.pragma library\s*/, "")
const Audio = new Function(source + "\nreturn { volumeName, drawingFor, channelDrawing, eqWord, appsLine, directLine, othersLine, escapeHtml }")()

const drawings = fs.readFileSync(path.join(__dirname, "..", "ui", "Drawings.js"), "utf8").replace(/^\.pragma library\s*/, "")
const known = Object.keys(new Function(drawings + "\nreturn drawings")())

// Every device shape the engine reports (profiles.device_form) has a drawing,
// and every drawing it picks exists.
const forms = ["laptop", "headphones", "headset", "earbuds", "bluetooth", "hdmi", "tv", "speaker", "mic", "camera", "", undefined]
for (const form of forms) {
  const name = Audio.drawingFor(form, "")
  assert.ok(name.indexOf("airpods") === 0 || known.includes(name), form + " -> " + name)
}
for (const key of ["game", "chat", "media", "aux"]) assert.ok(known.includes(Audio.channelDrawing(key)), key)

assert.strictEqual(Audio.drawingFor("earbuds", "AirPods Pro"), "airpods-pro")
assert.strictEqual(Audio.drawingFor("earbuds", "Galaxy Buds2 Pro"), "airpods-pro")
assert.strictEqual(Audio.drawingFor("earbuds", "AirPods"), "airpods")
assert.strictEqual(Audio.drawingFor("earbuds", "Productive Buds"), "airpods")
assert.strictEqual(Audio.drawingFor("hdmi", "HDMI 0"), "monitor")

assert.strictEqual(Audio.eqWord(true, false), "EQ on")
assert.strictEqual(Audio.eqWord(true, true), "EQ flat")
assert.strictEqual(Audio.eqWord(false, false), "EQ off")

assert.strictEqual(Audio.appsLine(0), "Nothing playing")
assert.strictEqual(Audio.appsLine(1), "1 app playing")
assert.strictEqual(Audio.appsLine(3), "3 apps playing")

assert.strictEqual(Audio.directLine("AirPods Pro"), "Straight to AirPods Pro")
assert.strictEqual(Audio.directLine(""), "Straight to the output")

assert.strictEqual(Audio.othersLine(0, "sink"), "")
assert.strictEqual(Audio.othersLine(1, "src"), "1 other input")
assert.strictEqual(Audio.othersLine(5, "sink"), "5 other outputs")

assert.strictEqual(Audio.volumeName(1, false), "Concert hall")
assert.strictEqual(Audio.volumeName(0.5, true), "Muted")

assert.strictEqual(Audio.escapeHtml("<b>A & B</b>"), "&lt;b&gt;A &amp; B&lt;/b&gt;")
assert.strictEqual(Audio.escapeHtml(undefined), "")

console.log("audio ok")
