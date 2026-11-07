.pragma library

// Short names for the output level, the same bands the Omarchy audio panel
// uses. Wide on purpose, so a small nudge does not rename the room.

function volumeName(volume, muted) {
  if (muted) return "Muted"
  var p = Math.round((Number(volume) || 0) * 100)
  if (p <= 0) return "Silenced"
  if (p >= 100) return "Concert hall"
  if (p >= 85) return "Party mode"
  if (p >= 70) return "Cranked up"
  if (p >= 50) return "Steady groove"
  if (p >= 30) return "Easy listening"
  if (p >= 15) return "Murmur"
  return "Whisper"
}

// A channel's EQ in two words: shaping the sound, switched on but flat, or
// switched off.
function eqWord(enabled, flat) {
  if (!enabled) return "EQ off"
  return flat ? "EQ flat" : "EQ on"
}

function appsLine(count) {
  if (!(count > 0)) return "Nothing playing"
  return count === 1 ? "1 app playing" : count + " apps playing"
}

// The tooltip on a device's name: how many others there are to pick.
function othersLine(count, section) {
  var noun = section === "sink" ? "output" : "input"
  if (!(count > 0)) return ""
  return count === 1 ? "1 other " + noun : count + " other " + noun + "s"
}

// The line under a channel's name: where it plays, until there is something
// more pressing to say about it.
// A name too long for the tile gives way, since the output's own tile shows it
// in full. `managed` is the setting: channels can also be missing while the
// graph starts up, and then "off in settings" would send you to the wrong place.
function channelLine(present, managed, muted, outputLabel) {
  if (!present) return managed ? "Not running" : "Off in settings"
  if (muted) return "Muted"
  return toOutput(outputLabel)
}

var LINE_LIMIT = 30

function toOutput(outputLabel) {
  if (!outputLabel) return "No output"
  var line = "To " + outputLabel
  return line.length <= LINE_LIMIT ? line : "To the output"
}

// The hero's caption keeps room for two lines in a narrow column, so a name that
// would need a third gives way to a shorter sentence.
var HERO_LIMIT = 34

function fitted(line, shorter) {
  return String(line).length <= HERO_LIMIT ? String(line) : String(shorter)
}

// What the hero's caption takes turns saying while nothing is happening,
// the way the official panels rotate theirs. The facts only: an empty list
// never comes back, so the caption always has something to show.
function heroPhrases(state) {
  var list = [appsLine(state.apps)]
  if (state.output) {
    var on = fitted("On " + state.output, "")
    if (on) list.push(on)
  }
  list.push(volumeName(state.volume, state.muted))
  if (state.eqOn && state.eqOn.length > 0) list.push("EQ on " + state.eqOn.join(", "))
  if (state.inputMuted) list.push("Mic muted")
  if (state.apps > 0 && state.channelsOn) {
    list.push("Drag apps between channels")
    list.push("One fader and EQ per channel")
  }
  return list
}

function movingLine(appName) {
  return fitted("Moving " + appName, "Moving an app")
}

function dropLine(appName, channelTitle) {
  return fitted("Move " + appName + " to " + channelTitle, "Move to " + channelTitle)
}

function movedLine(appName, channelTitle) {
  return fitted(appName + " moved to " + channelTitle, "Moved to " + channelTitle)
}

function switchedLine(section, label) {
  return section === "sink"
    ? fitted("Playing through " + label, "Output switched")
    : fitted("Recording from " + label, "Input switched")
}

// What an empty bucket says.
function bucketLine(present, dragging, appCount) {
  // While dragging, the outline, the hero and the card in the air already say it.
  if (!present || dragging) return ""
  return appCount > 0 ? "Drag an app here" : "No apps yet"
}

// The equalizer's caption while no band is being touched. The one warning
// worth saying comes first: a boost past 0 dB can clip.
function eqLine(enabled, presetName, gains, preamp) {
  if (!enabled) return "Bypassed"
  var peak = 0
  for (var i = 0; i < gains.length; i++) peak = Math.max(peak, Number(gains[i]) || 0)
  if (peak + (Number(preamp) || 0) > 0) return "Boost can clip, lower preamp"
  return presetName || "Custom curve"
}
