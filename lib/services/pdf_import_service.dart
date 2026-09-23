import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

import '../models/question_image.dart';
import '../utils/pdf_layout.dart';
import 'ai_service.dart';

/// PDF 抽取失败（[message] 可直接展示给用户）
class PdfExtractException implements Exception {
  PdfExtractException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 抽取结果：可直接喂 AI 结构化的纯文本（图片以 `{{img:N}}` 占位符内嵌）
/// + 文档级图片池（全局槽位 → 图）。题内槽位重编在导入物化时做。
class PdfExtractResult {
  const PdfExtractResult({
    required this.rawText,
    required this.imagePool,
    required this.pageCount,
    required this.charCount,
  });

  final String rawText;

  /// 全局槽位（文档内 0 起）→ 图
  final Map<int, QuestionImage> imagePool;

  final int pageCount;
  final int charCount;
}

/// PDF 题库抽取：文本行按阅读序交织图区占位符，图区光栅化压缩进图片池。
///
/// 全本地、不依赖 AI：切题/题型仍走既有 AI 结构化链路，占位符随文本流过。
/// 图区检测走「行间空隙 + 取样有无墨迹」，位图/矢量/线图统一光栅化，
/// 避开「抽 PDF 嵌入图对象」在 Dart 生态没有成熟方案的问题。
class PdfImportService {
  /// 压缩上限：长边 ≤ [_maxImageEdge]、单张 ≤ [_maxImageBytes]
  /// （同时是局域网同步 64MB 单次快照的体积保护）
  static const int _maxImageEdge = 1280;
  static const int _maxImageBytes = 512 * 1024;

  /// 无文字层判定：整册可抽字符低于此值视为扫描件/图片型 PDF
  static const int _minTextChars = 100;

  static Future<PdfExtractResult> extract(String filePath) async {
    final PdfDocument doc;
    try {
      doc = await PdfDocument.openFile(filePath);
    } catch (_) {
      throw PdfExtractException('无法打开 PDF 文件（可能已加密或已损坏）');
    }
    try {
      if (doc.pages.isEmpty) {
        throw PdfExtractException('PDF 没有任何页面');
      }
      final out = StringBuffer();
      final pool = <int, QuestionImage>{};
      var slot = 0;
      var charCount = 0;
      var seenQuestions = 0; // 已见题号行数（图归属期望题序用）

      for (final page in doc.pages) {
        final pageBox = (
          left: 0.0,
          top: page.height,
          right: page.width,
          bottom: 0.0,
        );

        var lines = <PdfTextLine>[];
        try {
          final text = await page.loadText();
          lines = groupTextLines([
            for (final f in text.fragments)
              PdfTextItem(
                f.text,
                (
                  left: f.bounds.left,
                  top: f.bounds.top,
                  right: f.bounds.right,
                  bottom: f.bounds.bottom,
                ),
              ),
          ]);
        } catch (_) {
          lines = const []; // 整页取不出文字：按整页候选处理
        }
        for (final l in lines) {
          charCount += l.text.trim().length;
        }

        // 行间空隙 → 取样判图 → 裁紧到墨迹范围
        // （不做相邻合并：被页脚/页码切开的整页图会各归各块，
        //  拆开显示好过猜错合并——两块通常同属一题，归属不受影响）
        final gaps = findGapCandidates(lines: lines, page: pageBox);
        final figures = <PdfBox>[];
        for (final gap in gaps) {
          final fig = await _detectFigure(page, gap.bounds, pageBox: pageBox);
          if (fig != null) figures.add(fig);
        }

        // 图文交织 + 图归属（「下图所示」原位 / 「上图所示」挂到下一题号前）
        final flow = assemblePageFlow(
          lines: lines,
          figures: figures,
          startsNewQuestion: AIService.isQuestionStart,
        );

        for (final item in flow) {
          if (item is PdfFlowTextItem) {
            out.writeln(item.line.text);
            if (AIService.isQuestionStart(item.line.text)) seenQuestions++;
          } else if (item is PdfFlowFigureItem) {
            // 期望题序：占位符都落在归属题号行之后，统一属当前题（seen-1）
            final ordinal = math.max(0, seenQuestions - 1);
            final image = await _renderFigure(
              page,
              item.bounds,
              pageBox: pageBox,
              slot: slot,
              expectedQuestion: ordinal,
            );
            if (image == null) continue;
            pool[slot] = image;
            out.writeln('{{img:${slot++}}}');
          }
        }
        out.writeln(); // 页间空行，防跨页两行粘连
      }

      if (charCount < _minTextChars) {
        throw PdfExtractException(
            '该 PDF 没有文字层（扫描件/图片型），暂不支持。\n请提供带文字层的 PDF（在电脑上能选中文字的那种）。');
      }
      return PdfExtractResult(
        rawText: out.toString(),
        imagePool: pool,
        pageCount: doc.pages.length,
        charCount: charCount,
      );
    } finally {
      await doc.dispose();
    }
  }

  /// 图区取样：低分辨率渲染空隙带，找墨迹包围盒（裁紧），过滤无图/线状噪声。
  /// 找不到真图返回 null。
  static Future<PdfBox?> _detectFigure(
    PdfPage page,
    PdfBox gap, {
    required PdfBox pageBox,
  }) async {
    if (boxHeight(gap) < 12) return null;
    final fullWidth = math.max(1, (boxWidth(pageBox) * 0.6).round());
    final fullHeight = math.max(1, (boxHeight(pageBox) * 0.6).round());
    final px = _clampPx(
        pdfBoxToPixels(gap, pageBox, fullWidth: fullWidth, fullHeight: fullHeight),
        fullWidth,
        fullHeight);
    final rendered = await page.render(
      x: px.x,
      y: px.y,
      width: px.width,
      height: px.height,
      fullWidth: fullWidth.toDouble(),
      fullHeight: fullHeight.toDouble(),
    );
    if (rendered == null) return null;
    final im = _decode(rendered);
    rendered.dispose();

    var minX = im.width, minY = im.height, maxX = -1, maxY = -1, ink = 0;
    for (var y = 0; y < im.height; y++) {
      for (var x = 0; x < im.width; x++) {
        final p = im.getPixel(x, y);
        if (p.r < 242 || p.g < 242 || p.b < 242) {
          ink++;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (ink < 30 || maxX < 0) return null;

    // 内部墨迹校验：行间缝隙里只有文字边缘的抗锯齿辉光时，
    // 墨迹全贴在带边——要求去掉 4px 边框后仍有实墨，才认作图
    var innerInk = 0;
    for (var y = 4; y < im.height - 4; y++) {
      for (var x = 4; x < im.width - 4; x++) {
        final p = im.getPixel(x, y);
        if (p.r < 242 || p.g < 242 || p.b < 242) innerInk++;
      }
    }
    if (innerInk < 20) return null;

    // 墨迹包围盒（带 1px 松弛）回写 PDF 点
    final box = pixelsToPdfBox(
      px.x + minX - 1,
      px.y + minY - 1,
      maxX - minX + 3,
      maxY - minY + 3,
      pageBox,
      fullWidth: fullWidth,
      fullHeight: fullHeight,
    );
    final tight = (
      left: math.max(pageBox.left, box.left),
      top: math.min(pageBox.top, box.top),
      right: math.min(pageBox.right, box.right),
      bottom: math.max(pageBox.bottom, box.bottom),
    );
    // 最小尺寸过滤：横线/装订线等噪声不入图
    if (boxWidth(tight) < 24 || boxHeight(tight) < 16) return null;
    return tight;
  }

  /// 图区成品：2 倍分辨率光栅化 + JPEG 压缩（位图/矢量/线图一视同仁）
  static Future<QuestionImage?> _renderFigure(
    PdfPage page,
    PdfBox fig, {
    required PdfBox pageBox,
    required int slot,
    required int expectedQuestion,
  }) async {
    final fullWidth = math.max(1, (boxWidth(pageBox) * 2).round());
    final fullHeight = math.max(1, (boxHeight(pageBox) * 2).round());
    final px = _clampPx(
        pdfBoxToPixels(fig, pageBox, fullWidth: fullWidth, fullHeight: fullHeight),
        fullWidth,
        fullHeight);
    if (px.width < 4 || px.height < 4) return null;
    final rendered = await page.render(
      x: px.x,
      y: px.y,
      width: px.width,
      height: px.height,
      fullWidth: fullWidth.toDouble(),
      fullHeight: fullHeight.toDouble(),
    );
    if (rendered == null) return null;
    final raw = _decode(rendered);
    rendered.dispose();

    final enc = _encodeJpeg(raw);
    return QuestionImage(
      position: slot,
      width: enc.width,
      height: enc.height,
      // anchor：页码:y 中心:期望题序（丢 token 抢修按期望题序补挂）
      anchor:
          '${page.pageNumber}:${((fig.top + fig.bottom) / 2).toStringAsFixed(1)}:$expectedQuestion',
      content: enc.bytes,
    );
  }

  static ({int x, int y, int width, int height}) _clampPx(
    ({int x, int y, int width, int height}) px,
    int fullWidth,
    int fullHeight,
  ) {
    final x = math.max(0, math.min(px.x, fullWidth - 2));
    final y = math.max(0, math.min(px.y, fullHeight - 2));
    return (
      x: x,
      y: y,
      width: math.max(1, math.min(px.width, fullWidth - x)),
      height: math.max(1, math.min(px.height, fullHeight - y)),
    );
  }

  /// PDFium 像素（RGBA/BGRA）→ image 包位图
  static img.Image _decode(PdfImage pi) {
    final order = pi.format == ui.PixelFormat.bgra8888
        ? img.ChannelOrder.bgra
        : img.ChannelOrder.rgba;
    return img.Image.fromBytes(
      width: pi.width,
      height: pi.height,
      bytes: pi.pixels.buffer,
      bytesOffset: pi.pixels.offsetInBytes,
      order: order,
    );
  }

  /// JPEG 压缩到上限内：先限长边，超 512KB 再逐级缩边（保底 128px 不死磕）
  static ({Uint8List bytes, int width, int height}) _encodeJpeg(img.Image src) {
    var im = src;
    final edge = math.max(im.width, im.height);
    if (edge > _maxImageEdge) {
      final s = _maxImageEdge / edge;
      im = img.copyResize(im,
          width: math.max(1, (im.width * s).round()),
          height: math.max(1, (im.height * s).round()),
          interpolation: img.Interpolation.linear);
    }
    var bytes = Uint8List.fromList(img.encodeJpg(im, quality: 85));
    var w = im.width, h = im.height;
    while (bytes.length > _maxImageBytes && (w > 128 || h > 128)) {
      im = img.copyResize(im,
          width: math.max(1, (w * 0.8).round()),
          height: math.max(1, (h * 0.8).round()),
          interpolation: img.Interpolation.linear);
      w = im.width;
      h = im.height;
      bytes = Uint8List.fromList(img.encodeJpg(im, quality: 75));
    }
    return (bytes: bytes, width: w, height: h);
  }
}
