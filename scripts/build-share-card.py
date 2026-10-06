#!/usr/bin/env python3
"""Regenerate assets/images/share-card.png, the 1200x630 link-preview card.

    python3 scripts/build-share-card.py            # write the PNG
    python3 scripts/build-share-card.py --check    # exit 1 if the PNG is stale

The card is the site's blue gradient, the existing headshot
(assets/images/uploads/jodi-daniel.jpg) in a circle, and her name set in
Raleway Bold -- the same face and letter-spacing as the page's <h1>. It carries
the NAME ONLY, deliberately: the card is served while the site is gated
(site_live: false), when no role or marketing claim may ship (issue #26).

Needs Pillow (PIL). The font is scripts/share-card/Raleway-Variable.ttf (SIL
OFL, license beside it); `scripts/` is excluded from the Jekyll build, so
neither the font nor this script is published. Output is deterministic for a
given Pillow/FreeType; if a different version moves a pixel, rerun this and
commit the PNG.

NOT /admin-editable: the name (NAME_LINES) and the headshot path are baked into
this script, and the PNG is a committed file. Changing her name or swapping the
photo in /admin does NOT update the card; a developer has to edit this script (if
the name changed), rerun it, and commit the PNG.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
HEADSHOT = os.path.join(ROOT, "assets", "images", "uploads", "jodi-daniel.jpg")
FONT = os.path.join(ROOT, "scripts", "share-card", "Raleway-Variable.ttf")
OUT = os.path.join(ROOT, "assets", "images", "share-card.png")

W, H = 1200, 630
SS = 2  # draw at 2x, then downsample, for smooth circle and text edges

# Stops copied from assets/css/jodidaniel.css (body background, 135deg).
GRADIENT = [(0.00, (0x1A, 0x3A, 0x5C)), (0.25, (0x2D, 0x5A, 0x7B)), (0.50, (0x3D, 0x7A, 0x9C)),
            (0.75, (0x4A, 0x8D, 0xAD)), (1.00, (0x5B, 0xA0, 0xBE))]
ACCENT = (0x5D, 0xD9, 0xE8)
WHITE = (255, 255, 255)
NAME_LINES = ("JODI", "DANIEL")
NAME_SIZE = 118   # px at 1x
TRACKING = 0.10   # em, like `header h1 { letter-spacing }`


def gradient(w, h):
    """135deg CSS-style linear gradient (corner to corner)."""
    img = Image.new("RGB", (w, h))
    px = img.load()
    # CSS 135deg: direction vector (1,1)/sqrt2; gradient line length = w*sin+h*cos.
    length = (w + h) / 2 ** 0.5
    for y in range(h):
        for x in range(w):
            t = ((x - w / 2) + (y - h / 2)) / 2 ** 0.5 / length + 0.5
            t = min(1.0, max(0.0, t))
            for (a, ca), (b, cb) in zip(GRADIENT, GRADIENT[1:]):
                if t <= b:
                    f = (t - a) / (b - a)
                    px[x, y] = tuple(round(ca[i] + (cb[i] - ca[i]) * f) for i in range(3))
                    break
    return img


def tracked_width(font, text, tracking_px):
    return sum(font.getlength(c) for c in text) + tracking_px * (len(text) - 1)


def draw_tracked(draw, xy, text, font, fill, tracking_px):
    x, y = xy
    for c in text:
        draw.text((x, y), c, font=font, fill=fill)
        x += font.getlength(c) + tracking_px


def render():
    w, h = W * SS, H * SS
    img = gradient(w, h)
    draw = ImageDraw.Draw(img)

    # Headshot: circle with a white ring, vertically centered on the left.
    d = 400 * SS
    cx, cy = 300 * SS, h // 2
    ring = 10 * SS
    draw.ellipse((cx - d // 2 - ring, cy - d // 2 - ring, cx + d // 2 + ring, cy + d // 2 + ring), fill=WHITE)
    shot = Image.open(HEADSHOT).convert("RGB").resize((d, d), Image.LANCZOS)
    mask = Image.new("L", (d * 4, d * 4), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, d * 4 - 1, d * 4 - 1), fill=255)
    mask = mask.resize((d, d), Image.LANCZOS)
    img.paste(shot, (cx - d // 2, cy - d // 2), mask)

    # Name, stacked, left-aligned at x=600, with an accent rule underneath.
    font = ImageFont.truetype(FONT, NAME_SIZE * SS)
    font.set_variation_by_axes([700])
    tracking = TRACKING * NAME_SIZE * SS
    ascent, descent = font.getmetrics()
    line_h = int((ascent + descent) * 0.92)
    block_h = line_h * len(NAME_LINES)
    rule_gap, rule_h = 34 * SS, 6 * SS
    top = (h - (block_h + rule_gap + rule_h)) // 2
    x = 600 * SS
    for i, line in enumerate(NAME_LINES):
        draw_tracked(draw, (x, top + i * line_h), line, font, WHITE, tracking)
    rule_w = int(tracked_width(font, NAME_LINES[-1], tracking))
    ry = top + block_h + rule_gap
    draw.rectangle((x, ry, x + rule_w, ry + rule_h), fill=ACCENT)

    return img.resize((W, H), Image.LANCZOS)


def main():
    img = render()
    if "--check" in sys.argv:
        from io import BytesIO
        buf = BytesIO()
        img.save(buf, "PNG", optimize=True)
        with open(OUT, "rb") as f:
            same = f.read() == buf.getvalue()
        print("share-card.png is current" if same else "share-card.png is STALE: run scripts/build-share-card.py")
        sys.exit(0 if same else 1)
    img.save(OUT, "PNG", optimize=True)
    print(f"wrote {os.path.relpath(OUT, ROOT)} ({os.path.getsize(OUT)} bytes)")


if __name__ == "__main__":
    main()
