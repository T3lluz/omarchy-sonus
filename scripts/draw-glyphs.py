#!/usr/bin/env python3
"""
Draw the panel's device and channel drawings and write ui/Drawings.js.

The same drawing style as Batteries (omarchy-batteries/scripts/draw-glyphs.py,
which the laptop, speaker, headphones and gamepad here are copied from): one
solid silhouette with fine details cut out of it. Each drawing is built from
plain shapes on a 48-unit grid and filled even-odd, so a shape inside another
cuts it and a shape inside a cut fills again. Shapes must never overlap, or the
overlap flips. Run from the repo root:

    python3 scripts/draw-glyphs.py

It also writes /tmp/sonus-drawings.svg, a sheet to check new drawings against
the others before using them.
"""

import json
import math
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def n(v):
    return ("%.3f" % v).rstrip("0").rstrip(".")


def rrect(x, y, w, h, r):
    r = min(r, w / 2, h / 2)
    return ("M%s %sH%sA%s %s 0 0 1 %s %sV%sA%s %s 0 0 1 %s %sH%sA%s %s 0 0 1 %s %sV%sA%s %s 0 0 1 %s %sZ" % (
        n(x + r), n(y), n(x + w - r), n(r), n(r), n(x + w), n(y + r), n(y + h - r), n(r), n(r), n(x + w - r), n(y + h),
        n(x + r), n(r), n(r), n(x), n(y + h - r), n(y + r), n(r), n(r), n(x + r), n(y)))


def circle(cx, cy, r):
    return "M%s %sA%s %s 0 1 1 %s %sA%s %s 0 1 1 %s %sZ" % (
        n(cx - r), n(cy), n(r), n(r), n(cx + r), n(cy), n(r), n(r), n(cx - r), n(cy))


def plus(cx, cy, arm, w):
    a, h = arm, w / 2
    pts = [(-h, -a), (h, -a), (h, -h), (a, -h), (a, h), (h, h), (h, a), (-h, a), (-h, h), (-a, h), (-a, -h), (-h, -h)]
    return "M" + "L".join("%s %s" % (n(cx + x), n(cy + y)) for x, y in pts) + "Z"


def band(cx, cy, r0, r1, a0, a1):
    """A ring segment between radii r0 < r1, from angle a0 to a1 in degrees
    (0 is right, 90 is down), drawn clockwise."""
    def at(r, a):
        t = math.radians(a)
        return cx + r * math.cos(t), cy + r * math.sin(t)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    ox0, oy0 = at(r1, a0)
    ox1, oy1 = at(r1, a1)
    ix1, iy1 = at(r0, a1)
    ix0, iy0 = at(r0, a0)
    return "M%s %sA%s %s 0 %d 1 %s %sL%s %sA%s %s 0 %d 0 %s %sZ" % (
        n(ox0), n(oy0), n(r1), n(r1), large, n(ox1), n(oy1), n(ix1), n(iy1), n(r0), n(r0), large, n(ix0), n(iy0))


def rotate(path, deg, cx=24, cy=24):
    """Turns a path drawn with M, L, H, V, A and Z about (cx, cy). Arcs here
    are circular, so only their end points move."""
    t = math.radians(deg)
    c, s = math.cos(t), math.sin(t)

    def turn(x, y):
        dx, dy = x - cx, y - cy
        return cx + dx * c - dy * s, cy + dx * s + dy * c

    out, x, y = [], 0.0, 0.0
    for cmd in re.finditer(r"([MLHVAZ])([^MLHVAZ]*)", path):
        op, args = cmd.group(1), [float(v) for v in re.findall(r"-?\d*\.?\d+", cmd.group(2))]
        if op in "ML":
            x, y = args
            out.append("%s%s %s" % ((op,) + tuple(map(n, turn(x, y)))))
        elif op == "H":
            x = args[0]
            out.append("L%s %s" % tuple(map(n, turn(x, y))))
        elif op == "V":
            y = args[0]
            out.append("L%s %s" % tuple(map(n, turn(x, y))))
        elif op == "A":
            rx, ry, rot, large, sweep, x, y = args
            out.append("A%s %s 0 %d %d %s %s" % ((n(rx), n(ry), int(large), int(sweep)) + tuple(map(n, turn(x, y)))))
        else:
            out.append("Z")
    return "".join(out)


# ---- from Batteries ----------------------------------------------------------

def laptop():
    # An open laptop from the front: the lid with a thin bezel, a camera in
    # it and a deeper chin, a hinge gap, then the wider base with its notch.
    return [
        rrect(6, 6, 36, 23.5, 2.2),
        rrect(7.7, 7.7, 32.6, 19.0, 0.8),
        circle(24, 6.85, 0.45),
        "M2 30.3H46V31.6C46 32.6 45.2 33.4 44.2 33.4H3.8C2.8 33.4 2 32.6 2 31.6Z",
        "M19.5 30.3H28.5V30.55A0.85 0.85 0 0 1 27.65 31.4H20.35A0.85 0.85 0 0 1 19.5 30.55Z",
    ]


def speaker():
    # A speaker from the front: the cabinet, a tweeter, and a woofer with its
    # surround and dust cap, each ring cut and filled in turn.
    return [
        rrect(11, 3, 26, 42, 5),
        circle(24, 12.6, 4.3), circle(24, 12.6, 3.1), circle(24, 12.6, 1.05),
        circle(24, 30.4, 9.7), circle(24, 30.4, 8.3), circle(24, 30.4, 4.5), circle(24, 30.4, 3.4),
    ]


def headphones():
    # Over-ear headphones: the band with a groove along it, hinges, then the
    # cups with the cushion line on their inner side.
    return [
        "M8.5 26A15.5 15.5 0 0 1 39.5 26H36.9A12.9 12.9 0 0 0 11.1 26Z",
        "M10.98 18.6A14.6 14.6 0 0 1 37.02 18.6L36.32 18.95A13.8 13.8 0 0 0 11.68 18.95Z",
        rrect(6.5, 26.8, 8.6, 16.2, 4),
        rrect(12.3, 29.2, 0.8, 11.4, 0.4),
        rrect(32.9, 26.8, 8.6, 16.2, 4),
        rrect(34.9, 29.2, 0.8, 11.4, 0.4),
    ]


def gamepad():
    # A controller: the d-pad, four face buttons, two sticks in their rings
    # and the two small buttons between.
    return [
        "M14 13H34C40 13 44 17 45 23L46.5 33C47.2 38 43 41 39.5 37.5L35.5 33.5H12.5L8.5 37.5C5 41 0.8 38 1.5 33L3 23C4 17 8 13 14 13Z",
        plus(12.5, 21.5, 3.6, 2.2),
        circle(35.5, 18.4, 1.15), circle(35.5, 24.6, 1.15), circle(32.4, 21.5, 1.15), circle(38.6, 21.5, 1.15),
        circle(18.5, 27.6, 2.8), circle(18.5, 27.6, 1.8),
        circle(29.5, 27.6, 2.8), circle(29.5, 27.6, 1.8),
        rrect(20.4, 18.6, 2.6, 1.1, 0.55), rrect(25, 18.6, 2.6, 1.1, 0.55),
    ]


# ---- Sonus's own -------------------------------------------------------------

def headset():
    # The headphones with a boom mic: the arm curves from under the left cup
    # toward the middle, a hairline away from the cup, and ends in the mic.
    return headphones() + [
        band(21, 36.4, 8.7, 10.6, 100, 136),
        rrect(20.3, 44.7, 6, 3.2, 1.6),
    ]


def monitor():
    # A display on a stand: thin bezel with a deeper chin, the neck and foot
    # in one outline with the frame, a hairline where the foot meets the desk.
    return [
        "M6.2 6H41.8A2.2 2.2 0 0 1 44 8.2V30.3A2.2 2.2 0 0 1 41.8 32.5H27V38.2H32.6A1.4 1.4 0 0 1 34 39.6"
        "V40.6A1.4 1.4 0 0 1 32.6 42H15.4A1.4 1.4 0 0 1 14 40.6V39.6A1.4 1.4 0 0 1 15.4 38.2H21V32.5H6.2"
        "A2.2 2.2 0 0 1 4 30.3V8.2A2.2 2.2 0 0 1 6.2 6Z",
        rrect(5.7, 7.7, 36.6, 21.6, 0.8),
        rrect(22.6, 33.6, 2.8, 0.8, 0.4),
    ]


def microphone():
    # A desk microphone: the capsule with its grille lines, held in a yoke a
    # hairline away, on a stem and a weighted foot.
    return [
        rrect(17, 2.5, 14, 25, 7),
        rrect(19.6, 9, 8.8, 0.9, 0.45),
        rrect(19.2, 12.4, 9.6, 0.9, 0.45),
        rrect(19.2, 15.8, 9.6, 0.9, 0.45),
        band(24, 18.5, 8.6, 10.4, 0, 180),
        rrect(22.9, 29.7, 2.2, 9.6, 0.4),
        rrect(14.5, 40.1, 19, 3.4, 1.7),
    ]


def music():
    # Two beamed notes: round heads, stems on their right and one slanted
    # beam, drawn as a single outline; a hairline splits the beam in two.
    path = ("M16.3 9L38.5 5V34.5A5.5 5.5 0 1 1 36.3 30.1V10.4L18.5 13.6V38.5"
            "A5.5 5.5 0 1 1 16.3 34.1Z")
    return [path, "M18.5 11.2L36.3 8V8.9L18.5 12.1Z"]


def jack():
    # A 3.5 mm plug lying corner to corner: the tip, ring and sleeve split by
    # the insulators, the grip with its grooves, the strain relief and cable.
    parts = [
        rrect(22.3, 2, 3.4, 5.4, 1.7),
        rrect(22.3, 8.2, 3.4, 4.6, 0),
        rrect(22.3, 13.6, 3.4, 7.4, 0),
        rrect(19.4, 21.8, 9.2, 14.2, 2.2),
        rrect(21.2, 30.2, 5.6, 0.8, 0.4),
        rrect(21.2, 32.4, 5.6, 0.8, 0.4),
        rrect(20.9, 36.8, 6.2, 3.6, 1.4),
        rrect(22.6, 41.2, 2.8, 6.2, 1.4),
    ]
    return [rotate(p, 45) for p in parts]


# Arcs only list their end points, so a drawing whose outline bulges past
# them names its extent here.
INK = {
    "headphones": [6.5, 10.5, 41.5, 43],
    "headset": [6.5, 10.5, 41.5, 47.8],
    "microphone": [13.6, 2.5, 34.4, 43.5],
    "music": [7.5, 5, 38.5, 44],
}

DRAWINGS = {
    "laptop": laptop,
    "speaker": speaker,
    "headphones": headphones,
    "gamepad": gamepad,
    "headset": headset,
    "monitor": monitor,
    "microphone": microphone,
    "music": music,
    "jack": jack,
}


def bounds(path):
    xs, ys = [], []
    for cmd in re.finditer(r"([MLHVCQAZ])([^MLHVCQAZ]*)", path):
        c, args = cmd.group(1), [float(v) for v in re.findall(r"-?\d*\.?\d+", cmd.group(2))]
        if c in "ML":
            xs += args[0::2]; ys += args[1::2]
        elif c == "H":
            xs += args
        elif c == "V":
            ys += args
        elif c in "CQ":
            xs += args[0::2]; ys += args[1::2]
        elif c == "A":
            xs.append(args[5]); ys.append(args[6])
    return xs, ys


def main():
    drawings = {}
    for name, draw in DRAWINGS.items():
        path = " ".join(draw())
        # The points each part moves or draws to, control points included:
        # close enough to the drawn extent for these shapes.
        xs, ys = bounds(path)
        ink = INK.get(name) or [min(xs), min(ys), max(xs), max(ys)]
        drawings[name] = {"ink": [round(v, 3) for v in ink], "path": path}

    lines = [
        ".pragma library",
        "",
        "// Generated by scripts/draw-glyphs.py: the panel's drawings, solid with",
        "// details cut out, on a 48-unit grid. Fill them odd-even. `ink` is each",
        "// drawing's extent as [left, top, right, bottom].",
        "",
        "var drawings = {",
    ]
    lines += ["  %s: %s," % (json.dumps(k), json.dumps(v)) for k, v in drawings.items()]
    lines[-1] = lines[-1].rstrip(",")
    lines += ["}", ""]
    with open(os.path.join(ROOT, "ui", "Drawings.js"), "w") as f:
        f.write("\n".join(lines))

    # A sheet at three sizes, for drawing new ones: the big row as the panel
    # draws an output, then a channel, then a list row.
    sizes, cell, pad = (80, 44, 30), 120, 20
    width = cell * len(drawings)
    rows = []
    y = pad
    for size in sizes:
        for i, (name, d) in enumerate(drawings.items()):
            x0, y0, x1, y1 = d["ink"]
            fit = size / max(x1 - x0, y1 - y0)
            tx = i * cell + (cell - (x1 - x0) * fit) / 2 - x0 * fit
            ty = y + (size - (y1 - y0) * fit) / 2 - y0 * fit
            rows.append('<path fill="#d8dadc" fill-rule="evenodd" transform="translate(%s %s) scale(%s)" d="%s"/>' % (
                n(tx), n(ty), n(fit), d["path"]))
        y += size + pad
    for i, name in enumerate(drawings):
        rows.append('<text x="%s" y="%s" fill="#8a8f94" font-family="monospace" font-size="13" text-anchor="middle">%s</text>' % (
            n(i * cell + cell / 2), n(y + 4), name))
    svg = '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d"><rect width="100%%" height="100%%" fill="#121518"/>%s</svg>' % (
        width, y + pad, "".join(rows))
    with open("/tmp/sonus-drawings.svg", "w") as f:
        f.write(svg)
    print("wrote ui/Drawings.js with %d drawings" % len(drawings))


if __name__ == "__main__":
    main()
