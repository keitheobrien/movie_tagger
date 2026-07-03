#!/usr/bin/env python3
"""
MovieTagger macOS app icon — minimal flat clapperboard.

Direction: modern Apple system-app restraint (Final Cut / QuickTime level).
A single bold clapperboard glyph — barely-open jaw — in one flat near-white,
sitting on a subtle single-hue indigo-blue vertical gradient, clipped to a
macOS superellipse (squircle) with a soft dock shadow. No text, no tag,
no tiny details — reads clearly all the way down to 16px.

Run with a Python that has Pillow + numpy, e.g.:
    /opt/homebrew/bin/python3.11 create_icon.py
"""

import os

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
SS = 4                       # supersampling factor
BASE = 1024                  # final master size
S = BASE * SS                # working resolution

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(
    SCRIPT_DIR, "MovieTagger", "Assets.xcassets", "AppIcon.appiconset"
)

# Palette — 2 flat glyph tones on a single-hue gradient ---------------------
BG_TOP = (92, 118, 251)      # indigo-blue, lighter at top (light from above)
BG_BOT = (48, 60, 196)       # same hue, deeper at bottom
GLYPH = (250, 251, 255)      # flat near-white clapperboard

SQUIRCLE_HALF = 0.805        # half-width factor of canvas half-size
SQUIRCLE_N = 5.0             # superellipse exponent


def f(v):
    """Canvas fraction -> working pixels."""
    return v * S


# ---------------------------------------------------------------------------
# Squircle mask + background
# ---------------------------------------------------------------------------
def squircle_mask():
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    half = S / 2.0
    a = half * SQUIRCLE_HALF
    dx = np.abs(xx - half) / a
    dy = np.abs(yy - half) / a
    inside = (dx ** SQUIRCLE_N + dy ** SQUIRCLE_N) <= 1.0
    mask = Image.fromarray((inside * 255).astype(np.uint8), "L")
    return mask.filter(ImageFilter.GaussianBlur(SS * 0.5))


def background():
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    ny = yy / (S - 1)
    nx = xx / (S - 1)

    # Subtle vertical single-hue gradient.
    t = ny[..., None]
    grad = (
        np.array(BG_TOP, np.float32)[None, None, :] * (1 - t)
        + np.array(BG_BOT, np.float32)[None, None, :] * t
    )

    # Very faint top-center lift — a single overhead light source.
    d2 = (nx - 0.5) ** 2 + (ny - 0.10) ** 2
    lift = np.exp(-d2 / (2 * 0.45 ** 2))[..., None] * 12.0
    grad = np.clip(grad + lift, 0, 255).astype(np.uint8)

    rgba = np.dstack([grad, np.full((S, S), 255, np.uint8)])
    return Image.fromarray(rgba, "RGBA")


def offset(img, dx, dy):
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (int(dx), int(dy)))
    return out


# ---------------------------------------------------------------------------
# Clapperboard glyph — one flat color, barely-open jaw
# ---------------------------------------------------------------------------
def build_glyph():
    """Returns an RGBA layer with the flat white clapperboard, centered."""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # Geometry (canvas fractions)
    left, right = f(0.250), f(0.750)
    body_top, body_bot = f(0.478), f(0.742)
    body_r = f(0.030)

    jaw_h = f(0.100)
    gap = f(0.014)                 # hinge-side mouth gap
    jaw_bot = body_top - gap
    jaw_top = jaw_bot - jaw_h
    jaw_r = f(0.026)
    open_deg = 8.0                 # barely open

    # --- body: plain flat rounded rectangle, nothing on it ---
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle([left, body_top, right, body_bot], body_r,
                        fill=GLYPH + (255,))

    # --- jaw: rounded bar with 3 diagonal notches, rotated slightly open ---
    jaw = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    jd = ImageDraw.Draw(jaw)
    jd.rounded_rectangle([left, jaw_top, right, jaw_bot], jaw_r,
                         fill=GLYPH + (255,))

    # Diagonal notches (background shows through) — the clapper stripes.
    notches = Image.new("L", (S, S), 0)
    nd = ImageDraw.Draw(notches)
    slant = jaw_h * 0.55
    notch_w = f(0.047)
    n_notch = 3
    inner_l = left + f(0.062)      # keep the hinge end solid
    inner_r = right - f(0.040)
    span = inner_r - inner_l - slant
    seg = (span - n_notch * notch_w) / (n_notch + 1)   # white segment width
    x = inner_l + seg
    for _ in range(n_notch):
        nd.polygon(
            [
                (x, jaw_bot + 2),
                (x + notch_w, jaw_bot + 2),
                (x + notch_w + slant, jaw_top - 2),
                (x + slant, jaw_top - 2),
            ],
            fill=255,
        )
        x += notch_w + seg
    jaw.putalpha(ImageChops.subtract(jaw.getchannel("A"), notches))

    # Rotate the jaw open around the hinge (bottom-left of the bar).
    hinge = (left + jaw_r, jaw_bot)
    jaw = jaw.rotate(open_deg, resample=Image.BICUBIC, center=hinge)

    layer = Image.alpha_composite(layer, jaw)
    return layer


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("Rendering MovieTagger minimal-flat icon...")
    mask = squircle_mask()
    bg = background()

    # Squircle tile (background clipped to squircle)
    tile = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    tile.paste(bg, mask=mask)

    # Glyph + a whisper of a shadow (one light source, from above)
    glyph = build_glyph()
    g_shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    g_shadow.putalpha(
        glyph.getchannel("A")
        .filter(ImageFilter.GaussianBlur(SS * 7))
        .point(lambda p: int(p * 0.20))
    )
    tile = Image.alpha_composite(tile, offset(g_shadow, 0, SS * 9))
    tile = Image.alpha_composite(tile, glyph)

    # Re-clip so nothing escapes the squircle
    clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    clipped.paste(tile, mask=mask)

    # Dock shadow beneath the squircle
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dock = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dock.paste((0, 0, 0, 110), mask=mask)
    dock = dock.filter(ImageFilter.GaussianBlur(SS * 12))
    canvas = Image.alpha_composite(canvas, offset(dock, 0, SS * 13))
    canvas = Image.alpha_composite(canvas, clipped)

    # Downsample into every asset-catalog size
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    sizes = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
        ("icon_1024x1024.png", 1024),
    ]
    for fname, sz in sizes:
        canvas.resize((sz, sz), Image.LANCZOS).save(
            os.path.join(OUTPUT_DIR, fname), "PNG"
        )
    print(f"Done -> {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
