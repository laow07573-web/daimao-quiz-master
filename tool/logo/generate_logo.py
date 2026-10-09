# -*- coding: utf-8 -*-
"""Rasterize the approved maojuan-logo.svg geometry using bundled Pillow only.

Coordinates are the exact 544x512 approved SVG (quadratics, round caps/joins).
Run from any directory; default builds all launchers and promo logo/favicon.
No HTML, theme files, or shared Android colors.xml are modified.
"""
import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
ANDROID = ROOT / 'android/app/src/main/res'
SS = 8
WIDTH, HEIGHT = 544, 512
ACCENT = (94, 106, 210)
FOLD = (203, 207, 244)
WHITE = (255, 255, 255)
INK = (11, 12, 14)
TILE_RADIUS_RATIO = 0.22
MARK_RATIO = 1.26
# 自适应图标（API>=26）前景的约束。
#   108dp 画布，Android 只保证「直径 66dp 的圆」在任何遮罩下都不被裁。
#   2026-10-07 放大：约束 66 → 80（仍乘 SAFE_MARGIN）。
#   为什么敢超过 66：标记的极值点全落在「可见 72dp 方框」（±36dp）之内，
#   实测最大 |dx|≈24dp、|dy|≈29dp，主流圆角方/超椭圆遮罩完全不会裁到；
#   只有严格圆形遮罩会把耳尖与纸角最外缘切掉约 2dp（约占标记 5%）。
#   收益：标记由画布的 46% 高变成 56% 高，图标里不再显得又小又空。
CANVAS_DP, SAFE_ZONE_DP, SAFE_MARGIN = 108, 80, 0.95
BODY = [
    ['M', 124, 178], ['L', 124, 84], ['Q', 124, 66, 139, 77],
    ['L', 236, 146], ['L', 308, 146], ['L', 405, 77],
    ['Q', 420, 66, 420, 84], ['L', 420, 342], ['L', 326, 436],
    ['L', 162, 436], ['Q', 124, 436, 124, 398], ['Z'],
]
CORNER = [
    ['M', 326, 436], ['L', 326, 374], ['Q', 326, 342, 358, 342],
    ['L', 420, 342], ['Z'],
]
EYES = [['M', 190, 227], ['L', 224, 227], ['M', 320, 227], ['L', 354, 227]]
MOUTH = [['M', 259, 264], ['L', 272, 277], ['L', 285, 264]]
LINES = [['M', 190, 329], ['L', 267, 329], ['M', 190, 367], ['L', 240, 367]]
EYE_WIDTH, MOUTH_WIDTH, LINE_WIDTH = 22, 12, 14


def contours(commands):
    """Flatten quadratic Beziers at 64 subdivisions (subpixel at all outputs)."""
    paths, points = [], []
    for op, *p in commands:
        if op == 'M':
            if points:
                paths.append(points)
            points = [tuple(p)]
        elif op == 'L':
            points.append(tuple(p))
        elif op == 'Q':
            x, y = points[-1]
            for i in range(1, 65):
                t = i / 64
                u = 1 - t
                points.append((u*u*x + 2*u*t*p[0] + t*t*p[2],
                               u*u*y + 2*u*t*p[1] + t*t*p[3]))
        elif op == 'Z':
            points.append(points[0])
    if points:
        paths.append(points)
    return paths


def mark_max_radius():
    # All Beziers lie in the convex hull of their endpoints/control points.
    # Thus this bound is conservative, unlike sampling a raster mask.
    points = [tuple(p[i:i+2]) for _, *p in BODY for i in range(0, len(p), 2)]
    return max(math.hypot(x - WIDTH/2, y - HEIGHT/2) for x, y in points)


def fg_ratio():
    return SAFE_ZONE_DP / 2 / mark_max_radius() * WIDTH / CANVAS_DP * SAFE_MARGIN


def luminance(color):
    linear = [v/255/12.92 if v/255 <= 0.04045 else ((v/255+0.055)/1.055)**2.4
              for v in color]
    return sum(a*b for a, b in zip(linear, (0.2126, 0.7152, 0.0722)))


def detail_color(fill):
    lum = luminance(fill)
    return WHITE if 1.05/(lum+0.05) >= (lum+0.05)/(luminance(INK)+0.05) else INK


def render_mark(px, color=ACCENT, ratio=1.0):
    """Fit original viewBox in a square, keeping its aspect ratio and whitespace."""
    size = px * SS
    scale = size / WIDTH * ratio
    ox, oy = (size - WIDTH*scale)/2, (size - HEIGHT*scale)/2
    image = Image.new('RGBA', (size, size))
    draw = ImageDraw.Draw(image)

    def draw_path(commands, fill, width=None):
        for points in contours(commands):
            pts = [(ox + x*scale, oy + y*scale) for x, y in points]
            if width is None:
                draw.polygon(pts, fill=fill)
            else:
                draw.line(pts, fill=fill, width=round(width*scale), joint='curve')
                r = width*scale/2
                # Explicit disks implement SVG round caps AND the mouth join.
                for x, y in pts:
                    draw.ellipse((x-r, y-r, x+r, y+r), fill=fill)

    detail = detail_color(color)
    fold = FOLD if color == ACCENT else tuple(round(a*0.3+b*0.7) for a, b in zip(color, detail))
    draw_path(BODY, color)
    draw_path(CORNER, fold)
    for path, width in ((EYES, EYE_WIDTH), (MOUTH, MOUTH_WIDTH), (LINES, LINE_WIDTH)):
        draw_path(path, detail, width)
    return image.resize((px, px), Image.Resampling.LANCZOS)


def render_tile(px):
    size = px*SS
    tile = Image.new('RGBA', (size, size))
    ImageDraw.Draw(tile).rounded_rectangle((0, 0, size-1, size-1),
                                           radius=size*TILE_RADIUS_RATIO, fill=WHITE)
    tile = tile.resize((px, px), Image.Resampling.LANCZOS)
    tile.alpha_composite(render_mark(px, ratio=MARK_RATIO))
    return tile


def save(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    print(path.relative_to(ROOT) if path.is_relative_to(ROOT) else path)


def geometry():
    return dict(width=WIDTH, height=HEIGHT, body=BODY, corner=CORNER, eyes=EYES,
                mouth=MOUTH, lines=LINES, eyeWidth=EYE_WIDTH, mouthWidth=MOUTH_WIDTH,
                lineWidth=LINE_WIDTH, tileRadiusRatio=TILE_RADIUS_RATIO,
                markRatio=MARK_RATIO, fgRatio=fg_ratio(), maxRadius=mark_max_radius(),
                safeZoneDp=SAFE_ZONE_DP, canvasDp=CANVAS_DP, safeMargin=SAFE_MARGIN,
                accent='#5E6AD2', fold='#CBCFF4')


def build(promo_dir=None):
    (ROOT / 'tool/logo/geometry.json').write_text(
        json.dumps(geometry(), indent=2) + '\n', encoding='utf-8')
    save(render_tile(512), ROOT / 'assets/app_logo.png')
    for density, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                        ('xxhdpi', 144), ('xxxhdpi', 192)]:
        save(render_tile(px), ANDROID / f'mipmap-{density}/ic_launcher.png')
    save(render_mark(432, ratio=fg_ratio()), ANDROID / 'drawable-xxxhdpi/ic_launcher_fg.png')
    adaptive = ANDROID / 'mipmap-anydpi-v26/ic_launcher.xml'
    adaptive.parent.mkdir(parents=True, exist_ok=True)
    # Use Android's built-in white; NEVER overwrite shared values/colors.xml.
    adaptive.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@android:color/white"/>\n'
        '    <foreground android:drawable="@drawable/ic_launcher_fg"/>\n'
        '</adaptive-icon>\n', encoding='utf-8')
    ico = ROOT / 'windows/runner/resources/app_icon.ico'
    sizes = [16, 24, 32, 48, 64, 128, 256]
    ico.parent.mkdir(parents=True, exist_ok=True)
    render_tile(256).save(ico, sizes=[(s, s) for s in sizes],
                          append_images=[render_tile(s) for s in sizes[:-1]])
    promo = Path(promo_dir) if promo_dir else ROOT / 'promo'
    save(render_tile(256), promo / 'assets/logo.png')
    save(render_tile(64), promo / 'favicon.png')
    validate(promo)


def validate(promo):
    """Check actual pixels, output dimensions, ICO frames, and contrast."""
    fg = Image.open(ANDROID / 'drawable-xxxhdpi/ic_launcher_fg.png').convert('RGBA')
    radius = SAFE_ZONE_DP / CANVAS_DP * fg.width / 2
    # 「可见 72dp 方框」的一半：主流圆角方/超椭圆遮罩都至少露出这么大，
    # 标记落在框内就等于在这些遮罩下不可能被裁。
    visible_half = 72 / CANVAS_DP * fg.width / 2
    for y in range(fg.height):
        for x in range(fg.width):
            if fg.getpixel((x, y))[3] > 8:
                dx, dy = abs(x+0.5-fg.width/2), abs(y+0.5-fg.height/2)
                assert math.hypot(dx, dy) <= radius
                assert dx <= visible_half and dy <= visible_half
    for fill in (ACCENT, INK, WHITE, (232, 232, 234)):
        a, b = sorted((luminance(fill), luminance(detail_color(fill))))
        assert (b+0.05)/(a+0.05) >= 4.5
    for path, size in [(ROOT/'assets/app_logo.png', 512), (promo/'assets/logo.png', 256),
                       (promo/'favicon.png', 64)]:
        assert Image.open(path).size == (size, size)
    ico = Image.open(ROOT / 'windows/runner/resources/app_icon.ico')
    assert ico.ico.sizes() == {(s, s) for s in (16, 24, 32, 48, 64, 128, 256)}
    print('PASS: fg inside %.0fdp circle and visible 72dp box; face contrast >=4.5; '
          'PNG/ICO sizes' % SAFE_ZONE_DP)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--promo-dir', type=Path, help='Optional promo resource directory')
    build(parser.parse_args().promo_dir)
