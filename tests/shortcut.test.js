// Run with: node tests/shortcut.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const source = fs.readFileSync(path.join(__dirname, "..", "ui", "Shortcut.js"), "utf8")
  .replace(/^\.pragma library\s*/, "")
const Shortcut = new Function(source + "\nreturn { KEYS, BEGIN, END, COMMAND, block, find, status, apply }")()

const block = Shortcut.block()
assert.ok(block.indexOf(Shortcut.BEGIN) === 0)
assert.ok(block.indexOf("hl.unbind(\"CTRL + ALT + V\")") > 0)
assert.ok(block.indexOf("o.bind(\"CTRL + ALT + V\", \"Sonus\", \"omarchy-shell sonus toggle\")") > 0)
assert.ok(block.endsWith(Shortcut.END))

// Unbind comes before bind: that is what overrides anything else on the chord.
const unbindAt = block.indexOf("hl.unbind")
const bindAt = block.indexOf("o.bind")
assert.ok(unbindAt >= 0 && bindAt > unbindAt)

assert.strictEqual(Shortcut.status(""), "missing")
assert.strictEqual(Shortcut.status("-- other stuff\n"), "missing")
assert.strictEqual(Shortcut.status(block + "\n"), "installed")

const once = Shortcut.apply("-- my bindings\n")
assert.strictEqual(Shortcut.status(once), "installed")
assert.ok(once.indexOf("-- my bindings") === 0)
assert.ok(once.trimEnd().endsWith(Shortcut.END))

// Rewriting is idempotent and repairs a stale or truncated block.
const twice = Shortcut.apply(once)
assert.strictEqual(Shortcut.status(twice), "installed")
assert.strictEqual(twice, once)

const stale = once.replace("omarchy-shell sonus toggle", "old-command")
assert.strictEqual(Shortcut.status(stale), "outdated")
const fixed = Shortcut.apply(stale)
assert.strictEqual(Shortcut.status(fixed), "installed")
assert.ok(fixed.indexOf("old-command") < 0)
assert.ok(fixed.indexOf("-- my bindings") === 0)

const truncated = once.split(Shortcut.END)[0]
assert.strictEqual(Shortcut.status(truncated), "outdated")
assert.strictEqual(Shortcut.status(Shortcut.apply(truncated + "\n-- after\n")), "installed")

// A bind after our block would win on load, so that counts as outdated and
// apply moves Sonus back to the end.
const followed = once + "\no.bind(\"CTRL + ALT + V\", \"Other\", \"echo no\")\n"
assert.strictEqual(Shortcut.status(followed), "outdated")
const reclaimed = Shortcut.apply(followed)
assert.strictEqual(Shortcut.status(reclaimed), "installed")
assert.ok(reclaimed.indexOf("echo no") < reclaimed.indexOf(Shortcut.BEGIN))
assert.ok(reclaimed.trimEnd().endsWith(Shortcut.END))

// Fresh install: empty file becomes just the block.
assert.strictEqual(Shortcut.status(Shortcut.apply("")), "installed")
assert.strictEqual(Shortcut.apply("").trim(), block)

console.log("shortcut.test.js: ok")
