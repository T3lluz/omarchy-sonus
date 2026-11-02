.pragma library

// Ctrl+Alt+V for the panel. Lives in ~/.config/hypr/bindings.lua inside a
// marked block the service writes and rewrites. Hyprland keeps an older bind
// for the same keys unless you unbind first, so the block always unbinds
// before it binds. It also always sits at the end of the file, so a bind
// added later by another tool cannot steal the chord on the next load.

var KEYS = "CTRL + ALT + V"
var BEGIN = "-- >>> sonus shortcut (written by Sonus; keeps Ctrl+Alt+V on the panel)"
var END = "-- <<< sonus shortcut"
var COMMAND = "omarchy-shell sonus toggle"

function block() {
  return [
    BEGIN,
    "hl.unbind(\"" + KEYS + "\")",
    "o.bind(\"" + KEYS + "\", \"Sonus\", \"" + COMMAND + "\")",
    END
  ].join("\n")
}

function find(text) {
  var s = String(text || "")
  var a = s.indexOf(BEGIN)
  if (a < 0) return null
  var b = s.indexOf(END, a)
  if (b < 0) return { start: a, end: s.length, body: s.slice(a) }
  var end = b + END.length
  return { start: a, end: end, body: s.slice(a, end) }
}

// "missing" | "outdated" | "installed"
function status(text) {
  var hit = find(text)
  if (!hit) return "missing"
  if (hit.body !== block()) return "outdated"
  // Trailing content after the block means something else can bind after us.
  var after = String(text || "").slice(hit.end).replace(/\s+$/, "")
  if (after.length) return "outdated"
  return "installed"
}

function apply(text) {
  var s = String(text || "")
  var hit = find(s)
  if (hit) s = s.slice(0, hit.start) + s.slice(hit.end)
  s = s.replace(/\s+$/, "")
  if (s.length) s += "\n\n"
  return s + block() + "\n"
}
