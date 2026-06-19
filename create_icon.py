#!/usr/bin/env python3
"""
Modern macOS app icon for MovieTagger — a clapperboard on a cinematic gradient.

Design goals (fixes the old near-black-on-near-black icon):
  * Vibrant blue -> indigo gradient so the board actually pops.
  * Proper macOS icon geometry: rounded "squircle" inset with a soft dock shadow.
  * High-contrast slate board with crisp white clapper stripes — reads at 16px.
  * 2x supersampling for smooth, antialiased edges.

Run with a Python that has Pillow + numpy, e.g.:
    /opt/homebrew/bin/python3.11 create_icon.py
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
SS = 2                      # supersampling factor
BASE = 1024                 # final master size
S = BASE * SS               # working resolution

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(
    SCRIPT_DIR, "MovieTagger", "Assets.xcassets", "AppIcon.appiconset"
)

# Cinematic gradient palette (RGB)
COLOR_TL = (104, 130, 255)  # vivid periwinkle blue (top-left, brightest)
COLOR_BR = (40, 28, 90)     # deep indigo (bottom-right)
GLOW = (48, 46, 70)         # additive radial light near top-left

# Clapboard palette
BODY = (36, 39, 51)         # board body — dark slate, not pure black
BAR = (20, 22, 31)          # fixed jaw + clapper arm base (darker)
STRIPE = (247, 248, 252)    # clapper stripes — crisp off-white
INK = (208, 214, 230)       # the "scene/take" text lines on the board
ACCENT = (60, 124, 248)     # brand-blue hinge accent


def f(v):
    """Fraction of the full canvas -> working-resolution pixels (float)."""
    return v * S


def lerp(a, b, t):
    return a + (b - a) * t


def rotate(points, angle, ox, oy):
    """Rotate (x, y) points around (ox, oy) by angle radians."""
    out = []
    ca, sa = math.cos(angle), math.sin(angle)
    for x, y in points:
        dx, dy = x - ox, y - oy
        out.append((dx * ca - dy * sa + ox, dx * sa + dy * ca + oy))
    return out


# ---------------------------------------------------------------------------
# Background: gradient + radial glow, clipped to a squircle, with dock shadow
# ---------------------------------------------------------------------------
def build_background():
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    nx, ny = xx / (S - 1), yy / (S - 1)

    # Diagonal gradient (top-left bright -> bottom-right deep)
    t = (nx + ny) * 0.5
    grad = (
        np.array(COLOR_TL, np.float32)[None, None, :] * (1 - t)[..., None]
        + np.array(COLOR_BR, np.float32)[None, None, :] * t[..., None]
    )

    # Soft radial light from the upper-left, like a lamp on glass
    d2 = (nx - 0.30) ** 2 + (ny - 0.24) ** 2
    glow = np.exp(-d2 / (2 * 0.34 ** 2))[..., None] * np.array(GLOW, np.float32)
    grad = np.clip(grad + glow, 0, 255).astype(np.uint8)

    rgba = np.dstack([grad, np.full((S, S), 255, np.uint8)])
    bg = Image.fromarray(rgba, "RGBA")

    # Squircle (superellipse) icon silhouette, inset to macOS-style margins
    half = S / 2.0
    a = half * 0.805            # content ~824/1024 of canvas
    n = 5.0
    dx = (xx - half) / a
    dy = (yy - half) / a
    inside = (np.abs(dx) ** n + np.abs(dy) ** n) <= 1.0
    mask = Image.fromarray((inside * 255).astype(np.uint8), "L")
    mask = mask.filter(ImageFilter.GaussianBlur(SS * 0.6))  # smooth the edge

    # Compose: dock shadow first, then the masked icon
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 120), mask=mask)
    shadow = shadow.filter(ImageFilter.GaussianBlur(SS * 13))
    shadow = Image.eval(shadow, lambda p: p)  # no-op keeps types tidy
    canvas = Image.alpha_composite(
        canvas, _offset(shadow, 0, int(SS * 14))
    )

    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    icon.paste(bg, mask=mask)
    canvas = Image.alpha_composite(canvas, icon)
    return canvas, mask


def _offset(img, dx, dy):
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (dx, dy))
    return out


def soft_shadow(draw_fn, blur, alpha, dx, dy):
    """Render a shape (via draw_fn) as a blurred drop shadow layer."""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(layer))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    if alpha != 255:
        layer = Image.eval(layer.getchannel("A"), lambda p: int(p * alpha / 255))
        a = layer
        layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        layer.putalpha(a)
    return _offset(layer, dx, dy)


# ---------------------------------------------------------------------------
# Clapboard
# ---------------------------------------------------------------------------
def diagonal_stripes(region_mask, x0, x1, y_top, y_bot, stripe_w, slant):
    """White diagonal stripes filling a region, clipped by region_mask."""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x = x0 - stripe_w * 3
    light = True
    while x < x1 + stripe_w * 3:
        if light:
            d.polygon(
                [
                    (x, y_bot),
                    (x + stripe_w, y_bot),
                    (x + stripe_w + slant, y_top),
                    (x + slant, y_top),
                ],
                fill=STRIPE + (255,),
            )
        x += stripe_w
        light = not light
    clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    clipped.paste(layer, mask=region_mask)
    return clipped


def build_board(canvas):
    cr = int(f(0.024))
    left, right = f(0.246), f(0.754)
    jaw_top, jaw_bot = f(0.451), f(0.534)
    bot = f(0.773)
    width = right - left

    # --- board drop shadow ---
    canvas = Image.alpha_composite(
        canvas,
        soft_shadow(
            lambda d: d.rounded_rectangle([left, jaw_top, right, bot], cr, fill=(0, 0, 0, 200)),
            blur=SS * 11, alpha=150, dx=0, dy=int(SS * 9),
        ),
    )

    board = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bd = ImageDraw.Draw(board)

    # --- body ---
    bd.rounded_rectangle([left, jaw_top, right, bot], cr, fill=BODY + (255,))

    # top sheen on the body (glass light)
    sheen_h = (bot - jaw_bot) * 0.45
    for y in range(int(jaw_bot), int(jaw_bot + sheen_h)):
        a = int(34 * (1 - (y - jaw_bot) / sheen_h) ** 2)
        bd.line([(left + cr, y), (right - cr, y)], fill=(255, 255, 255, a))

    # "scene / take" text lines
    tl_x = left + width * 0.09
    tr_x = right - width * 0.09
    t0 = jaw_bot + (bot - jaw_bot) * 0.20
    gap = (bot - jaw_bot) * 0.135
    for i, (wf, lw) in enumerate(
        [(0.55, 4), (0.92, 3), (0.74, 3), (0.84, 3), (0.62, 3)]
    ):
        ly = t0 + i * gap
        bd.line(
            [(tl_x, ly), (tl_x + (tr_x - tl_x) * wf, ly)],
            fill=INK + (70,), width=int(lw * SS / 2 + 1),
        )

    # --- fixed jaw (top bar of the board) with slanted stripes ---
    bd.rectangle([left, jaw_top, right, jaw_bot], fill=BAR + (255,))
    jaw_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(jaw_mask).rectangle([left, jaw_top, right, jaw_bot], fill=255)
    stripes = diagonal_stripes(
        jaw_mask, left, right, jaw_top, jaw_bot,
        stripe_w=f(0.044), slant=(jaw_bot - jaw_top),
    )
    board = Image.alpha_composite(board, stripes)

    # divider + crisp top edge highlight
    ImageDraw.Draw(board).line(
        [(left, jaw_bot), (right, jaw_bot)], fill=(0, 0, 0, 90), width=int(SS)
    )
    ImageDraw.Draw(board).line(
        [(left + cr, jaw_top + 1), (right - cr, jaw_top + 1)],
        fill=(255, 255, 255, 26), width=int(SS),
    )
    canvas = Image.alpha_composite(canvas, board)

    # --- clapper arm (open) ---
    hinge_x, hinge_y = left + width * 0.015, jaw_bot
    arm_len = width * 1.0
    arm_th = (jaw_bot - jaw_top)
    angle = math.radians(-23)

    corners = rotate(
        [
            (hinge_x, hinge_y - arm_th),
            (hinge_x + arm_len, hinge_y - arm_th),
            (hinge_x + arm_len, hinge_y),
            (hinge_x, hinge_y),
        ],
        angle, hinge_x, hinge_y,
    )

    # arm shadow
    canvas = Image.alpha_composite(
        canvas,
        soft_shadow(
            lambda d: d.polygon(corners, fill=(0, 0, 0, 170)),
            blur=SS * 8, alpha=130, dx=int(SS * 2), dy=int(SS * 6),
        ),
    )

    arm = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(arm).polygon(corners, fill=BAR + (255,))

    arm_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(arm_mask).polygon(corners, fill=255)

    # stripes along the arm (perpendicular bands)
    bl, br = corners[3], corners[2]   # bottom edge
    tl_, tr_ = corners[0], corners[1] # top edge
    edge = math.hypot(br[0] - bl[0], br[1] - bl[1])
    stripe_w = f(0.044)
    shift = stripe_w  # parallelogram slant fraction
    stripe_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(stripe_layer)
    n = int(edge / stripe_w) + 6
    for sidx in range(-3, n):
        if sidx % 2:
            continue
        t1, t2 = sidx * stripe_w / edge, (sidx + 1) * stripe_w / edge
        ds = shift / edge
        p_b1 = (lerp(bl[0], br[0], t1), lerp(bl[1], br[1], t1))
        p_b2 = (lerp(bl[0], br[0], t2), lerp(bl[1], br[1], t2))
        p_t1 = (lerp(tl_[0], tr_[0], t1 + ds), lerp(tl_[1], tr_[1], t1 + ds))
        p_t2 = (lerp(tl_[0], tr_[0], t2 + ds), lerp(tl_[1], tr_[1], t2 + ds))
        sd.polygon([p_b1, p_b2, p_t2, p_t1], fill=STRIPE + (255,))
    clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    clipped.paste(stripe_layer, mask=arm_mask)
    arm = Image.alpha_composite(arm, clipped)

    # bright highlight along the arm's top edge (glass)
    hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hl)
    for k in range(int(SS * 3)):
        fr = (k + 1) * 0.012
        a0 = (lerp(tl_[0], bl[0], fr), lerp(tl_[1], bl[1], fr))
        a1 = (lerp(tr_[0], br[0], fr), lerp(tr_[1], br[1], fr))
        hd.line([a0, a1], fill=(255, 255, 255, int(50 * (1 - k / (SS * 3)))), width=int(SS))
    hl_clip = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    hl_clip.paste(hl, mask=arm_mask)
    arm = Image.alpha_composite(arm, hl_clip)
    canvas = Image.alpha_composite(canvas, arm)

    # --- blue hinge accent ---
    hd_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    hr = f(0.018)
    ImageDraw.Draw(hd_layer).ellipse(
        [hinge_x - hr, hinge_y - hr, hinge_x + hr, hinge_y + hr],
        fill=ACCENT + (255,),
    )
    ImageDraw.Draw(hd_layer).ellipse(
        [hinge_x - hr * 0.4, hinge_y - hr * 0.55,
         hinge_x + hr * 0.4, hinge_y + hr * 0.05],
        fill=(150, 195, 255, 200),
    )
    canvas = Image.alpha_composite(canvas, hd_layer)
    return canvas


# ---------------------------------------------------------------------------
# Top specular sheen across the whole icon
# ---------------------------------------------------------------------------
def add_gloss(canvas, mask):
    gloss = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gloss)
    top, bottom = f(0.07), f(0.46)
    for y in range(int(top), int(bottom)):
        t = (y - top) / (bottom - top)
        a = int(12 * (1 - t) ** 2.5)
        x_l = f(0.12) + f(0.13) * t
        x_r = f(0.88) - f(0.18) * t
        gd.line([(x_l, y), (x_r, y)], fill=(255, 255, 255, a))
    clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    clipped.paste(gloss, mask=mask)
    return Image.alpha_composite(canvas, clipped)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("Rendering MovieTagger clapperboard icon (cinematic edition)...")
    canvas, mask = build_background()
    print("  board + clapper...")
    canvas = build_board(canvas)
    canvas = add_gloss(canvas, mask)

    # `canvas` already holds the masked icon content plus the dock shadow that
    # lives outside the squircle, so it is the finished full-res image.
    final = canvas
    master = final.resize((BASE, BASE), Image.LANCZOS)

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    master.save(os.path.join(OUTPUT_DIR, "icon_1024x1024.png"), "PNG")

    sizes = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]
    for fname, sz in sizes:
        final.resize((sz, sz), Image.LANCZOS).save(
            os.path.join(OUTPUT_DIR, fname), "PNG"
        )
    print(f"Done -> {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
