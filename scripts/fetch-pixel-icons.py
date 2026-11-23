#!/usr/bin/env python3
"""
Build ui/Pixels.js, Sonus's pixel icons, from Pixelarticons (MIT,
https://pixelarticons.com), plus the AirPods it lacks, drawn here on the same
grid in the same weight as Batteries draws them. The Sonus mark itself is
drawn by ui/Model.js (sonusLogo), since its knobs move.

Pixelarticons are drawn on a 24-unit grid with two-unit strokes. Their SVGs
are outlines of rectangles, so each icon turns into an exact grid of pixels:
a cell is on when its centre is inside the shape. PixelIcon.qml draws the
grid as rectangles on whole device pixels, so the icons stay sharp at any
scale. Small sizes use the same grid halved (see `halve`). Run from the repo root:

    python3 scripts/fetch-pixel-icons.py
"""

import io
import json
import os
import re
import sys
import tarfile
import urllib.request

VERSION = "2.4.2"
TARBALL = "https://registry.npmjs.org/pixelarticons/-/pixelarticons-%s.tgz" % VERSION
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

# The icons the panel draws, by the name Pixelarticons gives them.
ICONS = [
    # Devices.
    "laptop", "headphone", "volume-2", "monitor", "tv", "mic", "webcam",
    # Channels and the apps that skip them.
    "gamepad", "message-text", "music", "audio-waveform", "cancel",
    # Levels and marks.
    "volume-x", "volume-1", "volume-3", "mic-off", "sliders-horizontal",
    # An app without an icon of its own.
    "app-windows",
    # The panel's buttons and the kit's glyphs.
    "chevron-down", "chevron-up", "settings-cog", "arrow-left", "check",
    "close", "reload", "download", "warning-diamond", "circle-info", "keyboard",
]

# Drawn here on a 12-cell grid (each cell two units), in Pixelarticons'
# weight: one-cell lines, corners cut square.
CUSTOM = {
    # Two buds in outline like the rest: round heads, stems down.
    "airpods": [
        "............",
        ".###....###.",
        "#...#..#...#",
        "#...#..#...#",
        ".##.#..#.##.",
        "..#.#..#.#..",
        "..#.#..#.#..",
        "..#.#..#.#..",
        "..#.#..#.#..",
        "..###..###..",
        "............",
        "............",
    ],
}


# Drawn from another icon, as (source, first column, past the last column):
# the columns outside are cleared. None at the moment.
DERIVED = {}


def box(x0, y0, x1, y1):
    """The units of the 24 grid from (x0, y0) up to, not including, (x1, y1)."""
    return lambda x, y: x0 <= x < x1 and y0 <= y < y1


# The parts of an icon that move on their own (ui/Motion.js), in order: a
# pixel goes to the first part that takes it, and whatever no part takes is
# the icon's `base`. A part is a test on the 24 grid's units, or
# ("minus", other) for the pixels this icon has and the other has not.
PARTS = {
    "headphone": [("cup-left", box(0, 13, 12, 24)), ("cup-right", box(12, 13, 24, 24))],
    "airpods": [("bud-left", box(0, 0, 12, 24)), ("bud-right", box(12, 0, 24, 24))],
    "volume-1": [("wave-1", box(16, 0, 24, 24))],
    "volume-2": [("wave-1", box(14, 9, 18, 15)), ("wave-2", box(14, 0, 24, 24))],
    "volume-3": [("wave-1", box(13, 9, 16, 15)), ("wave-2", box(13, 5, 20, 19)), ("wave-3", box(13, 0, 24, 24))],
    "volume-x": [("cross", box(14, 0, 24, 24))],
    "mic": [("capsule", box(8, 0, 16, 16))],
    "mic-off": [("slash", ("minus", "mic"))],
    "webcam": [("lens", box(8, 6, 16, 14))],
    "gamepad": [("dpad", box(6, 9, 12, 15)), ("button-a", box(14, 9, 16, 11)), ("button-b", box(16, 13, 18, 15))],
    "message-text": [("line-1", box(6, 8, 14, 10)), ("line-2", box(6, 12, 10, 14))],
    "music": [("note-left", box(0, 0, 12, 24)), ("note-right", box(12, 0, 24, 24))],
    "cancel": [("slash", lambda x, y: 5 <= x < 19 and 5 <= y < 19 and 22 <= x + y <= 24)],
    "sliders-horizontal": [("knob-1", box(13, 2, 15, 8)), ("knob-2", box(7, 9, 9, 15)), ("knob-3", box(15, 16, 17, 22))],
    "download": [("arrow", box(7, 0, 17, 17))],
    "warning-diamond": [("mark", box(11, 7, 13, 17))],
    "circle-info": [("dot", box(11, 7, 13, 9))],
    "keyboard": [("key-1", box(5, 7, 7, 9)), ("key-2", box(13, 7, 15, 9)), ("key-3", box(11, 11, 13, 13)), ("space", box(6, 15, 18, 17))],
    "app-windows": [("button-1", box(12, 5, 14, 7)), ("button-2", box(16, 5, 18, 7))],
}

# Pixels an icon only shows while it moves, drawn here on the 24 grid as
# boxes (x0, y0, x1, y1) inside the icon's own lines, so they halve with it.
LAYERS = {
    # A line typed out on the laptop's screen.
    "laptop": {"text": [(7, 8, 9, 10), (9, 8, 11, 10), (11, 8, 13, 10), (13, 8, 15, 10), (7, 11, 9, 13), (9, 11, 11, 13)]},
    # The microphone's capsule filling with what it hears, a row at a time
    # from the bottom.
    "mic": {
        "fill-1": [(10, 12, 14, 14)],
        "fill-2": [(10, 10, 14, 12)],
        "fill-3": [(10, 8, 14, 10)],
        "fill-4": [(10, 6, 14, 8)],
        "fill-5": [(10, 4, 14, 6)],
    },
    # A line that sweeps the monitor's screen as it wakes.
    "monitor": {"scan": [(4, 4, 20, 6)]},
    # A tube coming on: a dot, then a line across the middle.
    "tv": {"dot": [(10, 9, 14, 11)], "line": [(4, 9, 20, 11)]},
}


def split(name, grid, grids):
    """The icon's parts and its base, each a 24 grid of its own."""
    taken = [[False] * 24 for _ in range(24)]
    parts = {}
    for part, test in PARTS.get(name, []):
        if isinstance(test, tuple):
            other = grids[test[1]]
            test = (lambda o: lambda x, y: not o[y][x])(other)
        cells = [[False] * 24 for _ in range(24)]
        for y in range(24):
            for x in range(24):
                if grid[y][x] and not taken[y][x] and test(x, y):
                    cells[y][x] = taken[y][x] = True
        if not any(any(row) for row in cells):
            raise SystemExit("%s: part %s is empty" % (name, part))
        parts[part] = cells
    parts["base"] = [[grid[y][x] and not taken[y][x] for x in range(24)] for y in range(24)]
    return parts


def layer(boxes):
    cells = [[False] * 24 for _ in range(24)]
    for x0, y0, x1, y1 in boxes:
        for y in range(y0, y1):
            for x in range(x0, x1):
                cells[y][x] = True
    return cells


def both(grid):
    return "{ g24: %s, g12: %s }" % (json.dumps(rects(grid)), json.dumps(rects(halve(grid))))


def polygons(d):
    """Rectilinear subpaths of an SVG path (M, H, V, L, h, v, l, m, Z)."""
    tokens = re.findall(r"[MmHhVvLlZz]|-?\d*\.?\d+", d)
    polys, cur, x, y, cmd, i = [], [], 0.0, 0.0, None, 0
    while i < len(tokens):
        t = tokens[i]
        if re.match(r"[A-Za-z]", t):
            cmd = t
            i += 1
            if cmd in "Zz":
                if cur:
                    polys.append(cur)
                    x, y = cur[0]
                cur = []
            continue
        if cmd in "Mm":
            nx, ny = float(tokens[i]), float(tokens[i + 1])
            i += 2
            if cmd == "m":
                nx, ny = x + nx, y + ny
            if cur:
                polys.append(cur)
            cur = [(nx, ny)]
            x, y = nx, ny
            cmd = "l" if cmd == "m" else "L"
        elif cmd in "Ll":
            nx, ny = float(tokens[i]), float(tokens[i + 1])
            i += 2
            if cmd == "l":
                nx, ny = x + nx, y + ny
            x, y = nx, ny
            cur.append((x, y))
        elif cmd in "Hh":
            v = float(tokens[i]); i += 1
            x = x + v if cmd == "h" else v
            cur.append((x, y))
        elif cmd in "Vv":
            v = float(tokens[i]); i += 1
            y = y + v if cmd == "v" else v
            cur.append((x, y))
        else:
            raise SystemExit("unsupported path command %r" % cmd)
    if cur:
        polys.append(cur)
    return polys


def raster(svg):
    """The 24x24 grid of an icon: rows of booleans, nonzero winding."""
    edges = []
    for d in re.findall(r'<path[^>]*\sd="([^"]+)"', svg):
        for poly in polygons(d):
            for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
                if x0 == x1 and y0 != y1:
                    edges.append((x0, y0, y1))
    for m in re.finditer(r'<rect[^>]*>', svg):
        a = dict(re.findall(r'(\w+)="([^"]+)"', m.group(0)))
        x, y, w, h = (float(a.get(k, 0)) for k in ("x", "y", "width", "height"))
        edges += [(x, y + h, y), (x + w, y, y + h)]
    if re.search(r"<(circle|ellipse|polygon|polyline|line)\b", svg):
        raise SystemExit("expected only paths and rects")
    grid = []
    for row in range(24):
        cy = row + 0.5
        line = []
        for col in range(24):
            cx = col + 0.5
            wind = 0
            for x, y0, y1 in edges:
                if x > cx and min(y0, y1) < cy < max(y0, y1):
                    wind += 1 if y1 > y0 else -1
            line.append(wind != 0)
        grid.append(line)
    return grid


def from_art(art):
    """A 12-cell drawing at 24 units: each cell two by two."""
    return [[art[r // 2][c // 2] == "#" for c in range(24)] for r in range(24)]


def halve(grid):
    # Every stroke is two units wide, so it covers exactly one odd unit:
    # sampling those keeps each stroke one cell wide, wherever it starts.
    return [[grid[r * 2 + 1][c * 2 + 1] for c in range(12)] for r in range(12)]


def rects(grid):
    """Runs along each row, merged down where the next rows repeat them."""
    n = len(grid)
    runs = []
    for r, line in enumerate(grid):
        c = 0
        while c < n:
            if line[c]:
                s = c
                while c < n and line[c]:
                    c += 1
                runs.append([s, r, c - s, 1])
            else:
                c += 1
    merged = []
    for run in runs:
        for m in merged:
            if m[0] == run[0] and m[2] == run[2] and m[1] + m[3] == run[1]:
                m[3] += 1
                break
        else:
            merged.append(list(run))
    return merged


def show(grid):
    return "\n".join("".join("#" if v else "." for v in line) for line in grid)


def main():
    with urllib.request.urlopen(TARBALL, timeout=30) as r:
        pack = tarfile.open(fileobj=io.BytesIO(r.read()))
    out = {}
    for name in ICONS:
        svg = pack.extractfile("package/svg/%s.svg" % name).read().decode()
        with open(os.path.join(ROOT, "pixels", name + ".svg"), "w") as f:
            f.write(svg)
        out[name] = raster(svg)
    for name, art in CUSTOM.items():
        out[name] = from_art(art)
    for name, (source, lo, hi) in DERIVED.items():
        out[name] = [[v and lo <= c < hi for c, v in enumerate(line)] for line in out[source]]
    if "--show" in sys.argv:
        for name, grid in out.items():
            print(name)
            print(show(grid))
            print(show(halve(grid)))
            print()
        return
    lines = [
        ".pragma library",
        "",
        "// Generated by scripts/fetch-pixel-icons.py from Pixelarticons %s (MIT," % VERSION,
        "// https://pixelarticons.com), plus the AirPods drawn there on the same grid.",
        "// Each icon is [x, y, width, height] rectangles: `g24` on the 24-unit grid,",
        "// `g12` on the same grid halved for small sizes. An icon that moves in parts",
        "// (ui/Motion.js) also has `parts`, which together draw the icon, and",
        "// `layers`, drawn only while it moves.",
        "",
        "var icons = {",
    ]
    for name, grid in out.items():
        extra = ""
        if name in PARTS:
            parts = split(name, grid, out)
            extra += ", parts: { %s }" % ", ".join("%s: %s" % (json.dumps(p), both(g)) for p, g in parts.items())
        if name in LAYERS:
            extra += ", layers: { %s }" % ", ".join("%s: %s" % (json.dumps(p), both(layer(b))) for p, b in LAYERS[name].items())
        lines.append("  %s: { g24: %s, g12: %s%s }," % (json.dumps(name), json.dumps(rects(grid)), json.dumps(rects(halve(grid))), extra))
    lines[-1] = lines[-1].rstrip(",")
    lines += ["}", ""]
    with open(os.path.join(ROOT, "ui", "Pixels.js"), "w") as f:
        f.write("\n".join(lines))
    print("wrote ui/Pixels.js with %d icons" % len(out))


if __name__ == "__main__":
    main()
