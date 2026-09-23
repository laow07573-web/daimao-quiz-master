# -*- coding: utf-8 -*-
"""猫卷吉祥物「墨墨」——草稿纸风格简笔黑猫，多姿态 × 抖动变体（定格动画用）。

风格：纯黑墨线（#1A1A18）勾边、纸色留白不填色、线条略抖（boil）。
输出 site/assets/mascot-<pose>-<seed>.png（透明底），官网与宣传视频共用同一来源。

姿态：wave（站立挥爪）/ highlight（举荧光笔划重点）/ pawprint（按爪印）。
每个姿态出 3 个抖动变体（seed 0/1/2），动画里循环播放即得手绘翻页感。
"""
import math
import os
import random

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "site", "assets")
INK = (26, 26, 24, 255)
S = 4  # 超采样倍数（抗锯齿）


class Hand:
    """带抖动的手绘笔：所有坐标过一道 jitter，线宽轻微呼吸"""

    def __init__(self, draw: ImageDraw.ImageDraw, rng: random.Random, scale: int):
        self.d = draw
        self.rng = rng
        self.s = scale

    def j(self, x: float, y: float):
        return (x * S + self.rng.uniform(-1.6, 1.6), y * S + self.rng.uniform(-1.6, 1.6))

    def line(self, pts, w: float = 3.2):
        wob = w * S * self.rng.uniform(0.9, 1.12)
        self.d.line([self.j(x, y) for x, y in pts], fill=INK, width=int(wob), joint="curve")
        for x, y in (pts[0], pts[-1]):  # 圆头
            r = wob / 2
            px, py = self.j(x, y)
            self.d.ellipse([px - r, py - r, px + r, py + r], fill=INK)

    def arc(self, cx, cy, r, a0, a1, w: float = 3.2, ry=None):
        ry = r if ry is None else ry
        pts = []
        n = max(10, int(abs(a1 - a0) / 6))
        for i in range(n + 1):
            a = math.radians(a0 + (a1 - a0) * i / n)
            pts.append((cx + r * math.cos(a), cy + ry * math.sin(a)))
        self.line(pts, w)

    def circle(self, cx, cy, r, w: float = 3.2, ry=None):
        self.arc(cx, cy, r, 0, 360, w, ry)

    def dot(self, cx, cy, r: float = 2.2):
        px, py = self.j(cx, cy)
        rr = r * S * self.rng.uniform(0.85, 1.2)
        self.d.ellipse([px - rr, py - rr, px + rr, py + rr], fill=INK)

    def tri(self, p1, p2, p3, w: float = 3.2):
        self.line([p1, p2, p3, p1], w)


def draw_cat(h: Hand, pose: str):
    """100×100 逻辑坐标里的墨墨（大头探爪贴纸式：头 + 两小爪 + 卷尾）"""
    # 尾巴（从头后卷出）
    h.line([(68, 54), (78, 52), (83, 45), (81, 37)], 3.2)
    # 头（略椭圆）+ 耳朵
    h.circle(50, 38, 20, w=3.6, ry=17)
    h.tri((34, 26), (30, 10), (44, 18))
    h.tri((66, 26), (70, 10), (56, 18))
    # 脸
    h.dot(43, 38, 2.4)
    h.dot(57, 38, 2.4)
    h.line([(48, 45), (50, 47), (52, 45)], 2.4)  # ᴗ 嘴
    for i, dy in enumerate((42, 46)):  # 胡须
        h.line([(36, dy - 1), (22, dy - 3 + i)], 1.8)
        h.line([(64, dy - 1), (78, dy - 3 + i)], 1.8)
    # 两只小爪搭在头底（探头感）
    h.arc(38, 56, 7, 180, 360, 3.0)
    h.arc(62, 56, 7, 180, 360, 3.0)

    if pose == "wave":
        h.line([(68, 52), (78, 42)], 3.4)  # 挥起的小爪
        h.circle(80, 38, 5, 2.8)
    elif pose == "highlight":
        # 荧光笔斜在头右侧（不压脸）：黄杆由调用方先铺，这里勾墨线轮廓
        h.line([(74, 58), (92, 38)], 4.5)
        h.line([(92, 38), (97, 33)], 3.2)
    elif pose == "pawprint":
        # 一枚爪印落在头左下的纸面上（避开胡须）
        h.circle(14, 64, 5.5, 2.6)
        for dx in (-5, 0, 5):
            h.dot(14 + dx, 56 + (0 if dx == 0 else 2), 1.8)


def render(pose: str, seed: int) -> Image.Image:
    rng = random.Random(f"maojuan-{pose}-{seed}")
    im = Image.new("RGBA", (100 * S, 100 * S), (0, 0, 0, 0))
    draw_cat(Hand(ImageDraw.Draw(im), rng, S), pose)
    return im.resize((600, 600), Image.LANCZOS)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for pose in ("wave", "highlight", "pawprint"):
        for seed in range(3):
            p = os.path.join(OUT, f"mascot-{pose}-{seed}.png")
            render(pose, seed).save(p)
            print(p)
