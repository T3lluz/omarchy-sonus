"""Sonus's desktop notifications, in the panel's Rooms look.

They stay real notifications, sent with notify-send, so they stack with the
shell's others, land in its history and keep to Do Not Disturb. A plugin
cannot draw inside the shell's toast or learn where its stack is, so the
look goes in through what a sender may set: the picture, the words and what
a click does.

The picture is a pixel badge drawn for the slot the shell gives it,
Style.space(40) on the focused screen in device pixels, so the shell shows
it at its own size and nothing is scaled. The service hands the engine
Style.space(40) (`set_slot`); the focused screen's scale comes from hyprctl
when a notification goes out.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import struct
import subprocess
import threading
import time
import zlib
from pathlib import Path

APP = "Sonus"
# The service's IPC target: `omarchy-shell sonus open`.
TARGET = "sonus"
PIXELS_JS = Path(__file__).resolve().parents[2] / "ui" / "Pixels.js"
# The urgent colour reads as a warning only with this much contrast on the
# background; some themes' red is a grey. Batteries uses the same line.
URGENT_CONTRAST = 3.5

# Style.space(40) as the service last said it. Until it says, the shell's
# unscaled 40.
_slot = 40
_slot_known = threading.Event()
_lock = threading.Lock()


def set_slot(value) -> None:
    global _slot
    try:
        n = int(round(float(value)))
    except (TypeError, ValueError):
        return
    if 8 <= n <= 400:
        _slot = n
        _slot_known.set()


def _state_dir() -> Path:
    value = os.environ.get("XDG_STATE_HOME")
    return (Path(value) if value else Path.home() / ".local/state") / "sonus"


def _ids_path() -> Path:
    return _state_dir() / "notices.json"


# ----- the words -----------------------------------------------------------


def sentence(text: str) -> str:
    text = (text or "").strip()
    if not text:
        return ""
    text = text[0].upper() + text[1:]
    return text if text[-1] in ".!?" else text + "."


def updated_text(version: str = "", stashed: bool = False) -> tuple[str, str]:
    body = f"Sonus is on {version} now." if version else "Sonus is on the latest version."
    if stashed:
        body += " Your local edits are in git stash."
    return "Sonus updated", body


def failed_text(message: str = "") -> tuple[str, str]:
    return "Sonus could not update", sentence(message) or "The update failed."


# ----- the picture ---------------------------------------------------------


def pixel_icon(name: str, path: Path = PIXELS_JS) -> dict | None:
    """One icon's rectangles from Pixels.js: {"g24": [...], "g12": [...]}."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    m = re.search(r'"' + re.escape(name) + r'":\s*\{\s*g24:\s*(\[.*?\]\]),\s*g12:\s*(\[.*?\]\])\s*\}', text)
    if not m:
        return None
    return {"g24": json.loads(m.group(1)), "g12": json.loads(m.group(2))}


# The Sonus mark as Model.sonusLogo draws it at rest: three faders on the
# 12 grid, a track one cell wide in columns 1, 5 and 9, knobs three by two.
# The track is lit under each knob and dim over it. tests/test_engine.py
# checks this against Model.js.
LOGO_TOP, LOGO_BOTTOM = 1, 10
LOGO_KNOBS = (6, 2, 4)


def logo(part: str = "lit") -> dict:
    rects = []
    for i, knob in enumerate(LOGO_KNOBS):
        col = 1 + i * 4
        if part == "lit":
            rects.append([col - 1, knob, 3, 2])
            if knob + 2 <= LOGO_BOTTOM:
                rects.append([col, knob + 2, 1, LOGO_BOTTOM - knob - 1])
        elif knob > LOGO_TOP:
            rects.append([col, LOGO_TOP, 1, knob - LOGO_TOP])
    return {"g12": rects, "g24": [[x * 2, y * 2, w * 2, h * 2] for x, y, w, h in rects]}


def hex_rgb(value: str) -> tuple[int, int, int]:
    v = (value or "").strip().lstrip("#")
    if len(v) == 8:  # Qt's #aarrggbb
        v = v[2:]
    if not re.fullmatch(r"[0-9a-fA-F]{6}", v):
        return (255, 255, 255)
    return (int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16))


def contrast(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    """WCAG contrast, as Model.contrast."""
    def lum(c):
        def ch(v):
            v = v / 255
            return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
        return 0.2126 * ch(c[0]) + 0.7152 * ch(c[1]) + 0.0722 * ch(c[2])
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def theme_colors(text: str) -> dict:
    """foreground, background and urgent from a theme's colors.toml, the way
    the shell's Color reads them, with the shell's own defaults."""
    out = {"foreground": "#cacccc", "background": "#101315", "urgent": "#a55555"}
    for line in (text or "").splitlines():
        m = re.match(r"""^\s*([A-Za-z0-9_]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})""", line)
        if not m:
            continue
        key, value = m.group(1), m.group(2)
        if key in ("foreground", "background"):
            out[key] = value
        elif key in ("red", "color1"):
            out["urgent"] = value
    return out


def read_theme() -> dict:
    path = Path.home() / ".local/state/omarchy/current/theme/colors.toml"
    try:
        return theme_colors(path.read_text(encoding="utf-8"))
    except OSError:
        return theme_colors("")


def tone(kind: str, colors: dict) -> tuple[int, int, int]:
    """Sonus's own room, the title room, has no tone and takes the text
    colour; a failure takes the urgent colour, as the panel's banner does,
    unless the theme's is too faint to read as one."""
    fg = hex_rgb(colors.get("foreground", ""))
    if kind != "failed":
        return fg
    urgent = hex_rgb(colors.get("urgent", ""))
    bg = hex_rgb(colors.get("background", ""))
    return urgent if contrast(urgent, bg) >= URGENT_CONTRAST else fg


def badge_pixels(size: int, layers: list[tuple[dict | None, float]], cells: int,
                 rgb: tuple[int, int, int]) -> list[bytearray]:
    """RGBA rows, laid out in units of `u` device pixels: a faint tile of the
    tone, the icon 12 units square (each layer at its own alpha), two units
    under it, then a meter 18 by 6 of five cells with `cells` of them lit.
    The meter is the update's progress: all of it lit when it went through,
    none when nothing changed."""
    size = max(12, min(512, int(size)))
    u = max(1, size // 20)
    rows = [bytearray(size * 4) for _ in range(size)]

    def fill(x: int, y: int, w: int, h: int, alpha: float) -> None:
        a = max(0, min(255, round(alpha * 255)))
        for yy in range(max(0, y), min(size, y + h)):
            row = rows[yy]
            for xx in range(max(0, x), min(size, x + w)):
                i = xx * 4
                # Over what is there (the tile), source-over in straight alpha.
                da = row[i + 3] / 255
                sa = a / 255
                oa = sa + da * (1 - sa)
                if oa <= 0:
                    continue
                for c in range(3):
                    row[i + c] = round((rgb[c] * sa + row[i + c] * da * (1 - sa)) / oa)
                row[i + 3] = round(oa * 255)

    fill(0, 0, size, size, 0.14)
    top = (size - 20 * u) // 2
    # The icon: the 24 grid at half a unit a cell where a unit is even, else the 12.
    fine = u % 2 == 0
    cell = u // 2 if fine else u
    ix = (size - 12 * u) // 2
    for icon, alpha in layers:
        if not icon:
            continue
        for x, y, w, h in icon["g24" if fine else "g12"]:
            fill(ix + x * cell, top + y * cell, w * cell, h * cell, alpha)
    # The meter: a one-unit outline, a unit inside it, five cells two units
    # square a unit apart.
    bx, by = (size - 18 * u) // 2, top + 14 * u
    fill(bx, by, 18 * u, u, 0.6)
    fill(bx, by + 5 * u, 18 * u, u, 0.6)
    fill(bx, by + u, u, 4 * u, 0.6)
    fill(bx + 17 * u, by + u, u, 4 * u, 0.6)
    for n in range(5):
        cx = bx + 2 * u + n * 3 * u
        fill(cx, by + 2 * u, 2 * u, 2 * u, 1 if n < cells else 0.12)
    return rows


def png(rows: list[bytearray]) -> bytes:
    h = len(rows)
    w = len(rows[0]) // 4 if rows else 0
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def badge(kind: str, size: int, colors: dict) -> list[bytearray]:
    rgb = tone(kind, colors)
    if kind == "failed":
        return badge_pixels(size, [(pixel_icon("warning-diamond"), 1.0)], 0, rgb)
    # The mark's dim track, then its lit faders, as SonusLogo draws them.
    return badge_pixels(size, [(logo("track"), 0.4), (logo("lit"), 1.0)], 5, rgb)


def focused_scale() -> float:
    try:
        done = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, timeout=3.0)
        for m in json.loads(done.stdout or "[]"):
            if m.get("focused"):
                scale = float(m.get("scale") or 1)
                return scale if scale > 0 else 1.0
    except (OSError, subprocess.SubprocessError, ValueError, TypeError, AttributeError):
        pass
    return 1.0


def badge_size(slot: int, scale: float) -> int:
    """The shell's picture slot in device pixels, as Batteries' badgeSize."""
    return max(12, round(slot * scale))


def write_badge(kind: str, size: int, colors: dict) -> str:
    """The badge's path, or "" if it could not be written. Under the state
    dir, never the plugin folder: the shell reloads every plugin when a file
    appears there. The size is in the name so the shell never shows a picture
    cached for another screen's scale."""
    out = _state_dir() / "notices" / f"{kind}-{size}.png"
    try:
        out.parent.mkdir(parents=True, exist_ok=True)
        tmp = out.with_suffix(".png.tmp")
        tmp.write_bytes(png(badge(kind, size, colors)))
        tmp.replace(out)
    except OSError:
        return ""
    return str(out)


# ----- sending -------------------------------------------------------------


def _ids() -> dict:
    try:
        data = json.loads(_ids_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def _save_ids(data: dict) -> None:
    try:
        path = _ids_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data), encoding="utf-8")
    except OSError:
        pass


def command(title: str, body: str, image: str, argv: list[str], replace: int = 0) -> list[str]:
    cmd = ["notify-send", "-p", "-a", APP, "-u", "normal", "-i", image or "audio-card",
           "-h", "string:omarchy-exec-argv:" + json.dumps(argv)]
    if replace:
        cmd += ["-r", str(replace)]
    return cmd + ["--", title, body]


def send(kind: str, title: str, body: str, argv: list[str], replace: int = 0) -> int:
    """Send one notification; returns its id, or 0."""
    if shutil.which("notify-send") is None:
        return 0
    # The engine can be asked before the service has said how big the slot
    # is (an update reported the moment the engine starts); give it a moment.
    _slot_known.wait(2.0)
    image = write_badge(kind, badge_size(_slot, focused_scale()), read_theme())
    try:
        done = subprocess.run(command(title, body, image, argv, replace),
                              capture_output=True, text=True, timeout=5.0)
    except (OSError, subprocess.SubprocessError):
        return 0
    line = (done.stdout or "").strip().splitlines()
    return int(line[0]) if line and line[0].isdigit() else 0


def updated(version: str = "", stashed: bool = False, key: str = "update") -> int:
    """An update went through. It takes the place of a failure still up from
    an earlier try, so the desktop does not say both."""
    title, body = updated_text(version, stashed)
    with _lock:
        ids = _ids()
        old = int(ids.pop(key, 0) or 0)
        nid = send("updated", title, body, ["omarchy-shell", TARGET, "open"], old)
        _save_ids(ids)
    return nid


def failed(message: str = "", key: str = "update") -> int:
    """An update failed. A click opens the settings page, where it can be
    tried again; a second failure replaces the first instead of stacking."""
    title, body = failed_text(message)
    with _lock:
        ids = _ids()
        nid = send("failed", title, body, ["omarchy-shell", TARGET, "settings"], int(ids.get(key, 0) or 0))
        if nid:
            ids[key] = nid
        _save_ids(ids)
    return nid


def preview(version: str = "", delay: float = 6.0) -> None:
    """Both notifications on made-up values, as they would live: an update
    fails, and a few seconds later a retry goes through on the same card."""
    failed("Could not reach github.com", key="preview")
    time.sleep(delay)
    updated(version or "9.9.9", key="preview")
