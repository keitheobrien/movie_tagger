#!/usr/bin/env python3
"""
Modern macOS app icon for MovieTagger — clapboard with liquid glass.
macOS Tahoe liquid glass aesthetic: translucent layers, soft highlights,
edge glow, frosted depth.
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
    print("Creating MovieTagger clapboard icon — liquid glass edition...")

    mask = create_squircle_mask(SIZE)

    # ===== BACKGROUND =====
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

    jaw_h = int(SIZE * 0.075)
    jaw_top = board_top
    jaw_bottom = board_top + jaw_h

    # Shadow — deeper for glass effect
    shadow = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [board_left + 6, board_top + 8, board_right + 6, board_bottom + 8],
        radius=corner_r, fill=(0, 0, 0, 140)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    canvas = Image.alpha_composite(canvas, shadow)

    board = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    bd = ImageDraw.Draw(board)

    # Main board — slightly translucent so background shows through (glass feel)
    bd.rounded_rectangle(
        [board_left, board_top, board_right, board_bottom],
        radius=corner_r, fill=(3, 3, 5, 220)
    )

    # ---- Liquid glass: soft top-edge highlight on board body ----
    for y in range(jaw_bottom + 2, jaw_bottom + int(board_h * 0.15)):
        t = (y - jaw_bottom) / (board_h * 0.15)
        alpha = int(18 * (1 - t)**2)
        bd.line([(board_left + 6, y), (board_right - 6, y)],
                fill=(255, 255, 255, alpha))

    # ---- Liquid glass: subtle bottom inner glow ----
    for y in range(board_bottom - int(board_h * 0.08), board_bottom - 4):
        t = (y - (board_bottom - board_h * 0.08)) / (board_h * 0.08)
        alpha = int(6 * t)
        bd.line([(board_left + 6, y), (board_right - 6, y)],
                fill=(180, 200, 240, alpha))

    # Lower jaw
    hinge_x_preview = board_left + int(board_w * 0.04)
    jaw_left = hinge_x_preview
    jaw_right = hinge_x_preview + int(board_w * 0.96)
    stripe_w = int(SIZE * 0.042)

    bd.rectangle([jaw_left, jaw_top, jaw_right, jaw_bottom], fill=(5, 5, 8, 240))

    # Jaw stripes
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
            bd.polygon(poly, fill=(240, 240, 245, 250))
        x += stripe_w
        is_light = not is_light

    bd.rectangle([0, jaw_top, jaw_left - 1, jaw_bottom], fill=(0, 0, 0, 0))
    bd.rectangle([jaw_right + 1, jaw_top, SIZE, jaw_bottom], fill=(0, 0, 0, 0))
    bd.rectangle([jaw_left, jaw_top, jaw_right, jaw_bottom], outline=(70, 76, 95, 130))

    # Re-draw board body below jaw
    bd.rounded_rectangle(
        [board_left, jaw_bottom, board_right, board_bottom],
        radius=corner_r, fill=(3, 3, 5, 220)
    )

    # Re-apply the glass highlights on the body area
    for y in range(jaw_bottom + 2, jaw_bottom + int(board_h * 0.15)):
        t = (y - jaw_bottom) / (board_h * 0.15)
        alpha = int(18 * (1 - t)**2)
        bd.line([(board_left + 6, y), (board_right - 6, y)],
                fill=(255, 255, 255, alpha))

    for y in range(board_bottom - int(board_h * 0.08), board_bottom - 4):
        t = (y - (board_bottom - board_h * 0.08)) / (board_h * 0.08)
        alpha = int(6 * t)
        bd.line([(board_left + 6, y), (board_right - 6, y)],
                fill=(180, 200, 240, alpha))

    # Divider line
    bd.line([(board_left, jaw_bottom), (board_right, jaw_bottom)],
            fill=(55, 60, 75, 140), width=2)

    # ---- Liquid glass: glowing border (brighter top/left, dimmer bottom/right) ----
    # Top edge
    bd.line([(board_left + corner_r, jaw_bottom + 1), (board_right - corner_r, jaw_bottom + 1)],
            fill=(120, 130, 160, 50), width=1)
    # Left edge
    for y in range(jaw_bottom + corner_r, board_bottom - corner_r):
        t = (y - jaw_bottom) / (board_bottom - jaw_bottom)
        alpha = int(35 * (1 - t * 0.6))
        bd.point((board_left + 1, y), fill=(140, 155, 185, alpha))
    # Right edge — dimmer
    for y in range(jaw_bottom + corner_r, board_bottom - corner_r):
        t = (y - jaw_bottom) / (board_bottom - jaw_bottom)
        alpha = int(15 * (1 - t * 0.5))
        bd.point((board_right - 1, y), fill=(100, 115, 145, alpha))
    # Bottom edge — subtle
    bd.line([(board_left + corner_r, board_bottom - 1), (board_right - corner_r, board_bottom - 1)],
            fill=(80, 90, 120, 20), width=1)

    # Board outer border
    bd.rounded_rectangle(
        [board_left, jaw_bottom, board_right, board_bottom],
        radius=corner_r, outline=(50, 55, 70, 100), width=1
    )

    # Text lines — slightly brighter for glass contrast
    text_area_top = jaw_bottom + int(board_h * 0.06)
    text_left = board_left + int(board_w * 0.07)
    text_right = board_right - int(board_w * 0.07)
    line_spacing = int((board_bottom - text_area_top - board_h * 0.08) / 6)

    for i, (wf, lw) in enumerate([
        (0.50, 3), (0.90, 2), (0.70, 2), (0.80, 2), (0.60, 2), (0.45, 2)
    ]):
        ly = text_area_top + i * line_spacing
        bd.line([(text_left, ly), (text_left + int((text_right - text_left) * wf), ly)],
                fill=(55, 60, 75, 65), width=lw)

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

    # Arm shadow
    arm_shadow = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    sc = [(x + 5, y + 6) for x, y in arm_corners]
    ImageDraw.Draw(arm_shadow).polygon(sc, fill=(0, 0, 0, 100))
    arm_shadow = arm_shadow.filter(ImageFilter.GaussianBlur(12))
    canvas = Image.alpha_composite(canvas, arm_shadow)

    arm_layer = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    ad = ImageDraw.Draw(arm_layer)
    ad.polygon(arm_corners, fill=(5, 5, 8, 240))

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

        sld.polygon([p_b1, p_b2, p_t2, p_t1], fill=(240, 240, 245, 250))

    arm_mask = Image.new('L', (SIZE, SIZE), 0)
    ImageDraw.Draw(arm_mask).polygon(arm_corners, fill=255)
    stripes_masked = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    stripes_masked.paste(stripe_layer, mask=arm_mask)

    arm_layer = Image.alpha_composite(arm_layer, stripes_masked)

    # ---- Liquid glass on arm: highlight along top edge ----
    # Top edge of arm: arm_corners[0] to arm_corners[1]
    glass_arm = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    ga_draw = ImageDraw.Draw(glass_arm)

    # Draw a thin bright line along the top edge
    ax0, ay0 = arm_corners[0]
    ax1, ay1 = arm_corners[1]
    # Slightly inset
    for offset in range(3):
        # Interpolate a line parallel to top edge, offset inward
        bx0, by0 = arm_corners[3]
        bx1_, by1_ = arm_corners[2]
        frac = (offset + 1) * 0.04
        lx0 = lerp(ax0, bx0, frac)
        ly0 = lerp(ay0, by0, frac)
        lx1 = lerp(ax1, bx1_, frac)
        ly1 = lerp(ay1, by1_, frac)
        alpha = int(40 * (1 - offset / 3))
        ga_draw.line([(int(lx0), int(ly0)), (int(lx1), int(ly1))],
                     fill=(200, 215, 240, alpha), width=1)

    # Mask to arm shape
    glass_arm_masked = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    glass_arm_masked.paste(glass_arm, mask=arm_mask)
    arm_layer = Image.alpha_composite(arm_layer, glass_arm_masked)

    # Arm outline — subtle glass border
    ImageDraw.Draw(arm_layer).polygon(arm_corners, outline=(80, 88, 110, 120))

    canvas = Image.alpha_composite(canvas, arm_layer)

    # ===== LIQUID GLASS: Specular highlight across the whole icon =====
    print("  Liquid glass effects...")
    glass_layer = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))

    # Broad soft highlight from upper-left — like light hitting glass
    for y in range(int(SIZE * 0.06), int(SIZE * 0.45)):
        t = (y - SIZE * 0.06) / (SIZE * 0.39)
        alpha = int(10 * (1 - t)**2.5)
        # Narrowing highlight
        x_left = int(SIZE * 0.10 + SIZE * 0.15 * t)
        x_right = int(SIZE * 0.90 - SIZE * 0.20 * t)
        ImageDraw.Draw(glass_layer).line([(x_left, y), (x_right, y)],
                                         fill=(255, 255, 255, alpha))

    canvas = Image.alpha_composite(canvas, glass_layer)

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
        radius=int(SIZE * 0.010), fill=(0, 0, 0, 70)
    )
    ts = ts.filter(ImageFilter.GaussianBlur(7))
    canvas = Image.alpha_composite(canvas, ts)

    tag_r = int(SIZE * 0.010)

    # Tag body — glass blue
    td.rounded_rectangle(
        [tag_cx - tag_w//2, tag_top, tag_cx + tag_w//2, tag_top + tag_h],
        radius=tag_r, fill=(35, 95, 195, 180)
    )

    # Glass highlight on tag — top portion
    td.rounded_rectangle(
        [tag_cx - tag_w//2 + 2, tag_top + 1,
         tag_cx + tag_w//2 - 2, tag_top + int(tag_h * 0.42)],
        radius=tag_r, fill=(90, 160, 245, 50)
    )

    # Glass edge glow — left edge brighter
    for y in range(tag_top + tag_r, tag_top + tag_h - tag_r):
        t = (y - tag_top) / tag_h
        alpha = int(30 * (1 - t * 0.5))
        td.point((tag_cx - tag_w//2 + 1, y), fill=(120, 180, 250, alpha))

    # Border — glowing glass edge
    td.rounded_rectangle(
        [tag_cx - tag_w//2, tag_top, tag_cx + tag_w//2, tag_top + tag_h],
        radius=tag_r, outline=(70, 145, 235, 160), width=1
    )
    # Second brighter border inset
    td.rounded_rectangle(
        [tag_cx - tag_w//2 + 1, tag_top + 1, tag_cx + tag_w//2 - 1, tag_top + tag_h - 1],
        radius=tag_r, outline=(100, 170, 250, 40), width=1
    )

    # Hole
    hole_r = int(SIZE * 0.009)
    hole_y = tag_top + int(tag_h * 0.14)
    td.ellipse([tag_cx - hole_r, hole_y - hole_r, tag_cx + hole_r, hole_y + hole_r],
               fill=(15, 45, 110, 200), outline=(70, 145, 235, 120), width=1)

    # Lines
    tlt = tag_top + int(tag_h * 0.33)
    tlx1 = tag_cx - tag_w//2 + int(tag_w * 0.15)
    tlx2 = tag_cx + tag_w//2 - int(tag_w * 0.15)
    for j in range(3):
        ly = tlt + j * int(tag_h * 0.17)
        shrink = int(tag_w * 0.12) if j == 2 else 0
        td.line([(tlx1, ly), (tlx2 - shrink, ly)],
                fill=(120, 185, 255, 60), width=1)

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
