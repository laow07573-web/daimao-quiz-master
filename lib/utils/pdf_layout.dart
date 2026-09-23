/// PDF 版面分析（纯几何）：文本分行、图区空隙检测、像素换算、图文交织与图归属。
///
/// 坐标系是 PDF 点、y 向上（top > bottom，原点在左下）；渲染像素则是 y 向下，
/// 两者的换算集中在 [pdfBoxToPixels] / [pixelsToPdfBox]。
/// 矩形用记录类型传递、与 pdfrx 解耦，便于单测。
library;

import 'dart:math' as math;

/// PDF 点坐标矩形（y 向上）
typedef PdfBox = ({double left, double top, double right, double bottom});

double boxWidth(PdfBox b) => b.right - b.left;

double boxHeight(PdfBox b) => b.top - b.bottom;

PdfBox mergeBox(PdfBox a, PdfBox b) => (
      left: math.min(a.left, b.left),
      top: math.max(a.top, b.top),
      right: math.max(a.right, b.right),
      bottom: math.min(a.bottom, b.bottom),
    );

/// 垂直重叠量（无重叠为负）
double vOverlap(PdfBox a, PdfBox b) =>
    math.min(a.top, b.top) - math.max(a.bottom, b.bottom);

/// 文本片段（pdfrx PdfPageTextFragment 的最小抽象）
class PdfTextItem {
  const PdfTextItem(this.text, this.bounds);
  final String text;
  final PdfBox bounds;
}

/// 文本行：行内片段已按左右合并，[bounds] 为行包围盒
class PdfTextLine {
  const PdfTextLine(this.text, this.bounds);
  final String text;
  final PdfBox bounds;
  double get height => bounds.top - bounds.bottom;
}

/// 片段合并成行：自上而下、行内自左到右。
/// 同一行判定按垂直重叠（不同字号混排也稳），行内水平空隙 ≥ [wordGap] 补空格。
List<PdfTextLine> groupTextLines(List<PdfTextItem> items,
    {double wordGap = 1.5}) {
  if (items.isEmpty) return const [];
  final sorted = [...items]
    ..sort((x, y) {
      final c = y.bounds.top.compareTo(x.bounds.top); // 页首在前
      return c != 0 ? c : x.bounds.left.compareTo(y.bounds.left);
    });

  final groups = <List<PdfTextItem>>[];
  for (final it in sorted) {
    List<PdfTextItem>? target;
    for (final g in groups) {
      var box = g.first.bounds;
      for (final o in g) {
        box = mergeBox(box, o.bounds);
      }
      final ov = vOverlap(box, it.bounds);
      if (ov >= 0.5 * boxHeight(it.bounds) ||
          (g.length == 1 && ov >= 0.5 * boxHeight(g.first.bounds))) {
        target = g;
        break;
      }
    }
    if (target != null) {
      target.add(it);
    } else {
      groups.add([it]);
    }
  }

  final lines = <PdfTextLine>[];
  for (final g in groups) {
    final items = [...g]
      ..sort((x, y) => x.bounds.left.compareTo(y.bounds.left));
    var box = items.first.bounds;
    final buf = StringBuffer();
    double? prevRight;
    for (final it in items) {
      if (prevRight != null && it.bounds.left - prevRight > wordGap) {
        buf.write(' ');
      }
      // 片段文本自带的换行/首尾空白是抽取噪声，压平它
      buf.write(it.text.trim());
      prevRight = it.bounds.right;
      box = mergeBox(box, it.bounds);
    }
    // 空白行丢弃：空行会把图区空隙切碎，归属判定跟着失真
    if (buf.toString().trim().isEmpty) continue;
    lines.add(PdfTextLine(buf.toString(), box));
  }
  lines.sort((x, y) => y.bounds.top.compareTo(x.bounds.top));
  return lines;
}

/// 行间空隙候选（含页顶/页底空隙）。带宽取满页宽——图可能只占部分宽度，
/// 实际范围由调用方渲染取样后裁紧。
class PdfGap {
  const PdfGap(this.bounds, {this.above, this.below});
  final PdfBox bounds;

  /// 空隙上方最近行（页顶空隙为 null）
  final PdfTextLine? above;

  /// 空隙下方最近行（页底空隙为 null）
  final PdfTextLine? below;
  double get height => bounds.top - bounds.bottom;
}

/// 空隙高度阈值 = max([minGap], [gapFactor] × 行高中位数)。
/// 图所在带必然显著高于普通行距，普通换行/段距不会误报。
double figureGapThreshold(List<PdfTextLine> lines,
    {double minGap = 24, double gapFactor = 1.8}) {
  if (lines.isEmpty) return minGap;
  final heights = lines.map((l) => l.height).toList()..sort();
  return math.max(minGap, gapFactor * heights[heights.length ~/ 2]);
}

List<PdfGap> findGapCandidates({
  required List<PdfTextLine> lines,
  required PdfBox page,
  double minGap = 24,
  double gapFactor = 1.8,
}) {
  // 整页无文字：整页作候选（整页图/扫描页）
  if (lines.isEmpty) return [PdfGap(page)];
  final threshold =
      figureGapThreshold(lines, minGap: minGap, gapFactor: gapFactor);
  final gaps = <PdfGap>[];

  final topH = page.top - lines.first.bounds.top;
  if (topH >= threshold) {
    gaps.add(PdfGap(
      (left: page.left, top: page.top, right: page.right, bottom: lines.first.bounds.top),
      below: lines.first,
    ));
  }
  for (var i = 0; i + 1 < lines.length; i++) {
    final a = lines[i], b = lines[i + 1];
    final h = a.bounds.bottom - b.bounds.top;
    if (h >= threshold) {
      gaps.add(PdfGap(
        (left: page.left, top: a.bounds.bottom, right: page.right, bottom: b.bounds.top),
        above: a,
        below: b,
      ));
    }
  }
  final bottomH = lines.last.bounds.bottom - page.bottom;
  if (bottomH >= threshold) {
    gaps.add(PdfGap(
      (left: page.left, top: lines.last.bounds.bottom, right: page.right, bottom: page.bottom),
      above: lines.last,
    ));
  }
  return gaps;
}

/// PDF 点（y 向上）→ 渲染像素（y 向下）
({int x, int y, int width, int height}) pdfBoxToPixels(
  PdfBox box,
  PdfBox page, {
  required int fullWidth,
  required int fullHeight,
}) {
  final sx = fullWidth / boxWidth(page);
  final sy = fullHeight / boxHeight(page);
  final x = (box.left - page.left) * sx;
  final y = (page.top - box.top) * sy; // y 翻转
  final w = boxWidth(box) * sx;
  final h = boxHeight(box) * sy;
  return (x: x.floor(), y: y.floor(), width: w.ceil(), height: h.ceil());
}

/// 渲染像素矩形 → PDF 点（取样裁紧后的图区回写）
PdfBox pixelsToPdfBox(
  int x,
  int y,
  int w,
  int h,
  PdfBox page, {
  required int fullWidth,
  required int fullHeight,
}) {
  final sx = boxWidth(page) / fullWidth;
  final sy = boxHeight(page) / fullHeight;
  return (
    left: page.left + x * sx,
    top: page.top - y * sy,
    right: page.left + (x + w) * sx,
    bottom: page.top - (y + h) * sy,
  );
}

/// 版面流元素：文字段或图区（按阅读序输出）
sealed class PdfFlowItem {
  const PdfFlowItem();
}

class PdfFlowTextItem extends PdfFlowItem {
  const PdfFlowTextItem(this.line);
  final PdfTextLine line;
}

class PdfFlowFigureItem extends PdfFlowItem {
  const PdfFlowFigureItem(this.bounds, {this.attachToNext = false});
  final PdfBox bounds;

  /// 前置图（「上图所示」）：占位符挂到下一文本行之前
  final bool attachToNext;
}

/// 自上而下把文本行与图区交织成阅读流，并做图归属：
///
/// - 图落在题干与选项之间等位置 → 留在原位（「下图所示」版式）；
/// - 图贴着下一题号行、且离它比离上一行更近 → 前置图（「上图所示」版式），
///   占位符移到该行之前。
List<PdfFlowItem> assemblePageFlow({
  required List<PdfTextLine> lines,
  required List<PdfBox> figures,
  required bool Function(String lineText) startsNewQuestion,
}) {
  final attachTo = <PdfBox, PdfTextLine>{}; // 前置图 → 归属行
  final attachBoxes = <PdfBox>{};

  for (final fig in figures) {
    PdfTextLine? above;
    PdfTextLine? below;
    for (final l in lines) {
      if (l.bounds.bottom >= fig.top) {
        if (above == null || l.bounds.bottom < above.bounds.bottom) above = l;
      } else if (l.bounds.top <= fig.bottom) {
        if (below == null || l.bounds.top > below.bounds.top) below = l;
      }
    }
    final gapAbove =
        above == null ? double.infinity : above.bounds.bottom - fig.top;
    final gapBelow =
        below == null ? double.infinity : fig.bottom - below.bounds.top;
    if (below != null && startsNewQuestion(below.text) && gapBelow <= gapAbove) {
      attachTo[fig] = below;
      attachBoxes.add(fig);
    }
  }

  // 阅读序合并：前置图不占原位，改挂到归属行之前
  final entries = <({double topY, PdfTextLine? line, PdfBox? fig})>[
    for (final l in lines) (topY: l.bounds.top, line: l, fig: null),
    for (final f in figures)
      if (!attachBoxes.contains(f)) (topY: f.top, line: null, fig: f),
  ]..sort((x, y) => y.topY.compareTo(x.topY));

  final out = <PdfFlowItem>[];
  final pendingByLine = <PdfTextLine, List<PdfBox>>{};
  attachTo.forEach((fig, line) => (pendingByLine[line] ??= []).add(fig));

  for (final e in entries) {
    final line = e.line;
    if (line != null) {
      out.add(PdfFlowTextItem(line));
      final pending = pendingByLine.remove(line);
      if (pending != null) {
        // 前置图（「上图所示」）紧跟题号行之后：占位符因此落进该题的
        // 文本块内——放在行前会随切块落进上一题
        pending.sort((x, y) => y.top.compareTo(x.top));
        for (final f in pending) {
          out.add(PdfFlowFigureItem(f, attachToNext: true));
        }
      }
    } else {
      out.add(PdfFlowFigureItem(e.fig!));
    }
  }
  // 兜底：归属行未出现（理论上不会），按原位收尾
  for (final fs in pendingByLine.values) {
    for (final f in fs) {
      out.add(PdfFlowFigureItem(f, attachToNext: true));
    }
  }
  return out;
}
