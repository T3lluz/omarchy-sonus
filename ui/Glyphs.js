.pragma library

// Material Design Icons from the theme's Nerd Font, by code point so the
// source stays ASCII. Every one was checked against JetBrainsMono Nerd Font.
function g(cp) { return String.fromCodePoint(cp) }

var speaker = g(0xF04C3)
var volumeHigh = g(0xF057E)
var volumeOff = g(0xF0581)
var gamepad = g(0xF0297)
var headset = g(0xF02CE)
var music = g(0xF075A)
var aux = g(0xF1072)
var sliders = g(0xF066A)
var cog = g(0xF0493)
var close = g(0xF0156)
var back = g(0xF004D)
var apps = g(0xF003B)
var check = g(0xF012C)
var app = g(0xF0387)

function channel(key) {
  if (key === "master") return speaker
  if (key === "game") return gamepad
  if (key === "chat") return headset
  if (key === "media") return music
  if (key === "aux") return aux
  return app
}
