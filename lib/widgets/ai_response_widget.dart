import 'package:flutter/material.dart';
import '../services/debug_log_service.dart';

/// AI 回复渲染器：轻量富文本解析（自研，不依赖第三方 Markdown 包）
/// 支持：**加粗**、`行内代码`、- 列表、1. 有序列表、#/##/### 标题。
/// v1.0.2 UI 审查修复：flutter_markdown 0.7.1 对「中文全角标点紧跟闭合
/// 星号」解析失败（**定性/计算**： 原样显示），改为自研 span 渲染器。
class AiResponseWidget extends StatelessWidget {
  final String text;
  final double fontSize;
  final Color? color;

  const AiResponseWidget({
    super.key,
    required this.text,
    this.fontSize = 13,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textColor = color ?? cs.onSurface;
    final spans = <InlineSpan>[];

    for (final rawLine in _sanitize(text).split('\n')) {
      var line = rawLine;
      if (line.isEmpty) {
        spans.add(TextSpan(text: '\n'));
        continue;
      }
      var leading = '';
      var headingLevel = 0;
      if (line.startsWith('### ')) {
        headingLevel = 3;
        line = line.substring(4);
      } else if (line.startsWith('## ')) {
        headingLevel = 2;
        line = line.substring(3);
      } else if (line.startsWith('# ')) {
        headingLevel = 1;
        line = line.substring(2);
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        leading = '•  ';
        line = line.substring(2);
      } else {
        final ol = RegExp(r'^(\d+)\. ').firstMatch(line);
        if (ol != null) {
          leading = '${ol.group(1)}. ';
          line = line.substring(ol.end);
        }
      }
      line = line.trimRight();

      final double sz = headingLevel == 1
          ? fontSize + 6
          : headingLevel == 2
              ? fontSize + 4
              : headingLevel == 3
                  ? fontSize + 2
                  : fontSize;
      final TextStyle base = TextStyle(
        fontSize: sz,
        height: 1.6,
        color: textColor,
        fontWeight: headingLevel > 0 ? FontWeight.bold : FontWeight.normal,
      );
      spans.add(TextSpan(style: base, children: [
        if (leading.isNotEmpty) TextSpan(text: leading),
        ..._inline(line, base),
      ]));
      spans.add(TextSpan(text: '\n'));
    }

    return Text.rich(
      TextSpan(children: spans),
    );
  }

  /// 行内解析：**加粗** 与 `代码` 交替扫描。
  List<InlineSpan> _inline(String s, TextStyle base) {
    final spans = <InlineSpan>[];
    var i = 0;
    while (i < s.length) {
      final bold = s.indexOf('**', i);
      final code = s.indexOf('`', i);
      int next;
      bool isBold;
      if (bold == -1 && code == -1) {
        spans.add(TextSpan(text: s.substring(i)));
        break;
      } else if (bold == -1) {
        next = code;
        isBold = false;
      } else if (code == -1) {
        next = bold;
        isBold = true;
      } else if (bold < code) {
        next = bold;
        isBold = true;
      } else {
        next = code;
        isBold = false;
      }
      if (next > i) spans.add(TextSpan(text: s.substring(i, next)));
      final close = s.indexOf(isBold ? '**' : '`', next + (isBold ? 2 : 1));
      if (close == -1) {
        spans.add(TextSpan(text: s.substring(next)));
        break;
      }
      final content = s.substring(next + (isBold ? 2 : 1), close);
      if (isBold) {
        spans.add(TextSpan(
          text: content,
          style: base.copyWith(fontWeight: FontWeight.bold),
        ));
        i = close + 2;
      } else {
        spans.add(TextSpan(
          text: content,
          style: base.copyWith(
            fontFamily: 'monospace',
            fontSize: (base.fontSize ?? 13) - 1,
            backgroundColor: base.color!.withOpacity(0.08),
          ),
        ));
        i = close + 1;
      }
    }
    return spans;
  }

  String _sanitize(String raw) {
    final result = raw
        .replaceAll('\u200B', '')
        .replaceAll('\u200C', '')
        .replaceAll('\u200D', '');
    final logger = DebugLogService.instance;
    final removed = raw.length - result.length;
    if (removed > 0) {
      logger.logSanitize(raw.length, result.length, removed);
    }
    return result;
  }
}
