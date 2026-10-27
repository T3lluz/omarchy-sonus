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
