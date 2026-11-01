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

// The drawing for one of the engine's device shapes (profiles.device_form).
// Earbuds are drawn as AirPods, the Pro when the name says so.
function drawingFor(form, label) {
  if (form === "earbuds") return /\bpro\b/i.test(String(label || "")) ? "airpods-pro" : "airpods"
  if (form === "laptop") return "laptop"
  if (form === "headphones") return "headphones"
  if (form === "headset") return "headset"
  if (form === "hdmi" || form === "tv") return "monitor"
  if (form === "mic" || form === "camera") return "microphone"
  return "speaker"
}

var CHANNEL_DRAWINGS = { game: "gamepad", chat: "headset", media: "music", aux: "jack" }

function channelDrawing(key) { return CHANNEL_DRAWINGS[key] || "speaker" }

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

// Under the lane of apps that skip the channels: where they play.
function directLine(outputLabel) {
  return outputLabel ? "Straight to " + outputLabel : "Straight to the output"
}

// The tooltip on a device's name: how many others there are to pick.
function othersLine(count, section) {
  var noun = section === "sink" ? "output" : "input"
  if (!(count > 0)) return ""
  return count === 1 ? "1 other " + noun : count + " other " + noun + "s"
}

// A name for a StyledText line, so a device called "<b>" stays plain text.
function escapeHtml(text) {
  return String(text === undefined || text === null ? "" : text)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}
