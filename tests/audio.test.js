// Run with: node tests/audio.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const source = fs.readFileSync(path.join(__dirname, "..", "ui", "Audio.js"), "utf8").replace(/^\.pragma library\s*/, "")
const Audio = new Function(source + "\nreturn { volumeName, eqWord, appsLine, toOutput, othersLine, channelLine, bucketLine, movingLine, fitted, heroPhrases, dropLine, movedLine, switchedLine, eqLine }")()

const glyphSource = fs.readFileSync(path.join(__dirname, "..", "ui", "Glyphs.js"), "utf8").replace(/^\.pragma library\s*/, "")
const Glyphs = new Function(glyphSource + "\nreturn { deviceGlyph, channel, speaker, chat, gamepad, music, aux, noChannel }")()

// Every device shape the engine reports (profiles.device_form) has an icon,
// and every channel has one of its own.
const forms = ["laptop", "headphones", "headset", "earbuds", "bluetooth", "hdmi", "tv", "speaker", "mic", "camera", "", undefined]
for (const form of forms) assert.ok(Glyphs.deviceGlyph(form), String(form))
assert.notStrictEqual(Glyphs.deviceGlyph("earbuds"), Glyphs.deviceGlyph("headphones"))
const channelIcons = ["game", "chat", "media", "aux", ""].map(Glyphs.channel)
assert.strictEqual(new Set(channelIcons).size, channelIcons.length)
// A channel's icon never looks like a device, or the tiles would read as devices.
for (const form of forms) assert.ok(!channelIcons.includes(Glyphs.deviceGlyph(form)), String(form))

assert.strictEqual(Audio.eqWord(true, false), "EQ on")
assert.strictEqual(Audio.eqWord(true, true), "EQ flat")
assert.strictEqual(Audio.eqWord(false, false), "EQ off")

assert.strictEqual(Audio.appsLine(0), "Nothing playing")
assert.strictEqual(Audio.appsLine(1), "1 app playing")
assert.strictEqual(Audio.appsLine(3), "3 apps playing")


assert.strictEqual(Audio.othersLine(0, "sink"), "")
assert.strictEqual(Audio.othersLine(1, "src"), "1 other input")
assert.strictEqual(Audio.othersLine(5, "sink"), "5 other outputs")

assert.strictEqual(Audio.volumeName(1, false), "Concert hall")
assert.strictEqual(Audio.volumeName(0.5, true), "Muted")

// The line under a channel's name: off beats muted beats where it plays.
assert.strictEqual(Audio.channelLine(true, true, false, "AirPods Pro"), "To AirPods Pro")
assert.strictEqual(Audio.channelLine(true, true, true, "AirPods Pro"), "Muted")
assert.strictEqual(Audio.channelLine(false, false, true, "AirPods Pro"), "Off in settings")
assert.strictEqual(Audio.channelLine(false, true, false, "AirPods Pro"), "Not running")
assert.strictEqual(Audio.channelLine(true, true, false, ""), "No output")
assert.strictEqual(Audio.channelLine(true, true, false, "Radeon High Definition Audio Controller"), "To the output")

assert.strictEqual(Audio.bucketLine(true, false, 2), "Drag an app here")
assert.strictEqual(Audio.bucketLine(true, true, 2), "")
assert.strictEqual(Audio.bucketLine(true, false, 0), "No apps yet")
assert.strictEqual(Audio.bucketLine(false, false, 2), "")

assert.strictEqual(Audio.movingLine("Zen"), "Moving Zen")
assert.strictEqual(Audio.movingLine("x".repeat(60)), "Moving an app")

// The hero's caption can be cut by the shell, so long lines give way.
const long = "Radeon High Definition Audio Controller Digital Stereo (HDMI)"
assert.strictEqual(Audio.switchedLine("sink", "AirPods Pro"), "Playing through AirPods Pro")
assert.strictEqual(Audio.switchedLine("sink", long), "Output switched")
assert.strictEqual(Audio.switchedLine("src", long), "Input switched")
assert.strictEqual(Audio.movedLine("Zen", "Game"), "Zen moved to Game")
assert.strictEqual(Audio.movedLine(long, "Game"), "Moved to Game")
assert.strictEqual(Audio.dropLine("Zen", "No channel"), "Move Zen to No channel")
assert.strictEqual(Audio.dropLine(long, "Aux"), "Move to Aux")

// With channels off there is nothing to drag between, and no EQ to be on.
assert.deepStrictEqual(Audio.heroPhrases({ apps: 2, output: "", volume: 1, muted: false, eqOn: [], inputMuted: false, channelsOn: false }), ["2 apps playing", "Concert hall"])

const phrases = Audio.heroPhrases({ apps: 2, output: "AirPods Pro", volume: 1, muted: false, eqOn: ["Game", "Aux"], inputMuted: true, channelsOn: true })
assert.deepStrictEqual(phrases, ["2 apps playing", "On AirPods Pro", "Concert hall", "EQ on Game, Aux", "Mic muted", "Drag apps between channels", "One fader and EQ per channel"])
assert.deepStrictEqual(Audio.heroPhrases({ apps: 0, output: long, volume: 0.5, muted: true, eqOn: [], inputMuted: false }), ["Nothing playing", "Muted"])
for (const line of phrases) assert.ok(line.length <= 34, line)

const flat = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
const boost = [6, 0, 0, 0, 0, 0, 0, 0, 0, 0]
assert.strictEqual(Audio.eqLine(true, "Flat", flat, 0), "Flat")
assert.strictEqual(Audio.eqLine(true, "", boost, -6), "Custom curve")
assert.ok(Audio.eqLine(true, "", boost, -3).includes("clip"))
assert.strictEqual(Audio.eqLine(false, "", boost, -3), "Bypassed")

console.log("audio ok")
