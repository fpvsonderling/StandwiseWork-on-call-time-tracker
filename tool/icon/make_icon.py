"""Draws the Standwise app icon (a clock face, right half work and left half
standby, with a smiling worker in front) and writes the 1024 px source
images used by flutter_launcher_icons.

  python3 tool/icon/make_icon.py
"""
import math
import os

from PIL import Image, ImageDraw

S = 4  # supersampling
N = 1024 * S
TEAL = (30, 95, 116)
TEAL_DARK = (17, 61, 76)
WORK = (46, 170, 106)
STANDBY = (245, 166, 35)
FACE = (250, 250, 247)
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "icon")


def clock(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float) -> None:
    box = [cx - r, cy - r, cx + r, cy + r]
    # Ring: right half work (green), left half standby (amber).
    draw.pieslice(box, -90, 90, fill=WORK)
    draw.pieslice(box, 90, 270, fill=STANDBY)
    inner = r * 0.74
    draw.ellipse([cx - inner, cy - inner, cx + inner, cy + inner], fill=FACE)
    # Hour ticks at 12, 3, 6, 9.
    for k in range(4):
        a = math.radians(k * 90)
        r1, r2 = inner * 0.80, inner * 0.94
        w = r * 0.055
        x1, y1 = cx + r1 * math.sin(a), cy - r1 * math.cos(a)
        x2, y2 = cx + r2 * math.sin(a), cy - r2 * math.cos(a)
        draw.line([x1, y1, x2, y2], fill=TEAL_DARK, width=int(w))
    # Hands: hour at 12, minute at 3 (a quarter: work starts).
    def hand(angle_deg: float, length: float, width: float) -> None:
        a = math.radians(angle_deg)
        x, y = cx + length * math.sin(a), cy - length * math.cos(a)
        draw.line([cx, cy, x, y], fill=TEAL_DARK, width=int(width))
        rr = width / 2
        draw.ellipse([x - rr, y - rr, x + rr, y + rr], fill=TEAL_DARK)

    hand(0, inner * 0.52, r * 0.10)
    hand(90, inner * 0.68, r * 0.075)
    c = r * 0.09
    draw.ellipse([cx - c, cy - c, cx + c, cy + c], fill=TEAL_DARK)


SKIN = (247, 205, 168)
HAIR = (74, 52, 40)
SHIRT = (250, 250, 247)


def person(draw: ImageDraw.ImageDraw, cx: float, top: float, s: float, bottom: float) -> None:
    """A smiling worker: head with hair, shoulders down to [bottom]."""
    outline = s * 0.035
    # Shoulders: a rounded block in a work shirt with a teal collar.
    sw = s * 0.92
    st = top + s * 0.47
    draw.rounded_rectangle(
        [cx - sw / 2 - outline, st - outline, cx + sw / 2 + outline, bottom + s],
        radius=s * 0.34, fill=TEAL_DARK)
    draw.rounded_rectangle([cx - sw / 2, st, cx + sw / 2, bottom + s], radius=s * 0.32, fill=SHIRT)
    draw.polygon([(cx - s * 0.11, st), (cx + s * 0.11, st), (cx, st + s * 0.13)], fill=TEAL)
    # Neck and head.
    hr = s * 0.23
    hy = top + hr + outline
    draw.ellipse([cx - hr - outline, hy - hr - outline, cx + hr + outline, hy + hr + outline], fill=TEAL_DARK)
    draw.ellipse([cx - hr, hy - hr, cx + hr, hy + hr], fill=SKIN)
    # Hair: a cap over the top of the head.
    draw.chord([cx - hr, hy - hr, cx + hr, hy + hr * 0.9], 180, 360, fill=HAIR)
    # Eyes and smile.
    er = s * 0.028
    for dx in (-0.085, 0.085):
        ex, ey = cx + s * dx, hy + s * 0.03
        draw.ellipse([ex - er, ey - er, ex + er, ey + er], fill=TEAL_DARK)
    sm = s * 0.11
    draw.arc([cx - sm, hy - sm * 0.2, cx + sm, hy + sm * 1.2], 20, 160, fill=TEAL_DARK, width=int(s * 0.03))


def scene(draw: ImageDraw.ImageDraw, ox: float, oy: float, size: float, bottom: float) -> None:
    """Clock behind, worker in front, laid out in the square (ox, oy, size)."""
    clock(draw, ox + size * 0.40, oy + size * 0.40, size * 0.34)
    person(draw, ox + size * 0.70, oy + size * 0.46, size * 0.56, bottom)


def save(img: Image.Image, name: str) -> None:
    img.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, name))


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    # Full icon (iOS, Windows, legacy Android): teal background.
    full = Image.new("RGBA", (N, N), TEAL + (255,))
    scene(ImageDraw.Draw(full), N * 0.06, N * 0.06, N * 0.88, N)
    save(full.convert("RGB"), "icon.png")
    # Android adaptive foreground (no inset): the scene sits in the central
    # safe zone; the worker's shoulders run to the bottom edge.
    fg = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    scene(ImageDraw.Draw(fg), N * 0.19, N * 0.19, N * 0.62, N)
    save(fg, "icon_foreground.png")
    # macOS: rounded square with margin; the scene is clipped to it.
    m = N * 0.1
    tile = Image.new("RGBA", (N, N), TEAL + (255,))
    scene(ImageDraw.Draw(tile), m + N * 0.05, m + N * 0.05, N - 2 * m - N * 0.1, N - m)
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle([m, m, N - m, N - m], radius=N * 0.18, fill=255)
    mac = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    mac.paste(tile, (0, 0), mask)
    save(mac, "icon_macos.png")


if __name__ == "__main__":
    main()
