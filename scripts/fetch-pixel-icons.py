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
        "// `g12` on the same grid halved for small sizes.",
        "",
        "var icons = {",
    ]
    for name, grid in out.items():
        lines.append("  %s: { g24: %s, g12: %s }," % (json.dumps(name), json.dumps(rects(grid)), json.dumps(rects(halve(grid)))))
    lines[-1] = lines[-1].rstrip(",")
    lines += ["}", ""]
    with open(os.path.join(ROOT, "ui", "Pixels.js"), "w") as f:
        f.write("\n".join(lines))
    print("wrote ui/Pixels.js with %d icons" % len(out))


if __name__ == "__main__":
    main()
