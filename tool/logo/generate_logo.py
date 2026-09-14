# -*- coding: utf-8 -*-
"""猫卷 logo 生成器 —— 几何唯一来源，纯代码绘制，无外部素材，可复现。

设计：「卡片/书卷轮廓 + 猫耳」。卡片形呼应「卷」（书卷）且贴合 Mao Des 2.0
的卡片圆角语言；两只三角耳 + 耳间浅凹给出「猫」。只有两个形状元素，
缩到 26px 仍可辨认（这是旧版字标 logo 做不到的）。

几何定义在 100x100 设计空间（y 向下），所有输出尺寸都从同一份几何推导，
8x 超采样后 LANCZOS 下采样，因此不存在"某个尺寸特别糊"。

注意：Dart 侧 lib/widgets/kit/mj_logo.dart 里的常量必须与本文件保持一致
（那边用 Path.combine 做同样的 并集 → 差集），改这里就要同步改那里。

用法：
    python tool/logo/generate_logo.py            # 生成全部正式资源
    python tool/logo/generate_logo.py --preview  # 只出对比图，不写正式资源
"""
import os
import re
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ASSETS = os.path.join(ROOT, 'assets')
ANDROID_RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
WINDOWS_RES = os.path.join(ROOT, 'windows', 'runner', 'resources')
PREVIEW = os.path.join(ROOT, 'tool', 'logo', 'preview')

SS = 8                 # 超采样倍率
DS = 100.0             # 设计空间边长

ACCENT = (94, 106, 210)   # #5E6AD2 —— Mao Des 2.0 clear 主题强调色
INK = (11, 12, 14)        # #0B0C0E —— 浅色底上的近黑
WHITE = (255, 255, 255)

# ────────────────────────── 几何（设计空间 100x100） ──────────────────────────
HEAD = (11.0, 34.0, 89.0, 92.0, 14.0)        # x0 y0 x1 y1 圆角：卡片/书卷
EAR_L = [(17.0, 34.0), (23.0, 5.0), (47.0, 34.0)]   # 外缘近垂直，内缘斜收
DIP = [(43.0, 32.0), (57.0, 32.0), (50.0, 43.0)]    # 耳间浅凹（从头顶挖掉）
TILE_RADIUS_RATIO = 0.22      # 图标方块圆角
MARK_RATIO = 0.68             # 标记在传统图标方块内的占比

# 自适应图标（API>=26）：系统只在 108dp 画布中心保证 66dp 直径的圆可见，
# 其余区域会被各厂商的遮罩（圆/圆角方/水滴）裁掉。前景该放多大不能拍脑袋——
# 由标记轮廓离画布中心的最远距离反推，留 5% 余量。旧的 0.60 是硬编码的，
# 结果耳尖正好落在安全圆外，在系统启动图标的圆形遮罩下被切掉。
CANVAS_DP = 108.0
SAFE_ZONE_DP = 66.0
SAFE_MARGIN = 0.95


def mark_max_radius():
    """标记轮廓上离设计空间中心 (50,50) 最远点的距离（设计单位）。

    决定自适应图标前景能占多大：点 (r, θ) 要落进安全圆，就要求
    r/DS × 前景边长 ≤ 安全半径。耳尖是当前几何的最远点。
    """
    px = 400
    m = mark_mask(px)
    p = m.load()
    cx = cy = px / 2.0
    best = 0.0
    for y in range(px):
        for x in range(px):
            if p[x, y] > 8:                    # 忽略抗锯齿的极淡边缘
                d = ((x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2) ** 0.5
                if d > best:
                    best = d
    return best / px * DS                  # 换算回设计单位


def fg_ratio():
    """自适应图标前景：100 设计单位占 108dp 画布的比例（由安全圆反推）。"""
    r_max = mark_max_radius()
    return (SAFE_ZONE_DP / 2) / (r_max / DS) / CANVAS_DP * SAFE_MARGIN


def _fg_ratio():
    """带缓存的 fg_ratio()（每次调用都要栅格化掩膜，不便宜）。"""
    global FG_RATIO
    if FG_RATIO is None:
        FG_RATIO = fg_ratio()
    return FG_RATIO


FG_RATIO = None      # 见 fg_ratio()，依赖 mark_mask()，故在首次使用时计算

MIRROR = lambda pts: [(DS - x, y) for x, y in pts]   # noqa: E731


def mark_mask(px):
    """返回 px×px 的 L 掩膜（255 = 上色）。"""
    W = int(px * SS)
    s = W / DS
    m = Image.new('L', (W, W), 0)
    d = ImageDraw.Draw(m)

    x0, y0, x1, y1, r = HEAD
    d.rounded_rectangle([x0 * s, y0 * s, x1 * s, y1 * s],
                        radius=r * s, fill=255)
    for pts in (EAR_L, MIRROR(EAR_L)):
        d.polygon([(x * s, y * s) for x, y in pts], fill=255)
    d.polygon([(x * s, y * s) for x, y in DIP], fill=0)

    return m.resize((px, px), Image.LANCZOS)


def render_mark(px, color=WHITE):
    """透明底单色标记。"""
    out = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    return Image.composite(Image.new('RGBA', (px, px), color + (255,)),
                           out, mark_mask(px))


def render_tile(px, bg=ACCENT, fg=WHITE, radius_ratio=TILE_RADIUS_RATIO,
                mark_ratio=MARK_RATIO, transparent_corners=True):
    """强调色方块 + 反白标记（应用图标）。"""
    tile = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    d = ImageDraw.Draw(tile)
    radius = px * radius_ratio
    if transparent_corners:
        d.rounded_rectangle([0, 0, px - 1, px - 1], radius=radius, fill=bg + (255,))
    else:
        d.rectangle([0, 0, px - 1, px - 1], fill=bg + (255,))
    inner = int(px * mark_ratio)
    tile.alpha_composite(render_mark(inner, color=fg),
                         ((px - inner) // 2, (px - inner) // 2))
    return tile


def render_adaptive(px, bg=ACCENT, fg=WHITE):
    """自适应图标合成（108dp 画布：bg 铺满，fg 缩到安全圆内）。"""
    tile = Image.new('RGBA', (px, px), bg + (255,))
    inner = int(px * _fg_ratio())
    tile.alpha_composite(render_mark(inner, color=fg),
                         ((px - inner) // 2, (px - inner) // 2))
    return tile


def _apply_mask(tile, shape):
    """按各厂商常见遮罩裁切图标（仅用于预览，验证安全区）。"""
    px = tile.size[0]
    m = Image.new('L', (px, px), 0)
    d = ImageDraw.Draw(m)
    if shape == 'circle':
        d.ellipse([0, 0, px - 1, px - 1], fill=255)
    elif shape == 'squircle':
        d.rounded_rectangle([0, 0, px - 1, px - 1], radius=px * 0.28, fill=255)
    else:  # rounded：更方一点
        d.rounded_rectangle([0, 0, px - 1, px - 1], radius=px * 0.18, fill=255)
    out = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    out.paste(tile, (0, 0), m)
    return out


def _save(img, path, desc=''):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print('  {:<58} {:<12} {:>8} B'.format(
        os.path.relpath(path, ROOT), desc, os.path.getsize(path)))


# ────────────────────────── 正式资源 ──────────────────────────
def build():
    print('geometry bbox (design units):', end=' ')
    m = mark_mask(100)
    print(m.getbbox())

    # 导出几何常量给 Dart 侧测试校验（test/logo_geometry_test.dart）：
    # mj_logo.dart 的 MJLogoGeometry 必须与这里逐个数一致，否则应用内标记
    # 会和启动图标长得不一样。
    import json
    geo = {
        'ds': DS,
        'head': list(HEAD),
        'earLeft': [list(p) for p in EAR_L],
        'dip': [list(p) for p in DIP],
        'tileRadiusRatio': TILE_RADIUS_RATIO,
        'markRatio': MARK_RATIO,
        'fgRatio': _fg_ratio(),
        'safeZoneDp': SAFE_ZONE_DP,
        'canvasDp': CANVAS_DP,
        'accent': '#%02X%02X%02X' % ACCENT,
    }
    geo_path = os.path.join(ROOT, 'tool', 'logo', 'geometry.json')
    with open(geo_path, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(geo, f, indent=2, ensure_ascii=False)
        f.write('\n')
    print('  {:<58} 同源校验用'.format(os.path.relpath(geo_path, ROOT)))

    print('\n[1] 应用图标（512，供商店素材/推广/二次加工；应用内不再引用位图）')
    _save(render_tile(512), os.path.join(ASSETS, 'app_logo.png'), '512 tile')

    print('\n[2] Android 传统图标（API<26 回退）')
    for folder, px in [('mipmap-mdpi', 48), ('mipmap-hdpi', 72),
                       ('mipmap-xhdpi', 96), ('mipmap-xxhdpi', 144),
                       ('mipmap-xxxhdpi', 192)]:
        _save(render_tile(px), os.path.join(ANDROID_RES, folder, 'ic_launcher.png'),
              f'{px}px')

    print('\n[3] Android 自适应图标（API>=26）')
    print('  标记最远点 {:.1f} 设计单位 → 前景占比 {:.3f}（安全圆 {}dp/{}dp）'.format(
        mark_max_radius(), _fg_ratio(), SAFE_ZONE_DP, CANVAS_DP))
    # 前景：透明底白标记，缩到安全圆内
    fg_px = 432
    inner = int(fg_px * _fg_ratio())
    fg = Image.new('RGBA', (fg_px, fg_px), (0, 0, 0, 0))
    fg.alpha_composite(render_mark(inner), ((fg_px - inner) // 2,) * 2)
    _save(fg, os.path.join(ANDROID_RES, 'drawable-xxxhdpi', 'ic_launcher_fg.png'),
          '432 fg')
    xml = ('<?xml version="1.0" encoding="utf-8"?>\n'
           '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
           '    <background android:drawable="@color/ic_launcher_background"/>\n'
           '    <foreground android:drawable="@drawable/ic_launcher_fg"/>\n'
           '</adaptive-icon>\n')
    anydpi = os.path.join(ANDROID_RES, 'mipmap-anydpi-v26', 'ic_launcher.xml')
    os.makedirs(os.path.dirname(anydpi), exist_ok=True)
    with open(anydpi, 'w', encoding='utf-8', newline='\n') as f:
        f.write(xml)
    print('  {:<58} adaptive-icon'.format(os.path.relpath(anydpi, ROOT)))
    colors = os.path.join(ANDROID_RES, 'values', 'colors.xml')
    with open(colors, 'w', encoding='utf-8', newline='\n') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<resources>\n'
                '    <!-- 自适应启动图标底色：Mao Des 2.0 clear 强调色 -->\n'
                '    <color name="ic_launcher_background">#5E6AD2</color>\n'
                '</resources>\n')
    print('  {:<58} #5E6AD2'.format(os.path.relpath(colors, ROOT)))

    print('\n[4] Windows 图标')
    ico = os.path.join(WINDOWS_RES, 'app_icon.ico')
    os.makedirs(WINDOWS_RES, exist_ok=True)
    render_tile(256).save(ico, sizes=[(16, 16), (24, 24), (32, 32), (48, 48),
                                      (64, 64), (128, 128), (256, 256)])
    print('  {:<58} {:<12} {:>8} B'.format(
        os.path.relpath(ico, ROOT), 'multi-size', os.path.getsize(ico)))


# ────────────────────────── 推广页同步 ──────────────────────────
# 推广页在旧仓库（D:\dev\flashcard_app\promo），它把 logo 缩到 28–32px 显示，
# 旧字标在那个尺寸完全糊掉，所以要跟着换。这里只在显式传 --promo-dir 时才动它，
# 且只碰 logo 素材与 demo.html 里那一处内嵌图，不碰任何应用代码。
def apply_promo(promo_dir):
    print('\n[5] 推广页同步 →', promo_dir)
    if not os.path.isdir(promo_dir):
        print('  (目录不存在，跳过)')
        return

    _save(render_tile(256), os.path.join(promo_dir, 'assets', 'logo.png'),
          '256 tile')
    _save(render_tile(64), os.path.join(promo_dir, 'favicon.png'), '64 tile')
    # 404.html 一直引用 favicon.png 但文件从不存在，这次顺手补上。

    demo = os.path.join(promo_dir, 'demo.html')
    if os.path.exists(demo):
        import base64
        import io
        buf = io.BytesIO()
        render_tile(256).save(buf, format='PNG')
        b64 = base64.b64encode(buf.getvalue()).decode('ascii')

        with open(demo, encoding='utf-8') as f:
            html = f.read()
        before = html
        html = re.sub(r'(var LOGO = "data:image/png;base64,)[A-Za-z0-9+/=]+(";)',
                      lambda m: m.group(1) + b64 + m.group(2), html)
        # hero 场景原来靠 brightness(0) invert(1) 把单色字标反白；
        # 新 logo 是自带底色的方块，再反白会变成一整块白色。
        html = html.replace('object-fit:contain;filter:brightness(0) invert(1)',
                            'object-fit:contain')
        if html != before:
            with open(demo, 'w', encoding='utf-8', newline='\n') as f:
                f.write(html)
            print('  {:<58} LOGO 内嵌图 + hero 反白滤镜'.format('demo.html'))
        else:
            print('  {:<58} 无需改动'.format('demo.html'))


# ────────────────────────── 预览 ──────────────────────────
def preview():
    os.makedirs(PREVIEW, exist_ok=True)
    cell, pad = 260, 20
    sizes = [256, 96, 64, 40, 26, 21]
    W = pad + len(sizes) * (cell + pad)
    H = pad + 3 * (cell + pad) + 150
    sheet = Image.new('RGBA', (W, H), (24, 25, 28, 255))
    d = ImageDraw.Draw(sheet)

    from PIL import ImageFont

    def font(size):
        try:
            return ImageFont.truetype(
                os.path.join(ROOT, 'fonts', 'MiSans-Semibold.ttf'), size)
        except Exception:
            return ImageFont.load_default()

    f = font(17)
    for ci, px in enumerate(sizes):
        x = pad + ci * (cell + pad)
        d.text((x, pad - 4), f'{px}px', font=f, fill=(140, 145, 155, 255))
        for ri, bg in enumerate([(16, 17, 19), (255, 255, 255)]):
            y = pad + 22 + ri * (cell + pad)
            box = Image.new('RGBA', (cell, cell), bg + (255,))
            col = WHITE if bg != (255, 255, 255) else INK
            box.alpha_composite(render_mark(px, color=col),
                                ((cell - px) // 2, (cell - px) // 2))
            sheet.alpha_composite(box, (x, y))
            d.rectangle([x, y, x + cell - 1, y + cell - 1], outline=(60, 62, 68, 255))

    # 图标方块
    y = pad + 22 + 2 * (cell + pad)
    for ci, px in enumerate([192, 96, 48]):
        sheet.alpha_composite(render_tile(px),
                              (pad + ci * (192 + 20), y + 20))
    # 大小对照：新版 vs 旧版字标（旧版本身是不透明白底，照原样贴出来即可见其问题）
    old_path = os.path.join(PREVIEW, 'old_wordmark.png')
    if os.path.exists(old_path):
        sheet.alpha_composite(
            Image.open(old_path).convert('RGBA').resize((192, 192), Image.LANCZOS),
            (pad + 3 * (192 + 20), y + 20))

    # 自适应图标在各厂商遮罩下的样子（这是最容易出问题的视图：
    # 安全圆之外会被裁掉，耳尖首当其冲）
    y2 = y + 192 + 20 + 34
    d.text((pad, y2), 'adaptive under launcher masks (circle / squircle / rounded)',
           font=f, fill=(140, 145, 155, 255))
    adaptive = render_adaptive(192)
    for si, shape in enumerate(['circle', 'squircle', 'rounded']):
        masked = _apply_mask(adaptive, shape)
        bg = Image.new('RGBA', (192, 192), (24, 25, 28, 255))
        bg.alpha_composite(masked)
        sheet.alpha_composite(bg, (pad + si * 200, y2 + 22))

    out = os.path.join(PREVIEW, 'final.png')
    sheet.convert('RGB').save(out, quality=95)
    print('preview ->', out)


if __name__ == '__main__':
    if '--preview' in sys.argv:
        preview()
    else:
        build()
        if '--promo-dir' in sys.argv:
            apply_promo(sys.argv[sys.argv.index('--promo-dir') + 1])
