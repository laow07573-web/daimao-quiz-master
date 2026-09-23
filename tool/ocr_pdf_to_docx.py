# -*- coding: utf-8 -*-
"""扫描版 PDF → 可导入 DOCX 的桥接工具。

背景：猫卷的 PDF 导入只支持「有文字层」的 PDF（切题靠文字）。扫描版/图片型
PDF（每页就是一张图）抽不出文字，会被明确拒绝。本工具把这类 PDF 先转成
DOCX——逐页取嵌入页图 → RapidOCR 离线中文识别 → 按阅读序拼回段落 → 出 DOCX，
再走猫卷现有的「DOCX 导入（AI 切题）」通道入库，题目一道不少。

用法:
  python tool/ocr_pdf_to_docx.py 输入.pdf [输出.docx]
  （缺省输出为同名 .docx；RapidOCR 离线跑，不联网、不上传任何内容）

原理说明（为什么这么做）:
- 扫描版每页在 PDF 里就是一张嵌入图（XObject），直接取图比"渲染整页"省事
  且不丢分辨率
- 识别行按 (y 桶, x) 排序还原阅读序；逐行一段写入 DOCX，交给猫卷的
  AI 切题去组题（结构识别本来就由它负责）
"""
import os
import sys

import numpy as np
from docx import Document
from pypdf import PdfReader
from rapidocr_onnxruntime import RapidOCR


def ocr_lines(engine, pil_img):
    """一页图 → 阅读序文本行列表（按行聚类：y 桶 + 行内 x）"""
    arr = np.array(pil_img.convert('RGB'))
    result, _ = engine(arr)
    if not result:
        return []
    items = []
    for box, text, score in result:
        xs = [p[0] for p in box]
        ys = [p[1] for p in box]
        items.append((sum(ys) / len(ys), min(xs), text))
    items.sort(key=lambda it: (round(it[0] / 14), it[1]))  # 14px 行桶
    return [t for _, _, t in items]


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else src.rsplit('.', 1)[0] + '.docx'

    reader = PdfReader(src)
    engine = RapidOCR()
    doc = Document()
    n_lines = 0
    for i, page in enumerate(reader.pages):
        page_lines = []
        for im in page.images:
            try:
                page_lines.extend(ocr_lines(engine, im.image))
            except Exception as e:  # 单页失败不拖垮全书
                print(f'  第{i+1}页识别失败: {e}')
        for ln in page_lines:
            s = ln.strip()
            if s:
                doc.add_paragraph(s)
                n_lines += 1
        print(f'第 {i + 1}/{len(reader.pages)} 页：{len(page_lines)} 行')

    doc.save(dst)
    print(f'完成：{n_lines} 行 → {dst}')
    print('下一步：在猫卷里用「导入题库 → DOCX」选这个文件（需配 API Key 让 AI 切题）')


if __name__ == '__main__':
    main()
