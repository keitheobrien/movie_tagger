#!/usr/bin/env python3
"""
Modern macOS app icon for MovieTagger — clapboard v3.
Darker background, no sparkles, thicker clapper arm, blue tag.
"""

from PIL import Image, ImageDraw, ImageFilter
import math
import os

SIZE = 1024
OUTPUT_DIR = "/Users/kobrien/Library/CloudStorage/OneDrive-Personal/git_repo/movie_tagger/MovieTagger/Assets.xcassets/AppIcon.appiconset"


def create_squircle_mask(size):
    mask = Image.new('L', (size, size), 0)
    half = size / 2
    a = half * 0.92
    n = 4.5
    for y in range(size):
        for x in range(size):
            dx = (x - half) / a
            dy = (y - half) / a
            if abs(dx)**n + abs(dy)**n <= 1.0:
                mask.putpixel((x, y), 255)
    mask = mask.filter(ImageFilter.GaussianBlur(1.5))
    mask = mask.point(lambda p: 255 if p > 128 else 0)
    mask = mask.filter(ImageFilter.GaussianBlur(0.8))
    return mask


def lerp(a, b, t):
    return a + (b - a) * t


def main():
    print("Creating MovieTagger clapboard icon v3...")

    mask = create_squircle_mask(SIZE)

    # ===== BACKGROUND — very dark, almost black =====
    canvas = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    for y in range(SIZE):
        for x in range(SIZE):
            tx, ty = x / SIZE, y / SIZE
            dist = math.sqrt((tx - 0.5)**2 + (ty - 0.50)**2) / 0.7
            dist = min(dist, 1.0)
            r = int(lerp(38, 22, dist))
            g = int(lerp(38, 22, dist))
            b = int(lerp(42, 25, dist))
            canvas.putpixel((x, y), (r, g, b, 255))

    # ===== CLAPBOARD BODY =====
    print("  Board body...")

    board_left = int(SIZE * 0.17)
    board_right = int(SIZE * 0.83)
    board_top = int(SIZE * 0.46)
    board_bottom = int(SIZE * 0.87)
    board_w = board_right - board_left
    board_h = board_bottom - board_top
    corner_r = int(SIZE * 0.015)

    # Lower jaw stripe section at top of board — matches arm thickness
    jaw_h = int(SIZE * 0.075)
    jaw_top = board_top
    jaw_bottom = board_top + jaw_h

    # Shadow
    shadow = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [board_left + 5, board_top + 7, board_right + 5, board_bottom + 7],
        radius=corner_r, fill=(0, 0, 0, 120)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    canvas = Image.alpha_composite(canvas, shadow)

    board = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    bd = ImageDraw.Draw(board)

    # Main board
    bd.rounded_rectangle(
        [board_left, board_top, board_right, board_bottom],
        radius=corner_r, fill=(35, 38, 48, 248)
    )

    # Subtle gradient
    for y in range(board_top + corner_r, board_bottom - corner_r):
        t = (y - board_top) / board_h
        alpha = int(8 * (1 - t))
        bd.line([(board_left + 4, y), (board_right - 4, y)],
                fill=(255, 255, 255, alpha))

    # Lower jaw — matches clapper arm exactly
    hinge_x_preview = board_left + int(board_w * 0.04)
    jaw_left = hinge_x_preview
    jaw_right = hinge_x_preview + int(board_w * 0.96)
    stripe_w = int(SIZE * 0.042)

    # Draw jaw background
    bd.rectangle([jaw_left, jaw_top, jaw_right, jaw_bottom], fill=(28, 32, 40, 252))

    # Draw diagonal stripes on jaw
    x = jaw_left - jaw_h * 2
    is_light = False
    while x < jaw_right + jaw_h:
        if is_light:
            poly = [
                (x, jaw_bottom),
                (x + stripe_w, jaw_bottom),
                (x + stripe_w + jaw_h * 1.0, jaw_top),
                (x + jaw_h * 1.0, jaw_top),
            ]
            bd.polygon(poly, fill=(190, 200, 220, 215))
        x += stripe_w
        is_light = not is_light

    # Clip stripes to jaw bounds
    bd.rectangle([0, jaw_top, jaw_left - 1, jaw_bottom], fill=(0, 0, 0, 0))
    bd.rectangle([jaw_right + 1, jaw_top, SIZE, jaw_bottom], fill=(0, 0, 0, 0))

    # Jaw outline
    bd.rectangle([jaw_left, jaw_top, jaw_right, jaw_bottom], outline=(70, 76, 95, 160))

    # Re-draw board body below jaw
    bd.rounded_rectangle(
        [board_left, jaw_bottom, board_right, board_bottom],
        radius=corner_r, fill=(35, 38, 48, 248)
    )
    for y in range(jaw_bottom, board_bottom - corner_r):
        t = (y - board_top) / board_h
        alpha = int(8 * (1 - t))
        bd.line([(board_left + 4, y), (board_right - 4, y)],
                fill=(255, 255, 255, alpha))

    # Divider line
    bd.line([(board_left, jaw_bottom), (board_right, jaw_bottom)],
            fill=(55, 60, 75, 160), width=2)

    # Board border
    bd.rounded_rectangle(
        [board_left, jaw_bottom, board_right, board_bottom],
        radius=corner_r, outline=(60, 66, 82, 140), width=2
    )

    # Text lines
    text_area_top = jaw_bottom + int(board_h * 0.06)
    text_left = board_left + int(board_w * 0.07)
    text_right = board_right - int(board_w * 0.07)
    line_spacing = int((board_bottom - text_area_top - board_h * 0.08) / 6)

    for i, (wf, lw) in enumerate([
        (0.50, 3), (0.90, 2), (0.70, 2), (0.80, 2), (0.60, 2), (0.45, 2)
    ]):
        ly = text_area_top + i * line_spacing
        bd.line([(text_left, ly), (text_left + int((text_right - text_left) * wf), ly)],
                fill=(75, 82, 100, 75), width=lw)

    canvas = Image.alpha_composite(canvas, board)

    # ===== CLAPPER ARM =====
    print("  Clapper arm...")

    hinge_x = board_left + int(board_w * 0.04)
    hinge_y = board_top + int(SIZE * 0.005)

    arm_length = board_w * 0.96
    arm_thickness = int(SIZE * 0.075)

    arm_corners_local = [
        (0, -arm_thickness),
        (arm_length, -arm_thickness),
        (arm_length, 0),
        (0, 0),
    ]

    open_angle = math.radians(-28)

    arm_corners = []
    for lx, ly in arm_corners_local:
        rx = lx * math.cos(open_angle) - ly * math.sin(open_angle) + hinge_x
        ry = lx * math.sin(open_angle) + ly * math.cos(open_angle) + hinge_y
        arm_corners.append((rx, ry))

    # Shadow
    arm_shadow = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    sc = [(x + 4, y + 5) for x, y in arm_corners]
    ImageDraw.Draw(arm_shadow).polygon(sc, fill=(0, 0, 0, 90))
    arm_shadow = arm_shadow.filter(ImageFilter.GaussianBlur(10))
    canvas = Image.alpha_composite(canvas, arm_shadow)

    arm_layer = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    ad = ImageDraw.Draw(arm_layer)
    ad.polygon(arm_corners, fill=(28, 32, 40, 252))

    # Diagonal stripes
    stripe_layer = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    sld = ImageDraw.Draw(stripe_layer)

    bx1, by1 = arm_corners[3]
    bx2, by2 = arm_corners[2]
    tx1, ty1 = arm_corners[0]
    tx2, ty2 = arm_corners[1]

    edge_len = math.sqrt((bx2 - bx1)**2 + (by2 - by1)**2)

    for s in range(-3, int(edge_len / stripe_w) + 6):
        if s % 2 == 0:
            continue

        t1 = s * stripe_w / edge_len
        t2 = (s + 1) * stripe_w / edge_len
        diag_shift = 1.0 * stripe_w / edge_len

        p_b1 = (lerp(bx1, bx2, t1), lerp(by1, by2, t1))
        p_b2 = (lerp(bx1, bx2, t2), lerp(by1, by2, t2))
        p_t1 = (lerp(tx1, tx2, t1 + diag_shift), lerp(ty1, ty2, t1 + diag_shift))
        p_t2 = (lerp(tx1, tx2, t2 + diag_shift), lerp(ty1, ty2, t2 + diag_shift))

        sld.polygon([p_b1, p_b2, p_t2, p_t1], fill=(190, 200, 220, 215))

    # Mask stripes
    arm_mask = Image.new('L', (SIZE, SIZE), 0)
    ImageDraw.Draw(arm_mask).polygon(arm_corners, fill=255)
    stripes_masked = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    stripes_masked.paste(stripe_layer, mask=arm_mask)

    arm_layer = Image.alpha_composite(arm_layer, stripes_masked)

    # Arm outline
    ImageDraw.Draw(arm_layer).polygon(arm_corners, outline=(70, 76, 95, 160))

    canvas = Image.alpha_composite(canvas, arm_layer)

    # ===== BLUE TAG =====
    print("  Blue tag...")

    tag_w = int(SIZE * 0.10)
    tag_h = int(SIZE * 0.14)
    tag_cx = hinge_x + int(SIZE * 0.01)
    tag_top = hinge_y + int(SIZE * 0.06)

    tag_layer = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    td = ImageDraw.Draw(tag_layer)

    # String
    for i in range(19):
        t = i / 18
        sx = lerp(hinge_x, tag_cx, t)
        sy = lerp(hinge_y + int(SIZE * 0.018), tag_top, t) + math.sin(t * math.pi) * SIZE * 0.006
        t2 = (i + 1) / 18
        sx2 = lerp(hinge_x, tag_cx, t2)
        sy2 = lerp(hinge_y + int(SIZE * 0.018), tag_top, t2) + math.sin(t2 * math.pi) * SIZE * 0.006
        td.line([(int(sx), int(sy)), (int(sx2), int(sy2))],
                fill=(85, 140, 210, 140), width=2)

    # Tag shadow
    ts = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(ts).rounded_rectangle(
        [tag_cx - tag_w//2 + 3, tag_top + 4,
         tag_cx + tag_w//2 + 3, tag_top + tag_h + 4],
        radius=int(SIZE * 0.010), fill=(0, 0, 0, 60)
    )
    ts = ts.filter(ImageFilter.GaussianBlur(6))
    canvas = Image.alpha_composite(canvas, ts)

    tag_r = int(SIZE * 0.010)

    # Tag body
    td.rounded_rectangle(
        [tag_cx - tag_w//2, tag_top, tag_cx + tag_w//2, tag_top + tag_h],
        radius=tag_r, fill=(40, 105, 205, 200)
    )

    # Highlight
    td.rounded_rectangle(
        [tag_cx - tag_w//2 + 2, tag_top + 1,
         tag_cx + tag_w//2 - 2, tag_top + int(tag_h * 0.38)],
        radius=tag_r, fill=(75, 145, 235, 45)
    )

    # Border
    td.rounded_rectangle(
        [tag_cx - tag_w//2, tag_top, tag_cx + tag_w//2, tag_top + tag_h],
        radius=tag_r, outline=(65, 135, 230, 175), width=2
    )

    # Hole
    hole_r = int(SIZE * 0.009)
    hole_y = tag_top + int(tag_h * 0.14)
    td.ellipse([tag_cx - hole_r, hole_y - hole_r, tag_cx + hole_r, hole_y + hole_r],
               fill=(18, 55, 125, 210), outline=(65, 135, 230, 130), width=1)

    # Lines
    tlt = tag_top + int(tag_h * 0.33)
    tlx1 = tag_cx - tag_w//2 + int(tag_w * 0.15)
    tlx2 = tag_cx + tag_w//2 - int(tag_w * 0.15)
    for j in range(3):
        ly = tlt + j * int(tag_h * 0.17)
        shrink = int(tag_w * 0.12) if j == 2 else 0
        td.line([(tlx1, ly), (tlx2 - shrink, ly)],
                fill=(110, 175, 250, 70), width=1)

    canvas = Image.alpha_composite(canvas, tag_layer)

    # ===== APPLY MASK & SAVE =====
    print("  Saving...")
    result = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    result.paste(canvas, mask=mask)

    result.save(os.path.join(OUTPUT_DIR, "icon_1024x1024.png"), 'PNG')

    for fname, sz in [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]:
        result.resize((sz, sz), Image.LANCZOS).save(
            os.path.join(OUTPUT_DIR, fname), 'PNG')

    print("Done!")


if __name__ == '__main__':
    main()
