.pragma library

// Material Design Icons from the theme's Nerd Font, by code point so the
// source stays ASCII. Every one was checked against JetBrainsMono Nerd Font.
function g(cp) { return String.fromCodePoint(cp) }

var speaker = g(0xF04C3)
var volumeHigh = g(0xF057E)
var volumeMid = g(0xF0580)
var volumeLow = g(0xF057F)
var volumeOff = g(0xF0581)
var headphones = g(0xF02CB)
var earbuds = g(0xF184F)
var laptop = g(0xF0322)
var bluetooth = g(0xF00AF)
var speakerBluetooth = g(0xF09A2)
var monitor = g(0xF0379)
var monitorSpeaker = g(0xF0F5F)
var television = g(0xF0502)
var microphone = g(0xF036C)
var microphoneOff = g(0xF036D)
var camera = g(0xF0100)
var gamepad = g(0xF0297)
var headset = g(0xF02CE)
var music = g(0xF075A)
var aux = g(0xF147D)
var sliders = g(0xF066A)
var cog = g(0xF0493)
var close = g(0xF0156)
var back = g(0xF004D)
var apps = g(0xF003B)
var check = g(0xF012C)
var chevronDown = g(0xF0140)
var chevronUp = g(0xF0143)
var app = g(0xF0387)
var sync = g(0xF04E6)
var download = g(0xF01DA)
var alert = g(0xF0026)
var info = g(0xF02FD)
var keyboard = g(0xF030C)
var update = g(0xF06B0)

// The engine's coarse device shapes (profiles.device_form) as icons.
function deviceGlyph(form) {
  if (form === "laptop") return laptop
  if (form === "headphones") return headphones
  if (form === "headset") return headset
  if (form === "earbuds") return earbuds
  if (form === "bluetooth") return speakerBluetooth
  if (form === "hdmi") return monitorSpeaker
  if (form === "tv") return television
  if (form === "mic") return microphone
  if (form === "camera") return camera
  return speaker
}

// The volume level, as Omarchy's own volume icon.
function levelIcon(muted, volume) {
  if (muted || !(volume > 0)) return volumeOff
  if (volume >= 0.67) return volumeHigh
  if (volume >= 0.34) return volumeMid
  return volumeLow
}

// The volume toast. The machine's own speakers are the usual case and show
// the level; anything else (headphones, AirPods, a Bluetooth speaker, a
// monitor) shows itself, so a glance says where the sound goes.
function outputIcon(form, muted, volume) {
  if (muted || !(volume > 0) || form === "laptop" || form === "speaker" || !form) return levelIcon(muted, volume)
  return deviceGlyph(form)
}

function channel(key) {
  if (key === "master") return speaker
  if (key === "game") return gamepad
  if (key === "chat") return headset
  if (key === "media") return music
  if (key === "aux") return aux
  return app
}
