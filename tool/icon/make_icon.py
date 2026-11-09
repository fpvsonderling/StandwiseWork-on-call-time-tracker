"""Draws the Standwise app icon (a clock face: right half work, left half
standby) and writes the 1024 px source images used by flutter_launcher_icons.

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


def save(img: Image.Image, name: str) -> None:
    img.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, name))


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    # Full icon: teal background, clock filling ~70%.
    full = Image.new("RGBA", (N, N), TEAL + (255,))
    clock(ImageDraw.Draw(full), N / 2, N / 2, N * 0.35)
    save(full.convert("RGB"), "icon.png")
    # Android adaptive foreground: transparent; the launcher XML insets it by
    # 16%, which leaves the clock inside the 66% safe zone.
    fg = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    clock(ImageDraw.Draw(fg), N / 2, N / 2, N * 0.44)
    save(fg, "icon_foreground.png")
    # macOS: rounded square with margin, transparent corners.
    mac = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(mac)
    m = N * 0.1
    d.rounded_rectangle([m, m, N - m, N - m], radius=N * 0.18, fill=TEAL)
    clock(d, N / 2, N / 2, N * 0.28)
    save(mac, "icon_macos.png")


if __name__ == "__main__":
    main()
