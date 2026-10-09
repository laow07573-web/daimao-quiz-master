# -*- coding: utf-8 -*-
"""猫卷 · 宣传动画《草稿纸与荧光笔》生成器（PIL 逐帧渲染 + ffmpeg 合成）。

创意：定格动画 / 手绘翻页感。纸底 #F6F1E7 + 极淡横线纹理，纸片卡片 #FFFDF8 + 2px 墨线
#1A1A18 + 硬偏移阴影（offset 4px、0 模糊、黑 10%），荧光笔涂抹（#FFE86B/#A8E6A3/#FFB3C6，
边缘略不规则、wipe 展开、multiply 叠色＝真马克笔压过纸与墨线），手绘黑墨线元素（圈注、
箭头、波浪线、✓/✗ 印章、爪印），吉祥物「墨墨」3 变体 10fps 循环＝手绘 boil。

分镜（70s @ 30fps = 2100 帧，严格按节拍，每拍收尾留 2~3s 停顿）：
    0~5s   开场    纸面拉开 → 猫爪推出「猫卷」+ slogan（荧光黄划过）+ 墨墨 wave
    5~13s  痛点    题库文档落下（PDF/DOCX）→「期末周，题库堆成山」→ 荧光笔匆忙划重点
    13~24s 一键建库 纸片飞进猫卷纸盒 → 题目卡片弹出（插图随题）→「DOCX / PDF / JSON 一键建库」
    24~37s 刷题与AI 答题卡 A/B/C/D → 选中 → ✓ 印章 → AI 讲解气泡（荧光划两行）→「用你自己的 Key…」
    37~48s 复习    FSRS 遗忘曲线抬升（墨线 draw-on）+ 错题卡片叠放 →「错题本 + FSRS-5…」
    48~57s 数据    真机 stats.png 手机纸框 + 数字滚动 + 热力图逐格点亮 →「每一次刷题都算数」
    57~70s 收尾    墨墨 highlight + 三枚贴纸 → 下载/开源提示 → 定格（标题 + 猫爪印）

用法（参数化输出路径，可复现）：
    python tool/make_promo_video.py                          # 1080p 全流程出片（默认路径）
    python tool/make_promo_video.py --scale 0.5              # 960×540 快速试跑节奏
    python tool/make_promo_video.py --stills 3.6,15.9,68.2   # 只渲关键帧做美术校对
    python tool/make_promo_video.py --out D:/x/promo.mp4 --poster D:/x/p.jpg
    python tool/make_promo_video.py --skip-encode            # 只出帧

管线：PIL 渲染 PNG 序列（临时帧放 D:\\dev\\maojuan_private\\video_frames_build\\）→
    ffmpeg -y -framerate 30 -i frames/f_%05d.png -c:v libx264 -pix_fmt yuv420p -crf 20
           -movflags +faststart out.mp4
无音频（静音成片）。
"""
import argparse
import math
import random
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

# ---------------------------------------------------------------- 常量
INK = (26, 26, 24, 255)          # #1A1A18 墨线
INK_SOFT = (107, 102, 92, 255)   # 次级文字
BAR_GRAY = (186, 180, 166, 255)  # 假文本条
PAPER = (246, 241, 231)          # #F6F1E7 纸底
PAPER_LINE = (230, 223, 208)     # 极淡横线纹理
CARD = (255, 253, 248, 255)      # #FFFDF8 纸片卡片
SLOT_DARK = (54, 52, 47, 255)    # 纸盒入口
# 荧光笔 multiply 前按纸底做补偿，落纸即为标注色 #FFE86B/#A8E6A3/#FFB3C6
HL = {'y': (255, 241, 118), 'g': (174, 245, 180), 'p': (255, 191, 218)}
STICKER = {'y': (255, 232, 107), 'g': (168, 230, 163), 'p': (255, 179, 198)}
SHADOW = (0, 0, 0, 26)           # 硬偏移阴影：0 模糊、黑 10%
HEAT = [(219, 223, 210), (223, 242, 219), (192, 233, 185), (160, 224, 152), (116, 204, 108)]

DESIGN_W, DESIGN_H = 1920, 1080
FPS = 30
DURATION = 70.0                  # 60~75s 区间内
BEATS = [                        # (t0, t1, 名称) —— 严格按分镜节奏
    (0.0, 5.0, '开场'), (5.0, 13.0, '痛点'), (13.0, 24.0, '一键建库'),
    (24.0, 37.0, '刷题与AI'), (37.0, 48.0, '复习'), (48.0, 57.0, '数据'),
    (57.0, 70.0, '收尾'),
]
SMEAR_TIMES = [5.0, 13.0, 24.0, 37.0, 48.0, 57.0, 64.0]   # 荧光涂抹转场（含收尾内转场）
SMEAR_COLORS = ['y', 'g', 'p', 'y', 'g', 'p', 'y']

ROOT = Path(__file__).resolve().parent.parent
FONTS_DIR = ROOT / 'fonts'
SITE_ASSETS = ROOT / 'site' / 'assets'
SCREENSHOTS = ROOT / 'docs' / 'screenshots'
DEFAULT_OUT = SITE_ASSETS / 'promo.mp4'
DEFAULT_POSTER = SITE_ASSETS / 'promo-poster.jpg'
DEFAULT_BUILD = Path(r'D:\dev\maojuan_private\video_frames_build')
DEFAULT_SAMPLES = Path(r'D:\dev\maojuan_private\video_frames')

S = 1.0   # 全局缩放（--scale 0.5 → 960×540 试跑）
W, H = DESIGN_W, DESIGN_H


def U(v):
    """设计坐标/尺寸 → 输出像素（浮点）"""
    return v * S


def UI(v):
    """设计坐标/尺寸 → 输出像素（整数 ≥1）"""
    return max(1, int(round(v * S)))


# ---------------------------------------------------------------- 缓动
def clamp01(x):
    return 0.0 if x < 0 else (1.0 if x > 1 else x)


def seg(t, t0, t1):
    return clamp01((t - t0) / (t1 - t0)) if t1 > t0 else 1.0


def ease_out_cubic(u):
    return 1 - (1 - u) ** 3


def ease_out_back(u, k=1.70158):
    """缓出 + 略过冲（印章/贴纸落位）"""
    v = u - 1
    return 1 + v * v * ((k + 1) * v + k)


def ease_in_out(u):
    return u * u * (3 - 2 * u)


def ease_in_cubic(u):
    return u ** 3


def lerp(a, b, u):
    return a + (b - a) * u


def oc(t, t0, t1):
    return ease_out_cubic(seg(t, t0, t1))


def ob(t, t0, t1):
    return ease_out_back(seg(t, t0, t1))


def ioc(t, t0, t1):
    return ease_in_out(seg(t, t0, t1))


def boil(f):
    """10fps 三变体循环 —— 手绘 boil（30fps 每 3 帧换一变体）"""
    return (f // 3) % 3


def poly_partial(pts, u):
    """折线按弧长截取到 u（0..1）—— 墨线 draw-on"""
    if u <= 0:
        return []
    total = sum(math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
                for i in range(len(pts) - 1))
    run, buf = 0.0, [pts[0]]
    for i in range(len(pts) - 1):
        seg_len = math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
        if run + seg_len <= u * total + 1e-6:
            buf.append(pts[i + 1])
            run += seg_len
        else:
            k = (u * total - run) / max(1e-6, seg_len)
            buf.append((lerp(pts[i][0], pts[i + 1][0], k), lerp(pts[i][1], pts[i + 1][1], k)))
            break
    return buf


# ---------------------------------------------------------------- 字体与文本
_font_cache = {}
_text_cache = {}


def get_font(size, bold=True):
    key = (UI(size), bold)
    f = _font_cache.get(key)
    if f is None:
        path = FONTS_DIR / ('MiSans-Semibold.ttf' if bold else 'MiSans-Regular.ttf')
        f = ImageFont.truetype(str(path), UI(size))   # 必须 truetype 加载（支持中文）
        _font_cache[key] = f
    return f


def text_img(s, size, bold=True, fill=INK):
    """文本 → RGBA 小图（按内容缓存）"""
    key = (s, UI(size), bold, fill)
    im = _text_cache.get(key)
    if im is None:
        fnt = get_font(size, bold)
        probe = ImageDraw.Draw(Image.new('RGBA', (1, 1)))
        bb = probe.textbbox((0, 0), s, font=fnt)
        pad = UI(4)
        im = Image.new('RGBA', (bb[2] - bb[0] + 2 * pad, bb[3] - bb[1] + 2 * pad), (0, 0, 0, 0))
        ImageDraw.Draw(im).text((pad - bb[0], pad - bb[1]), s, font=fnt, fill=fill)
        _text_cache[key] = im
    return im


def measure(s, size, bold=True):
    """文本宽度（设计 px）"""
    return get_font(size, bold).getlength(s) / S


def substr_span(s, size, bold, sub):
    """子串在文本中的 (x 偏移, 宽度)（设计 px）—— 荧光笔精确盖住重点词"""
    i = s.find(sub)
    if i < 0:
        return 0.0, measure(s, size, bold)
    return measure(s[:i], size, bold), measure(sub, size, bold)


# ---------------------------------------------------------------- 贴图工具
_rot_cache = {}
_zoom_cache = {}


def rotated(spr, deg):
    if abs(deg) < 0.05:
        return spr
    key = (id(spr), round(deg * 2))
    out = _rot_cache.get(key)
    if out is None:
        out = spr.rotate(-deg, resample=Image.BICUBIC, expand=True)
        _rot_cache[key] = out
    return out


def zoomed(spr, sc):
    if abs(sc - 1.0) < 0.01:
        return spr
    key = (id(spr), round(sc * 40))
    out = _zoom_cache.get(key)
    if out is None:
        out = spr.resize((max(1, int(spr.width * sc)), max(1, int(spr.height * sc))), Image.LANCZOS)
        _zoom_cache[key] = out
    return out


_ANCHOR = {'mm': (0.5, 0.5), 'lm': (0.0, 0.5), 'lt': (0.0, 0.0), 'lc': (0.0, 0.5),
           'rm': (1.0, 0.5), 'ct': (0.5, 0.0), 'lb': (0.0, 1.0), 'rb': (1.0, 1.0)}


def paste_at(img, spr, x, y, anchor='mm', rot=0.0, sc=1.0):
    """x,y 为输出像素；anchor：mm 中心 / lm 左中 / lt 左上 / lc 左中（缩放原点）…"""
    spr = rotated(zoomed(spr, sc), rot)
    ax, ay = _ANCHOR[anchor]
    img.paste(spr, (int(x - spr.width * ax), int(y - spr.height * ay)), spr)


def put(img, spr, x, y, anchor='mm', rot=0.0, sc=1.0):
    """场景层贴图：x,y 为设计坐标"""
    paste_at(img, spr, U(x), U(y), anchor=anchor, rot=rot, sc=sc)


# ---------------------------------------------------------------- 手绘墨笔
class Pen:
    """带抖动的手绘笔（与 make_mascot 同语言）：设计坐标 → 超采样画布，线宽呼吸、圆头"""

    def __init__(self, draw, rng, ss, pad, ox=0.0, oy=0.0):
        self.d, self.rng, self.ss, self.pad = draw, rng, ss, pad
        self.ox, self.oy = ox, oy

    def pt(self, x, y):
        j = 1.5 * S
        return ((U(x) + self.ox + self.pad + self.rng.uniform(-j, j)) * self.ss,
                (U(y) + self.oy + self.pad + self.rng.uniform(-j, j)) * self.ss)

    def line(self, pts, w=4.0, fill=INK, caps=True):
        sp = [self.pt(x, y) for x, y in pts]
        ww = max(1, int(w * S * self.ss * self.rng.uniform(0.88, 1.12)))
        if len(sp) > 1:
            self.d.line(sp, fill=fill, width=ww, joint='curve')
        if caps:
            for px, py in (sp[0], sp[-1]):
                r = ww / 2
                self.d.ellipse([px - r, py - r, px + r, py + r], fill=fill)

    def poly(self, pts, fill=None, outline=INK, w=3.0):
        sp = [self.pt(x, y) for x, y in pts]
        if fill is not None:
            self.d.polygon(sp, fill=fill)
        if outline is not None:
            self.d.line(sp + [sp[0]], fill=outline,
                        width=max(1, int(w * S * self.ss * self.rng.uniform(0.9, 1.1))),
                        joint='curve')

    def dashed(self, pts, w=3.0, dash=13.0, gap=9.0, fill=INK):
        """虚线（灰幽灵曲线）"""
        total = 0.0
        runs, on = [], True
        while total < 1e6:
            runs.append(on)
            total += (dash if on else gap)
            on = not on
            if total > 2000:
                break
        segs, acc, on, buf = [], 0.0, True, [pts[0]]
        for i in range(len(pts) - 1):
            (x0, y0), (x1, y1) = pts[i], pts[i + 1]
            length = math.hypot(x1 - x0, y1 - y0)
            cur = 0.0
            while cur < length - 1e-6:
                run = (dash if on else gap) - acc
                nxt = min(length, cur + max(0.35, run))
                t1 = nxt / length
                p1 = (x0 + (x1 - x0) * t1, y0 + (y1 - y0) * t1)
                if on:
                    buf.append(p1)
                acc += nxt - cur
                cur = nxt
                if acc >= (dash if on else gap) - 1e-6:
                    if on and len(buf) > 1:
                        segs.append(buf)
                    acc, on = 0.0, not on
                    buf = [p1]
        if on and len(buf) > 1:
            segs.append(buf)
        for s2 in segs:
            self.line(s2, w, fill, caps=False)

    def arc(self, cx, cy, r, a0, a1, w=4.0, fill=INK, ry=None, caps=True):
        ry = r if ry is None else ry
        n = max(8, int(abs(a1 - a0) / 7))
        pts = []
        for i in range(n + 1):
            a = math.radians(a0 + (a1 - a0) * i / n)
            pts.append((cx + r * math.cos(a), cy + ry * math.sin(a)))
        self.line(pts, w, fill, caps)

    def circle(self, cx, cy, r, w=4.0, fill=INK, ry=None):
        self.arc(cx, cy, r, 0, 366, w, fill, ry)

    def dot(self, cx, cy, r=3.0, fill=INK):
        px, py = self.pt(cx, cy)
        rr = r * S * self.ss * self.rng.uniform(0.85, 1.18)
        self.d.ellipse([px - rr, py - rr, px + rr, py + rr], fill=fill)

    def bean(self, cx, cy, rx, ry, fill=INK):
        sp = [self.pt(cx, cy)]
        self.d.ellipse([sp[0][0] - rx * S * self.ss, sp[0][1] - ry * S * self.ss,
                        sp[0][0] + rx * S * self.ss, sp[0][1] + ry * S * self.ss], fill=fill)


def _rect_path(x, y, w, h, segs=5):
    pts = []

    def edge(x0, y0, x1, y1):
        for i in range(segs):
            t = i / segs
            pts.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))

    edge(x, y, x + w, y)
    edge(x + w, y, x + w, y + h)
    edge(x + w, y + h, x, y + h)
    edge(x, y + h, x, y)
    return pts


def _rrect_path(x, y, w, h, r, per=4):
    pts = []
    for cx, cy, a0, a1 in ((x + w - r, y + r, -90, 0), (x + w - r, y + h - r, 0, 90),
                           (x + r, y + h - r, 90, 180), (x + r, y + r, 180, 270)):
        for i in range(per + 1):
            a = math.radians(a0 + (a1 - a0) * i / per)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


_doodle_cache = {}


def doodle(name, w, h, painter, ss=3, crop=True):
    """手绘墨线元素 → 3 个 boil 变体 RGBA。painter(pen) 在设计坐标 0..w / 0..h 里画。
    crop=True 时对齐到 v0 内容框（变体间微差即 boil），配 'mm' 锚点使用。"""
    key = (name, UI(w), UI(h), crop)
    out = _doodle_cache.get(key)
    if out is not None:
        return out
    pad = UI(10)
    cw, ch = (UI(w) + 2 * pad) * ss, (UI(h) + 2 * pad) * ss
    out = []
    for b in range(3):
        rng = random.Random(f'mj-doodle-{name}-{b}')
        canvas = Image.new('RGBA', (cw, ch), (0, 0, 0, 0))
        painter(Pen(ImageDraw.Draw(canvas), rng, ss, pad))
        out.append(canvas.resize((cw // ss, ch // ss), Image.LANCZOS))
    if crop:
        bb = out[0].getbbox()
        out = [im.crop(bb) for im in out]
    _doodle_cache[key] = out
    return out


def do(img, name, w, h, painter, x, y, f, anchor='mm', rot=0.0, sc=1.0):
    put(img, doodle(name, w, h, painter)[boil(f)], x, y, anchor=anchor, rot=rot, sc=sc)


def do_origin(img, name, w, h, painter, x, y, f):
    """固定原点版本：设计坐标 (0,0) 落在场景 (x,y)，适合坐标系图形（曲线/坐标轴）"""
    put(img, doodle(name, w, h, painter, crop=False)[boil(f)], x - 10, y - 10, anchor='lt')


def do_dynamic(img, name, w, h, painter, x, y, f, ss=2):
    """逐帧现画（draw-on / 时变图形，不缓存）：ss 超采样抗锯齿，rng 按 boil 抖动。
    设计坐标 (0,0) 落在场景 (x,y)。"""
    pad = UI(10)
    cw, ch = (UI(w) + 2 * pad) * ss, (UI(h) + 2 * pad) * ss
    canvas = Image.new('RGBA', (cw, ch), (0, 0, 0, 0))
    painter(Pen(ImageDraw.Draw(canvas), random.Random(f'mj-dyn-{name}-{boil(f)}'), ss, pad))
    spr = canvas.resize((cw // ss, ch // ss), Image.LANCZOS)
    put(img, spr, x - 10, y - 10, anchor='lt')


# ---- 具体墨线元素 ----
def paw_print(p):
    """猫爪印：掌垫 + 4 趾"""
    p.bean(50, 64, 26, 20)
    for dx, dy, rx, ry in ((-27, 42, 9, 11), (-10, 32, 9.5, 12), (11, 32, 9.5, 12), (28, 42, 9, 11)):
        p.bean(50 + dx, dy, rx, ry)


def wavy_underline(p):
    p.line([(4 + i * 12.7, 14 + math.sin(i * 1.35) * 6) for i in range(13)], 4.5)


def circle_doodle(p):
    p.arc(70, 45, 62, 200, 520, 4.5, ry=38)


def check_stamp(p):
    p.circle(60, 60, 52, 7)
    p.circle(60, 60, 45, 3.5)
    p.line([(36, 62), (53, 80), (86, 34)], 11)


def cross_stamp(p):
    p.circle(60, 60, 52, 7)
    p.circle(60, 60, 45, 3.5)
    p.line([(40, 40), (80, 80)], 11)
    p.line([(80, 40), (40, 80)], 11)


def key_doodle(p):
    p.circle(24, 34, 15, 5.5)
    p.line([(34, 44), (88, 78)], 5.5)
    p.line([(70, 66), (62, 80)], 5.5)
    p.line([(82, 74), (74, 88)], 5.5)


def bubble_tail(p):
    """气泡尾巴：纸三角 + 硬阴影 + 墨线"""
    sp_pts = [(88, 6), (4, 50), (88, 64)]
    sp = [p.pt(x, y) for x, y in sp_pts]
    off = 4 * S * p.ss
    p.d.polygon([(x + off, y + off) for x, y in sp], fill=SHADOW)
    p.d.polygon(sp, fill=CARD)
    p.d.line(sp + [sp[0]], fill=INK, width=max(1, int(2.2 * S * p.ss)), joint='curve')


def thumb_microbe(p):
    p.circle(52, 52, 26, 4.5, ry=20)
    p.dot(44, 48, 4)
    p.dot(62, 56, 4)
    p.line([(78, 30), (96, 18)], 3.5)
    p.line([(24, 78), (12, 90)], 3.5)
    p.circle(92, 74, 10, 3.5)


def thumb_organ(p):
    p.line([(50, 84), (26, 56), (32, 28), (56, 34), (50, 84)], 4.5)
    p.line([(50, 84), (74, 56), (68, 28), (44, 34)], 4.5)
    p.line([(86, 22), (104, 34), (86, 46)], 3.5)


def thumb_cell(p):
    p.circle(56, 52, 34, 4.5)
    p.circle(62, 50, 13, 3.8)
    p.dot(34, 70, 3.5)
    p.dot(76, 78, 3.5)


THUMBS = {'microbe': thumb_microbe, 'organ': thumb_organ, 'cell': thumb_cell}


# ---------------------------------------------------------------- 纸片卡片
_paper_cache = {}
_styled_cache = {}


class Gfx:
    """纸片内容画笔：设计坐标（纸片左上为原点）→ 合成图（印刷内容不抖）"""

    def __init__(self, img, pad):
        self.img, self.pad = img, pad

    def text(self, s, x, y, size, bold=True, fill=INK, anchor='lm'):
        paste_at(self.img, text_img(s, size, bold, fill), U(x) + self.pad, U(y) + self.pad, anchor=anchor)

    def sprite(self, spr, x, y, anchor='mm', rot=0.0, sc=1.0):
        paste_at(self.img, spr, U(x) + self.pad, U(y) + self.pad, anchor=anchor, rot=rot, sc=sc)

    def doodle(self, name, w, h, painter, x, y, b=0, anchor='mm', rot=0.0):
        self.sprite(doodle(name, w, h, painter)[b], x, y, anchor=anchor, rot=rot)

    def bar(self, x, y, w, h, fill=BAR_GRAY, r=0):
        d = ImageDraw.Draw(self.img)
        px, py, pw, ph = U(x) + self.pad, U(y) + self.pad, U(w), U(h)
        if r:
            d.rounded_rectangle([px, py, px + pw, py + ph], radius=U(r), fill=fill)
        else:
            d.rectangle([px, py, px + pw, py + ph], fill=fill)

    def outline(self, x, y, w, h, fill=None, r=6, line=2.0):
        d = ImageDraw.Draw(self.img)
        px, py, pw, ph = U(x) + self.pad, U(y) + self.pad, U(w), U(h)
        d.rounded_rectangle([px, py, px + pw, py + ph], radius=U(r), fill=fill,
                            outline=INK, width=max(1, UI(line)))


def _paper_pad(shadow, line):
    return UI(shadow) + UI(line) * 2 + 8


def paper_base(name, w, h, fill=CARD, line=2.0, shadow=4.0, r=0, ss=3, segs=5):
    """手绘纸片（wobbly 轮廓 + 墨线 + 硬偏移阴影）→ 3 个 boil 变体"""
    key = (name, UI(w), UI(h), fill, round(line, 1), round(shadow, 1), round(r), segs)
    out = _paper_cache.get(key)
    if out is not None:
        return out
    pad = _paper_pad(shadow, line)
    cw, ch = (UI(w) + 2 * pad) * ss, (UI(h) + 2 * pad) * ss
    out = []
    for b in range(3):
        rng = random.Random(f'mj-paper-{name}-{b}')
        canvas = Image.new('RGBA', (cw, ch), (0, 0, 0, 0))
        pen = Pen(ImageDraw.Draw(canvas), rng, ss, pad)
        path = _rect_path(0, 0, w, h, segs) if r <= 0 else _rrect_path(0, 0, w, h, r)
        sp = [pen.pt(x, y) for x, y in path]
        off = shadow * S * ss                            # 硬阴影：同轮廓偏移、0 模糊
        pen.d.polygon([(px + off, py + off) for px, py in sp], fill=SHADOW)
        pen.d.polygon(sp, fill=fill)
        pen.d.line(sp + [sp[0]], fill=INK,
                   width=max(1, int(line * S * ss * rng.uniform(0.9, 1.1))), joint='curve')
        out.append(canvas.resize((cw // ss, ch // ss), Image.LANCZOS))
    _paper_cache[key] = out
    return out


def styled_paper(name, w, h, content=None, **kw):
    """纸片 + 静态内容烘焙 → 3 个 boil 变体（边框 boil、印刷内容不抖）。
    name 需按内容唯一（缓存键）。"""
    key = (name, UI(w), UI(h), tuple(sorted((k, str(v)) for k, v in kw.items())))
    out = _styled_cache.get(key)
    if out is not None:
        return out
    base = paper_base(name, w, h, **kw)
    pad = _paper_pad(kw.get('shadow', 4.0), kw.get('line', 2.0))
    out = []
    for spr in base:
        comp = spr.copy()
        if content:
            content(Gfx(comp, pad))
        out.append(comp)
    _styled_cache[key] = out
    return out


def chip_sprite(name, s, w, h, size, fill_bg=CARD, bold=True, line=1.8, shadow=3.0):
    """小标签片（印刷感纸片 + 墨线 + 文字）"""

    def content(g):
        g.text(s, w / 2, h / 2, size, bold=bold, anchor='mm')

    return styled_paper(name, w, h, content, fill=fill_bg, line=line, shadow=shadow, segs=3)


# ---------------------------------------------------------------- 荧光笔
class HlStroke:
    """荧光涂抹条：wipe 展开、边缘略不规则、微倾斜；multiply 叠色（压墨线仍是墨黑）"""

    def __init__(self, name, x, y, w, h, color='y', tilt=0.0):
        self.name, self.x, self.y, self.w, self.h = name, x, y, w, h
        self.color = HL[color]
        self.slope = math.tan(math.radians(tilt))
        self.margin = UI(16)

    def _geom(self):
        dy = abs(U(self.slope * self.w / 2))
        bw = int(UI(self.w) + 2 * self.margin)
        bh = int(UI(self.h) + 2 * dy + 2 * self.margin)
        x0 = int(U(self.x) - self.margin)
        y0 = int(U(self.y) - self.margin - dy)
        return x0, y0, bw, bh

    def _shape(self, reveal, b):
        """bbox 内 L 蒙版（SS=2 抗锯齿）；reveal 决定 wipe 展开长度"""
        rng = random.Random(f'mj-hl-{self.name}-{b}')
        ss = 2
        wob = 0.13
        xe = max(2.0, self.w * reveal)
        n = max(6, int(self.w / 46))
        dy = abs(self.slope * self.w / 2)
        pts = []

        def ty(x, y):
            return y + self.slope * (x - self.w / 2) + dy

        for i in range(n + 1):                       # 上边
            x = xe * i / n
            pts.append((x, ty(x, self.h * rng.uniform(-wob, wob))))
        for i in range(1, 6):                        # 前缘（wipe 端，波浪）
            y = self.h * i / 6
            pts.append((xe + self.w * 0.022 * rng.uniform(-1, 1), ty(xe, y)))
        for i in range(n + 1):                       # 下边
            x = xe * (n - i) / n
            pts.append((x, ty(x, self.h * (1 + rng.uniform(-wob, wob)))))
        for i in range(5, 0, -1):                    # 尾缘
            y = self.h * i / 6
            pts.append((self.w * 0.016 * rng.uniform(-1, 1), ty(0, y)))

        _, _, bw, bh = self._geom()
        mask = Image.new('L', (bw * ss, bh * ss), 0)
        ImageDraw.Draw(mask).polygon(
            [((U(px) + self.margin) * ss, (U(py) + self.margin) * ss) for px, py in pts], fill=255)
        return mask.resize((bw, bh), Image.LANCZOS)


def apply_highlights(img, strokes, b):
    """一次性 multiply 叠加全部荧光笔（strokes: [(HlStroke, reveal)]）"""
    live = [(s, r) for s, r in strokes if r > 0.003]
    if not live:
        return
    mult = Image.new('RGB', img.size, (255, 255, 255))
    for st, rev in live:
        x0, y0, _, _ = st._geom()
        mask = st._shape(rev, b)
        mult.paste(Image.new('RGB', mask.size, st.color), (x0, y0), mask)
    img.paste(ImageChops.multiply(img, mult))


def hl(name, x, y, w, h, t, t0, t1, color='y', tilt=0.0):
    """便捷：按时间窗 wipe 的荧光笔 → (stroke, reveal)"""
    return (HlStroke(name, x, y, w, h, color, tilt), seg(t, t0, t1))


# ---------------------------------------------------------------- 素材
_mascot_cache = {}
_shot_cache = {}
_zoom_m_cache = {}


def mascot(pose):
    """墨墨 3 个抖动变体（同姿态 seed 0/1/2），按 v0 内容框对齐 → 循环即 boil"""
    out = _mascot_cache.get(pose)
    if out is not None:
        return out
    ims = [Image.open(SITE_ASSETS / f'mascot-{pose}-{i}.png').convert('RGBA') for i in range(3)]
    bb = ims[0].getchannel('A').getbbox()
    out = [im.crop(bb) for im in ims]
    _mascot_cache[pose] = out
    return out


def mascot_size(pose, size):
    """按画布设计尺寸（600 基准）缩放 3 变体（缓存）"""
    key = (pose, UI(size))
    out = _zoom_m_cache.get(key)
    if out is not None:
        return out
    k = U(size) / 600.0
    out = [im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)
           for im in mascot(pose)]
    _zoom_m_cache[key] = out
    return out


def put_mascot(img, pose, x, y, size, f, rot=0.0):
    put(img, mascot_size(pose, size)[boil(f)], x, y, rot=rot)


def phone_sprite(shot_name):
    """真机截图贴进手绘手机外框（硬阴影烘焙、墨线轮廓；旋转/位移由调用方施加）"""
    out = _shot_cache.get(shot_name)
    if out is not None:
        return out
    shot = Image.open(SCREENSHOTS / shot_name).convert('RGB').resize((UI(383), UI(830)), Image.LANCZOS)
    fw, fh = 417.0, 876.0                        # 设计尺寸：外框（内屏 383×830）

    def content(g):
        paste_at(g.img, shot.convert('RGBA'), g.pad + U(17), g.pad + U(16), anchor='lt')
        g.bar(fw / 2 - 30, fh - 22, 60, 6, fill=(120, 116, 106, 255), r=3)   # home 指示条

    out = styled_paper('phone-' + shot_name, fw, fh, content,
                       fill=(38, 38, 35, 255), line=2.5, shadow=5.0, r=22, segs=6)
    _shot_cache[shot_name] = out
    return out


# ---- 复合部件 ----
def lecture_sheet(name, tag):
    """题库文档纸片：假文本条 + PDF/DOCX 角标"""

    def content(g):
        g.bar(28, 30, 150, 14, fill=(150, 144, 130, 255))
        y = 74
        for w2 in (244, 230, 244, 200, 244, 214, 236, 176):
            g.bar(28, y, w2, 9, r=4)
            y += 26
        g.sprite(chip_sprite('tag-' + tag, tag, 96, 44, 24)[0], 244, 40, anchor='mm', rot=3)

    return styled_paper('sheet-' + name, 300, 400, content, segs=5)


def question_card(name, lines, thumb):
    """题目卡片（插图随题）：小插图 + 题干两行"""

    def content(g):
        g.doodle('thumb-' + thumb, 130, 100, THUMBS[thumb], 92, 128, 0)
        g.outline(27, 78, 130, 100, r=8, line=2.0)
        for i, ln in enumerate(lines):
            g.text(ln, 182, 108 + i * 44, 27, bold=False)
        g.bar(182, 180, 120, 10, r=5)

    return styled_paper('qcard-' + name, 540, 280, content, segs=5)


def wrong_card(name, line, chip_text, chip_col):
    """错题卡片：题干 + 到期标签 + ✗ 印章"""

    def content(g):
        g.text(line, 30, 78, 27, bold=False)
        g.sprite(chip_sprite('wc-' + chip_text, chip_text, 150, 46, 24, fill_bg=STICKER[chip_col])[0],
                 105, 130, anchor='mm', rot=-2)
        g.doodle('cross-s', 120, 120, cross_stamp, 378, 72, 0, rot=8)

    return styled_paper('wcard-' + name, 440, 270, content, segs=5)


def option_strip(k, s):
    def content(g):
        g.doodle('opq-' + k, 58, 58, lambda p: p.circle(29, 29, 25, 4), 58, 48, 0)
        g.text(k, 58, 48, 34, anchor='mm')
        g.text(s, 128, 48, 36, bold=False)

    return content


def box_sprite():
    """猫卷纸盒入口：开口 + 猫卷标记"""

    def content(g):
        g.bar(52, 6, 316, 34, fill=SLOT_DARK, r=8)                # 入口槽
        g.outline(48, 2, 324, 42, r=10, line=2.0)
        g.text('猫卷', 210, 150, 52, anchor='mm')
        g.doodle('boxpaw', 100, 100, paw_print, 210, 226, 0)

    return styled_paper('mjbox', 420, 300, content, segs=5)


BUBBLE_L1 = '题眼：细胞壁的“主要成分”'
BUBBLE_L2 = '阳性菌 = 肽聚糖 + 磷壁酸'
BUBBLE_L3 = '脂多糖只在阴性菌的外膜'


def bubble_sprite():
    """AI 讲解气泡（尾巴单独成 doodle，贴在纸片后）"""

    def content(g):
        g.sprite(chip_sprite('ai-chip', 'AI 讲解', 176, 58, 30, fill_bg=STICKER['y'])[0], 128, 62, rot=-2)
        g.text(BUBBLE_L1, 46, 148, 30, bold=False)
        g.text(BUBBLE_L2, 46, 218, 30, bold=False)
        g.text(BUBBLE_L3, 46, 288, 30, bold=False)

    return styled_paper('bubble', 700, 380, content, segs=5)


# ---------------------------------------------------------------- 背景 / 转场
def build_bg():
    """纸底 + 极淡横线纹理 + 纸纹噪声（预渲染一次复用）"""
    img = Image.new('RGB', (W, H), PAPER)
    d = ImageDraw.Draw(img)
    y = UI(46)
    while y < H:
        d.line([(0, y), (W, y)], fill=PAPER_LINE, width=1)
        y += UI(46)
    noise = Image.effect_noise((W, H), 26).point(lambda v: int(128 + (v - 128) * 0.45))
    return ImageChops.add(img, Image.merge('RGB', (noise, noise, noise)), scale=1, offset=-128)


def draw_smear(img, p, color, seed):
    """荧光笔涂抹转场：宽涂抹条自左扫到右（p=0.5 全遮 = 换镜点）"""
    if not (0.0 < p < 1.0):
        return
    rng = random.Random(f'mj-smear-{seed}')
    band_w = W * 1.06
    x_le = -band_w + p * (W + band_w)
    tilt = 0.06
    n = 26
    pts = []
    for i in range(n + 1):                       # 前缘（右）自上而下
        y = -0.12 * H + 1.24 * H * i / n
        pts.append((x_le + band_w + math.sin(i * 1.1 + seed) * U(16) + rng.uniform(-U(8), U(8)),
                    y + (y - H / 2) * tilt))
    for i in range(n + 1):                       # 尾缘（左）自下而上
        y = -0.12 * H + 1.24 * H * (n - i) / n
        pts.append((x_le + math.sin(i * 1.3 + seed) * U(16) + rng.uniform(-U(8), U(8)),
                    y + (y - H / 2) * tilt))
    lay = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    c = STICKER[color]
    d.polygon(pts, fill=c + (252,))
    for k in range(2):                           # 细斜条纹：马克笔来回扫的色阶
        cx = x_le + rng.uniform(0.15, 0.85) * band_w
        bw2 = band_w * rng.uniform(0.03, 0.07)
        sk = H * tilt
        d.polygon([(cx, -0.12 * H), (cx + bw2, -0.12 * H),
                   (cx + bw2 + sk, 1.12 * H), (cx + sk, 1.12 * H)],
                  fill=(min(255, c[0] + 14), min(255, c[1] + 16), min(255, c[2] + 12), 85))
    img.paste(lay, (0, 0), lay)


def draw_transitions(img, t):
    for i, (tb, col) in enumerate(zip(SMEAR_TIMES, SMEAR_COLORS)):
        if tb - 0.32 <= t <= tb + 0.32:
            draw_smear(img, seg(t, tb - 0.30, tb + 0.30), col, i)


# ---------------------------------------------------------------- 场景
def scene1(img, f, t):
    """0~5s 开场：纸面拉开 → 猫爪推出「猫卷」+ slogan（荧光黄）+ 墨墨 wave"""
    b = boil(f)
    strokes = []
    slogan = '题库文档，导入即刷'
    put(img, text_img('猫卷', 230), lerp(-520, 980, oc(t, 0.52, 1.42)), 430)
    if t >= 1.55:
        put(img, text_img(slogan, 64), 960, 640 + lerp(60, 0, oc(t, 1.55, 2.15)))
        sw = measure(slogan, 64)
        strokes.append(hl('s1-slogan', 960 - sw / 2 - 14, 610, sw + 28, 62, t, 2.05, 2.85, 'y', 0.6))
    # 猫爪推标题（收爪跑走出画，留下两枚小爪印）
    if t < 1.45:
        px, py = lerp(170, 645, oc(t, 0.45, 1.30)), 470
    else:
        u = ease_in_cubic(seg(t, 1.45, 1.85))
        px, py = lerp(645, 40, u), lerp(470, 1240, u)
    do(img, 'paw', 100, 100, paw_print, px, py, f, rot=-12, sc=2.3)
    if t >= 1.30:
        do(img, 'paw-t1', 100, 100, paw_print, 330, 830, f, rot=-24, sc=0.9)
    if t >= 1.42:
        do(img, 'paw-t2', 100, 100, paw_print, 480, 762, f, rot=10, sc=0.9)
    if t >= 2.25:                                   # 墨墨 wave（3 变体 10fps boil）
        put_mascot(img, 'wave', 1560, lerp(1120, 720, ob(t, 2.25, 3.10)), 640, f)
    apply_highlights(img, strokes, b)
    if t < 0.95:                                    # 纸面拉开（两扇纸片盖板）
        u = ioc(t, 0.0, 0.85)
        panels = styled_paper('openp', DESIGN_W / 2, DESIGN_H, line=2.5, shadow=6, ss=2, segs=8)
        put(img, panels[b], lerp(480, -540, u), 540, rot=lerp(0, -2.2, u))
        put(img, panels[b], lerp(1440, 2460, u), 540, rot=lerp(0, 2.2, u))


def scene2(img, f, t):
    """5~13s 痛点：题库文档落下 →「期末周，题库堆成山」→ 荧光笔匆忙划重点"""
    b = boil(f)
    strokes = []
    pile = [(860, 660, -5, 'PDF'), (735, 596, 3, 'DOCX'), (985, 612, 6, 'DOCX'),
            (822, 532, -3, 'PDF'), (944, 700, 4, 'DOCX'), (698, 686, -6, 'PDF'), (1005, 528, 2, 'DOCX')]
    for i, (cx, cy, rot0, tag) in enumerate(pile):
        t0 = 5.05 + i * 0.26
        if t < t0:
            continue
        u = oc(t, t0, t0 + 0.75)
        y = lerp(-320, cy, ease_out_back(seg(t, t0, t0 + 0.78), 1.1))
        put(img, lecture_sheet(f's2-{i}', tag)[b], lerp(cx + ((i % 3) - 1) * 130, cx, u), y,
            rot=lerp(rot0 * 2.4, rot0, u))
    if t >= 7.35:                                   # 「期末周，题库堆成山」
        put(img, text_img('期末周，题库堆成山', 96), 960, 132 + lerp(46, 0, oc(t, 7.35, 8.05)))
    frantic = [('a', 585, 470, 420, 56, 'y', -7, 8.35), ('b', 700, 560, 480, 62, 'p', 5, 8.62),
               ('c', 560, 640, 430, 58, 'y', -4, 8.92), ('d', 800, 690, 420, 64, 'g', 8, 9.22),
               ('e', 640, 520, 380, 54, 'y', -10, 9.57), ('f', 830, 600, 360, 60, 'p', 3, 9.95)]
    for nm, x, y, w2, h2, col, tilt, t0 in frantic:
        strokes.append(hl('s2-' + nm, x, y, w2, h2, t, t0, t0 + 0.28, col, tilt))
    if t >= 10.4:
        do(img, 'circ1', 140, 90, circle_doodle, 772, 588, f, rot=-6)
    if t >= 10.8:
        do(img, 'circ2', 140, 90, circle_doodle, 1002, 646, f, rot=5)
    apply_highlights(img, strokes, b)


def scene3(img, f, t):
    """13~24s 一键建库：纸片飞进猫卷纸盒 → 题目卡片弹出（插图随题）→ 大字"""
    b = boil(f)
    strokes = []
    slot = (460, 585)
    flaps = styled_paper('flap', 210, 88, line=2, shadow=4, segs=4)
    box = box_sprite()
    if t >= 12.95:
        k = ob(t, 13.0, 13.5)
        put(img, flaps[b], 372, 600, rot=-24, sc=k)
        put(img, flaps[b], 552, 600, rot=24, sc=k)
        put(img, box[b], 460, 770, sc=k)
    flyers = [('PDF', 1560, 60), ('DOCX', 1700, 320), ('JSON', 1420, -40), ('DOCX', 1640, 170)]
    for i, (tag, x0, y0) in enumerate(flyers):
        t0 = 13.35 + i * 0.45
        u = ioc(t, t0, t0 + 1.05)
        if t < t0 or u >= 1:
            continue
        put(img, lecture_sheet(f'fly-{i}', tag)[b], lerp(x0, slot[0], u), lerp(y0, slot[1], u),
            sc=lerp(0.62, 0.16, u), rot=lerp(-14 if i % 2 else 12, 0, u))
    cards = [(1180, 320, -2, ['革兰氏阳性菌的', '细胞壁主要成分？'], 'microbe'),
             (1450, 560, 2, ['人体最大的', '免疫器官是？'], 'organ'),
             (1180, 800, -1, ['MHC Ⅱ 类分子', '表达于哪些细胞？'], 'cell')]
    for i, (cx, cy, rot0, lines, thumb) in enumerate(cards):
        t0 = 15.6 + i * 0.55
        if t < t0:
            continue
        u3 = ob(t, t0, t0 + 0.85)
        u = oc(t, t0, t0 + 0.85)
        put(img, question_card(f'c{i}', lines, thumb)[b],
            lerp(slot[0], cx, u), lerp(slot[1], cy, u) - math.sin(min(u3, 1.0) * math.pi) * 90,
            rot=lerp(0, rot0, u3), sc=lerp(0.45, 1.0, min(u3, 1.12)))
    if t >= 17.4:                                   # 「插图随题」批注 + 箭头 draw-on
        put(img, chip_sprite('s3-callout', '插图随题', 210, 66, 32)[b], 1520, 130, rot=2)
        u = seg(t, 17.7, 18.3)
        if u > 0.02:
            pts = poly_partial([(290, 15), (215, 32), (135, 58), (42, 88)], u)

            def arrow_pen(p, pts=pts):
                p.line(pts, 5)
                if u >= 0.97:
                    p.line([(42, 88), (72, 78)], 4.5)
                    p.line([(42, 88), (52, 58)], 4.5)

            do_dynamic(img, 'arrow-c', 340, 120, arrow_pen, 1020, 190, f)
    chips3 = [('DOCX', 150, 'y'), ('PDF', 410, 'g'), ('JSON', 670, 'p')]
    for i, (s, x, col) in enumerate(chips3):
        t0 = 19.2 + i * 0.2
        if t >= t0:
            put(img, chip_sprite(f's3ch-{s}', s, 220, 76, 40, fill_bg=STICKER[col])[b],
                x, 180, rot=(-2 + i * 2), sc=ob(t, t0, t0 + 0.5))
    if t >= 19.9:
        put(img, text_img('一键建库', 130), 150, 330 + lerp(40, 0, oc(t, 19.9, 20.6)), anchor='lm')
        strokes.append(hl('s3-title', 138, 278, measure('一键建库', 130) + 30, 118,
                          t, 20.6, 21.35, 'y', 0.5))
    apply_highlights(img, strokes, b)


def scene4(img, f, t):
    """24~37s 刷题与 AI：答题卡 → 选中 → ✓ 印章 → AI 气泡 → BYOK"""
    b = boil(f)
    strokes = []
    if t >= 24.02:
        put(img, chip_sprite('s4q', '单选', 176, 62, 32)[b], 238, 172, rot=-2)
        put(img, text_img('革兰氏阳性菌细胞壁的主要成分是？', 46), 150, 268, anchor='lm')
    opts = [('A', '肽聚糖', 380), ('B', '脂多糖', 500), ('C', '外膜蛋白', 620), ('D', '荚膜多糖', 740)]
    for i, (k, s, cy) in enumerate(opts):
        t0 = 24.05 + i * 0.3
        if t < t0:
            continue
        u = oc(t, t0, t0 + 0.8)
        sel = (i == 0)
        dy = lerp(0, -10, oc(t, 26.2, 26.9)) if sel else 0
        put(img, styled_paper(f'opt-{k}', 700, 96, option_strip(k, s), segs=4)[b],
            lerp(-320, 500, u), cy + dy, rot=lerp(-1.2 + 0.8 * i, 0, u))
        if sel and t >= 26.35:
            strokes.append(hl('s4-optA', 250, cy - 28 + dy, 520, 56, t, 26.35, 26.85, 'y', 0.4))
    if t >= 27.2:                                   # ✓ 印章（scale-in 略过冲）
        do(img, 'vstamp', 120, 120, check_stamp, 905, 380, f, rot=-8, sc=ob(t, 27.2, 28.0) * 1.25)
    if t >= 28.2:                                   # AI 气泡自左展开 + 尾巴
        k = ob(t, 28.2, 29.2)
        paste_at(img, doodle('btail', 90, 70, bubble_tail)[b], U(1132), U(448), anchor='rm', sc=max(0.08, k))
        paste_at(img, bubble_sprite()[b], U(1130), U(330), anchor='lc', sc=max(0.08, k))
        if t >= 29.3:
            x0, w2 = substr_span(BUBBLE_L2, 30, False, '肽聚糖 + 磷壁酸')
            strokes.append(hl('s4-b1', 1176 + x0, 338, w2, 42, t, 29.3, 29.9, 'y', 0.3))
        if t >= 29.7:
            x0, w2 = substr_span(BUBBLE_L3, 30, False, '脂多糖')
            strokes.append(hl('s4-b2', 1176 + x0, 408, w2, 42, t, 29.7, 30.3, 'g', -0.3))
    if t >= 31.0:                                   # BYOK 副标 + 钥匙
        s = '用你自己的 Key，数据不出设备'
        put(img, text_img(s, 72), 150, 902 + lerp(46, 0, oc(t, 31.0, 31.8)), anchor='lm')
        x0, w2 = substr_span(s, 72, True, '数据不出设备')
        strokes.append(hl('s4-byok', 150 + x0 - 10, 868, w2 + 20, 66, t, 31.9, 32.5, 'g', 0.4))
    if t >= 32.3:
        do(img, 'keyd', 110, 100, key_doodle, 1352, 895, f, sc=ob(t, 32.3, 32.8))
    if t >= 32.6:                                   # 墨墨 pawprint 角落围观
        put_mascot(img, 'pawprint', lerp(1860, 1580, oc(t, 32.6, 33.6)), 850, 520, f)
    apply_highlights(img, strokes, b)


def scene5(img, f, t):
    """37~48s 复习：FSRS 遗忘曲线抬升（墨线 draw-on）+ 错题卡片叠放"""
    b = boil(f)
    strokes = []
    u_ax = seg(t, 37.05, 37.9)
    u_g = seg(t, 38.9, 39.6)
    u1 = seg(t, 38.05, 39.1)
    u2 = seg(t, 39.7, 40.3)
    u3 = seg(t, 40.3, 41.2)
    u4 = seg(t, 41.2, 41.7)
    u5 = seg(t, 41.7, 42.5)
    axes = [(200, 730), (1010, 730)]
    yaxis = [(200, 730), (200, 230)]
    ghost = [(455, 545), (560, 625), (700, 672), (850, 700), (995, 715)]
    d1 = [(230, 255), (300, 395), (380, 480), (455, 545)]
    up1 = [(455, 545), (472, 330)]
    d2 = [(472, 330), (560, 425), (650, 495), (745, 545)]
    up2 = [(745, 545), (762, 300)]
    d3 = [(762, 300), (845, 375), (925, 425), (995, 455)]

    def chart(p):
        if u_ax > 0.02:                              # 坐标轴 + 箭头
            p.line(poly_partial(axes, u_ax), 5)
            p.line(poly_partial(yaxis, u_ax), 5)
            if u_ax >= 0.98:
                p.line([(1010, 730), (988, 722)], 4.5)
                p.line([(1010, 730), (988, 738)], 4.5)
                p.line([(200, 230), (192, 252)], 4.5)
                p.line([(200, 230), (208, 252)], 4.5)
        if u1 > 0.02:                                # 主遗忘曲线（墨线 draw-on）
            p.line(poly_partial(d1, u1), 6)
        if u_g > 0.02:                                # 不复习的灰幽灵
            p.dashed(ghost, 3.5)
        for pts, u in ((up1, u2), (d2, u3), (up2, u4), (d3, u5)):
            if u > 0.02:
                p.line(poly_partial(pts, u), 6)

    if u_ax > 0.02:
        do_dynamic(img, 'fsrs', 1200, 900, chart, 0, 0, f, ss=2)
    if t >= 37.95:
        put(img, text_img('记忆留存', 30, bold=False, fill=INK_SOFT), 212, 200, anchor='lm')
        put(img, text_img('时间', 30, bold=False, fill=INK_SOFT), 950, 782, anchor='mm')
    if t >= 39.0:
        put(img, text_img('不复习', 26, bold=False, fill=INK_SOFT), 1005, 686, anchor='lm')
    for cx, cy, t0 in ((462, 618, 40.5), (753, 598, 41.6)):
        if t >= t0:
            put(img, chip_sprite(f'rv-{int(cy)}', '复习', 190, 62, 32, fill_bg=STICKER['y'])[b],
                cx, cy, rot=-2, sc=ob(t, t0, t0 + 0.45))
    wcs = [('w0', 'MHC Ⅱ 类分子表达于？', '已到期 4 天', 'y', 1300, 350, -3),
           ('w1', '补体经典途径始于？', '今天复习', 'g', 1362, 515, 2),
           ('w2', 'IgG 的功能不包括？', '明天复习', 'p', 1330, 680, -1)]
    for nm, line, ct, col, cx, cy, rot0 in wcs:
        t0 = 42.3 + (int(nm[1])) * 0.4
        if t < t0:
            continue
        put(img, wrong_card(nm, line, ct, col)[b], lerp(cx + 320, cx, oc(t, t0, t0 + 0.75)), cy, rot=rot0)
    if t >= 44.3:
        s = '错题本 + FSRS-5，只复习该看的'
        put(img, text_img(s, 80), 150, 922 + lerp(46, 0, oc(t, 44.3, 45.0)), anchor='lm')
        x0, w2 = substr_span(s, 80, True, '只复习该看的')
        strokes.append(hl('s5-sub', 150 + x0 - 10, 884, w2 + 20, 74, t, 45.1, 45.8, 'g', 0.35))
    apply_highlights(img, strokes, b)


def scene6(img, f, t):
    """48~57s 数据：真机 stats 纸框手机 + 数字滚动 + 热力图逐格点亮"""
    b = boil(f)
    strokes = []
    if t >= 48.02:                                   # 真机截图（手机纸框、轻微旋转、硬阴影）
        put(img, phone_sprite('stats.png')[b], 390, lerp(1180, 568, oc(t, 48.05, 49.3)), rot=-2.0)
    cols = [(930, '刷题量', 12480, lambda n: f'{n:,}'), (1320, '正确率', 874, lambda n: f'{n / 10:.1f}%'),
            (1710, '最长连击', 46, lambda n: f'{n} 天')]
    for i, (cx, label, target, fmt) in enumerate(cols):
        t0 = 49.3 + i * 0.25
        if t < t0:
            continue
        put(img, text_img(label, 34, bold=False, fill=INK_SOFT), cx, 238, anchor='mm')
        put(img, text_img(fmt(int(target * oc(t, t0, t0 + 1.3))), 96), cx, 332, anchor='mm')
    if t >= 51.2:                                   # 年度热力图：小格子逐个点亮
        put(img, text_img('年度坚持', 32, bold=False, fill=INK_SOFT), 760, 500, anchor='lm')
        cell, gap = 13.0, 4.0
        rng = random.Random('maojuan-heatmap')
        order = list(range(53 * 7))
        rng.shuffle(order)
        lv = [1 + ((i * 2654435761) % 100 < 45) + ((i * 40503) % 100 < 72) + ((i * 97) % 100 < 88)
              for i in range(53 * 7)]
        lit = int(seg(t, 51.2, 53.5) * 53 * 7)
        lit_set = set(order[:lit])
        d = ImageDraw.Draw(img)
        for idx in range(53 * 7):
            r, c = idx % 7, idx // 7
            x0 = U(760 + c * (cell + gap))
            y0 = U(545 + r * (cell + gap))
            box = [x0, y0, x0 + U(cell) - 1, y0 + U(cell) - 1]
            if idx in lit_set:
                d.rectangle(box, fill=HEAT[min(4, lv[idx])])
            else:
                d.rectangle(box, outline=(205, 199, 185), width=1)
    if t >= 53.5:
        s = '每一次刷题都算数'
        put(img, text_img(s, 88), 760, 812 + lerp(46, 0, oc(t, 53.5, 54.3)), anchor='lm')
        strokes.append(hl('s6-sub', 748, 770, measure(s, 88) + 26, 80, t, 54.4, 55.1, 'y', 0.4))
    apply_highlights(img, strokes, b)


def scene7_end(img, f, t):
    """定格结束画面：标题 + 猫爪印（+ slogan/落款小字）"""
    b = boil(f)
    strokes = []
    slogan = '题库文档，导入即刷'
    put(img, text_img('猫卷', 230), lerp(-520, 980, oc(t, 64.42, 65.32)), 430)
    if t >= 65.35:
        put(img, text_img(slogan, 64), 960, 640 + lerp(50, 0, oc(t, 65.35, 65.95)))
        sw = measure(slogan, 64)
        strokes.append(hl('s7-slogan', 960 - sw / 2 - 14, 610, sw + 28, 62, t, 65.7, 66.4, 'y', 0.6))
    if t < 65.4:
        px, py = lerp(170, 645, oc(t, 64.35, 65.2)), 470
    else:
        u = ease_in_cubic(seg(t, 65.4, 65.8))
        px, py = lerp(645, 40, u), lerp(470, 1240, u)
    do(img, 'paw', 100, 100, paw_print, px, py, f, rot=-12, sc=2.3)
    if t >= 65.9:                                   # 猫爪印落款（stamp scale-in 略过冲）
        do(img, 'paw-stamp', 100, 100, paw_print, 1520, 700, f, rot=10,
           sc=max(0.05, ob(t, 65.9, 66.6)) * 2.1)
    if t >= 66.6:
        put(img, text_img('Android · Windows · AGPL-3.0 开源 · GitHub 搜 猫卷', 40,
                          bold=False, fill=INK_SOFT), 960, 952 + lerp(30, 0, oc(t, 66.6, 67.2)))
    apply_highlights(img, strokes, b)


def scene7(img, f, t):
    """57~70s 收尾：墨墨 highlight + 三枚贴纸 → 下载/开源 → 定格"""
    if t >= 64.0:
        scene7_end(img, f, t)
        return
    b = boil(f)
    strokes = []
    if t >= 57.02:                                   # 墨墨 highlight 姿态
        put_mascot(img, 'highlight', lerp(2020, 1545, oc(t, 57.05, 58.1)), 660, 660, f)
    stickers = [('无账号', 430, 330, 'y', -3, 58.4), ('无广告', 830, 300, 'g', 2, 58.75),
                ('完全免费', 1230, 335, 'p', -2, 59.1)]
    for s, cx, cy, col, rot0, t0 in stickers:
        if t >= t0:
            spr = styled_paper('stk-' + s, 384, 136,
                               (lambda ss: (lambda g: g.text(ss, 192, 68, 58, anchor='mm')))(s),
                               fill=STICKER[col], line=2.4, shadow=4.5, segs=4)
            put(img, spr[b], cx, cy, rot=rot0, sc=ob(t, t0, t0 + 0.6))
    for s, cx, t0 in (('Android', 390, 60.4), ('Windows', 710, 60.7)):
        if t >= t0:
            put(img, chip_sprite('dl-' + s, s, 280, 84, 40)[b], cx, 560, rot=-1, sc=ob(t, t0, t0 + 0.5))
    if t >= 61.0:
        s = 'AGPL-3.0 开源 · GitHub 搜 猫卷'
        put(img, text_img(s, 56), 250, 722 + lerp(40, 0, oc(t, 61.0, 61.7)), anchor='lm')
        x0, w2 = substr_span(s, 56, True, 'GitHub 搜 猫卷')
        strokes.append(hl('s7-oss', 250 + x0 - 10, 695, w2 + 20, 52, t, 61.8, 62.5, 'g', 0.3))
    apply_highlights(img, strokes, b)


SCENES = [scene1, scene2, scene3, scene4, scene5, scene6, scene7]


def draw_frame(bg, f):
    t = f / FPS
    img = bg.copy()
    for (t0, t1, _), fn in zip(BEATS, SCENES):
        if t0 <= t < t1:
            fn(img, f, t)
            break
    draw_transitions(img, t)
    return img


# ---------------------------------------------------------------- 渲染 / 编码
def render_frames(bg, build_dir, fps, quiet=False):
    n = int(round(DURATION * fps))
    build_dir.mkdir(parents=True, exist_ok=True)
    for f in range(n):
        draw_frame(bg, f).save(build_dir / f'f_{f + 1:05d}.png', compress_level=1)
        if not quiet and f % 150 == 0:
            print(f'  帧 {f + 1}/{n}  t={f / fps:.1f}s')
    return n


def run_ffmpeg(args):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stderr[-2000:])
        raise SystemExit(f'ffmpeg 失败：{" ".join(map(str, args[:6]))}…')
    return r


def encode_video(build_dir, out_path, fps):
    run_ffmpeg(['ffmpeg', '-y', '-framerate', str(fps), '-i', str(build_dir / 'f_%05d.png'),
                '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', '-movflags', '+faststart',
                '-hide_banner', '-loglevel', 'error', str(out_path)])


def grab_frame(video, t, png_path):
    run_ffmpeg(['ffmpeg', '-y', '-ss', f'{t:.3f}', '-i', str(video), '-frames:v', '1', '-update', '1',
                '-hide_banner', '-loglevel', 'error', str(png_path)])


def make_poster(video, t, poster_path):
    """海报帧：最好看的关键帧、16:9、质量 88"""
    tmp = poster_path.parent / '_poster_tmp.png'
    grab_frame(video, t, tmp)
    Image.open(tmp).convert('RGB').save(poster_path, quality=88)
    tmp.unlink()


def make_samples(video, samples_dir, times):
    """8 张跨节拍样帧（frame_01..08.png）"""
    samples_dir.mkdir(parents=True, exist_ok=True)
    for i, t in enumerate(times, 1):
        grab_frame(video, t, samples_dir / f'frame_{i:02d}.png')


def video_stats(path):
    r = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0',
                        '-show_entries', 'stream=width,height,r_frame_rate,nb_read_frames,duration',
                        '-count_frames', '-show_entries', 'format=size', '-of', 'default=nw=1',
                        str(path)], capture_output=True, text=True)
    return r.stdout.strip()


def main():
    global S, W, H
    ap = argparse.ArgumentParser(description='猫卷宣传动画《草稿纸与荧光笔》生成器')
    ap.add_argument('--out', default=str(DEFAULT_OUT), help='输出 mp4 路径')
    ap.add_argument('--poster', default=str(DEFAULT_POSTER), help='输出海报 jpg 路径')
    ap.add_argument('--samples-dir', default=str(DEFAULT_SAMPLES), help='8 张样帧输出目录')
    ap.add_argument('--build-dir', default=str(DEFAULT_BUILD), help='临时帧目录（仓库外）')
    ap.add_argument('--scale', type=float, default=1.0, help='0.5 = 960×540 快速试跑')
    ap.add_argument('--fps', type=int, default=FPS)
    ap.add_argument('--stills', default='', help='仅渲染这些时间点关键帧（逗号分隔）→ build-dir/stills/')
    ap.add_argument('--poster-time', type=float, default=3.55, help='海报取帧时间（s）')
    ap.add_argument('--sample-times', default='3.55,9.2,15.9,30.1,41.3,52.8,59.7,68.3',
                    help='8 张跨节拍样帧时间点')
    ap.add_argument('--skip-encode', action='store_true', help='只渲染帧，不合成 mp4')
    ap.add_argument('--skip-samples', action='store_true', help='不抽取样帧/海报')
    ap.add_argument('--clean-frames', action='store_true', help='合成后删除临时帧目录')
    args = ap.parse_args()

    S = args.scale
    W, H = int(DESIGN_W * S), int(DESIGN_H * S)
    build_dir = Path(args.build_dir)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    print(f'画布 {W}×{H} @ {args.fps}fps  时长 {DURATION}s  临时帧 {build_dir}')
    bg = build_bg()

    if args.stills:                                     # 美术校对模式
        still_dir = build_dir / 'stills'
        still_dir.mkdir(parents=True, exist_ok=True)
        for t in [float(x) for x in args.stills.split(',') if x.strip()]:
            p = still_dir / f'still_{t:06.2f}s.png'
            draw_frame(bg, int(round(t * args.fps))).save(p)
            print('  still →', p)
        return

    n = render_frames(bg, build_dir, args.fps)
    print(f'渲染完成：{n} 帧')
    if args.skip_encode:
        return

    encode_video(build_dir, out_path, args.fps)
    print('成片 →', out_path)
    print(video_stats(out_path))

    if not args.skip_samples:
        times = [float(x) for x in args.sample_times.split(',') if x.strip()]
        make_samples(out_path, Path(args.samples_dir), times[:8])
        print('样帧 →', args.samples_dir)
        make_poster(out_path, args.poster_time, Path(args.poster))
        print('海报 →', args.poster, f'(t={args.poster_time}s)')
    if args.clean_frames:
        shutil.rmtree(build_dir, ignore_errors=True)
        print('已清理临时帧目录')


if __name__ == '__main__':
    main()
