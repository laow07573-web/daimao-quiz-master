# -*- coding: utf-8 -*-
"""生成「PDF 导入题库 + 题目配图」验收样张（考试体例，带文字层）。

覆盖点：
  Q1 「下图所示」：题干与选项之间的位图插图（PIL 画的心电图）
  Q2 「上图所示」：图在题号之前的前置图（归属要挂到第 2 题最前）
  Q3 一题两图 + 矢量线图（fpdf2 直接画线，考验光栅化取图）
  Q4 跨页题：题干在第 2 页末、选项在第 3 页
  Q5 解析带图：图落在解析段里（渲染要挂在解析区）
  第 4 页：整页扫描图（无文字层），用于验证扫描件明确报错

样张是过程素材，不入仓库；本脚本才是源码。输出目录：
  D:/dev/maojuan_private/pdf_samples/
"""
import math
import os
import random

from fpdf import FPDF
from PIL import Image, ImageDraw

OUT_DIR = r"D:/dev/maojuan_private/pdf_samples"
FONT = r"D:/dev/flashcard_app/fonts/MiSans-Regular.ttf"
W_MM, H_MM = 210, 297
MARGIN = 20


def make_ecg_png(path: str) -> None:
    """位图插图：类心电图曲线（含网格），宽扁构图"""
    w, h = 900, 260
    im = Image.new("RGB", (w, h), "white")
    d = ImageDraw.Draw(im)
    for x in range(0, w, 15):
        d.line([(x, 0), (x, h)], fill=(230, 210, 210))
    for y in range(0, h, 15):
        d.line([(0, y), (w, y)], fill=(230, 210, 210))
    random.seed(7)
    pts = []
    base = h // 2
    for x in range(0, w):
        y = base
        phase = x % 150
        if 20 <= phase < 28:
            y = base - 8
        elif 30 <= phase < 36:
            y = base + 90  # R 波
        elif 36 <= phase < 42:
            y = base - 25
        elif 70 <= phase < 95:
            y = base - 22 * math.sin((phase - 70) / 25 * math.pi)  # T 波
        pts.append((x, y + random.randint(-1, 1)))
    d.line(pts, fill=(20, 20, 20), width=2)
    im.save(path)


def make_histology_png(path: str) -> None:
    """位图插图：类病理切片（圆形视野 + 深浅不一的细胞核）"""
    s = 520
    im = Image.new("RGB", (s, s), "white")
    d = ImageDraw.Draw(im)
    d.ellipse([10, 10, s - 10, s - 10], outline=(60, 40, 120), width=4)
    random.seed(11)
    for _ in range(220):
        ang = random.random() * 2 * math.pi
        r = random.random() ** 0.5 * (s / 2 - 40)
        cx, cy = s / 2 + r * math.cos(ang), s / 2 + r * math.sin(ang)
        rr = random.randint(4, 11)
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr],
                  fill=(random.randint(120, 190), random.randint(60, 110), random.randint(150, 210)))
    im.save(path)


def make_scan_page_png(path: str) -> None:
    """整页扫描图（无文字层）：把一页“印”成图片"""
    w, h = 850, 1200
    im = Image.new("RGB", (w, h), (248, 246, 240))
    d = ImageDraw.Draw(im)
    random.seed(3)
    y = 90
    d.text((70, 40), "SCANNED PAGE (no text layer)", fill=(90, 90, 90))
    while y < h - 80:
        d.line([(70, y), (w - 70, y)], fill=(70, 70, 70), width=3)
        y += 26
        if random.random() < 0.15:
            y += 40
    im.save(path)


def draw_vector_figure(pdf: FPDF, y: float) -> float:
    """矢量线图：三条心电样曲线（纯画线，无位图对象）"""
    pdf.set_draw_color(20, 20, 20)
    pdf.set_line_width(0.5)
    top = y
    for k in range(3):
        base = top + 8 + k * 14
        pts = []
        for i in range(0, 151):
            x = MARGIN + i * (W_MM - 2 * MARGIN) / 150
            phase = i % 25
            dy = 0
            if 4 <= phase < 7:
                dy = -3
            elif 8 <= phase < 11:
                dy = 6
            elif 15 <= phase < 20:
                dy = -2
            pts.append((x, base + dy))
        pdf.polyline(pts)
    # 把光标推到图下沿：polyline 是绝对坐标绘制、不动光标，
    # 不推的话后续文字/图片会叠画进图里（两张图粘成一张）
    pdf.set_y(top + 50)
    return top + 50


class SamplePDF(FPDF):
    no_footer = False  # 整页扫描页不印页脚：页脚文本行会把整页图切开

    def footer(self) -> None:  # 页脚页码（文字层）
        if self.no_footer:
            return
        self.set_y(-15)
        self.set_font("misans", size=9)
        self.set_text_color(120, 120, 120)
        self.cell(0, 8, f"猫卷导入样张 · 第 {self.page_no()} 页", align="C")


def build() -> str:
    os.makedirs(OUT_DIR, exist_ok=True)
    ecg = os.path.join(OUT_DIR, "_fig_ecg.png")
    his = os.path.join(OUT_DIR, "_fig_histo.png")
    scan = os.path.join(OUT_DIR, "_fig_scanpage.png")
    make_ecg_png(ecg)
    make_histology_png(his)
    make_scan_page_png(scan)

    pdf = SamplePDF(format="A4")
    # 自动分页必须开：关掉时超出版心的内容会写到页外，
    # y 序一乱（曾把下一题的题干插进上一题的选项中间），样张就失去验收意义
    pdf.set_auto_page_break(auto=True, margin=25)
    pdf.add_font("misans", fname=FONT)
    pdf.add_page()

    def text(s: str, size=11, h=7, gap=1.2) -> float:
        pdf.set_font("misans", size=size)
        pdf.set_text_color(20, 20, 20)
        pdf.set_x(MARGIN)
        pdf.multi_cell(W_MM - 2 * MARGIN, h, s)
        pdf.ln(gap)
        return pdf.get_y()

    text("2026 猫卷 PDF 导入样张（测试用，非真实试题）", size=14, h=9, gap=6)

    # ---- Q1「下图所示」：题干 → 图 → 选项 ----
    y = text("1．下图所示心电图最可能的诊断是")
    pdf.ln(6)
    pdf.image(ecg, x=MARGIN + 25, w=130)
    pdf.ln(5)
    text("图1  患者入院时心电图")
    text("A．窦性心动过速")
    text("B．心房颤动")
    text("C．三度房室传导阻滞")
    y = text("D．室性早搏", gap=10)

    # ---- Q2「上图所示」：图在题号之前（前置图，距下一题号更近） ----
    pdf.image(his, x=MARGIN + 45, w=90)
    pdf.ln(2)  # 图与题号间距要小于图与上一题的间距
    y = text("2．如上图所示，该病理切片最可能取自哪个器官")
    text("A．肝")
    text("B．肾")
    text("C．脾")
    text("D．肺", gap=10)

    # ---- Q3 一题两图 + 矢量线图 ----
    y = text("3．对比下两幅图，患者的异常改变是")
    pdf.ln(5)
    y = draw_vector_figure(pdf, pdf.get_y())
    pdf.ln(3)
    text("图2  三次复查曲线（矢量绘制）")
    pdf.image(his, x=MARGIN + 55, w=70)
    pdf.ln(4)
    text("图3  复查病理切片")
    text("A．无变化")
    text("B．波形振幅进行性增高")
    text("C．出现病理性 Q 波")
    text("D．以上都不对", gap=8)

    # ---- Q4 跨页题：题干贴页底、选项在下一页 ----
    # 只在确有余量时压到页底（y 超版心会触发自动分页，反而到不了页底）
    if pdf.get_y() < H_MM - 75:
        pdf.set_y(H_MM - 60)
    text("4．关于上述心电图与病理表现的关系，下列说法正确的是")
    pdf.add_page()
    text("（接上题）")
    text("A．两者无关联")
    text("B．心电改变可先于形态学改变出现")
    text("C．形态学改变一定先出现")
    text("D．无法判断", gap=10)

    # ---- Q5 解析带图 ----
    y = text("5．下列对图示结构的描述，错误的是")
    text("A．参与构成血-气屏障")
    text("B．由单层上皮构成")
    text("C．基底膜完整")
    text("D．无弹性纤维")
    y = text("【答案】D")
    y = text("【解析】如下图所示，该结构弹性纤维丰富，故 D 错误：")
    pdf.ln(4)
    pdf.image(ecg, x=MARGIN + 35, w=110)
    pdf.ln(3)
    text("图4  图示结构示意（矢量+位图混合）")

    # ---- 第 4 页：整页扫描图（无文字层） ----
    pdf.no_footer = True
    pdf.add_page()
    pdf.image(scan, x=0, y=0, w=W_MM, h=H_MM)

    out = os.path.join(OUT_DIR, "猫卷-导入样张.pdf")
    pdf.output(out)
    return out


if __name__ == "__main__":
    print(build())
