# -*- coding: utf-8 -*-
"""猫卷 meme 宣传片《Why's this dealer taking the piss?》生成器（135 BPM 拍网格锁死）。

歌与梗：Niko B - Why's this dealer?（2024，Believe UK，135 BPM、4/4、全长 129.6s）讲的是
「雨里干等贩子半小时、贩子狂飙赶到」。猫卷就是那个题贩子——但它带着你的讲义狂飙赶到：
讲义变题、秒判秒讲、不用等。视觉母语 = 二创圈「弹跳丰田威姿」：卡片/手机/吉祥物每个整拍
一次解析式果冻 squash&stretch，多物件错相位 10~30ms，像一排威姿踩着鼓点跳舞。

拍网格合同（验收线）：
    t_k = k × 60/bpm（默认 135 → 1 拍 0.444444444s，1 小节 1.777777778s，1 十六分 0.111111111s）
    事件真源 = 十六分格位 idx16（音乐位置）；渲染时间 t_event = idx16 × 15/bpm，天然落在
    整拍/十六分格点上（整拍 = idx16%4==0）。beatmap.txt 每条事件都可核对。
    吸附规则：给定时间戳（Hook punch 行 / 段落边界）→ snap 到最近十六分格点；自设踩拍事件
    = 锚点 + 整拍偏移。--bpm 变化 → 锚点按给定时间重新吸附、下游偏移跟随 = 全事件自动重排。

果冻弹跳为什么用解析式（jelly()/hop()/punch_env()）而不是逐帧物理模拟：拍网格要求每拍形变
可预测、可复现；解析式直接吃相位参数（多物件错相位 10-30ms 就是相位平移），改 --bpm 重排后
同一套形变仍精确压在拍点上，渲染可审计、可回归；物理模拟会逐帧漂移，没法保证「压扁恰在拍点」。

拿到音源后一条命令 mux（成片无音轨，-c:v copy 零重编码）：
    ffmpeg -i test_out.mp4 -i song.mp3 -c:v copy -c:a aac -shortest 猫卷-题贩子.mp4
音源到位后可用 D:\\dev\\maojuan_private\\dealer_video\\beat_sync.py 核验 BPM 是否真是 135、
拍网是否对齐（必要时用 --bpm 微调重排）：
    ffmpeg -i song.mp3 -ac 1 -ar 22050 song.wav
    python D:\\dev\\maojuan_private\\dealer_video\\beat_sync.py song.wav

用法：
    python tool/make_dealer_video.py                     # 1080p30 全片出片（默认 0~129.6s）
    python tool/make_dealer_video.py --scale 0.5         # 先 540p 试跑节奏/美术
    python tool/make_dealer_video.py --stills 14.13,21.2,56.82   # 只渲关键帧做美术校对
    python tool/make_dealer_video.py --bpm 134.6 --end 129.964   # 微调 BPM 全事件重排（--end 按 129.6×135/bpm 等比）
    python tool/make_dealer_video.py --beatmap-only      # 只出 beatmap.txt（秒级，可核对网格）

产物（--out 同目录）：
    test_out.mp4   1920×1080 / 30fps / H.264 yuv420p crf20 +faststart / 无音轨 / 129.6s
    beatmap.txt    全部事件 → 秒数 + 拍号（bar.beat.sxt）+ 核验段（含抽查）
    sync_proof\\    ≥8 个关键事件的前 2/后 2 帧（另含命中帧），文件名含事件名与拍号
    frames_build\\  帧目录（背景/装饰/吉祥物预合成小图复用，逐帧只做变换与合成）
"""
import argparse
import math
import random
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

# ---------------------------------------------------------------- 调色板 / 画布
INK = (26, 26, 24, 255)          # #1A1A18 墨线
INK_SOFT = (107, 102, 92, 255)   # 次级文字
BAR_GRAY = (186, 180, 166, 255)  # 假文本条
PAPER = (246, 241, 231)          # #F6F1E7 暖纸底
PAPER_LINE = (230, 223, 208)     # 极淡横线纹理
CARD = (255, 253, 248, 255)      # #FFFDF8 白纸片
SLOT_DARK = (54, 52, 47, 255)    # 纸盒入口
RAIN = (122, 118, 108)           # 雨丝（细墨线）
HL = {'y': (255, 241, 118), 'g': (174, 245, 180), 'p': (255, 191, 218)}    # multiply 补偿色
STICKER = {'y': (255, 232, 107), 'g': (168, 230, 163), 'p': (255, 179, 198)}  # #FFE86B/#A8E6A3/#FFB3C6
SHADOW = (0, 0, 0, 26)           # 硬偏移阴影：0 模糊、黑 10%
HEAT = [(219, 223, 210), (223, 242, 219), (192, 233, 185), (160, 224, 152), (116, 204, 108)]

DESIGN_W, DESIGN_H = 1920, 1080
FPS = 30
TOTAL_SEC = 129.6                # 歌曲全长（135 BPM 事实），默认渲染窗 0~129.6s

ROOT = Path(__file__).resolve().parent.parent
FONTS_DIR = ROOT / 'fonts'
SITE_ASSETS = ROOT / 'site' / 'assets'
SCREENSHOTS = ROOT / 'docs' / 'screenshots'
DEFAULT_OUT = Path(r'D:\dev\maojuan_private\dealer_video\test_out.mp4')
DEFAULT_FRAMES = Path(r'D:\dev\maojuan_private\dealer_video\frames_build')

SONG_FACTS = (                   # 歌曲事实（已核实）：段落给定时间戳 → 事件吸附到最近拍上
    ('intro',   'Intro',      0.0,  14.2),
    ('chorus1', 'Chorus①',   14.2,  27.9),
    ('verse1',  'Verse 1',    27.9,  56.8),
    ('chorus2', 'Chorus②',   56.8,  70.6),
    ('verse2',  'Verse 2',    70.6,  99.4),
    ('chorus3', 'Chorus③',   99.4, 113.7),
    ('chorus4', 'Chorus④',  113.7, 123.9),
    ('outro',   '尾奏',      123.9, 129.6),
)

S = 1.0                          # 全局缩放（--scale 0.5 → 960×540 试跑）
W, H = DESIGN_W, DESIGN_H
GRID = None                      # Grid 实例（main 里按 --bpm 建立）


def U(v):
    """设计坐标/尺寸 → 输出像素（浮点）"""
    return v * S


def UI(v):
    """设计坐标/尺寸 → 输出像素（整数 ≥1）"""
    return max(1, int(round(v * S)))


# ---------------------------------------------------------------- 拍网格
class Grid:
    """拍网格：事件以十六分格位 idx16 存储（= 音乐位置），秒数按 bpm 换算。

    为什么格位是真源而不是秒：--bpm 微调后「全事件自动重排到新网格」只改换算系数与吸附结果，
    事件之间「每 4 拍一镜 / 每拍一果冻 / 每十六分点亮一格」的拍关系天然保持不变。
    """

    def __init__(self, bpm, fps=FPS):
        self.bpm = float(bpm)
        self.fps = fps
        self.beat = 60.0 / self.bpm              # 1 拍秒数（135 → 0.444444444s）
        self.sixteenth = self.beat / 4.0         # 1 十六分格秒数（135 → 0.111111111s）

    def t(self, idx16):
        """格位 → 秒（t = idx16 × 15/bpm，天然在格点上）"""
        return idx16 * self.sixteenth

    def snap16(self, sec):
        """给定时间 → 最近十六分格位（整拍是十六分格点的子集，最坏偏差 = 半个十六分）"""
        return int(round(sec / self.sixteenth))

    def beat_no(self, idx16):
        """全局拍号（如 31.75）"""
        return idx16 / 4.0

    @staticmethod
    def bar_label(idx16):
        """拍号 → bar.beat.sxt（4/4；idx16%4==0 即整拍）"""
        return f'B{idx16 // 16 + 1}.{(idx16 % 16) // 4 + 1}.{idx16 % 4 + 1}'

    def is_beat(self, idx16):
        return idx16 % 4 == 0


def bx(anchor, beats):
    """锚点 + 整拍偏移（beats 可为 0.5 等半拍）→ 格位"""
    return anchor + int(round(beats * 4))


def beat_up(idx16):
    """格位向上取整到整拍（切镜等要落在拍头上）"""
    return -(-idx16 // 4) * 4


# ---------------------------------------------------------------- 事件表（唯一真源）
class Ev:
    """动画事件：name=事件名（英文/文件名安全）；label=中文说明；target=给定时间（吸附来源）"""

    __slots__ = ('name', 'label', 'idx16', 'section', 'target', 'note')

    def __init__(self, name, label, idx16, section, target=None, note=''):
        self.name, self.label, self.idx16 = name, label, int(idx16)
        self.section, self.target, self.note = section, target, note


def build_events(g):
    """全部动画事件 → [Ev]（按格位排序）。渲染与 beatmap.txt 都只认这张表。

    两类来源：
    1) 给定时间戳（Hook punch 行 / 段落边界 / 17.0s 字幕）→ g.snap16() 吸附最近十六分格点；
    2) 自设踩拍事件 = 锚点 + 整拍偏移（--bpm 变化时随锚点整体重排，拍关系不变）。
    """
    snap = g.snap16
    E = []

    def add(name, label, idx16, section, target=None, note=''):
        E.append(Ev(name, label, idx16, section, target, note))

    # ---- 段落锚点（给定时间吸附；段落开场 punch/切镜与锚点共用同一事件，避免两个真源） ----
    a_intro = snap(0.0)          # 135BPM: 0
    a_c1 = snap(14.13)           # Hook punch 行 14.13s → 127（beat 31.75，bar 8 最后一个十六分）
    a_v1 = snap(27.9)            # → 251
    a_c2 = snap(56.82)           # Hook punch 行 56.82s → 511
    a_v2 = snap(70.6)            # → 635
    a_c3 = snap(99.46)           # Hook punch 行 99.46s → 895
    a_c4 = snap(113.68)          # Hook punch 行 113.68s → 1023
    a_out = snap(123.9)          # → 1115
    t_sub = snap(17.0)           # 17.0s 中文字幕 → 153（恰在十六分格点）
    t_p2 = snap(21.20)           # Hook punch 行 21.20s → 191
    t_line = snap(63.74)         # Hook punch 行 63.74s → 574
    t_p3 = snap(106.52)          # Hook punch 行 106.52s → 959
    t_slg = snap(120.78)         # Hook punch 行 120.78s → 1087

    # ================= Intro 0.0–14.2「等」 =================
    add('intro_scene_in', '开场：纸伞下顶讲义蹲守 + 雨丝', a_intro, 'intro', 0.0, '段落锚点')
    add('waitcard_01_flip', '等待三连①踩拍翻面「押题资料 · 404」', bx(a_intro, 16), 'intro', None,
        'beat 16 整拍')
    add('waitcard_02_flip', '等待三连②踩拍翻面「网课缓冲 · 87%」', bx(a_intro, 18), 'intro', None,
        'beat 18 整拍')
    add('waitcard_03_flip', '等待三连③踩拍翻面「外卖式讲解 · 骑手正在赶」', bx(a_intro, 20), 'intro',
        None, 'beat 20 整拍')
    add('intro_caption_in', '大字幕 punch 进场「期末周，我在等一个救星」', bx(a_intro, 24), 'intro',
        10.667, '最后 2 小节（beat 24 = bar 7 起）')
    add('waitcard_01_out', '纸卡①翻面退场', bx(a_intro, 29), 'intro')
    add('waitcard_02_out', '纸卡②翻面退场', bx(a_intro, 29.5), 'intro', None, '半拍错开')
    add('waitcard_03_out', '纸卡③翻面退场', bx(a_intro, 30), 'intro')
    add('intro_caption_out', '大字幕 punch 退场', bx(a_intro, 31), 'intro')

    # ================= Chorus① 14.2–27.9「题贩子驾到」 =================
    add('hook_punch_title', "PUNCH 大字幕「WHY'S THIS DEALER TAKING THE PISS?」（超粗+手绘抖）",
        a_c1, 'chorus1', 14.13, 'Hook punch 行；段落锚点')
    add('qcard_fall_start', '题目卡从天而降（起跳）', bx(a_c1, 2.25), 'chorus1')
    add('qcard_land', '题目卡砸在纸面（大 squash）→ 此后每拍弹跳', bx(a_c1, 4.25), 'chorus1')
    add('title_out', 'PUNCH 大字幕 punch-out', bx(a_c1, 5.25), 'chorus1')
    add('cn_subtitle_in', '中文字幕「为什么这个题贩子让我等半天？！」', t_sub, 'chorus1', 17.0,
        '17.0s 恰在十六分格点（beat 38.25）')
    add('hook_punch2', 'PUNCH 2（缩放 1.08 冲击环）', t_p2, 'chorus1', 21.20, 'Hook punch 行')
    add('qcard_dance_on', '卡片切「跳舞」模式（摇摆+弹，威姿群舞单卡版）', t_p2, 'chorus1', 21.20,
        '与 punch2 同拍')
    add('cn_subtitle_out', '中文字幕退场', bx(a_c1, 26.25), 'chorus1')
    add('qcard_exit', '题目卡 punch-out', bx(a_c1, 29.25), 'chorus1')

    # ================= Verse 1 27.9–56.8「干等实录」 =================
    add('verse1_title_in', '段落标题 punch「干等实录」', a_v1, 'verse1', 27.9, '段落锚点')
    shot0_v1 = beat_up(a_v1 + 5)                 # 标题 1 拍引导后，切镜全部落整拍（135BPM: 256）
    for k in range(16):                          # 4 拍一镜 × 16 镜（4 场景 × 4 循环）
        add(f'v1_shot_{k + 1:02d}', f'蒙太奇切镜 {k + 1:02d}（4 拍一镜）', shot0_v1 + 16 * k,
            'verse1', None, f'beat {g.beat_no(shot0_v1 + 16 * k):g} 整拍')
    add('v1_title_out', '段落标题退场', shot0_v1 + 4, 'verse1')
    caps = ['等押题等成望夫石', '讲解比外卖还慢', '讲义 300 页，题呢？', '雨都小了，进度条没动']
    for k, cap in enumerate(caps):               # 每 4 小节一句吐槽（第 4 句自拟补足 4 槽）
        add(f'v1_cap_{k + 1}_in', f'吐槽字幕「{cap}」', shot0_v1 + 64 * k, 'verse1', None,
            f'beat {g.beat_no(shot0_v1 + 64 * k):g} = 每 4 小节')
        add(f'v1_cap_{k + 1}_out', f'吐槽字幕{k + 1}退场', shot0_v1 + 64 * k + 56, 'verse1')

    # ================= Chorus② 56.8–70.6「真身揭晓」 =================
    add('phone_drift_in', '手机纸框（home.png）从右滑跳甩尾入场（急刹甩尾）', a_c2, 'chorus2', 56.82,
        'Hook punch 行；段落锚点')
    add('phone_land', '手机甩尾落定（阻尼回摆收束）', bx(a_c2, 2), 'chorus2')
    add('brand_text_in', '大字「猫卷 · 把讲义变成能刷的题」', bx(a_c2, 2), 'chorus2')
    add('hl_no_wait', '荧光黄涂抹 punch「不用等」', bx(a_c2, 4), 'chorus2')
    add('cards_lineup', 'PUNCH：4 张题目卡一字排开群舞（错相位 0/12/21/30ms）', t_line, 'chorus2',
        63.74, 'Hook punch 行')
    add('cards_dance_unison', '4 卡去相位 → 齐弹两轮', t_line + 28, 'chorus2', None, '7 拍后')

    # ================= Verse 2 70.6–99.4「狂飙赶到」 =================
    add('verse2_title_in', '段落标题 punch「狂飙赶到」+ 速度线', a_v2, 'verse2', 70.6, '段落锚点')
    shot0_v2 = beat_up(a_v2 + 5)                 # 135BPM: 640
    for k in range(16):
        add(f'v2_shot_{k + 1:02d}', f'工作流切镜 {k + 1:02d}（4 拍一镜 × 4 轮）', shot0_v2 + 16 * k,
            'verse2', None, f'beat {g.beat_no(shot0_v2 + 16 * k):g} 整拍')
    add('v2_title_out', '段落标题退场', shot0_v2 + 4, 'verse2')
    for c in range(4):                           # 4 轮循环 × 4 镜（讲义进炉/插图随题/秒判秒讲/FSRS）
        base, n = shot0_v2 + 64 * c, c + 1
        add(f'v2_chips_fly_{n}', f'轮{n}：DOCX/PDF 纸片飞入猫卷', base, 'verse2')
        add(f'v2_card_pop_{n}', f'轮{n}：题卡带小插图弹出', base + 16, 'verse2')
        add(f'v2_stamp_{n}_1', f'轮{n}：✓ 印章咚咚落（第 1 印）', base + 32, 'verse2')
        add(f'v2_stamp_{n}_2', f'轮{n}：✓ 印章咚咚落（第 2 印）', base + 36, 'verse2', None, '1 拍后')
        add(f'v2_bubble_{n}', f'轮{n}：AI 讲解气泡 + 荧光笔划重点', base + 40, 'verse2')
        add(f'v2_fsrs_{n}', f'轮{n}：FSRS 曲线墨线 draw-on', base + 48, 'verse2')
        add(f'v2_review_{n}', f'轮{n}：「下次复习 · 明天」标签', base + 56, 'verse2')

    # ================= Chorus③ 99.4–113.7「算得清」 =================
    add('stats_phone_in', 'stats.png 进画 + 数字滚动起转', a_c3, 'chorus3', 99.46,
        'Hook punch 行；段落锚点')
    r0 = beat_up(a_c3 + 1)                       # 第一个整拍起滚（135BPM: 896 = beat 224）
    for k, nm in enumerate(('num_1', 'num_2', 'num_3')):
        add(f'{nm}_roll', f'数字滚动{k + 1}起转', r0 + 4 * k, 'chorus3', None, '1 拍一列')
        add(f'{nm}_land', f'数字{k + 1}落定（落定 squash）', r0 + 4 * k + 8, 'chorus3', None, '滚 2 拍')
    for k in range(128):                         # 8×16 热力图：每十六分点亮一格（1 拍 4 格）
        add(f'heat_cell_{k + 1:03d}', f'热力图第 {k + 1:03d} 格点亮（16 分逐格）', a_c3 + k, 'chorus3',
            None, (f'第 {k // 4 + 1} 拍整拍' if k % 4 == 0 else f'第 {k // 4 + 1} 拍第 {k % 4 + 1} 个16分'))
    add('punch3_phone_jelly', 'PUNCH：手机果冻猛弹一下', t_p3, 'chorus3', 106.52, 'Hook punch 行')

    # ================= Chorus④ 113.7–123.9「不等了」 =================
    add('sticker_1', '贴纸 punch①「无账号」', a_c4, 'chorus4', 113.68,
        'Hook punch 行；段落锚点；三贴纸各一拍')
    add('sticker_2', '贴纸 punch②「无广告」', bx(a_c4, 1), 'chorus4', None, '1 拍后')
    add('sticker_3', '贴纸 punch③「完全免费」', bx(a_c4, 2), 'chorus4', None, '1 拍后')
    add('slogan_freeze', 'SLOGAN 定格「把讲义变成能刷的题」', t_slg, 'chorus4', 120.78,
        'Hook punch 行')
    add('download_line', '下载行「Android / Windows · AGPL-3.0 开源」', bx(t_slg, 1), 'chorus4')

    # ================= 尾奏 123.9–129.6 =================
    add('outro_scene', '墨墨 highlight 姿态定格', a_out, 'outro', 123.9, '段落锚点')
    add('paw_1', '爪印①落印', bx(a_out, 0.5), 'outro', None, '半拍错开（咚-咚-咚）')
    add('paw_2', '爪印②落印', bx(a_out, 1.0), 'outro')
    add('paw_3', '爪印③落印', bx(a_out, 1.5), 'outro')
    add('final_caption', '终字幕「不用等贩子 —— 讲义自己变题」', bx(a_out, 2.0), 'outro')

    E.sort(key=lambda e: (e.idx16, e.name))
    return E


# sync_proof 抽帧名单：≥8 个关键事件（覆盖 punch/落地/甩尾/群舞/16 分点亮/印章/定格）
SYNC_PROOF = [
    'waitcard_01_flip', 'intro_caption_in', 'hook_punch_title', 'qcard_fall_start', 'qcard_land',
    'hook_punch2', 'v1_shot_01', 'phone_drift_in', 'cards_lineup', 'v2_stamp_1_1',
    'stats_phone_in', 'heat_cell_033', 'punch3_phone_jelly', 'sticker_1', 'slogan_freeze',
    'final_caption',
]


class Timeline:
    """事件表 + 网格的查询门面：场景代码只写事件名，时间永远来自格位换算（单一真源）。"""

    def __init__(self, events, grid):
        self.ev = {e.name: e for e in events}
        self.grid = grid

    def t(self, name):
        return self.grid.t(self.ev[name].idx16)


# ---------------------------------------------------------------- 缓动 / 解析式果冻
def clamp01(x):
    return 0.0 if x < 0 else (1.0 if x > 1 else x)


def seg(t, t0, t1):
    return clamp01((t - t0) / (t1 - t0)) if t1 > t0 else 1.0


def lerp(a, b, u):
    return a + (b - a) * u


def ease_out_cubic(u):
    return 1 - (1 - u) ** 3


def ease_in_cubic(u):
    return u ** 3


def ease_out_back(u, k=1.70158):
    v = u - 1
    return 1 + v * v * ((k + 1) * v + k)


def ease_in_out(u):
    return u * u * (3 - 2 * u)


def key_interp(p, keys):
    """分段关键帧 + 余弦缓动（果冻/punch 共用）：keys=[(p, v...), ...]"""
    if p <= keys[0][0]:
        return keys[0][1:]
    for i in range(len(keys) - 1):
        p0, *v0 = keys[i]
        p1, *v1 = keys[i + 1]
        if p <= p1 or i == len(keys) - 2:
            u = 0.5 - 0.5 * math.cos(math.pi * clamp01((p - p0) / (p1 - p0)))
            return tuple(lerp(a, b, u) for a, b in zip(v0, v1))
    return keys[-1][1:]


# 每拍一次 squash&stretch 关键帧：压扁 0.94×/1.08 → 弹回 1.0×（Q 弹的招牌曲线）
JELLY_KEYS = [(0.00, 1.080, 0.940),   # 落地压扁
              (0.14, 0.958, 1.058),   # 反向拉伸（果冻回弹）
              (0.30, 1.014, 0.986),   # 二次小回摆
              (0.48, 1.000, 1.000)]   # 归位保持到下一拍
PUNCH_KEYS = [(0.0, 1.0), (0.16, 1.08), (0.40, 0.975), (0.66, 1.01), (1.0, 1.0)]


def beat_phase(t, phase=0.0):
    """拍内相位 p∈[0,1)；phase = 秒单位的错相位（多物件 10-30ms = 相位平移）"""
    return ((t - phase) / GRID.beat) % 1.0


def jelly(t, phase=0.0):
    """招牌果冻：每拍一次 squash&stretch，解析式关键帧（不吃历史状态，可复现）"""
    return key_interp(beat_phase(t, phase), JELLY_KEYS)


def hop(t, phase=0.0, height=0.0):
    """每拍一次果冻跳：p=0/1 触地，中段抛物线抬升（落地瞬间正压在 squash 上）"""
    if height <= 0:
        return 0.0
    p = beat_phase(t, phase)
    q = min(p / 0.88, 1.0)                     # 0.88 拍完成跳跃，留 0.12 拍下蹲预备
    return -height * 4.0 * q * (1.0 - q)


def punch_env(t, t0, dur):
    """冲击 pop（punch 点）：1 → 1.08 → 0.975 → 1.0，与果冻同一形变母语"""
    return key_interp(seg(t, t0, t0 + dur), PUNCH_KEYS)[0]


def flip_scalex(t, t0, dur):
    """翻面：|cos| 半程折叠，0.5 处换面（解析式，恰好踩在拍窗内）"""
    u = seg(t, t0, t0 + dur)
    return abs(math.cos(math.pi * u)), u


def drift_damp(u, freq=1.15, damp=3.0):
    """急刹甩尾的阻尼回摆（解析弹簧）：快速逼近 + 过冲 + 摆尾归位"""
    return math.exp(-damp * u) * math.cos(2 * math.pi * freq * u)


def sway_swing(u, freq=1.15, damp=3.0):
    return math.exp(-damp * u) * math.sin(2 * math.pi * freq * u)


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
_hand_cache = {}


def get_font(size, bold=True):
    key = (UI(size), bold)
    f = _font_cache.get(key)
    if f is None:
        path = FONTS_DIR / ('MiSans-Semibold.ttf' if bold else 'MiSans-Regular.ttf')  # 必须 truetype
        f = ImageFont.truetype(str(path), UI(size))
        _font_cache[key] = f
    return f


def text_img(s, size, bold=True, fill=INK, stroke=0):
    """文本 → RGBA 小图（缓存；stroke>0 加粗成「超粗」标题）"""
    key = (s, UI(size), bold, fill, stroke)
    im = _text_cache.get(key)
    if im is None:
        fnt = get_font(size, bold)
        probe = ImageDraw.Draw(Image.new('RGBA', (1, 1)))
        bb = probe.textbbox((0, 0), s, font=fnt, stroke_width=stroke)
        pad = UI(6) + stroke
        im = Image.new('RGBA', (bb[2] - bb[0] + 2 * pad, bb[3] - bb[1] + 2 * pad), (0, 0, 0, 0))
        ImageDraw.Draw(im).text((pad - bb[0], pad - bb[1]), s, font=fnt, fill=fill,
                                stroke_width=stroke, stroke_fill=fill)
        _text_cache[key] = im
    return im


def hand_text_img(s, size, seed, bold=True, fill=INK, stroke=0):
    """逐字抖动的手绘标题（3 seed = boil 变体）。为什么逐字：整体刚性抖动不像手写，
    逐字基线/字距扰动才像马克笔写在纸上还一直「沸腾」。"""
    key = (s, UI(size), seed, bold, stroke)
    im = _hand_cache.get(key)
    if im is None:
        rng = random.Random(f'mj-hand-{s}-{seed}')
        fnt = get_font(size, bold)
        probe = ImageDraw.Draw(Image.new('RGBA', (1, 1)))
        widths = [probe.textbbox((0, 0), ch, font=fnt, stroke_width=stroke)[2] for ch in s]
        gap = UI(size) * 0.02
        total_w = sum(widths) + gap * (len(s) - 1) + 2 * (UI(14) + stroke)
        total_h = UI(size) * 1.7 + 2 * (UI(14) + stroke)
        im = Image.new('RGBA', (int(total_w), int(total_h)), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        x = UI(14) + stroke
        for ch, w in zip(s, widths):
            dy = rng.uniform(-1, 1) * UI(size) * 0.035
            d.text((x + rng.uniform(-1, 1) * UI(2), total_h / 2 + dy), ch, font=fnt, fill=fill,
                   anchor='lm', stroke_width=stroke, stroke_fill=fill)
            x += w + gap + rng.uniform(-1, 1) * UI(1.5)
        _hand_cache[key] = im
    return im


def measure(s, size, bold=True):
    return get_font(size, bold).getlength(s) / S


def substr_span(s, size, bold, sub):
    """子串在文本中的 (x 偏移, 宽度)（设计 px）—— 荧光笔精确盖住重点词"""
    i = s.find(sub)
    if i < 0:
        return 0.0, measure(s, size, bold)
    return measure(s[:i], size, bold), measure(sub, size, bold)


# ---------------------------------------------------------------- 贴图 / 变换
_xf_cache = {}


def xformed(spr, sx, sy, rot):
    """非等比缩放 + 旋转（果冻 squash 用）；参数量化缓存，避免逐帧重复重采样"""
    if abs(sx - 1) < 0.008 and abs(sy - 1) < 0.008 and abs(rot) < 0.05:
        return spr
    key = (id(spr), round(sx * 160), round(sy * 160), round(rot * 2))
    out = _xf_cache.get(key)
    if out is None:
        out = spr.resize((max(1, int(spr.width * sx)), max(1, int(spr.height * sy))), Image.LANCZOS)
        if abs(rot) > 0.05:
            out = out.rotate(-rot, resample=Image.BICUBIC, expand=True)
        _xf_cache[key] = out
    return out


_ANCHOR = {'mm': (0.5, 0.5), 'lm': (0.0, 0.5), 'lc': (0.0, 0.5), 'lt': (0.0, 0.0),
           'rm': (1.0, 0.5), 'lb': (0.0, 1.0), 'rb': (1.0, 1.0), 'bc': (0.5, 1.0),
           'ct': (0.5, 0.0)}


def put(img, spr, x, y, anchor='mm', rot=0.0, sx=1.0, sy=1.0, sc=1.0):
    """场景贴图：x,y 为设计坐标；sx/sy 非等比（果冻）；anchor='bc' 以落地点为压扁支点"""
    out = xformed(spr, sx * sc, sy * sc, rot)
    ax, ay = _ANCHOR[anchor]
    img.paste(out, (int(U(x) - out.width * ax), int(U(y) - out.height * ay)), out)


def paste_at(img, spr, x, y, anchor='mm', rot=0.0, sc=1.0):
    """烘焙期贴图：x,y 为输出像素（纸片内容合成用）"""
    out = xformed(spr, sc, sc, rot)
    ax, ay = _ANCHOR[anchor]
    img.paste(out, (int(x - out.width * ax), int(y - out.height * ay)), out)


def put_jelly(img, spr, x, y, t, phase=0.0, hop_h=0.0, anchor='bc', rot=0.0, amp=1.0, sc=1.0):
    """果冻贴图一站式：每拍 squash&stretch + 可选每拍跳（amp 整体压低强度）"""
    sx, sy = jelly(t, phase)
    sx, sy = lerp(1.0, sx, amp), lerp(1.0, sy, amp)
    put(img, spr, x, y + hop(t, phase, hop_h * amp), anchor=anchor, rot=rot, sx=sx, sy=sy, sc=sc)


# ---------------------------------------------------------------- 手绘墨笔
class Pen:
    """带抖动的手绘笔：设计坐标 → 超采样画布，线宽呼吸、圆头"""

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
        """虚线（灰幽灵曲线用）"""
        segs, acc, on, buf = [], 0.0, True, [pts[0]]
        for i in range(len(pts) - 1):
            (x0, y0), (x1, y1) = pts[i], pts[i + 1]
            length = math.hypot(x1 - x0, y1 - y0)
            cur = 0.0
            while cur < length - 1e-6:
                run = (dash if on else gap) - acc
                nxt = min(length, cur + max(0.35, run))
                p1 = (x0 + (x1 - x0) * (nxt / length), y0 + (y1 - y0) * (nxt / length))
                if on:
                    buf.append(p1)
                acc += nxt - cur
                cur = nxt
                if acc >= (dash if on else gap) - 1e-6:
                    if on and len(buf) > 1:
                        segs.append(buf)
                    acc, on, buf = 0.0, not on, [p1]
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
            tt = i / segs
            pts.append((x0 + (x1 - x0) * tt, y0 + (y1 - y0) * tt))

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
    """手绘墨线元素 → 3 个 boil 变体 RGBA（seed 变体间微差 = 手绘沸腾）"""
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
        out = [im.crop(bb) if bb else im for im in out]
    _doodle_cache[key] = out
    return out


def do(img, name, w, h, painter, x, y, f, anchor='mm', rot=0.0, sc=1.0):
    put(img, doodle(name, w, h, painter)[boil(f)], x, y, anchor=anchor, rot=rot, sc=sc)


def do_dynamic(img, name, w, h, painter, x, y, f, ss=2):
    """逐帧现画（draw-on / 时变图形，不缓存）：设计坐标 (0,0) 落在场景 (x,y)"""
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


def check_stamp(p):
    """✓ 印章（咚咚落用）"""
    p.circle(60, 60, 52, 7)
    p.circle(60, 60, 45, 3.5)
    p.line([(36, 62), (53, 80), (86, 34)], 11)


def umbrella(p):
    """纸伞（躲雨意象）：伞面 + 伞骨 + 扇贝缘 + 弯柄"""
    p.arc(120, 130, 118, 182, 358, 6, ry=96)
    for a in (205, 250, 295, 340):
        rad = math.radians(a)
        p.line([(120, 130), (120 + 112 * math.cos(rad), 130 + 92 * math.sin(rad))], 3.6)
    for a0, a1 in ((182, 226), (226, 272), (272, 316), (316, 358)):
        mid = math.radians((a0 + a1) / 2)
        p.arc(120 + 59 * math.cos(mid), 130 + 96 * math.sin(mid) + 8, 30, a0, a1, 3.4, ry=16)
    p.line([(120, 130), (120, 232)], 6)
    p.arc(108, 232, 14, 0, 175, 6)


def qmark(p):
    p.arc(50, 42, 28, 200, 340, 7, ry=28)
    p.line([(76, 58), (52, 78)], 7)
    p.dot(50, 96, 5)


def speed_dashes(p):
    for y, x0, x1 in ((20, 8, 150), (52, 40, 190), (84, 0, 110), (116, 55, 200)):
        p.line([(x0, y), (x1, y)], 6)


def thumb_microbe(p):
    p.circle(52, 52, 26, 4.5, ry=20)
    p.dot(44, 48, 4)
    p.dot(62, 56, 4)
    p.line([(78, 30), (96, 18)], 3.5)
    p.line([(24, 78), (12, 90)], 3.5)
    p.circle(92, 74, 10, 3.5)


def thumb_cell(p):
    p.circle(56, 52, 34, 4.5)
    p.circle(62, 50, 13, 3.8)
    p.dot(34, 70, 3.5)
    p.dot(76, 78, 3.5)


def thumb_pill(p):
    p.circle(34, 66, 22, 5)
    p.circle(66, 34, 22, 5)
    p.line([(30, 88), (88, 30)], 5)


def thumb_spore(p):
    p.circle(52, 52, 30, 5)
    p.circle(52, 52, 14, 4)
    p.line([(52, 8), (52, 20)], 4)
    p.line([(52, 84), (52, 96)], 4)


THUMBS = {'microbe': thumb_microbe, 'cell': thumb_cell, 'pill': thumb_pill, 'spore': thumb_spore}


def bubble_tail(p):
    sp_pts = [(88, 6), (4, 50), (88, 64)]
    sp = [p.pt(x, y) for x, y in sp_pts]
    off = 4 * S * p.ss
    p.d.polygon([(x + off, y + off) for x, y in sp], fill=SHADOW)
    p.d.polygon(sp, fill=CARD)
    p.d.line(sp + [sp[0]], fill=INK, width=max(1, int(2.2 * S * p.ss)), joint='curve')


# ---------------------------------------------------------------- 纸片卡片
_paper_cache = {}
_styled_cache = {}


class Gfx:
    """纸片内容画笔：设计坐标（纸片左上为原点）→ 合成图（印刷内容不抖，只有边框 boil）"""

    def __init__(self, img, pad):
        self.img, self.pad = img, pad

    def text(self, s, x, y, size, bold=True, fill=INK, anchor='lm', stroke=0):
        paste_at(self.img, text_img(s, size, bold, fill, stroke), U(x) + self.pad, U(y) + self.pad,
                 anchor=anchor)

    def sprite(self, spr, x, y, anchor='mm', rot=0.0, sc=1.0):
        paste_at(self.img, spr, U(x) + self.pad, U(y) + self.pad, anchor=anchor, rot=rot, sc=sc)

    def doodle(self, name, w, h, painter, x, y, b=0, anchor='mm', rot=0.0, sc=1.0):
        self.sprite(doodle(name, w, h, painter)[b], x, y, anchor=anchor, rot=rot, sc=sc)

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
    """手绘纸片（wobbly 轮廓 + 2px 墨线 + 硬偏移阴影）→ 3 个 boil 变体"""
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
    """纸片 + 静态内容烘焙 → 3 个 boil 变体（name 按内容唯一 = 缓存键）"""
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
    def content(g):
        g.text(s, w / 2, h / 2, size, bold=bold, anchor='mm')

    return styled_paper(name, w, h, content, fill=fill_bg, line=line, shadow=shadow, segs=3)


# ---------------------------------------------------------------- 荧光笔
class HlStroke:
    """荧光涂抹条：wipe 展开、边缘略不规则、微倾斜；multiply 叠色（压过墨线仍是墨黑）"""

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
        rng = random.Random(f'mj-hl-{self.name}-{b}')
        ss = 2
        wob = 0.13
        xe = max(2.0, self.w * reveal)
        n = max(6, int(self.w / 46))
        dy = abs(self.slope * self.w / 2)
        pts = []

        def ty(x, y):
            return y + self.slope * (x - self.w / 2) + dy

        for i in range(n + 1):
            x = xe * i / n
            pts.append((x, ty(x, self.h * rng.uniform(-wob, wob))))
        for i in range(1, 6):
            y = self.h * i / 6
            pts.append((xe + self.w * 0.022 * rng.uniform(-1, 1), ty(xe, y)))
        for i in range(n + 1):
            x = xe * (n - i) / n
            pts.append((x, ty(x, self.h * (1 + rng.uniform(-wob, wob)))))
        for i in range(5, 0, -1):
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
        mult.paste(Image.new('RGB', st._shape(rev, b).size, st.color), (x0, y0), st._shape(rev, b))
    img.paste(ImageChops.multiply(img, mult))


def hl(name, x, y, w, h, t, t0, t1, color='y', tilt=0.0):
    return (HlStroke(name, x, y, w, h, color, tilt), seg(t, t0, t1))


# ---------------------------------------------------------------- 素材
_mascot_cache = {}
_zoom_m_cache = {}
_shot_cache = {}
_rain_cache = {}


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
    key = (pose, UI(size))
    out = _zoom_m_cache.get(key)
    if out is not None:
        return out
    k = U(size) / 600.0
    out = [im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)
           for im in mascot(pose)]
    _zoom_m_cache[key] = out
    return out


def put_mascot(img, pose, x, y, size, f, rot=0.0, anchor='mm'):
    put(img, mascot_size(pose, size)[boil(f)], x, y, anchor=anchor, rot=rot)


def phone_sprite(shot_name):
    """真机截图贴进手绘手机纸框（硬阴影烘焙、墨线轮廓；果冻/位移由调用方施加）"""
    out = _shot_cache.get(shot_name)
    if out is not None:
        return out
    shot = Image.open(SCREENSHOTS / shot_name).convert('RGB').resize((UI(383), UI(830)), Image.LANCZOS)
    fw, fh = 417.0, 876.0

    def content(g):
        paste_at(g.img, shot.convert('RGBA'), g.pad + U(17), g.pad + U(16), anchor='lt')
        g.bar(fw / 2 - 30, fh - 22, 60, 6, fill=(120, 116, 106, 255), r=3)

    out = styled_paper('phone-' + shot_name, fw, fh, content,
                       fill=(38, 38, 35, 255), line=2.5, shadow=5.0, r=22, segs=6)
    _shot_cache[shot_name] = out
    return out


def fake_phone_sprite():
    """手绘假屏手机（「AI 讲解 · 正在生成…」转圈用；真机截图不适合表达过程态）。
    屏幕区先铺浅底再印字——深色机身压深色字会整块糊掉（踩过坑）。"""

    def content(g):
        g.bar(14, 14, 389, 612, fill=CARD, r=14)          # 浅色屏幕
        g.text('AI 讲解', 46, 92, 34, bold=True)
        g.text('正在生成…', 46, 170, 54, bold=True)
        for i, w2 in enumerate((300, 337, 260)):
            g.bar(46, 280 + i * 46, w2, 16, r=8)
        g.outline(44, 470, 300, 26, r=13)
        g.bar(50, 476, 208, 14, fill=STICKER['y'], r=7)
        g.text('讲义 → 题目 · 已等 87 分钟', 46, 560, 26, bold=False, fill=INK_SOFT)

    return styled_paper('fakephone', 417.0, 640.0, content, fill=(38, 38, 35, 255),
                        line=2.5, shadow=5.0, r=22, segs=6)


def lecture_sheet(name, tag):
    """讲义纸片：假文本条 + PDF/DOCX/PPTX 角标"""

    def content(g):
        g.bar(28, 30, 150, 14, fill=(150, 144, 130, 255))
        y = 74
        for w2 in (244, 230, 244, 200, 244, 214, 236, 176):
            g.bar(28, y, w2, 9, r=4)
            y += 26
        g.sprite(chip_sprite('tag-' + tag, tag, 96, 44, 24)[0], 244, 40, anchor='mm', rot=3)

    return styled_paper('sheet-' + name, 300, 400, content, segs=5)


Q_LINE1, Q_LINE2 = '革兰氏阳性菌细胞壁的', '主要成分是？'


def hero_question_card():
    """题目卡卡面：革兰氏阳性菌细胞壁的主要成分是？（+ 自拟小标签与选项）"""

    def content(g):
        g.sprite(chip_sprite('qtag', '刚到货 · 新题', 220, 56, 27, fill_bg=STICKER['y'])[0],
                 750, 56, anchor='mm', rot=-2)
        g.text(Q_LINE1, 50, 148, 58, bold=True, anchor='lm')
        g.text(Q_LINE2, 50, 234, 58, bold=True, anchor='lm')
        for i, (k, s) in enumerate((('A', '肽聚糖'), ('B', '磷壁酸'), ('C', '脂多糖'), ('D', '外膜'))):
            x = 50 + (i % 2) * 430
            y = 336 + (i // 2) * 74
            g.outline(x, y - 30, 380, 60, r=12, line=2.0)
            g.text(k, x + 34, y, 32, anchor='mm')
            g.text(s, x + 84, y, 32, bold=False, anchor='lm')

    return styled_paper('herocard', 900, 430, content, segs=5)


def mini_question_card(name, lines, thumb):
    def content(g):
        g.doodle('mth-' + thumb, 130, 100, THUMBS[thumb], 92, 118, 0)
        g.outline(27, 72, 130, 100, r=8, line=2.0)
        for i, ln in enumerate(lines):
            g.text(ln, 182, 96 + i * 42, 27, bold=False)
        g.bar(182, 172, 120, 10, r=5)

    return styled_paper('mqcard-' + name, 430, 250, content, segs=5)


def wait_card(name, label, value, note, with_bar=0.0):
    """「等待三连」纸卡内容面（翻面对的另一面是 ? 问号面）"""

    def content(g):
        g.text(label, 30, 46, 30, bold=False, fill=INK_SOFT, anchor='lm')
        g.text(value, 30, 116, 52, bold=True, anchor='lm')
        if with_bar > 0:
            g.outline(30, 162, 540, 22, r=11, line=2.0)
            g.bar(34, 166, 532 * with_bar, 14, fill=STICKER['y'], r=7)
            g.text(note, 30, 210, 24, bold=False, fill=INK_SOFT, anchor='lm')
        else:
            g.text(note, 30, 176, 24, bold=False, fill=INK_SOFT, anchor='lm')

    h = 250 if with_bar > 0 else 210
    return styled_paper('wcard-' + name, 640, h, content, segs=5), h


def wait_card_front(name, h):
    def content(g):
        g.doodle('wq-' + name, 110, 110, qmark, 320, h / 2 - 8, 0)

    return styled_paper('wfront-' + name, 640, h, content, segs=5)


BUBBLE_L1, BUBBLE_L2, BUBBLE_L3 = '秒判：A · 肽聚糖', '为什么：阳性菌=肽聚糖骨架', '对比：脂多糖只在阴性菌'


def ai_bubble_sprite():
    def content(g):
        g.sprite(chip_sprite('ai-chip2', 'AI 讲解', 176, 58, 30, fill_bg=STICKER['y'])[0], 128, 62,
                 rot=-2)
        g.text(BUBBLE_L1, 46, 148, 30, bold=False)
        g.text(BUBBLE_L2, 46, 218, 30, bold=False)
        g.text(BUBBLE_L3, 46, 288, 30, bold=False)

    return styled_paper('bubble2', 700, 380, content, segs=5)


def box_sprite():
    """猫卷纸盒（讲义进炉用）"""

    def content(g):
        g.bar(52, 6, 316, 34, fill=SLOT_DARK, r=8)
        g.outline(48, 2, 324, 42, r=10, line=2.0)
        g.text('猫卷', 210, 150, 52, anchor='mm')
        g.doodle('boxpaw', 100, 100, paw_print, 210, 226, 0)

    return styled_paper('mjbox', 420, 300, content, segs=5)


# ---------------------------------------------------------------- 背景 / 雨（预合成复用）
def build_bg():
    """暖纸底 + 极淡横线 + 纸纹噪声 + 手绘角饰，预合成一张复用（性能线）"""
    img = Image.new('RGB', (W, H), PAPER)
    d = ImageDraw.Draw(img)
    y = UI(46)
    while y < H:
        d.line([(0, y), (W, y)], fill=PAPER_LINE, width=1)
        y += UI(46)
    noise = Image.effect_noise((W, H), 26).point(lambda v: int(128 + (v - 128) * 0.45))
    img = ImageChops.add(img, Image.merge('RGB', (noise, noise, noise)), scale=1, offset=-128)
    for name, painter, w2, h2, x, y2, rot in (
            ('bg-star', lambda p: (p.line([(30, 6), (30, 56)], 4), p.line([(6, 30), (56, 30)], 4),
                                   p.line([(13, 13), (47, 47)], 3.4), p.line([(47, 13), (13, 47)], 3.4)),
             64, 64, 1780, 80, 8),
            ('bg-wavy', lambda p: p.line([(2 + i * 12.7, 14 + math.sin(i * 1.35) * 6) for i in range(13)], 4.5),
             170, 34, 120, 1010, -4),
            ('bg-curl', lambda p: (p.arc(40, 30, 26, 160, 520, 4.5, ry=20), p.line([(66, 40), (96, 20)], 3.6)),
             100, 60, 1810, 1000, 6)):
        paste_at(img, doodle(name, w2, h2, painter)[0], U(x), U(y2), anchor='mm', rot=rot)
    return img


def draw_rain(img, t, n=40, area=(0, 0, DESIGN_W, DESIGN_H), speed=1250.0, weight=2.0, seed=7):
    """雨丝 = 细墨线斜落（解析式循环：位置只是时间的函数，无粒子系统 → 可复现）"""
    params = _rain_cache.get((seed, n))
    if params is None:
        rng = random.Random(f'mj-rain-{seed}')
        params = [(rng.random(), rng.random(), rng.uniform(46, 96), rng.uniform(0.8, 1.25))
                  for _ in range(n)]
        _rain_cache[(seed, n)] = params
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = area
    slant, span = 0.28, (y1 - y0) + 160
    for fx, fy, ln, sm in params:
        px = x0 + fx * (x1 - x0)
        py = (fy * (y1 - y0) + t * speed * sm) % span - 80
        ax, ay = U(x0 + (px - x0)), U(y0 + py)
        d.line([(ax, ay), (ax - U(ln * slant), ay + U(ln))], fill=RAIN, width=max(1, int(weight * S)))


def micro_jelly_frame(bg, img, t, t0):
    """切镜拍上整帧一次极小 squash（「每镜轻微果冻抖」，威姿过减速带）。
    斜切的顶边条纹露出的是同一张预合成背景，观感无缝。"""
    k = punch_env(t, t0, GRID.beat * 0.8)
    if abs(k - 1.0) < 0.004:
        return img
    sx, sy = 1.0 + (k - 1.0) * 0.5, 1.0 - (k - 1.0) * 0.5
    nw, nh = max(1, int(W * sx)), max(1, int(H * sy))
    im2 = img.resize((nw, nh), Image.BILINEAR)
    out = bg.copy()
    out.paste(im2, ((W - nw) // 2, H - nh))
    return out


# ---------------------------------------------------------------- 文案（全部自拟；标题行是歌曲名式引用）
CAP_INTRO = '期末周，我在等一个救星'
PUNCH_TITLE_1, PUNCH_TITLE_2 = "WHY'S THIS DEALER", 'TAKING THE PISS?'
CAP_CN = '为什么这个题贩子让我等半天？！'
V1_CAPS = ['等押题等成望夫石', '讲解比外卖还慢', '讲义 300 页，题呢？', '雨都小了，进度条没动']
BRAND_LINE = '猫卷 · 把讲义变成能刷的题'
SLOGAN = '把讲义变成能刷的题'
DOWNLOAD = 'Android / Windows · AGPL-3.0 开源'
FINAL_CAP = '不用等贩子 —— 讲义自己变题'


# ---------------------------------------------------------------- 场景
def sc_intro(img, f, t, tl):
    """Intro 0.0–14.2「等」：纸伞下顶讲义蹲守 + 等待三连踩拍翻面 + 末 2 小节大字幕"""
    b = boil(f)
    draw_rain(img, t, n=40, speed=1250)
    # 「顶着一摞讲义缩在纸伞下」：纸堆坐在头顶、伞罩住纸堆，三者成一组（勿散开）
    head_top = 730 - mascot_size('pawprint', 520)[0].height / (2 * S)
    do(img, 'umb', 240, 250, umbrella, 470, 360, f, sc=1.6)
    put_mascot(img, 'pawprint', 470, 730, 520, f)
    stack = lecture_sheet('pile', 'PDF')[b]
    for i in range(4):
        put_jelly(img, stack, 470 + (i % 2 - 0.5) * 14, head_top + 8 - i * 22, t,
                  phase=0.010 * i, anchor='bc', rot=(i % 2 - 0.5) * 5, sc=0.5, amp=0.7)
    put(img, text_img('已经等了 87 分钟', 26, bold=False, fill=INK_SOFT), 470,
        head_top + mascot_size('pawprint', 520)[0].height / S + 42, anchor='mm')
    waits = [
        ('waitcard_01', '押题资料', '404', '考点呢？', 0.0, 300, 0.000),
        ('waitcard_02', '网课缓冲', '87%', '加载到天荒地老', 0.87, 555, 0.014),
        ('waitcard_03', '外卖式讲解', '骑手正在赶', '超时赔付 5 元券', 0.0, 810, 0.026),
    ]
    for nm, label, value, note, bar, cy, phase in waits:
        t_in, t_out = tl.t(nm + '_flip'), tl.t(nm + '_out')
        if t < t_in or t >= t_out + GRID.beat:
            continue
        back, ch = wait_card(nm, label, value, note, bar)
        front = wait_card_front(nm, ch)[b]
        if t < t_in + GRID.beat:                     # 入场翻面（1 拍，踩拍）
            sx, u = flip_scalex(t, t_in, GRID.beat)
            put(img, front if u < 0.5 else back[b], 1320, cy, anchor='mm', sx=max(0.02, sx))
        elif t < t_out:                              # 常驻：每拍果冻（错相位 0/14/26ms）
            put_jelly(img, back[b], 1320, cy, t, phase=phase, anchor='mm', amp=0.8)
        else:                                        # 退场翻面
            sx, u = flip_scalex(t, t_out, GRID.beat)
            put(img, back[b] if u < 0.5 else front, 1320, cy, anchor='mm', sx=max(0.02, sx))
    t_cap, t_cout = tl.t('intro_caption_in'), tl.t('intro_caption_out')
    if t >= t_cap:
        k = punch_env(t, t_cap, GRID.beat * 0.8)
        ex = punch_env(t, t_cout, GRID.beat * 0.5) if t >= t_cout else 1.0
        put(img, text_img(CAP_INTRO, 96), 960, 972, anchor='mm', sc=max(0.01, k * (2 - ex)),
            sy=(2.0 - ex) if t >= t_cout else 1.0)


def sc_chorus1(img, f, t, tl):
    """Chorus① 14.2–27.9「题贩子驾到」：PUNCH 标题 + 题目卡砸落每拍弹 + 21.20s 起跳舞"""
    b = boil(f)
    draw_rain(img, t, n=14, speed=1350, weight=1.6)
    t0, t_out = tl.t('hook_punch_title'), tl.t('title_out')
    if t >= t0 and t < t_out + GRID.beat * 0.5:
        k = punch_env(t, t0, GRID.beat * 0.7)
        ex = punch_env(t, t_out, GRID.beat * 0.5) if t >= t_out else 1.0
        for i, (line, size) in enumerate(((PUNCH_TITLE_1, 118), (PUNCH_TITLE_2, 132))):
            put(img, hand_text_img(line, size, b, stroke=7), 960, 150 + i * 155, anchor='mm',
                sc=max(0.01, k * (2 - ex)), sy=(2.0 - ex) if t >= t_out else 1.0)
    t_fall, t_land = tl.t('qcard_fall_start'), tl.t('qcard_land')
    t_dance, t_exit = tl.t('qcard_dance_on'), tl.t('qcard_exit')
    if t >= t_fall and t < t_exit + GRID.beat:
        card = hero_question_card()
        ground = 830
        if t < t_land:                               # 下落：解析式加速（重感 u²）+ 微拉伸
            u = seg(t, t_fall, t_land)
            cx, y, sx, sy, rot = 960, lerp(-460, ground, u * u), 1.0, 1.06, lerp(-7, 0, u)
        else:
            p = beat_phase(t)
            dance = t >= t_dance
            sx, sy = jelly(t)
            hit = punch_env(t, t_land, GRID.beat * 0.6)   # 落地大 squash 叠在常规果冻上
            if t < t_land + GRID.beat * 0.6:
                sx, sy = lerp(1.0, sx, hit), lerp(1.0, sy, hit)
            y = ground + hop(t, 0.0, 30.0 if dance else 16.0)
            rot = 4.5 * math.sin(2 * math.pi * p) if dance else 0.0
            cx = 960 + (26 * math.sin(2 * math.pi * p * 0.5 + 0.6) if dance else 0.0)
            if t >= t_exit:
                ex = punch_env(t, t_exit, GRID.beat * 0.5)
                sx, sy = lerp(1.0, sx, ex), lerp(1.0, sy, ex)
        put(img, card[b], cx, y, anchor='bc', rot=rot, sx=sx, sy=sy)
    t_sub, t_sout = tl.t('cn_subtitle_in'), tl.t('cn_subtitle_out')
    if t >= t_sub and t < t_sout + GRID.beat * 0.5:
        k = punch_env(t, t_sub, GRID.beat * 0.6)
        ex = punch_env(t, t_sout, GRID.beat * 0.5) if t >= t_sout else 1.0
        strip = styled_paper('cstrip', 1240, 128,
                             lambda g: g.text(CAP_CN, 620, 64, 62, anchor='mm'), segs=4)
        put(img, strip[b], 960, 990, anchor='mm', sc=max(0.01, k * (2 - ex)),
            sy=(2.0 - ex) if t >= t_sout else 1.0)
    t2 = tl.t('hook_punch2')                          # 21.20s 第二次 punch：冲击环
    if t2 <= t < t2 + 0.5:
        u = seg(t, t2, t2 + 0.5)

        def ring(p, u=u):
            p.circle(360, 240, lerp(60, 340, u), w=lerp(12, 2, u))

        do_dynamic(img, 'punch2ring', 760, 520, ring, 960, 560, f)


def _v1_scene_a(img, f, t, b):
    """自习室干瞪讲义"""
    do(img, 'lamp', 150, 150, lambda p: (p.line([(40, 130), (70, 40)], 6),
                                         p.arc(70, 34, 44, 190, 350, 6),
                                         p.line([(20, 132), (110, 132)], 6)), 300, 300, f, sc=1.5)
    do(img, 'clock', 120, 120, lambda p: (p.circle(60, 60, 52, 6),
                                          p.line([(60, 60), (60, 26)], 5),
                                          p.line([(60, 60), (88, 72)], 5)), 1660, 240, f)

    def book_content(g):
        g.bar(60, 60, 330, 16, fill=(150, 144, 130, 255))
        for i in range(5):
            g.bar(60, 120 + i * 40, 300 - i * 12, 12, r=6)
        g.bar(510, 60, 240, 16, fill=(150, 144, 130, 255))
        for i in range(5):
            g.bar(510, 120 + i * 40, 300 - ((i + 2) % 5) * 12, 12, r=6)
        g.doodle('bookline', 30, 300, lambda p: p.line([(15, 10), (15, 290)], 3), 450, 200)

    put_jelly(img, styled_paper('v1book', 900, 380, book_content, segs=5)[b], 960, 700, t,
              anchor='mm', amp=0.55)
    put_mascot(img, 'pawprint', 1580, 780, 430, f)
    put(img, text_img('第 47 分钟', 30, bold=False, fill=INK_SOFT), 620, 950, anchor='mm')


def _v1_scene_b(img, f, t, b):
    """手机上「AI 讲解 · 正在生成…」转圈"""
    put_jelly(img, fake_phone_sprite()[b], 830, 620, t, anchor='mm', amp=0.5)
    ang = (t / (GRID.beat * 2)) * 360.0               # 转圈 = 解析式连续旋转（2 拍一圈）

    def spinner(p, ang=ang):
        p.arc(60, 60, 44, ang, ang + 250, 10)

    do_dynamic(img, 'spin', 140, 140, spinner, 790, 330, f)
    put_mascot(img, 'wave', 1560, 780, 400, f)
    put(img, text_img('客服：您的讲解正在加急', 28, bold=False, fill=INK_SOFT), 1480, 930, anchor='mm')


def _v1_scene_c(img, f, t, b):
    """翻讲义翻到暴躁（纸页乱飞）"""
    put_mascot(img, 'wave', 600, 780, 480, f, rot=-3)

    def rage_content(g):
        for i in range(5):
            g.bar(50, 60 + i * 44, 420 - i * 30, 14, r=7)

    put_jelly(img, styled_paper('ragebook', 520, 300, rage_content, segs=5)[b], 880, 930, t,
              anchor='mm', rot=4, amp=0.8)
    beat_i = int(math.floor(t / GRID.beat))            # 每拍飞 1 页：解析式抛物线 + 自旋
    for k in range(5):
        tb = (beat_i - k) * GRID.beat
        u = (t - tb) / (GRID.beat * 2.6)
        if not (0.02 < u < 1.0):
            continue
        rng = random.Random(f'mj-page-{beat_i - k}')
        x = lerp(900, rng.uniform(1150, 1750), u)
        y = 860 - math.sin(math.pi * u) * rng.uniform(320, 520) + u * 160
        put(img, lecture_sheet(f'fly{(beat_i - k) % 4}', 'DOCX')[b], x, y,
            rot=rng.uniform(-40, 40) * u + rng.uniform(-8, 8), sc=0.42, anchor='mm')
    do(img, 'anger', 90, 90, lambda p: (p.line([(20, 45), (70, 45)], 7),
                                        p.line([(45, 20), (45, 70)], 7)), 1030, 350, f, rot=12, sc=1.4)


def _v1_scene_d(img, f, t, b):
    """窗外雨更大、墨墨继续蹲守"""

    def win_content(g):
        g.bar(24, 24, 712, 472, fill=(226, 231, 233, 255))
        g.outline(370, 24, 10, 472, fill=CARD, r=0, line=2.0)
        g.outline(24, 252, 712, 10, fill=CARD, r=0, line=2.0)

    put_jelly(img, styled_paper('win', 760, 520, win_content, line=2.5, shadow=5, segs=6)[b],
              1250, 430, t, anchor='mm', amp=0.35)
    draw_rain(img, t, n=30, area=(880, 190, 1620, 660), speed=1750, weight=2.4, seed=21)  # 雨更大
    put_mascot(img, 'pawprint', 520, 840, 500, f)
    stack = lecture_sheet('pud', 'DOCX')[b]
    for i in range(3):
        put_jelly(img, stack, 520, 650 - i * 22, t, phase=0.012 * i, anchor='bc',
                  rot=(i % 2 - 0.5) * 6, sc=0.44, amp=0.6)
    do(img, 'drop', 120, 60, lambda p: p.arc(60, 30, 52, 10, 170, 5, ry=18), 1560, 910, f)


_V1_SHOTS = (_v1_scene_a, _v1_scene_b, _v1_scene_c, _v1_scene_d)


def sc_verse1(img, f, t, tl):
    """Verse 1 27.9–56.8「干等实录」：4 拍一镜蒙太奇（4 场景 × 4 循环）+ 每 4 小节一句吐槽"""
    b = boil(f)
    shot0 = tl.ev['v1_shot_01'].idx16
    k_shot = max(0, min(15, int((t / GRID.sixteenth - shot0) // 16)))
    _V1_SHOTS[k_shot % 4](img, f, t, b)
    t_start, t_vout = tl.t('verse1_title_in'), tl.t('v1_title_out')
    if t >= t_start:
        k = punch_env(t, t_start, GRID.beat * 0.6)
        ex = punch_env(t, t_vout, GRID.beat * 0.5) if t >= t_vout else 1.0
        put(img, chip_sprite('v1tag', '干等实录', 320, 108, 52, fill_bg=STICKER['p'], line=2.4,
                             shadow=4.5)[b], 210, 120, anchor='mm', rot=-3,
            sc=max(0.01, k * (2 - ex)))
    for i, cap in enumerate(V1_CAPS):
        t_in, t_out = tl.t(f'v1_cap_{i + 1}_in'), tl.t(f'v1_cap_{i + 1}_out')
        if not (t_in <= t < t_out + GRID.beat * 0.5):
            continue
        k = punch_env(t, t_in, GRID.beat * 0.6)
        ex = punch_env(t, t_out, GRID.beat * 0.5) if t >= t_out else 1.0
        strip = styled_paper(f'v1cap{i}', 1180, 120,
                             (lambda s: (lambda g: g.text(s, 590, 60, 58, anchor='mm')))(cap), segs=4)
        put(img, strip[b], 960, 982, anchor='mm', sc=max(0.01, k * (2 - ex)),
            sy=(2.0 - ex) if t >= t_out else 1.0)
    # 每镜轻微果冻抖：切镜拍上整帧一次极小 squash（合成后施加，内容才跟着抖）
    return micro_jelly_frame(Background.bg, img, t, tl.t(f'v1_shot_{k_shot + 1:02d}'))


class Background:
    """预合成背景的全局持有者（micro_jelly_frame 需要按帧复用同一张底图）"""
    bg = None


def sc_chorus2(img, f, t, tl):
    """Chorus② 56.8–70.6「真身揭晓」：手机甩尾入场 + 大字 + 「不用等」荧光涂抹 + 4 卡群舞"""
    b = boil(f)
    strokes = []
    t_in, t_land = tl.t('phone_drift_in'), tl.t('phone_land')
    u_drift = seg(t, t_in, t_in + GRID.beat * 3)
    settle = 1.0 - seg(t, t_land, t_land + GRID.beat)   # 落定后强制收束残余摆
    dx = 760 * drift_damp(u_drift) * settle
    rot = (-2.0 + 9.0 * sway_swing(u_drift) * settle) if t >= t_in else -2.0
    px = 1420 + dx
    if t_in <= t < tl.t('cards_lineup'):                 # 甩尾期手机（4 卡进场后由下方接管绘制）
        if t < t_in + 0.55:                              # 甩尾速度线
            for i in range(5):
                def streak(p, i=i):
                    p.line([(0, 40 + i * 40), (210 + i * 34, 40 + i * 40)], 5)

                do_dynamic(img, f'spdl{i}', 260, 260, streak, px - 340, 300 + i * 110, f)
        put_jelly(img, phone_sprite('home.png')[b], px + 50, 560, t, anchor='mm', rot=rot, amp=0.45)
    t_brand = tl.t('brand_text_in')
    if t >= t_brand:
        t_line = tl.t('cards_lineup')
        up = seg(t, t_line, t_line + GRID.beat) * 300    # 4 卡进场时大字上移让位
        k = punch_env(t, t_brand, GRID.beat * 0.6)
        put(img, text_img(BRAND_LINE, 78), 780, 620 - up, anchor='mm', sc=k)
        t_hl = tl.t('hl_no_wait')
        if t >= t_hl:
            kh = punch_env(t, t_hl, GRID.beat * 0.6)
            put(img, text_img('不用等', 150, stroke=4), 560, 810 - up, anchor='mm', sc=kh)
            w2 = measure('不用等', 150)
            strokes.append(hl('nowait', 560 - w2 / 2 - 16, 750 - up, w2 + 32, 138,
                              t, t_hl + 0.1, t_hl + 0.55, 'y', 0.8))
    t_line = tl.t('cards_lineup')
    if t >= t_line:
        t_uni = tl.t('cards_dance_unison')
        arr = seg(t, t_line, t_line + GRID.beat)      # 4 卡进场时手机让位到右上角
        qs = [('q1', ['革兰阳性菌', '细胞壁主成分？'], 'microbe'),
              ('q2', ['青霉素的', '作用靶点是？'], 'pill'),
              ('q3', ['芽胞耐热的', '关键原因是？'], 'spore'),
              ('q4', ['外毒素与', '内毒素区别？'], 'cell')]
        for i, (nm, lines, th) in enumerate(qs):
            card = mini_question_card(nm, lines, th)
            k = punch_env(t, t_line + i * 0.03, GRID.beat * 0.5)   # 依次 punch
            phase = 0.0 if t >= t_uni else 0.012 * (i + 1)         # 齐弹段吃掉相位差（0/12/24/36ms）
            sx, sy = jelly(t, phase)
            sx, sy = lerp(1, sx, k), lerp(1, sy, k)
            put(img, card[b], 300 + i * 440, 920 + hop(t, phase, 34), anchor='bc',
                rot=(i - 1.5) * 1.6, sx=sx, sy=sy, sc=0.92)
        put_jelly(img, phone_sprite('home.png')[b], lerp(px + 50, 1650, arr), lerp(560, 380, arr),
                  t, anchor='mm', rot=rot, amp=0.3, sc=lerp(1.0, 0.6, arr))
    apply_highlights(img, strokes, b)


def _v2_scene_a(img, f, t, b, cyc, t_shot):
    """DOCX/PDF 纸片飞入猫卷（+ 速度线）；纸盒居中偏左，纸片横穿画面 = 狂飙感"""
    flaps = styled_paper('flap2', 210, 88, line=2, shadow=4, segs=4)[b]
    put(img, flaps, 850, 650, rot=-24)
    put(img, flaps, 1030, 650, rot=24)
    put_jelly(img, box_sprite()[b], 940, 810, t, anchor='mm', amp=0.6)
    for i, (tag, x0, y0) in enumerate((('DOCX', 2100, 240), ('PDF', 2180, 560),
                                       ('PPTX', 2050, 880), ('DOCX', 2260, 60))):
        t0 = t_shot + i * GRID.beat * 0.5            # 半拍一叠，快节奏
        uu = ease_in_out(seg(t, t0, t0 + GRID.beat * 2.0))
        if not (0 < uu < 1):
            continue
        put(img, lecture_sheet(f'v2fly{cyc}-{i}', tag)[b], lerp(x0, 940, uu), lerp(y0, 700, uu),
            sc=lerp(0.72, 0.16, uu), rot=lerp(-14 if i % 2 else 12, 0, uu))
    for i in range(4):
        def streak(p, i=i):
            p.line([(0, 40 + i * 30), (300 + i * 40, 40 + i * 30)], 6)

        do_dynamic(img, f'v2sp{cyc}{i}', 380, 220, streak, 300, 380 + i * 120, f)


def _v2_scene_b(img, f, t, b, cyc, tl):
    """题卡带小插图弹出（「插图随题」小字）"""
    t0 = tl.t(f'v2_card_pop_{cyc + 1}')
    k = ease_out_back(seg(t, t0, t0 + GRID.beat * 0.6))
    put_jelly(img, mini_question_card(f'pop{cyc}', ['革兰阳性菌', '细胞壁主成分？'], 'microbe')[b],
              830, 640, t, anchor='mm', amp=0.9, hop_h=26, sc=1.75 * max(0.05, k))
    t_chip = t0 + GRID.beat
    if t >= t_chip:
        put(img, chip_sprite(f'v2ill{cyc}', '插图随题', 240, 72, 34, fill_bg=STICKER['g'])[b],
            1100, 350, anchor='mm', rot=3, sc=punch_env(t, t_chip, GRID.beat * 0.5))
    put_jelly(img, phone_sprite('start.png')[b], 1590, 620, t, anchor='mm', amp=0.45, rot=2, sc=0.8)


def _v2_scene_c(img, f, t, b, cyc, tl):
    """✓ 印章咚咚落 + AI 讲解气泡（荧光笔划重点）→ 返回荧光笔列表"""
    strokes = []
    for i, (sx0, sy0, nm) in enumerate(((700, 620, f'v2_stamp_{cyc + 1}_1'),
                                        (880, 760, f'v2_stamp_{cyc + 1}_2'))):
        t0 = tl.t(nm)
        if t < t0:
            continue
        fall = ease_in_cubic(min(seg(t, t0, t0 + GRID.beat * 0.55) / 0.6, 1.0))
        sc = lerp(2.4, 1.0, fall) * punch_env(t, t0 + GRID.beat * 0.33, GRID.beat * 0.5)
        do(img, f'vstamp{cyc}-{i}', 120, 120, check_stamp, sx0, lerp(sy0 - 260, sy0, fall), f,
           rot=-8 + i * 6, sc=max(0.01, sc) * 1.25)
    t_b = tl.t(f'v2_bubble_{cyc + 1}')
    if t >= t_b:
        k = ease_out_back(seg(t, t_b, t_b + GRID.beat * 0.8))
        put(img, doodle('btail2', 90, 70, bubble_tail)[b], 430, 500, anchor='rm', sc=max(0.05, k))
        put(img, ai_bubble_sprite()[b], 430, 380, anchor='lc', sc=max(0.05, k))
        x1, w1 = substr_span(BUBBLE_L1, 30, False, '肽聚糖')
        x3, w3 = substr_span(BUBBLE_L3, 30, False, '脂多糖')
        strokes.append(hl(f'v2b1{cyc}', 476 + x1 - 8, 332, w1 + 16, 44, t,
                          t_b + GRID.beat, t_b + GRID.beat * 1.5, 'y', 0.3))
        strokes.append(hl(f'v2b3{cyc}', 476 + x3 - 8, 472, w3 + 16, 44, t,
                          t_b + GRID.beat * 1.5, t_b + GRID.beat * 2, 'g', -0.3))
    put_jelly(img, phone_sprite('errorbook.png')[b], 1600, 640, t, anchor='mm', amp=0.4, rot=-2, sc=0.78)
    return strokes


def _v2_scene_d(img, f, t, b, cyc, tl):
    """FSRS 曲线墨线爬升 +「下次复习 · 明天」"""
    t0 = tl.t(f'v2_fsrs_{cyc + 1}')
    u = seg(t, t0, t0 + GRID.beat * 2.0)
    axes = [(180, 760), (1560, 760)]
    yaxis = [(180, 760), (180, 260)]
    ghost = [(420, 600), (620, 660), (900, 690), (1200, 706), (1500, 714)]
    d1 = [(220, 300), (420, 600), (450, 380), (620, 520), (700, 330), (900, 450), (960, 300),
          (1200, 380), (1500, 330)]

    def chart(p):
        p.line(poly_partial(axes, min(1, u * 2)), 5)
        p.line(poly_partial(yaxis, min(1, u * 2)), 5)
        p.dashed(ghost, 3.5)
        p.line(poly_partial(d1, u), 6)

    if u > 0.01:
        do_dynamic(img, f'fsrs{cyc}', 1600, 900, chart, 170, 130, f)
    put(img, text_img('记忆留存', 30, bold=False, fill=INK_SOFT), 110, 220, anchor='lm')
    put(img, text_img('天数', 30, bold=False, fill=INK_SOFT), 1520, 812, anchor='mm')
    t_r = tl.t(f'v2_review_{cyc + 1}')
    if t >= t_r:
        put(img, chip_sprite(f'v2rv{cyc}', '下次复习 · 明天', 330, 84, 38, fill_bg=STICKER['y'])[b],
            1150, 300, anchor='mm', rot=-2, sc=ease_out_back(seg(t, t_r, t_r + GRID.beat * 0.5)))


def sc_verse2(img, f, t, tl):
    """Verse 2 70.6–99.4「狂飙赶到」= 工作流狂飙：4 镜 × 4 拍 × 4 轮快剪 + 速度线"""
    b = boil(f)
    strokes = []
    shot0 = tl.ev['v2_shot_01'].idx16
    k_shot = max(0, min(15, int((t / GRID.sixteenth - shot0) // 16)))
    cyc, sub = divmod(k_shot, 4)
    t_shot = tl.t(f'v2_shot_{k_shot + 1:02d}')
    if sub == 0:
        _v2_scene_a(img, f, t, b, cyc, t_shot)
    elif sub == 1:
        _v2_scene_b(img, f, t, b, cyc, tl)
    elif sub == 2:
        strokes += _v2_scene_c(img, f, t, b, cyc, tl)
    else:
        _v2_scene_d(img, f, t, b, cyc, tl)
    t_start, t_vout = tl.t('verse2_title_in'), tl.t('v2_title_out')
    if t >= t_start:
        k = punch_env(t, t_start, GRID.beat * 0.6)
        ex = punch_env(t, t_vout, GRID.beat * 0.5) if t >= t_vout else 1.0
        put(img, chip_sprite('v2tag', '狂飙赶到', 320, 108, 52, fill_bg=STICKER['g'], line=2.4,
                             shadow=4.5)[b], 210, 120, anchor='mm', rot=-2,
            sc=max(0.01, k * (2 - ex)))
    do(img, 'spd', 220, 130, speed_dashes, 1700, 130, f, sc=1.3 + 0.25 * math.sin(t * 9))
    apply_highlights(img, strokes, b)
    return micro_jelly_frame(Background.bg, img, t, t_shot)   # 切镜整帧微果冻抖


def sc_chorus3(img, f, t, tl):
    """Chorus③ 99.4–113.7「算得清」：stats 进画 + 数字滚动 + 热力图 16 分逐格点亮 + punch 猛弹"""
    b = boil(f)
    t_in = tl.t('stats_phone_in')
    t_p3 = tl.t('punch3_phone_jelly')
    if t >= t_in:
        k = punch_env(t, t_in, GRID.beat * 0.7)
        big = punch_env(t, t_p3, GRID.beat * 0.8) if t >= t_p3 else 1.0   # 猛弹 = 果冻幅度拉满
        amp = 0.5 if t < t_p3 else 0.5 + (big - 1.0) / 0.08 * 0.5
        dy = 0.0 if t < t_p3 else hop(t, 0.0, 30)
        put_jelly(img, phone_sprite('stats.png')[b], 420, 580 + dy, t, anchor='mm', rot=-2,
                  amp=min(amp, 1.0), sc=k)
    cols = [(1080, '累计刷题', 12480, lambda n: f'{n:,}', 'num_1'),
            (1430, '正确率', 874, lambda n: f'{n / 10:.1f}%', 'num_2'),
            (1770, '连续复习', 46, lambda n: f'{n} 天', 'num_3')]
    for cx, label, target, fmt, nm in cols:
        t0, t1 = tl.t(nm + '_roll'), tl.t(nm + '_land')
        if t < t0:
            continue
        put(img, text_img(label, 32, bold=False, fill=INK_SOFT), cx, 210, anchor='mm')
        val = int(target * ease_out_cubic(seg(t, t0, t1)))     # odometer：解析式滚动 2 拍
        land = punch_env(t, t1, GRID.beat * 0.5)               # 落定 squash
        put(img, text_img(fmt(val), 92), cx, 306, anchor='mm',
            sy=lerp(1.0, 1.08, (land - 1.0) / 0.08 * 1.2))
    cell, gap = 40.0, 8.0
    x0g, y0g = 1060, 430
    lv = _heat_levels()
    d = ImageDraw.Draw(img)
    for idx in range(128):
        t_on = tl.t(f'heat_cell_{idx + 1:03d}')
        r, c = idx // 16, idx % 16
        if t < t_on:                                   # 未点亮：空格（虚位以待）
            x, y = U(x0g + c * (cell + gap)), U(y0g + r * (cell + gap))
            d.rectangle([x, y, x + U(cell) - 1, y + U(cell) - 1], outline=(205, 199, 185), width=1)
            continue
        pop = punch_env(t, t_on, GRID.beat * 0.45)     # 点亮瞬间小 pop（果冻语言的「闪一下」）
        cs = cell * lerp(1.0, 1.22, (pop - 1.0) / 0.08)
        x = U(x0g + c * (cell + gap) + (cell - cs) / 2)
        y = U(y0g + r * (cell + gap) + (cell - cs) / 2)
        d.rectangle([x, y, x + U(cs) - 1, y + U(cs) - 1], fill=HEAT[min(4, lv[idx])])
    put(img, text_img('每日刷题热力图 · 一格 = 一天', 30, bold=False, fill=INK_SOFT), 1060, 890,
        anchor='lm')


_heat_cache = []


def _heat_levels():
    if not _heat_cache:
        rng = random.Random('dealer-heat')
        _heat_cache.extend(rng.randint(1, 4) for _ in range(128))
    return _heat_cache


def sc_chorus4(img, f, t, tl):
    """Chorus④ 113.7–123.9「不等了」：三贴纸各一拍 punch + slogan 定格"""
    b = boil(f)
    strokes = []
    t_freeze = tl.t('slogan_freeze')
    fro = seg(t, t_freeze, t_freeze + GRID.beat)      # 定格：阻尼把果冻幅度收 0（只留 10fps boil）
    amp = 1.0 - fro
    stickers = [('sticker_1', '无账号', 'y', 560, 350, -3), ('sticker_2', '无广告', 'g', 960, 300, 2),
                ('sticker_3', '完全免费', 'p', 1360, 350, -2)]
    for i, (nm, s, col, cx, cy, rot0) in enumerate(stickers):
        t0 = tl.t(nm)
        if t < t0:
            continue
        k = punch_env(t, t0, GRID.beat * 0.6)          # 各一拍 punch
        px, py = (lerp(cx, 560 + i * 400, fro), lerp(cy, 330, fro)) if t >= t_freeze else (cx, cy)
        sx, sy = jelly(t, 0.012 * i)
        sx, sy = lerp(1, sx, k * amp), lerp(1, sy, k * amp)
        put(img, chip_sprite(nm, s, 360, 130, 56, fill_bg=STICKER[col], line=2.4, shadow=4.5)[b],
            px, py + hop(t, 0.012 * i, 18) * amp, anchor='mm', rot=rot0 * amp, sx=sx, sy=sy)
    if t >= t_freeze:
        k = punch_env(t, t_freeze, GRID.beat * 0.7)
        put(img, text_img(SLOGAN, 132, stroke=3), 960, 620, anchor='mm', sc=k)
        w2 = measure(SLOGAN, 132)
        strokes.append(hl('slogan', 960 - w2 / 2 - 18, 560, w2 + 36, 128, t, t_freeze + 0.12,
                          t_freeze + 0.6, 'y', 0.5))
    t_dl = tl.t('download_line')
    if t >= t_dl:
        put(img, text_img(DOWNLOAD, 56, bold=False, fill=INK_SOFT), 960, 780, anchor='mm',
            sc=punch_env(t, t_dl, GRID.beat * 0.6))
    apply_highlights(img, strokes, b)


def sc_outro(img, f, t, tl):
    """尾奏 123.9–129.6：墨墨 highlight 定格 + 爪印 + 终字幕（最后 2 帧硬切黑在 draw_frame）"""
    b = boil(f)
    put_jelly(img, mascot_size('highlight', 560)[b], 960, 520, t, anchor='mm', amp=0.35)
    for i, nm in enumerate(('paw_1', 'paw_2', 'paw_3')):
        t0 = tl.t(nm)
        if t < t0:
            continue
        do(img, f'pawo{i}', 110, 110, paw_print, 620 + i * 130, 860 - (i % 2) * 60, f,
           rot=-14 + i * 12, sc=max(0.01, punch_env(t, t0, GRID.beat * 0.5)) * 1.5)
    t_c = tl.t('final_caption')
    if t >= t_c:
        strip = styled_paper('finalcap', 1360, 132,
                             lambda g: g.text(FINAL_CAP, 680, 66, 64, anchor='mm'), segs=4)
        put(img, strip[b], 960, 972, anchor='mm', sc=punch_env(t, t_c, GRID.beat * 0.7))


SECTION_FUNCS = (
    ('intro_scene_in', sc_intro), ('hook_punch_title', sc_chorus1), ('verse1_title_in', sc_verse1),
    ('phone_drift_in', sc_chorus2), ('verse2_title_in', sc_verse2), ('stats_phone_in', sc_chorus3),
    ('sticker_1', sc_chorus4), ('outro_scene', sc_outro),
)


def draw_frame(bg, f, t, tl, sections):
    """单帧合成：预合成背景复用 + 当前段落场景。场景状态机全部按绝对时间（--start 切片渲染也一致）。"""
    img = bg.copy()
    fn = sections[0][1]
    for idx16, func in sections:
        if t + 1e-9 >= GRID.t(idx16):
            fn = func
    out = fn(img, f, t, tl)          # 场景就地作画；verse 蒙太奇会整帧微果冻后返回新图
    return img if out is None else out


# ---------------------------------------------------------------- beatmap.txt
def write_beatmap(path, events, grid, t_start, t_end):
    """全部事件 → 秒数 + 拍号 + 核验段（可核对「全在整拍/十六分上」）"""
    sixteenth = grid.sixteenth
    lines = []
    A = lines.append
    A("# 猫卷 meme 宣传片《Why's this dealer taking the piss? —— 为什么这个题贩子让我等半天？！》")
    A('# 生成器: tool/make_dealer_video.py    渲染窗: --start %g --end %g    --bpm %g'
      % (t_start, t_end, grid.bpm))
    A('#')
    A('# ================= 拍网格定义 =================')
    A('# %g BPM、4/4：1 拍 = 60/%g = %.9fs，1 小节 = 4 拍，1 十六分 = %.9fs'
      % (grid.bpm, grid.bpm, grid.beat, sixteenth))
    A('# 拍点 t_k = k × 60/%g；十六分格点 t_m = m × 15/%g（135 时恰为 m/9 s）' % (grid.bpm, grid.bpm))
    A('# 事件真源 = 十六分格位 idx16（音乐位置）；t_event = idx16 × 15/%g。'
      '--bpm 变 → 全事件自动重排到新网格。' % grid.bpm)
    A('# 吸附规则：给定时间戳（Hook punch 行/段落边界）→ 最近十六分格点（整拍是十六分格点的子集，')
    A('#          最坏偏差 = 半个十六分 = %.1fms）；自设踩拍事件 = 锚点 + 整拍偏移。' % (sixteenth * 500))
    A('# 果冻弹跳 = 解析式每拍一次 squash&stretch（相位参数化，错相位 10-30ms），非逐帧物理模拟。')
    n_frames = int(round((t_end - t_start) * grid.fps))
    A('# 尾奏最后 2 帧硬切黑 = 帧级约定（f%05d/f%05d），不属于拍上动画事件，故不入事件表。'
      % (n_frames - 1, n_frames))
    A('#')
    A('# ================= 段落锚点（事实给定秒 → 吸附格位） =================')
    A('# %-10s %10s %10s %13s %13s %12s' % ('段落', 'stated起', 'stated止', 'snapped起', 'snapped止', '起拍号'))
    anchor_names = ('intro_scene_in', 'hook_punch_title', 'verse1_title_in', 'phone_drift_in',
                    'verse2_title_in', 'stats_phone_in', 'sticker_1', 'outro_scene')
    anchors = [next(e for e in events if e.name == nm) for nm in anchor_names]
    for (key, cn, ts, te), e in zip(SONG_FACTS, anchors):
        nxt = anchors[anchors.index(e) + 1] if anchors.index(e) + 1 < len(anchors) else None
        A('# %-10s %10.2f %10.2f %13.3f %13s %12s'
          % (cn, ts, te, grid.t(e.idx16),
             f'{grid.t(nxt.idx16):.3f}' if nxt else f'{t_end:.3f}',
             f'beat {grid.beat_no(e.idx16):g}'))
    A('#')
    A('# ================= 事件表（共 %d 条，按格位排序） =================' % len(events))
    A('# %-6s %-8s %-11s %-9s %-11s %-8s %-6s %-22s %s'
      % ('idx16', 'beat', 'bar.beat.sxt', 't_target', 't_event', 'Δ目标ms', 'kind', 'event', 'label'))
    whole, max_grid_err, max_tgt = 0, 0.0, 0.0
    for e in events:
        te = grid.t(e.idx16)
        max_grid_err = max(max_grid_err, abs(te - e.idx16 * sixteenth))
        if e.target is not None:
            d_ms = (te - e.target) * 1000.0
            max_tgt = max(max_tgt, abs(d_ms))
            d_s = f'{d_ms:+.1f}'
        else:
            d_s = '-'
        kind = 'beat' if grid.is_beat(e.idx16) else '16th'
        whole += kind == 'beat'
        A('%-6d %-8.2f %-11s %-9s %-11.6f %-8s %-6s %-22s %s'
          % (e.idx16, grid.beat_no(e.idx16), Grid.bar_label(e.idx16),
             f'{e.target:.3f}' if e.target is not None else '-', te, d_s, kind, e.name, e.label))
    A('#')
    A('# ================= 核验 =================')
    A('# 事件总数 %d（整拍 %d 条 / 十六分 %d 条），全部满足 t_event == idx16 × 15/%g'
      % (len(events), whole, len(events) - whole, grid.bpm))
    A('# 格点浮点偏差 max %.2e s（≈ %.3e ms）→ 逐条精确落在整拍/十六分格点上' %
      (max_grid_err, max_grid_err * 1000))
    A('# 吸附事件与给定时间戳最大差 %.1fms ≤ 半个十六分 %.1fms（吸附规则上限）'
      % (max_tgt, sixteenth * 500))
    A('# 抽查 6 条（拍号与 t_event 自洽）：')
    for nm in ('hook_punch_title', 'qcard_land', 'phone_drift_in', 'cards_lineup', 'heat_cell_064',
               'slogan_freeze'):
        e = next(x for x in events if x.name == nm)
        A('#   %-16s idx16=%-5d beat %-7g %-11s t=%.6fs → %s'
          % (nm, e.idx16, grid.beat_no(e.idx16), Grid.bar_label(e.idx16), grid.t(e.idx16),
             '整拍' if grid.is_beat(e.idx16) else '十六分'))
    txt = '\n'.join(lines) + '\n'
    if str(path) == '-':
        print(txt)
    else:
        path.write_text(txt, encoding='utf-8')
    return len(events), whole


# ---------------------------------------------------------------- 渲染 / 编码
def run_ffmpeg(args):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stderr[-2000:])
        raise SystemExit(f'ffmpeg 失败：{" ".join(map(str, args[:6]))}…')
    return r


def encode_video(frames_dir, out_path, fps):
    """H.264 yuv420p crf20 +faststart；无音轨（mux 一条命令见文件头 docstring）"""
    run_ffmpeg(['ffmpeg', '-y', '-framerate', str(fps), '-i', str(frames_dir / 'f_%05d.png'),
                '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', '-movflags', '+faststart',
                '-an', '-hide_banner', '-loglevel', 'error', str(out_path)])


def sync_proof_plan(events, grid, t_start, fps):
    """sync_proof 抽帧计划：{帧号: [(事件名, 拍号, 帧号, 后缀)]}（命中帧 + 前 2/后 2）"""
    plan = {}
    by = {e.name: e for e in events}
    for nm in SYNC_PROOF:
        e = by[nm]
        f0 = int(math.floor((grid.t(e.idx16) - t_start) * fps + 1e-6))
        beat = f'{grid.beat_no(e.idx16):g}'
        for df, suf in ((-2, 'm2'), (-1, 'm1'), (0, 'hit'), (1, 'p1'), (2, 'p2')):
            if f0 + df >= 0:
                plan.setdefault(f0 + df, []).append((nm, beat, f0 + df, suf))
    return plan


def video_stats(path):
    r = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-count_frames',
                        '-show_entries',
                        'stream=codec_name,profile,width,height,r_frame_rate,pix_fmt,nb_read_frames,duration'
                        ':format=duration,size,bit_rate', '-of', 'default=nw=1', str(path)],
                       capture_output=True, text=True)
    return r.stdout.strip()


def main():
    global S, W, H, GRID
    ap = argparse.ArgumentParser(
        description="猫卷 meme 宣传片《Why's this dealer taking the piss?》生成器（135 BPM 拍网格）")
    ap.add_argument('--bpm', type=float, default=135.0,
                    help='拍网格 BPM（默认 135；改变后全事件自动重排到新网格）')
    ap.add_argument('--start', type=float, default=0.0, help='渲染窗起点（秒，默认 0）')
    ap.add_argument('--end', type=float, default=TOTAL_SEC,
                    help='渲染窗终点（秒，默认 129.6；--bpm 微调后可按 129.6×135/bpm 等比传入）')
    ap.add_argument('--out', default=str(DEFAULT_OUT), help='输出 mp4 路径')
    ap.add_argument('--frames-dir', default=str(DEFAULT_FRAMES),
                    help='帧目录（背景/装饰/吉祥物预合成复用）')
    ap.add_argument('--beatmap-out', default='',
                    help='beatmap.txt 路径（默认 <out 同目录>/beatmap.txt，传 - 打印到 stdout）')
    ap.add_argument('--scale', type=float, default=1.0, help='0.5 = 960×540 快速试跑')
    ap.add_argument('--fps', type=int, default=FPS)
    ap.add_argument('--stills', default='', help='仅渲染这些时间点关键帧（逗号分隔）→ frames-dir/stills/')
    ap.add_argument('--beatmap-only', action='store_true', help='只写 beatmap.txt（不渲染）')
    ap.add_argument('--skip-encode', action='store_true', help='只渲染帧，不合成 mp4')
    ap.add_argument('--skip-sync-proof', action='store_true', help='不抽 sync_proof 帧')
    ap.add_argument('--clean-frames', action='store_true', help='合成后删除帧目录')
    args = ap.parse_args()

    S = args.scale
    W, H = int(DESIGN_W * S), int(DESIGN_H * S)
    GRID = Grid(args.bpm, args.fps)
    events = build_events(GRID)
    tl = Timeline(events, GRID)
    sections = [(tl.ev[nm].idx16, fn) for nm, fn in SECTION_FUNCS]
    out_path = Path(args.out)
    out_dir = out_path.parent
    out_dir.mkdir(parents=True, exist_ok=True)
    frames_dir = Path(args.frames_dir)
    beatmap_path = Path(args.beatmap_out) if args.beatmap_out else out_dir / 'beatmap.txt'

    print(f'网格 {GRID.bpm:g} BPM | 1 拍 {GRID.beat:.6f}s | 1 十六分 {GRID.sixteenth:.6f}s | '
          f'事件 {len(events)} 条')
    if args.beatmap_only:
        write_beatmap(beatmap_path, events, GRID, args.start, args.end)
        if str(beatmap_path) != '-':
            print('beatmap →', beatmap_path)
        return

    write_beatmap(beatmap_path, events, GRID, args.start, args.end)
    print('beatmap →', beatmap_path)
    bg = build_bg()
    Background.bg = bg

    if args.stills:                                    # 美术校对模式
        still_dir = frames_dir / 'stills'
        still_dir.mkdir(parents=True, exist_ok=True)
        for t in [float(x) for x in args.stills.split(',') if x.strip()]:
            p = still_dir / f'still_{t:06.2f}s.png'
            draw_frame(bg, int(round(t * args.fps)), t, tl, sections).save(p)
            print('  still →', p)
        return

    n = int(round((args.end - args.start) * args.fps))
    frames_dir.mkdir(parents=True, exist_ok=True)
    for old in frames_dir.glob('f_*.png'):
        old.unlink()
    plan = {} if args.skip_sync_proof else sync_proof_plan(events, GRID, args.start, args.fps)
    proof_dir = out_dir / 'sync_proof'
    if plan:
        proof_dir.mkdir(parents=True, exist_ok=True)
        for old in proof_dir.glob('beat*_*.png'):
            old.unlink()
    print(f'画布 {W}×{H} @ {args.fps}fps  渲染 {n} 帧（{args.start}~{args.end}s）  帧目录 {frames_dir}')
    for f in range(n):
        # 采样点取帧区间末端（-0.1ms 余量）：帧 f 在播放中显示于 [f/fps,(f+1)/fps)，
        # 末端采样保证「事件恰在该帧区间内发生」时就画在该帧上 = floor(t×fps) 严格同步；
        # 若用区间起点采样，事件会稳定晚 1 帧（0~33ms 抖动），踩拍就不紧了。
        t = args.start + (f + 1) / args.fps - 1e-4
        img = draw_frame(bg, f, t, tl, sections)
        if f >= n - 2:                                  # 验收线：最后 2 帧硬切黑
            img = Image.new('RGB', (W, H), (0, 0, 0))
        img.save(frames_dir / f'f_{f + 1:05d}.png', compress_level=1)
        for nm, beat, ff, suf in plan.get(f, []):
            img.save(proof_dir / f'beat{beat}_{nm}_f{ff:05d}_{suf}.png')
        if f % 150 == 0:
            print(f'  帧 {f + 1}/{n}  t={t:.2f}s')
    print(f'渲染完成：{n} 帧' + (f'  sync_proof {sum(len(v) for v in plan.values())} 张' if plan else ''))
    if args.skip_encode:
        return
    encode_video(frames_dir, out_path, args.fps)
    print('成片 →', out_path)
    print(video_stats(out_path))
    if args.clean_frames:
        shutil.rmtree(frames_dir, ignore_errors=True)
        print('已清理帧目录')


if __name__ == '__main__':
    main()
