"""Draws the Standwise app icon ("split ring": a green work arc and an amber
standby arc around white clock hands, on a dark navy gradient) and writes the
1024 px source images used by flutter_launcher_icons.

  python3 tool/icon/make_icon.py && dart run flutter_launcher_icons
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 4  # supersampling
N = 1024 * S
WHITE = (255, 255, 255)
GREEN = ((90, 225, 150), (22, 140, 86))
AMBER = ((255, 210, 110), (232, 130, 20))
NAVY = ((28, 58, 82), (8, 20, 33))
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "icon")


def layer() -> Image.Image:
    return Image.new("RGBA", (N, N), (0, 0, 0, 0))


def background() -> Image.Image:
    """Radial navy gradient, lighter at the top left."""
    y, x = np.mgrid[0:N, 0:N] / N
    t = np.clip(np.hypot(x - 0.3, y - 0.25) / 1.1, 0, 1)[..., None]
    c = np.array(NAVY[0]) * (1 - t) + np.array(NAVY[1]) * t
    return Image.fromarray(c.astype(np.uint8), "RGB").convert("RGBA")


def gradient_fill(shape: Image.Image, colors, angle: float) -> Image.Image:
    y, x = np.mgrid[0:N, 0:N] / N
    a = math.radians(angle)
    t = x * math.cos(a) + y * math.sin(a)
    t = ((t - t.min()) / (t.max() - t.min()))[..., None]
    c = np.array(colors[0]) * (1 - t) + np.array(colors[1]) * t
    img = Image.fromarray(c.astype(np.uint8), "RGB").convert("RGBA")
    img.putalpha(shape.split()[3])
    return img


def with_shadow(base: Image.Image, shape: Image.Image, alpha: int, blur: float) -> None:
    sh = Image.new("RGBA", (N, N), (0, 10, 20, 0))
    sh.putalpha(shape.split()[3].point(lambda v: v * alpha // 255))
    sh = sh.filter(ImageFilter.GaussianBlur(N * blur))
    base.alpha_composite(sh, (0, int(N * 0.02)))
    base.alpha_composite(shape)


def arc(cx, cy, r, w, start, end) -> Image.Image:
    img = layer()
    d = ImageDraw.Draw(img)
    d.arc([cx - r, cy - r, cx + r, cy + r], start, end, fill=WHITE, width=int(w))
    for ang in (start, end):  # round caps
        a = math.radians(ang)
        x, y = cx + (r - w / 2) * math.cos(a), cy + (r - w / 2) * math.sin(a)
        d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=WHITE)
    return img


def symbol(base: Image.Image, cx: float, cy: float, scale: float) -> None:
    """The split ring and hands, drawn onto [base]; scale 1 fills ~62%."""
    r, w = N * 0.31 * scale, N * 0.085 * scale
    with_shadow(base, gradient_fill(arc(cx, cy, r, w, -73, 103), GREEN, 90), 90, 0.02)
    with_shadow(base, gradient_fill(arc(cx, cy, r, w, 137, 253), AMBER, 270), 90, 0.02)
    hands = layer()
    d = ImageDraw.Draw(hands)
    hw = N * 0.045 * scale
    for ang, length in ((-90, 0.15), (20, 0.11)):
        a = math.radians(ang)
        x, y = cx + N * length * scale * math.cos(a), cy + N * length * scale * math.sin(a)
        d.line([cx, cy, x, y], fill=WHITE, width=int(hw))
        for px, py in ((x, y), (cx, cy)):
            d.ellipse([px - hw / 2, py - hw / 2, px + hw / 2, py + hw / 2], fill=WHITE)
    with_shadow(base, hands, 80, 0.015)


def save(img: Image.Image, name: str) -> None:
    img.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, name))


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    c = N / 2
    # Full icon (iOS, Windows, legacy Android).
    full = background()
    symbol(full, c, c, 1.0)
    save(full.convert("RGB"), "icon.png")
    # Android adaptive icon: gradient background layer and a transparent
    # foreground with the symbol inside the central 66% safe zone.
    save(background().convert("RGB"), "icon_background.png")
    fg = layer()
    symbol(fg, c, c, 0.68)
    save(fg, "icon_foreground.png")
    # macOS: rounded tile with a margin and transparent corners.
    m = N * 0.1
    tile = background()
    symbol(tile, c, c, 0.8)
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle([m, m, N - m, N - m], radius=N * 0.18, fill=255)
    mac = layer()
    mac.paste(tile, (0, 0), mask)
    save(mac, "icon_macos.png")


if __name__ == "__main__":
    main()
