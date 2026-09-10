import '../services/theme_service.dart';
import 'package:flutter/material.dart';
import '../services/debug_log_service.dart';

/// AI 回复渲染器：轻量富文本解析（自研，不依赖第三方 Markdown 包）
/// 支持：**加粗**、`行内代码`、- 列表、1. 有序列表、#/##/### 标题、
/// Markdown 表格（| a | b | / |---|---|）。
/// v1.0.2 UI 审查修复：flutter_markdown 0.7.1 对「中文全角标点紧跟闭合
/// 星号」解析失败（**定性/计算**： 原样显示），改为自研 span 渲染器。
/// v1.0.2 用户反馈修复：补充 Markdown 表格块级渲染。
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
    final ac = AppThemeColors.of(context);
    final textColor = color ?? ac.textPrimary;
    final base = TextStyle(
      fontSize: fontSize,
      height: 1.6,
      color: textColor,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _parseBlocks(_sanitize(text)).map((b) => _buildBlock(b, base, ac)).toList(),
    );
  }

  // ======================== 块级解析 ========================

  List<_Block> _parseBlocks(String raw) {
    final blocks = <_Block>[];
    final lines = raw.split('\n');
    var i = 0;
    while (i < lines.length) {
      final t = lines[i].replaceFirst(RegExp(r'^\s+'), '');
      if (t.isEmpty) {
        i++;
        continue;
      }
      // 表格块：| ... | 行 + 下一行分隔行 |---|
      if (t.startsWith('|') && i + 1 < lines.length &&
          _isTableDivider(lines[i + 1].replaceFirst(RegExp(r'^\s+'), ''))) {
        final rows = <List<String>>[_splitTableRow(t)];
        i += 2;
        while (i < lines.length) {
          final l = lines[i].replaceFirst(RegExp(r'^\s+'), '');
          if (l.startsWith('|')) {
            rows.add(_splitTableRow(l));
            i++;
          } else {
            break;
          }
        }
        blocks.add(_TableBlock(rows));
        continue;
      }
      // 文本块：连续非表格行聚合
      final textLines = <_TextLine>[];
      while (i < lines.length) {
        final line = lines[i].replaceFirst(RegExp(r'^\s+'), '');
        if (line.startsWith('|') && i + 1 < lines.length &&
            _isTableDivider(lines[i + 1].replaceFirst(RegExp(r'^\s+'), ''))) {
          break; // 下一段是表格
        }
        if (line.isEmpty) {
          break; // 空行分段
        }
        textLines.add(_parseTextLine(line));
        i++;
      }
      if (textLines.isNotEmpty) blocks.add(_TextBlock(textLines));
    }
    return blocks;
  }

  _TextLine _parseTextLine(String line) {
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
    return _TextLine(leading, headingLevel, line.trimRight());
  }

  bool _isTableDivider(String line) {
    if (!line.startsWith('|') || line.length < 4) return false;
    // 去掉 |、空格、-、: 后应无其他字符
    final rest = line.replaceAll('|', '').replaceAll('-', '').replaceAll(':', '').trim();
    return rest.isEmpty;
  }

  List<String> _splitTableRow(String line) {
    return line
        .trim()
        .replaceAll(RegExp(r'^\|'), '')
        .replaceAll(RegExp(r'\|$'), '')
        .split('|')
        .map((c) => c.trim())
        .toList();
  }

  // ======================== 块级渲染 ========================

  Widget _buildBlock(_Block block, TextStyle base, AppThemeColors ac) {
    if (block is _TableBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Table(
          border: TableBorder.all(color: ac.border.withOpacity(0.6), width: 0.6),
          columnWidths: {
            for (var c = 0; c < block.rows.first.length; c++) c: const FlexColumnWidth(),
          },
          children: block.rows.take(30).toList().asMap().entries.map((e) {
            final isHead = e.key == 0;
            return TableRow(
              children: e.value.map((cell) {
                final cellBase = base.copyWith(
                  fontSize: fontSize - 1,
                  height: 1.4,
                  fontWeight: isHead ? FontWeight.bold : FontWeight.normal,
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Text.rich(TextSpan(
                    style: cellBase,
                    children: _inline(cell, cellBase),
                  )),
                );
              }).toList(),
            );
          }).toList(),
        ),
      );
    }

    final spans = <InlineSpan>[];
    for (final line in (block as _TextBlock).lines) {
      final L = line;
      final double sz = L.headingLevel == 1
          ? fontSize + 6
          : L.headingLevel == 2
              ? fontSize + 4
              : L.headingLevel == 3
                  ? fontSize + 2
                  : fontSize;
      final TextStyle ls = base.copyWith(
        fontSize: sz,
        fontWeight: L.headingLevel > 0 ? FontWeight.bold : null,
      );
      spans.add(TextSpan(style: ls, children: [
        if (L.leading.isNotEmpty) TextSpan(text: L.leading),
        ..._inline(L.content, ls),
      ]));
      spans.add(TextSpan(text: '\n'));
    }
    return Text.rich(TextSpan(children: spans));
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

// ======================== 块类型（库顶层） ========================

abstract class _Block {}

class _TextBlock extends _Block {
  final List<_TextLine> lines;
  _TextBlock(this.lines);
}

class _TextLine {
  final String leading;
  final int headingLevel;
  final String content;
  _TextLine(this.leading, this.headingLevel, this.content);
}

class _TableBlock extends _Block {
  final List<List<String>> rows;
  _TableBlock(this.rows);
}
