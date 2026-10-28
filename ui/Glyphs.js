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
var bluetooth = g(0xF00AF)
var monitor = g(0xF0379)
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

function deviceGlyph(form) {
  if (form === "headphones") return headphones
  if (form === "bluetooth") return bluetooth
  if (form === "hdmi") return monitor
  if (form === "mic") return microphone
  if (form === "camera") return camera
  return speaker
}

// The bar icon: headphones stay headphones, everything else follows the level.
function outputIcon(form, muted, volume) {
  if (muted || !(volume > 0)) return volumeOff
  if (form === "headphones") return headphones
  if (volume >= 0.67) return volumeHigh
  if (volume >= 0.34) return volumeMid
  return volumeLow
}

function channel(key) {
  if (key === "master") return speaker
  if (key === "game") return gamepad
  if (key === "chat") return headset
  if (key === "media") return music
  if (key === "aux") return aux
  return app
}
