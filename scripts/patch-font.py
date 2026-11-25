#!/usr/bin/env python3
"""
Patch the bundled Monocraft (assets/fonts) so MonoText can put every one of
its pixels on whole device pixels, and so every copy loaded into the shell is
one of its own.

Batteries, ROG Deck, Server Dashboard and Sonus each bundle Monocraft, and all
four load into the one shell process. Under one family name Qt draws whichever
copy registered first, so each plugin's copy gets a name of its own (FAMILIES,
picked by manifest.json's id). Every plugin runs this same script on the same
release, so the four copies differ only in their names.

What changes, on Monocraft 4.2.1 as released (a font pixel is 120 units):

- The em is ten font pixels (1200 units; nine as released). Qt rounds every
  font size to a whole logical pixel, and a font pixel lands on whole device
  pixels only at an em of 9 * n / scale for nine to the em: 13.5 or 7.2,
  never whole at a 1.25 scale. At ten to the em it is 10 * n / scale: 5n at 2,
  8n at 1.25, 10n at 1. The glyphs keep their coordinates; only the em they
  are measured against grows, so a size draws them a tenth smaller.
- Line box: 9 font pixels over the baseline, 2 under, no line gap (typo and
  hhea). As released a line was nine pixels with a fractional gap, and
  descenders sat on the next line's capitals. Eleven whole pixels a line keeps
  the baseline of every line on the grid and three pixels of air between a
  descender and the capitals under it.
- Half-pixel glyphs: f, i, k, l, t, their accented forms, <= and >= sit half a
  font pixel off the grid (centred in the cell). They move right by half a
  pixel, which puts their stems on the cell's middle column like the rest.
- The ellipsis drew its third dot past the end of its cell, so an elided line
  ran a pixel out of its box. Its dots are now one pixel apart.
- Added glyphs: an empty zero-width space (U+200B, which the panels put where
  a long name may break; from a fallback font it opened a taller line), the
  prompt sign U+276F (drawn as Monocraft's U+203A) and the half block cursor
  U+258C (the left half of the cell, the whole line tall).

Bold gets the same changes, but its strokes are a fifth of a font pixel wider
each side than the grid, so it is never crisp. MonoText never draws it.

The licence (SIL OFL 1.1, assets/fonts/OFL.txt) reserves no font name, so a
modified copy may keep or change it. Needs fontTools. Run from anywhere, on
the files as released or already patched; running it twice changes nothing:

    python3 scripts/patch-font.py
"""

import json
import os
import sys

from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

sys.dont_write_bytecode = True

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
FONTS = ["assets/fonts/Monocraft.ttf", "assets/fonts/Monocraft-Bold.ttf"]
FAMILIES = {
    "io.github.t3lluz.batteries": "Monocraft Batteries",
    "io.github.t3lluz.rog-deck": "Monocraft ROG Deck",
    "io.github.t3lluz.server-dashboard": "Monocraft Server Dashboard",
    "io.github.t3lluz.sonus": "Monocraft Sonus",
}

PX = 120  # one font pixel
EM = 10 * PX
ASCENT, DESCENT = 9 * PX, 2 * PX

ZWSP, ZWSP_NAME = 0x200B, "uni200B"
PROMPT, PROMPT_LIKE = 0x276F, 0x203A
HALF_BLOCK, HALF_BLOCK_NAME = 0x258C, "uni258C"
ELLIPSIS = 0x2026


def family():
    with open(os.path.join(ROOT, "manifest.json")) as f:
        plugin = json.load(f)["id"]
    if plugin not in FAMILIES:
        sys.exit("patch-font: no family name for %s; add it to FAMILIES" % plugin)
    return FAMILIES[plugin]


def rename(font, name):
    names = font["name"]
    style = names.getDebugName(2) or "Regular"
    full = name if style == "Regular" else name + " " + style
    postscript = name.replace(" ", "") + "-" + style.replace(" ", "")
    values = {1: name, 3: postscript, 4: full, 6: postscript}
    for record in names.names:
        if record.nameID in values:
            record.string = values[record.nameID]


def metrics(font):
    font["head"].unitsPerEm = EM
    os2, hhea = font["OS/2"], font["hhea"]
    os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap = ASCENT, -DESCENT, 0
    hhea.ascent, hhea.descent, hhea.lineGap = ASCENT, -DESCENT, 0
    os2.fsSelection |= 1 << 7  # USE_TYPO_METRICS


def grid(font):
    """Where the font's "a" sits: whole pixels in the regular, a fifth of a
    pixel out from them in the bold. Returns the x and y remainders and how
    far a stroke grows past the grid."""
    a = font["glyf"][font.getBestCmap()[ord("a")]].coordinates
    xs = {x % PX for x, _ in a}
    return xs, {y % PX for _, y in a}, (PX - max(xs)) % PX


def snap_half_pixels(font):
    """Move glyphs drawn wholly half a pixel off the grid onto it."""
    glyf, hmtx = font["glyf"], font["hmtx"]
    grid_x, grid_y, _ = grid(font)
    half_x = {(x + PX // 2) % PX for x in grid_x}
    for name in font.getGlyphOrder():
        glyph = glyf[name]
        if glyph.numberOfContours <= 0:
            continue
        coords = glyph.coordinates
        xs = {x % PX for x, _ in coords}
        if not xs <= half_x or xs <= grid_x:
            continue
        if not {y % PX for _, y in coords} <= grid_y:
            continue
        coords.translate((PX // 2, 0))
        set_bounds(font, name)


def set_bounds(font, name):
    glyph = font["glyf"][name]
    glyph.recalcBounds(font["glyf"])
    font["hmtx"][name] = (font["hmtx"][name][0], getattr(glyph, "xMin", 0))


def boxes(pen, rects, grow):
    for x0, y0, x1, y1 in rects:
        pen.moveTo((x0 - grow, y0 - grow))
        pen.lineTo((x0 - grow, y1 + grow))
        pen.lineTo((x1 + grow, y1 + grow))
        pen.lineTo((x1 + grow, y0 - grow))
        pen.closePath()


def set_glyph(font, name, rects, advance, weighted=True):
    """Draw `name` as pixel boxes, adding it to the font if it is new. A
    weighted glyph grows with the face, as the bold's dots do."""
    if name not in font["glyf"]:
        font.setGlyphOrder(font.getGlyphOrder() + [name])
    pen = TTGlyphPen(None)
    boxes(pen, rects, grid(font)[2] if weighted else 0)
    font["glyf"][name] = pen.glyph()
    font["hmtx"][name] = (advance, 0)
    set_bounds(font, name)


def map_char(font, code, name):
    for table in font["cmap"].tables:
        if table.isUnicode():
            table.cmap[code] = name


def patch(path, name):
    # The saved file depends only on what it was patched from.
    font = TTFont(path, recalcTimestamp=False)
    rename(font, name)
    metrics(font)
    snap_half_pixels(font)
    cmap = font.getBestCmap()
    advance = font["hmtx"][cmap[ord("a")]][0]
    set_glyph(font, cmap[ELLIPSIS], [(x * PX, 0, (x + 1) * PX, PX) for x in (0, 2, 4)], advance)
    set_glyph(font, ZWSP_NAME, [], 0)
    set_glyph(font, HALF_BLOCK_NAME, [(0, -DESCENT, 3 * PX, ASCENT)], advance, weighted=False)
    map_char(font, ZWSP, ZWSP_NAME)
    map_char(font, HALF_BLOCK, HALF_BLOCK_NAME)
    map_char(font, PROMPT, cmap[PROMPT_LIKE])
    font.save(path)


def main():
    name = family()
    for rel in FONTS:
        patch(os.path.join(ROOT, rel), name)
        print("%s: %s" % (rel, name))


if __name__ == "__main__":
    main()
