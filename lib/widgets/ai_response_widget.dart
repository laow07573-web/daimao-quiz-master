import '../services/theme_service.dart';
import 'package:flutter/material.dart';
import '../services/debug_log_service.dart';

/// AI 回复渲染器：轻量富文本解析（自研，不依赖第三方 Markdown 包）
/// 支持：**加粗**、`行内代码`、- 列表、1. 有序列表、#/##/### 标题、
/// Markdown 表格（| a | b | / |---|---|）。
/// v1.0.2 UI 审查修复：flutter_markdown 0.7.1 对「中文全角标点紧跟闭合
/// 星号」解析失败（**定性/计算**： 原样显示），改为自研 span 渲染器。
/// v1.0.2 用户反馈修复：补充 Markdown 表格块级渲染。
/// v1.28 用户反馈增强：
///  1. 结构色 —— 答案(绿)/题眼(蓝)/避坑指南(红+浅底)/一句话记忆(蓝+浅底)
///  2. 关键词标记 —— `==关键词==` 蓝、`!!关键词!!` 红（AI 按提示输出）
///  标记均容错：未闭合时按普通文本原样显示。
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
    // 结构标签：答案 / 题眼 / 解析 / 避坑指南 / 一句话记忆
    // 兼容 `**答案：** B`、`**答案：B**`、`答案：B` 三种写法
    final sec = RegExp(r'^\*{0,2}(答案|题眼|解析|避坑指南|一句话记忆)：\*{0,2}\s*')
        .firstMatch(line);
    if (sec != null) {
      final name = sec.group(1)!;
      final rest = line.substring(sec.end).replaceAll('**', '');
      return _TextLine('$name：', 0, rest.trimRight(), name);
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
                    children: _inline(cell, cellBase, ac),
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
      // v1.28：结构色 —— 按标签给整行上色/加底
      final sec = _sectionStyle(L.section, ac);
      final TextStyle ls = base.copyWith(
        fontSize: sz,
        fontWeight: L.headingLevel > 0 || sec.bold ? FontWeight.bold : null,
        color: sec.color ?? base.color,
        backgroundColor: sec.background,
      );
      spans.add(TextSpan(style: ls, children: [
        if (L.leading.isNotEmpty) TextSpan(text: L.leading),
        ..._inline(L.content, ls, ac),
      ]));
      spans.add(TextSpan(text: '\n'));
    }
    return Text.rich(TextSpan(children: spans));
  }

  /// 结构标签 → 颜色/字重/底色（v1.28）
  /// 答案=绿、题眼=蓝、避坑指南=红+浅红底、一句话记忆=蓝+浅蓝底
  _SectionStyle _sectionStyle(String? section, AppThemeColors ac) {
    switch (section) {
      case '答案':
        return _SectionStyle(color: ac.success, bold: true);
      case '题眼':
        return _SectionStyle(color: ac.accent, bold: true);
      case '解析':
        return const _SectionStyle(bold: true);
      case '避坑指南':
        return _SectionStyle(
            color: ac.danger, bold: true, background: ac.dangerSoft);
      case '一句话记忆':
        return _SectionStyle(
            color: ac.accent, bold: true, background: ac.accentSoft);
      default:
        return const _SectionStyle();
    }
  }

  /// 行内解析：**加粗**、`代码`、==蓝关键词==、!!红关键词!! 交替扫描。
  /// 任一标记未闭合时，剩余内容按普通文本原样输出（容错）。
  List<InlineSpan> _inline(String s, TextStyle base, AppThemeColors ac) {
    final spans = <InlineSpan>[];
    var i = 0;
    // 按优先级寻找最早的标记起点
    int? findNext(int from) {
      final cands = <int>[
        s.indexOf('**', from),
        s.indexOf('`', from),
        s.indexOf('==', from),
        s.indexOf('!!', from),
      ].where((p) => p != -1).toList();
      if (cands.isEmpty) return null;
      cands.sort();
      return cands.first;
    }

    while (i < s.length) {
      final next = findNext(i);
      if (next == null) {
        spans.add(TextSpan(text: s.substring(i)));
        break;
      }
      if (next > i) spans.add(TextSpan(text: s.substring(i, next)));

      final isBold = s.startsWith('**', next);
      final isCode = !isBold && s.startsWith('`', next);
      final isBlueKw = !isBold && !isCode && s.startsWith('==', next);
      // 其余为 !! 红关键词
      final markerLen = isCode ? 1 : 2;
      final closeMarker = isBold
          ? '**'
          : isCode
              ? '`'
              : isBlueKw
                  ? '=='
                  : '!!';
      final close = s.indexOf(closeMarker, next + markerLen);
      if (close == -1) {
        // 未闭合 → 原样输出剩余文本
        spans.add(TextSpan(text: s.substring(next)));
        break;
      }
      final content = s.substring(next + markerLen, close);
      if (isBold) {
        spans.add(TextSpan(
          text: content,
          style: base.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (isCode) {
        spans.add(TextSpan(
          text: content,
          style: base.copyWith(
            fontFamily: 'monospace',
            fontSize: (base.fontSize ?? 13) - 1,
            backgroundColor: base.color!.withOpacity(0.08),
          ),
        ));
      } else if (isBlueKw) {
        // ==关键词== → 强调蓝（保留外层底色，仅换字色+加粗）
        spans.add(TextSpan(
          text: content,
          style: base.copyWith(color: ac.accent, fontWeight: FontWeight.bold),
        ));
      } else {
        // !!关键词!! → 警示红
        spans.add(TextSpan(
          text: content,
          style: base.copyWith(color: ac.danger, fontWeight: FontWeight.bold),
        ));
      }
      i = close + closeMarker.length;
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

  /// 结构标签（答案/题眼/解析/避坑指南/一句话记忆），null 表示普通行
  final String? section;
  _TextLine(this.leading, this.headingLevel, this.content, [this.section]);
}

class _TableBlock extends _Block {
  final List<List<String>> rows;
  _TableBlock(this.rows);
}

/// 结构标签的样式描述（v1.28）
class _SectionStyle {
  final Color? color;
  final Color? background;
  final bool bold;
  const _SectionStyle({this.color, this.background, this.bold = false});
}
