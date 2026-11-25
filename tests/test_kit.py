"""The shared kit's text, font and updater, the same file in Batteries, ROG
Deck, Server Dashboard and Sonus: the patched Monocraft (scripts/patch-font.py),
MonoText's size rule, the kit files' text, and the updater's restart and
closed banner (Batteries, ROG Deck and Server Dashboard)."""

import importlib.machinery
import importlib.util
import json
import os
import re
import shutil
import struct
import subprocess
import unittest
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KIT_DIR = next(os.path.join(ROOT, d) for d in (".", "components", "ui")
               if os.path.exists(os.path.join(ROOT, d, "MonoText.qml")))
KIT = ["SectionHeader", "StatTile", "ToggleTile", "SwitchRow", "Seg", "Notice", "LevelBar",
       "OptionRow", "Caption", "UpdateSection"]
FONTS = [os.path.join(ROOT, "assets", "fonts", n) for n in ("Monocraft.ttf", "Monocraft-Bold.ttf")]
FAMILIES = {
    "io.github.t3lluz.batteries": "Monocraft Batteries",
    "io.github.t3lluz.rog-deck": "Monocraft ROG Deck",
    "io.github.t3lluz.server-dashboard": "Monocraft Server Dashboard",
    "io.github.t3lluz.sonus": "Monocraft Sonus",
}
NODE = shutil.which("node")

try:
    from fontTools.ttLib import TTFont
except ImportError:
    TTFont = None


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def manifest_id():
    return json.loads(read(os.path.join(ROOT, "manifest.json")))["id"]


def tables(path):
    with open(path, "rb") as f:
        data = f.read()
    count = struct.unpack(">H", data[4:6])[0]
    out = {}
    for i in range(count):
        tag, _, offset, length = struct.unpack(">4sIII", data[12 + 16 * i:28 + 16 * i])
        out[tag.decode("latin-1")] = data[offset:offset + length]
    return out


def node(script):
    done = subprocess.run([NODE, "-e", script], capture_output=True, text=True, timeout=30)
    if done.returncode != 0:
        raise AssertionError(done.stderr)
    return json.loads(done.stdout)


class FontTest(unittest.TestCase):
    def test_em_is_ten_pixels_and_lines_eleven(self):
        for path in FONTS:
            t = tables(path)
            self.assertEqual(struct.unpack(">H", t["head"][18:20])[0], 1200, path)
            self.assertEqual(struct.unpack(">hhh", t["hhea"][4:10]), (1080, -240, 0), path)
            self.assertEqual(struct.unpack(">hhh", t["OS/2"][68:74]), (1080, -240, 0), path)

    @unittest.skipUnless(TTFont, "needs fontTools")
    def test_family_is_this_plugins_own(self):
        family = FAMILIES[manifest_id()]
        for path in FONTS:
            self.assertEqual(TTFont(path)["name"].getDebugName(1), family, path)

    @unittest.skipUnless(TTFont, "needs fontTools")
    def test_every_regular_glyph_on_the_pixel_grid(self):
        font = TTFont(FONTS[0])
        glyf = font["glyf"]
        off = [name for name in font.getGlyphOrder()
               if name != ".notdef" and glyf[name].numberOfContours > 0
               and any(x % 120 or y % 120 for x, y in glyf[name].getCoordinates(glyf)[0])]
        self.assertEqual(off, [])

    @unittest.skipUnless(TTFont, "needs fontTools")
    def test_added_glyphs_and_an_ellipsis_inside_its_cell(self):
        font = TTFont(FONTS[0])
        cmap, hmtx, glyf = font.getBestCmap(), font["hmtx"], font["glyf"]
        self.assertEqual(hmtx[cmap[0x200B]][0], 0)
        self.assertIn(0x276F, cmap)
        self.assertIn(0x258C, cmap)
        ellipsis = glyf[cmap[0x2026]]
        ellipsis.recalcBounds(glyf)
        self.assertLessEqual(ellipsis.xMax, hmtx[cmap[0x2026]][0])

    @unittest.skipUnless(TTFont, "needs fontTools")
    def test_every_character_the_panel_types_is_in_the_font(self):
        cmap = TTFont(FONTS[0]).getBestCmap()
        # Drawn as rectangles (BigFigure) or as Nerd Font icons, never typed in Monocraft.
        drawn = {0x2580, 0x2584, 0x2588}
        missing = {}
        for folder, dirs, files in os.walk(ROOT):
            dirs[:] = [d for d in dirs if d not in (".git", "tests", "pixels", "assets", "engine", "__pycache__")]
            for name in files:
                if not name.endswith((".qml", ".js")):
                    continue
                text = read(os.path.join(folder, name))
                chars = {ord(c) for c in text if ord(c) > 126}
                chars |= {int(m, 16) for m in re.findall(r"\\u([0-9a-fA-F]{4})", text)}
                for c in chars:
                    pua = 0xE000 <= c <= 0xF8FF or c >= 0xF0000
                    if not pua and c not in drawn and c not in cmap:
                        missing.setdefault("U+%04X" % c, []).append(name)
        self.assertEqual(missing, {})


@unittest.skipUnless(NODE, "needs node")
class MonoTextTest(unittest.TestCase):
    def cells(self, scales):
        source = read(os.path.join(KIT_DIR, "MonoText.qml"))
        body = re.search(r"function cellFor\(step, d\) \{.*?\n  \}", source, re.S).group(0)
        return node(body + "; console.log(JSON.stringify(%s.map(d => ['small', 'body', 'title'].map(s => cellFor(s, d)))))"
                    % json.dumps(scales))

    def test_steps_per_scale(self):
        self.assertEqual(self.cells([1, 1.25, 1.5, 2]), [[1, 2, 3], [1, 2, 3], [2, 3, 4], [2, 3, 4]])

    def test_steps_grow_at_every_scale(self):
        for small, body, title in self.cells([1, 1.25, 1.5, 1.75, 2, 2.5, 3]):
            self.assertLess(small, body)
            self.assertLess(body, title)

    def test_whole_font_sizes_at_one_one_and_a_quarter_and_two(self):
        for d, steps in zip([1, 1.25, 2], self.cells([1, 1.25, 2])):
            for cell in steps:
                self.assertAlmostEqual(10 * cell / d, round(10 * cell / d), places=6)


class KitTextTest(unittest.TestCase):
    def kit(self, name):
        return read(os.path.join(KIT_DIR, name + ".qml"))

    def test_text_goes_through_mono_text(self):
        for name in KIT:
            source = self.kit(name)
            self.assertIsNone(re.search(r"^\s*Text \{", source, re.M), name)
            self.assertNotIn("PanelSectionHeader", source, name)
            self.assertNotIn("font.bold: true", source, name)
            self.assertNotIn("letterSpacing", source, name)

    def test_dim_mixes_toward_the_background(self):
        for name in KIT:
            self.assertNotIn("Qt.darker", self.kit(name), name)

    def test_motion_respects_reduced_motion(self):
        for name in KIT:
            source = self.kit(name)
            self.assertIsNone(re.search(r"duration: \d", source), name)
            self.assertNotIn("RotationAnimation", source, name)

    def test_release_notes_in_full(self):
        self.assertNotIn("maximumLineCount", self.kit("UpdateSection"))


UPDATER = os.path.join(ROOT, "bin", "plugin-update")


@unittest.skipUnless(os.path.exists(UPDATER), "Sonus updates through its engine")
class UpdaterTest(unittest.TestCase):
    def load(self):
        loader = importlib.machinery.SourceFileLoader("plugin_update", UPDATER)
        spec = importlib.util.spec_from_loader("plugin_update", loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        return module

    def test_restart_runs_in_a_unit_of_its_own_after_a_delay(self):
        update = self.load()
        update.QUIET = False
        tools = {"omarchy-restart-shell": "/usr/bin/omarchy-restart-shell", "systemd-run": "/usr/bin/systemd-run"}
        with mock.patch.object(update.shutil, "which", side_effect=tools.get), \
             mock.patch.object(update.subprocess, "run", return_value=mock.Mock(returncode=0)) as run:
            self.assertTrue(update.restart_shell())
        command = run.call_args[0][0]
        self.assertEqual(command[:2], ["systemd-run", "--user"])
        self.assertIn("--on-active=%d" % update.RESTART_DELAY, command)
        self.assertIn("--unit=%s-restart-shell" % update.SLUG, command)
        self.assertEqual(command[-1], "/usr/bin/omarchy-restart-shell")

    def test_tests_never_restart_the_shell(self):
        update = self.load()
        update.QUIET = True
        with mock.patch.object(update.subprocess, "run") as run, mock.patch.object(update.subprocess, "Popen") as popen:
            self.assertFalse(update.restart_shell())
        run.assert_not_called()
        popen.assert_not_called()

    def test_wording(self):
        source = read(UPDATER)
        self.assertIn('"%s updated to %s" % (NAME, after)', source)
        self.assertIn('"%s couldn\'t update" % NAME', source)

    @unittest.skipUnless(NODE, "needs node")
    def test_a_closed_banner_is_known_by_what_it_is_about(self):
        source = read(os.path.join(KIT_DIR, "Update.js")).replace(".pragma library", "")
        seen = node(source + """
const now = 1000
const c = { available: true, current: "1.0", latest: "1.0", commit: "abc" }
console.log(JSON.stringify([
  notice("T", c, null, "1.0", now).seen,
  notice("T", Object.assign({}, c, { commit: "def" }), null, "1.0", now).seen,
  notice("T", { available: true, current: "1.0", latest: "1.1" }, null, "1.0", now).seen,
  notice("T", null, { state: "failed", message: "x", at: 990 }, "1.0", now).seen,
]))""")
        self.assertEqual(seen, ["available abc", "available def", "available 1.1", "failed 990"])
        updater = read(os.path.join(KIT_DIR, "Updater.qml"))
        self.assertIn('"/dismissed.json"', updater)
        self.assertIn("n.seen !== dismissedSeen", updater)


if __name__ == "__main__":
    unittest.main()
