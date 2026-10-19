#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Maurin Rasi
#
# Renders the Juno Island brand assets that Tools/MakeIcon.swift consumes:
#   Resources/Brand/AppIcon-Default.png  (1024x1024 finished app icon)
#   Resources/Brand/logo.png             (black-on-transparent mark, ~2:1,
#                                         menu bar glyph + in-app BrandMark)
# Needs Pillow. Run from the repository root:  python3 Tools/make-brand-assets.py
from PIL import Image, ImageDraw, ImageFilter
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRAND = os.path.join(ROOT, "Resources", "Brand")
os.makedirs(BRAND, exist_ok=True)

SS = 4  # supersampling factor for smooth edges


def radial_glow(size, center, radius, color, strength):
    """A soft radial glow layer (RGBA) centred at `center`."""
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    glow = Image.new("L", size, 0)
    d = ImageDraw.Draw(glow)
    cx, cy = center
    d.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=255)
    glow = glow.filter(ImageFilter.GaussianBlur(radius * 0.55))
    glow = glow.point(lambda v: int(v * strength))
    layer.putalpha(glow)
    solid = Image.new("RGBA", size, color + (255,))
    solid.putalpha(glow)
    return solid


def make_app_icon(path):
    N = 1024 * SS
    canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))

    # macOS icon grid: the plate is 824pt in a 1024pt canvas.
    margin = 100 * SS
    plate = [margin, margin, N - margin, N - margin]
    radius = 186 * SS

    # Soft drop shadow under the plate.
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle([p + (0 if i % 2 == 0 else 14 * SS) for i, p in enumerate(plate)],
                         radius=radius, fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(22 * SS))
    canvas.alpha_composite(shadow)

    # Plate: vertical night gradient.
    top = (34, 36, 64)
    bottom = (10, 10, 20)
    grad = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    for y in range(plate[1], plate[3]):
        t = (y - plate[1]) / (plate[3] - plate[1])
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        gd.line([(plate[0], y), (plate[2], y)], fill=c + (255,))
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle(plate, radius=radius, fill=255)
    grad.putalpha(mask)
    canvas.alpha_composite(grad)

    # Indigo glow behind the island, clipped to the plate.
    glow = radial_glow((N, N), (N // 2, int(N * 0.46)), int(N * 0.30), (96, 84, 220), 0.55)
    glow.putalpha(Image.composite(glow.getchannel("A"), Image.new("L", (N, N), 0), mask))
    canvas.alpha_composite(glow)

    # Top edge highlight (light catching the material).
    hl = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hl)
    hd.rounded_rectangle(plate, radius=radius, outline=(255, 255, 255, 46), width=6 * SS)
    hl_mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(hl_mask).rectangle([0, 0, N, plate[1] + 260 * SS], fill=255)
    hl_mask = hl_mask.filter(ImageFilter.GaussianBlur(120 * SS))
    hl.putalpha(Image.composite(hl.getchannel("A"), Image.new("L", (N, N), 0), hl_mask))
    canvas.alpha_composite(hl)

    # The island: a black pill with a thin inner rim.
    pw, ph = 560 * SS, 164 * SS
    px, py = (N - pw) // 2, int(N * 0.46) - ph // 2
    pill = [px, py, px + pw, py + ph]
    island = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    idr = ImageDraw.Draw(island)
    idr.rounded_rectangle([pill[0], pill[1] + 10 * SS, pill[2], pill[3] + 10 * SS],
                          radius=ph // 2, fill=(0, 0, 0, 90))
    island = island.filter(ImageFilter.GaussianBlur(10 * SS))
    canvas.alpha_composite(island)
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle(pill, radius=ph // 2, fill=(6, 6, 10, 255), outline=(255, 255, 255, 38), width=3 * SS)

    # Inside: a glowing mint orb (Juno) and a typing line (the pad).
    orb_r = 44 * SS
    ocx, ocy = pill[0] + 96 * SS, (pill[1] + pill[3]) // 2
    orb_glow = radial_glow((N, N), (ocx, ocy), orb_r * 2.6, (92, 232, 190), 0.9)
    canvas.alpha_composite(orb_glow)
    d = ImageDraw.Draw(canvas)
    d.ellipse([ocx - orb_r, ocy - orb_r, ocx + orb_r, ocy + orb_r], fill=(120, 244, 206, 255))
    d.ellipse([ocx - orb_r * 0.55, ocy - orb_r * 0.7, ocx + orb_r * 0.1, ocy - orb_r * 0.05],
              fill=(236, 255, 248, 180))
    line_h = 30 * SS
    lx0 = ocx + orb_r + 56 * SS
    lx1 = pill[2] - 150 * SS
    d.rounded_rectangle([lx0, ocy - line_h // 2, lx1, ocy + line_h // 2],
                        radius=line_h // 2, fill=(170, 172, 196, 255))
    cur_w = 14 * SS
    cx0 = lx1 + 40 * SS
    d.rounded_rectangle([cx0, ocy - 44 * SS, cx0 + cur_w, ocy + 44 * SS],
                        radius=cur_w // 2, fill=(255, 255, 255, 235))

    out = canvas.resize((1024, 1024), Image.LANCZOS)
    out.save(path, "PNG")


def make_logo(path):
    # ~2:1 mark, black on transparent: a pill outline with the orb and a bar.
    W, H = 1024 * SS, 520 * SS
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    stroke = 92 * SS
    pad = stroke // 2 + 8 * SS
    pill = [pad, pad, W - pad, H - pad]
    d.rounded_rectangle(pill, radius=(H - 2 * pad) // 2, outline=(0, 0, 0, 255), width=stroke)
    cy = H // 2
    orb_r = 86 * SS
    ocx = pill[0] + 250 * SS
    d.ellipse([ocx - orb_r, cy - orb_r, ocx + orb_r, cy + orb_r], fill=(0, 0, 0, 255))
    bar_h = 72 * SS
    bx0 = ocx + orb_r + 96 * SS
    bx1 = pill[2] - 230 * SS
    d.rounded_rectangle([bx0, cy - bar_h // 2, bx1, cy + bar_h // 2], radius=bar_h // 2, fill=(0, 0, 0, 255))
    out = img.resize((1024, 520), Image.LANCZOS)
    out.save(path, "PNG")


make_app_icon(os.path.join(BRAND, "AppIcon-Default.png"))
make_logo(os.path.join(BRAND, "logo.png"))
print("brand assets written to", BRAND)
