import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/debug_log_service.dart';

/// AI 回复渲染器：透传文本 → 零宽空格转义 → Markdown 解析 → 富文本
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

    return MarkdownBody(
      data: _sanitize(text),
      selectable: false,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(fontSize: fontSize, color: textColor, height: 1.6),
        h1: TextStyle(fontSize: fontSize + 6, fontWeight: FontWeight.bold, color: textColor),
        h2: TextStyle(fontSize: fontSize + 4, fontWeight: FontWeight.bold, color: textColor),
        h3: TextStyle(fontSize: fontSize + 2, fontWeight: FontWeight.bold, color: textColor),
        strong: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: textColor),
        code: TextStyle(fontSize: fontSize - 1, color: textColor),
        listBullet: TextStyle(fontSize: fontSize, color: textColor),
        tableBody: TextStyle(fontSize: fontSize - 1, color: textColor),
        tableHead: TextStyle(fontSize: fontSize - 1, fontWeight: FontWeight.bold, color: textColor),
        tableBorder: TableBorder.all(color: textColor.withOpacity(0.2)),
      ),
    );
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
