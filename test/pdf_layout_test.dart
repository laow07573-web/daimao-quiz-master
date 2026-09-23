import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/utils/pdf_layout.dart';

/// PDF 版面分析（纯几何）的回归测试。
///
/// 图文归属是 PDF 导入最容易出错的一环：图挂错题 = 图片出现在错误的题目里，
/// 违背「图片作为题目的一部分」。这里用合成坐标把两种真实版式钉死：
/// 「下图所示」（图在题干与选项之间）与「上图所示」（图在题号之前）。
void main() {
  // 约定：页面 600×800pt，y 向上（top > bottom）
  const page = (left: 0.0, top: 800.0, right: 600.0, bottom: 0.0);

  PdfBox line(double top, {double left = 50, double right = 550, double h = 14}) =>
      (left: left, top: top, right: right, bottom: top - h);

  group('文本分行', () {
    test('同一视觉行的不同片段合并成一行，行内按左右排序、空隙补空格', () {
      // 两片段同高同带（垂直重叠过半）→ 一行；水平相隔 20pt → 中间补空格
      final items = [
        PdfTextItem('诊断', (left: 100, top: 700, right: 140, bottom: 686)),
        PdfTextItem('是', (left: 160, top: 701, right: 180, bottom: 687)),
      ];
      final lines = groupTextLines(items);
      expect(lines, hasLength(1));
      expect(lines.single.text, '诊断 是');
    });

    test('不同 y 带分成多行，输出自上而下', () {
      final items = [
        PdfTextItem('第二行', line(400)),
        PdfTextItem('第一行', line(700)),
      ];
      final lines = groupTextLines(items);
      expect(lines.map((l) => l.text), ['第一行', '第二行']);
    });

    test('紧邻片段不补空格（连续中英文）', () {
      final items = [
        PdfTextItem('心电图', (left: 50, top: 700, right: 110, bottom: 686)),
        PdfTextItem('诊断', (left: 111, top: 700, right: 151, bottom: 686)),
      ];
      expect(groupTextLines(items).single.text, '心电图诊断');
    });
  });

  group('图区空隙检测', () {
    PdfTextLine tl(String text, double top) => PdfTextLine(text, line(top));

    test('普通行距不误报，图区高度才报', () {
      final lines = [tl('a', 700), tl('b', 676), tl('c', 652)]; // 行高14、行距10
      // 页面贴住该段文字：页顶/页底空隙也不存在，纯验行距不误报
      const tight = (left: 0.0, top: 714.0, right: 600.0, bottom: 638.0);
      final gaps = findGapCandidates(lines: lines, page: tight);
      expect(gaps, isEmpty);
    });

    test('大空隙报候选（含页顶/页间/页底）', () {
      final lines = [tl('a', 600), tl('b', 400)]; // 中间 186pt 空隙
      final gaps = findGapCandidates(lines: lines, page: page, minGap: 24);
      expect(gaps, hasLength(3)); // 页顶 + 页间 + 页底
      expect(gaps[1].above?.text, 'a');
      expect(gaps[1].below?.text, 'b');
    });

    test('整页无文字：整页作唯一候选（整页图/扫描页）', () {
      final gaps = findGapCandidates(lines: const [], page: page);
      expect(gaps, hasLength(1));
      expect(gaps.single.height, 800);
    });
  });

  group('像素坐标换算（y 翻转）', () {
    test('页面顶端在像素里 y≈0，底端 y≈fullHeight', () {
      final topPx = pdfBoxToPixels(
        (left: 0, top: 800, right: 100, bottom: 700),
        page,
        fullWidth: 600,
        fullHeight: 800,
      );
      expect(topPx.y, 0);
      expect(topPx.height, 100);

      final bottomPx = pdfBoxToPixels(
        (left: 0, top: 100, right: 100, bottom: 0),
        page,
        fullWidth: 600,
        fullHeight: 800,
      );
      expect(bottomPx.y, 700);
    });

    test('像素 → PDF 点往返一致（取样裁紧后的图区回写）', () {
      const box = (left: 120.0, top: 500.0, right: 420.0, bottom: 300.0);
      final px = pdfBoxToPixels(box, page, fullWidth: 1200, fullHeight: 1600);
      final back = pixelsToPdfBox(px.x, px.y, px.width, px.height, page,
          fullWidth: 1200, fullHeight: 1600);
      expect(back.left, closeTo(box.left, 0.5));
      expect(back.top, closeTo(box.top, 0.5));
      expect(back.right, closeTo(box.right, 1.5));
      expect(back.bottom, closeTo(box.bottom, 1.5));
    });
  });

  group('图文交织与图归属', () {
    bool isQuestionStart(String t) =>
        RegExp(r'^\s*\d+[\.、．]').hasMatch(t);

    PdfTextLine qline(double top, String text) =>
        PdfTextLine(text, line(top));

    test('「下图所示」：图在题干与选项之间 → 留在原位', () {
      final lines = [
        qline(700, '1．下图所示心电图最可能的诊断是'),
        qline(400, 'A．窦性心动过速'),
      ];
      final fig = (left: 150.0, top: 640.0, right: 450.0, bottom: 460.0);
      final flow = assemblePageFlow(
        lines: lines,
        figures: [fig],
        startsNewQuestion: isQuestionStart,
      );
      expect(flow, hasLength(3));
      expect((flow[0] as PdfFlowTextItem).line.text, startsWith('1．'));
      final f = flow[1] as PdfFlowFigureItem;
      expect(f.attachToNext, isFalse);
      expect((flow[2] as PdfFlowTextItem).line.text, startsWith('A．'));
    });

    test('「上图所示」：图贴着下一题号且离它更近 → 挂到该行之后（进该题文本块）', () {
      final lines = [
        qline(700, '1．上一题的选项 D'),
        qline(300, '2．如上图所示，病变部位是'),
      ];
      final fig = (left: 150.0, top: 486.0, right: 450.0, bottom: 326.0);
      final flow = assemblePageFlow(
        lines: lines,
        figures: [fig],
        startsNewQuestion: isQuestionStart,
      );
      expect((flow[0] as PdfFlowTextItem).line.text, startsWith('1．'));
      expect((flow[1] as PdfFlowTextItem).line.text, startsWith('2．'));
      final f = flow[2] as PdfFlowFigureItem;
      expect(f.attachToNext, isTrue);
    });

    test('下一题号上方但离上一行更近 → 仍留原位（不盲信前置）', () {
      final lines = [
        qline(700, '1．上一题的选项 D'),
        qline(200, '2．下一题'),
      ];
      final fig = (left: 150.0, top: 640.0, right: 450.0, bottom: 500.0);
      final flow = assemblePageFlow(
        lines: lines,
        figures: [fig],
        startsNewQuestion: isQuestionStart,
      );
      expect((flow[1] as PdfFlowFigureItem).attachToNext, isFalse);
    });

    test('多张前置图按 y 自上而下挂在同一行后', () {
      final lines = [qline(200, '3．如上两图所示')];
      final fig1 = (left: 50.0, top: 640.0, right: 300.0, bottom: 520.0);
      final fig2 = (left: 50.0, top: 480.0, right: 300.0, bottom: 360.0);
      final flow = assemblePageFlow(
        lines: lines,
        figures: [fig1, fig2],
        startsNewQuestion: isQuestionStart,
      );
      expect(flow, hasLength(3));
      expect((flow[0] as PdfFlowTextItem).line.text, startsWith('3．'));
      expect((flow[1] as PdfFlowFigureItem).bounds.top, 640);
      expect((flow[2] as PdfFlowFigureItem).bounds.top, 480);
    });
  });
}
