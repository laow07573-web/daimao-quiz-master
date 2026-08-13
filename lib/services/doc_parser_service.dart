import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:xml/xml.dart';
import '../models/question.dart';

class DocParserService {

  /// 从 DOCX 文件中提取原始纯文本
  static Future<String> extractRawText(String filePath) async {
    return await Isolate.run(() => _extractRawTextSync(filePath));
  }

  static String _extractRawTextSync(String filePath) {
    try {
      final fileBytes = File(filePath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(fileBytes);
      ArchiveFile? docXml;
      for (final f in archive) {
        if (f.name == 'word/document.xml') {
          docXml = f;
          break;
        }
      }
      if (docXml == null) return '';
      final xmlContent = utf8.decode(docXml.content as List<int>);
      final document = XmlDocument.parse(xmlContent);
      final paragraphs = <String>[];
      for (final p in document.findAllElements('w:p')) {
        final texts = p.findAllElements('w:t');
        final line = texts.map((t) => t.innerText).join('').trim();
        if (line.isNotEmpty) paragraphs.add(line);
      }
      return paragraphs.join('\n');
    } catch (_) {
      return '';
    }
  }

  /// 检测文件格式：'docx' / 'doc' / 'unknown'
  static String detectFormat(String filePath) {
    try {
      final bytes = File(filePath).readAsBytesSync();
      if (bytes.length < 4) return 'unknown';
      if (bytes[0] == 0x50 && bytes[1] == 0x4B) return 'docx';
      if (bytes[0] == 0xD0 && bytes[1] == 0xCF) return 'doc';
      return 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  /// 在 Isolate 中解析单个文件（公开方法，供 AppState 使用）
  static Future<List<Question>> parseFileInIsolate(
      String filePath, int bankId) async {
    return await Isolate.run(() => _parseDocxFile(filePath, bankId));
  }

  /// 解析单个 DOCX 文件核心逻辑
  static List<Question> _parseDocxFile(String filePath, int bankId) {
    try {
      final fileBytes = File(filePath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(fileBytes);

      // 查找 document.xml
      ArchiveFile? docXml;
      for (final file in archive) {
        if (file.name == 'word/document.xml') {
          docXml = file;
          break;
        }
      }

      if (docXml == null) return [];

      final xmlContent = utf8.decode(docXml.content as List<int>);
      final document = XmlDocument.parse(xmlContent);

      // 提取所有段落文本
      final paragraphs = <String>[];
      final elements = document.findAllElements('w:p');
      for (final p in elements) {
        final texts = p.findAllElements('w:t');
        final line = texts.map((t) => t.innerText).join('');
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          paragraphs.add(trimmed);
        }
      }

      return _extractQuestions(paragraphs, bankId, filePath);
    } catch (e) {
      return [];
    }
  }

  /// 从段落文本中提取题目
  static List<Question> _extractQuestions(
      List<String> paragraphs, int bankId, String source) {
    final questions = <Question>[];
    final now = DateTime.now().toIso8601String();

    // 合并连续的非题目行
    final merged = <String>[];
    String? pendingText;

    for (final p in paragraphs) {
      final isQuestionStart = _isQuestionLine(p);
      if (isQuestionStart && pendingText != null) {
        merged.add(pendingText);
        pendingText = p;
      } else if (isQuestionStart) {
        if (pendingText != null) merged.add(pendingText);
        pendingText = p;
      } else if (pendingText != null) {
        pendingText += '\n$p';
      } else {
        merged.add(p);
      }
    }
    if (pendingText != null) merged.add(pendingText);

    // 将文本分组成题目块
    final blocks = _groupIntoBlocks(merged);

    for (final block in blocks) {
      final question = _parseQuestionBlock(block, bankId, source, now);
      if (question != null) {
        questions.add(question);
      }
    }

    return questions;
  }

  /// 判断是否是题目起始行
  static bool _isQuestionLine(String line) {
    // 匹配: "1.", "1、", "1)", "第1题", "1．"（全角点）等
    final patterns = [
      RegExp(r'^\s*\d+[\.、．\)）]\s*'),
      RegExp(r'^\s*第\s*\d+\s*题'),
      RegExp(r'^\s*[（\(]\s*\d+\s*[）\)]\s*'),
    ];
    for (final p in patterns) {
      if (p.hasMatch(line)) return true;
    }
    return false;
  }

  /// 将合并后的段落分组成题目块
  static List<List<String>> _groupIntoBlocks(List<String> lines) {
    // v1.0.2: 合并行拆回——前一步 merge 把题目+选项拼成了多行字符串，
    // 这里先拆回单行再分组，否则选项/答案会被整行吞掉（丢失根因）
    final expanded = <String>[];
    for (final l in lines) {
      expanded.addAll(l.split('\n'));
    }

    final blocks = <List<String>>[];
    List<String>? currentBlock;

    for (final line in expanded) {
      if (_isQuestionLine(line)) {
        if (currentBlock != null) {
          blocks.add(currentBlock);
        }
        currentBlock = [line];
      } else if (currentBlock != null) {
        currentBlock.add(line);
      } else {
        // 孤立的非题目行，跳过
        continue;
      }
    }

    if (currentBlock != null &&
        currentBlock.isNotEmpty &&
        _isQuestionLine(currentBlock.first)) {
      blocks.add(currentBlock);
    }

    // 如果没有任何题目块，尝试把整个文档作为一个块
    if (blocks.isEmpty && lines.isNotEmpty) {
      blocks.add(lines);
    }

    return blocks;
  }

  /// 解析单个题目块
  static Question? _parseQuestionBlock(
    List<String> block,
    int bankId,
    String source,
    String now,
  ) {
    if (block.isEmpty) return null;

    final allText = block.join('\n');
    final lines = block;

    // 提取标题：第一行去掉题号
    String title = lines.first.replaceAll(
        RegExp(r'^[\s]*[\d]+[\.、．\)）]\s*|^第\s*\d+\s*题[\s：:]*'), '');

    // 如果标题为空，使用下一行
    int titleEndIdx = 0;
    if (title.trim().isEmpty && lines.length > 1) {
      titleEndIdx = 1;
      title = lines[1];
    }

    // 提取选项（支持 A-Z 任意数量，兼容首个选项无前缀的格式）
    final options = <String>[];
    String? correctAnswer;
    String? analysis;

    bool seenLabeledOption = false;

    for (int i = titleEndIdx + 1; i < lines.length; i++) {
      final line = lines[i].trim();

      final optLabel = _detectOptionLabel(line);
      if (optLabel != null) {
        seenLabeledOption = true;
        // v1.0.2: 合并行拆回（"A.x B.y C.z" 一行多选项 → 拆成多个选项，
        // 修复选项/答案丢失根因）
        final merged = _splitMergedOptions(line);
        if (merged.length > 1) {
          // 每个拆出的片段去掉自己的标签前缀
          options.addAll(merged.map((m) {
            final label = _detectOptionLabel(m);
            return label != null ? _cleanOption(m, label) : m;
          }));
        } else {
          options.add(_cleanOption(line, optLabel));
        }
      } else if (_isAnswerLine(line)) {
        correctAnswer = _extractAnswer(line);
      } else if (_isAnalysisLine(line)) {
        analysis = line.replaceFirst(RegExp(r'^[解析：:]\s*'), '');
      } else if (!seenLabeledOption && options.isEmpty) {
        // 首个选项可能没有 A. 前缀，直接当作选项 A
        options.add(line);
      } else if (seenLabeledOption && options.isNotEmpty) {
        // 已有带标签选项的情况下，后续无标签短线可能是续行或新选项
        // 如果是短文本（不含句号），当作选项
        if (line.length < 80 && !line.contains('。') && !line.contains('；')) {
          options.add(line);
        } else if (correctAnswer == null && analysis == null) {
          analysis = (analysis ?? '') + '\n$line';
        }
      } else if (correctAnswer == null && analysis == null) {
        analysis = (analysis ?? '') + '\n$line';
      }
    }

    if (title.trim().isEmpty) return null;

    // 尝试从所有文本中提取答案
    if (correctAnswer == null) {
      correctAnswer = _tryExtractAnswerFromText(allText);
    }

    // 推测题型
    String questionType = 'single_choice';
    if (correctAnswer != null && correctAnswer.contains(',')) {
      questionType = 'multi_choice';
    } else if (options.isEmpty) {
      // 无选项：看答案判断是填空还是判断
      final ans = correctAnswer?.trim().toUpperCase() ?? '';
      if (RegExp(r'^(对|错|正确|错误|√|×|A|B)$').hasMatch(ans)) {
        questionType = 'true_false';
      } else {
        questionType = 'fill_blank';
      }
    }

    return Question(
      bankId: bankId,
      title: title.trim(),
      options: options,
      correctAnswer: correctAnswer?.trim().toUpperCase() ?? '',
      analysis: analysis?.trim(),
      questionType: questionType,
      source: source,
      createdAt: now,
    );
  }

  /// 检测行首是否为选项标签（A-Z），返回标签字母或 null
  static String? _detectOptionLabel(String line) {
    final match = RegExp(r'^\s*([A-Z])[\.、．\s]', caseSensitive: true).firstMatch(line);
    return match?.group(1);
  }

  static String _cleanOption(String line, String label) {
    return line.replaceFirst(RegExp('^\\s*${label}[\.、．\\s]*', caseSensitive: false), '');
  }

  /// 合并行拆回（v1.0.2）：一行包含多个 "X. " 选项时拆成多个选项
  static List<String> _splitMergedOptions(String line) {
    final matches =
        RegExp(r'[A-Z][\.、．]\s*').allMatches(line).toList();
    if (matches.length <= 1) return [line];
    final parts = <String>[];
    for (var i = 0; i < matches.length; i++) {
      final start = matches[i].start;
      final end = i + 1 < matches.length ? matches[i + 1].start : line.length;
      final part = line.substring(start, end).trim();
      if (part.isNotEmpty) parts.add(part);
    }
    return parts;
  }

  static bool _isAnswerLine(String line) {
    return RegExp(r'^[答案参考正确][答案案确]?[：:\s]*', caseSensitive: false)
        .hasMatch(line);
  }

  static String? _extractAnswer(String line) {
    // 匹配 A-Z（含分隔符，供多选归一；支持 E/F 等五选以上）或 对/错 或 √/×
    final match = RegExp(r'[答案参考正确][答案案确]?[：:\s]*([A-Za-z][A-Za-z、，,;；/\s]*)',
            caseSensitive: false)
        .firstMatch(line);
    if (match != null) {
      return _normalizeMultiAnswer(match.group(1)!);
    }
    // 尝试直接匹配字母
    final letterMatch =
        RegExp(r'([A-Za-z][A-Za-z、，,;；/\s]*)').firstMatch(line);
    if (letterMatch != null) {
      return _normalizeMultiAnswer(letterMatch.group(1)!);
    }
    // 判断题（先检查否定/错误类，避免 "不对" 被 "对" 误判）
    if (line.contains('不对') ||
        line.contains('不正确') ||
        line.contains('错误') ||
        line.contains('错') ||
        line.contains('×')) {
      return '错';
    }
    if (line.contains('正确') || line.contains('对') || line.contains('√')) {
      return '对';
    }
    // 填空题：提取 "答案：" 后的全部文本
    final textMatch = RegExp(r'[答案参考正确][答案案确]?[：:\s]+(.+)',
            caseSensitive: false)
        .firstMatch(line);
    if (textMatch != null) {
      final text = textMatch.group(1)!.trim();
      if (text.isNotEmpty && !RegExp(r'^[A-Za-z]+$').hasMatch(text)) {
        return text;
      }
    }
    return null;
  }

  static bool _isAnalysisLine(String line) {
    return line.startsWith('解析') ||
        line.startsWith('【解析】') ||
        line.startsWith('【答案】');
  }

  /// 多选答案归一（v1.0.2）：A、C / A, C / AC / A和C → A,C（支持 A-Z 五选以上）
  static String _normalizeMultiAnswer(String letters) {
    final normalized = letters
        .toUpperCase()
        .replaceAll(RegExp(r'[和及]'), ',')
        .replaceAll(RegExp(r'[、，,;；/\s]+'), '')
        .split('')
        .where((c) => RegExp(r'^[A-Z]$').hasMatch(c))
        .toSet()
        .toList()
      ..sort();
    if (normalized.length <= 1) return letters.toUpperCase().trim();
    return normalized.join(',');
  }

  /// 尝试从整段文本中提取答案
  static String? _tryExtractAnswerFromText(String text) {
    // 在全部文本中搜索"答案"关键词
    final patterns = [
      RegExp(r'答案[：:\s]*([A-Za-z][A-Za-z、，,;；/\s]*)', caseSensitive: false),
      RegExp(r'正确答案[：:\s]*([A-Za-z][A-Za-z、，,;；/\s]*)', caseSensitive: false),
      RegExp(r'参考[答案][：:\s]*([A-Za-z][A-Za-z、，,;；/\s]*)', caseSensitive: false),
      RegExp(r'正确[答案][：:\s]*([对错√×])', caseSensitive: false),
    ];

    for (final p in patterns) {
      final match = p.firstMatch(text);
      if (match != null) {
        final v = match.group(1)!;
        if (RegExp(r'^[对错√×]$').hasMatch(v)) return v;
        return _normalizeMultiAnswer(v);
      }
    }
    // 填空题：提取 "答案：" 后的全部文本
    final textMatch = RegExp(r'[答案参考正确][答案案确]?[：:\s]+(.+?)(?:\n|$|解析|【)',
            caseSensitive: false)
        .firstMatch(text);
    if (textMatch != null) {
      final t = textMatch.group(1)!.trim();
      if (t.isNotEmpty && !RegExp(r'^[A-Da-d]+$').hasMatch(t)) return t;
    }
    return null;
  }
}
