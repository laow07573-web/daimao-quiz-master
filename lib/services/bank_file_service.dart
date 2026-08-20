import 'dart:convert';
import 'dart:io';
import '../models/question.dart';
import '../models/question_bank.dart';
import 'database_service.dart';

/// JSON 题库文件导入导出（v1.0.2）
///
/// 导入格式支持两种：
/// 1. 单题库：JSON 数组（题目列表）→ 建一个以文件名命名的题库
/// 2. 多题库分组：JSON 对象 { "题库名": [题目...], ... } → 分组建库
///
/// 题目字段（宽松兼容）：title/题干、options/选项（字符串数组或 "A. xxx" 带标签）、
/// correct_answer/answer/correctAnswer、analysis/解析、question_type/type、
/// knowledge_point/knowledgePoint/知识点
class BankFileService {
  static final DatabaseService _db = DatabaseService.instance;

  /// v1.0.2 改名「猫卷」：导出文件格式标记。
  /// 导入同时接受旧标记（daimao-flashcard-questions），旧版导出的题库文件仍可导入
  static const String formatMarker = 'maojuan-quiz-questions';
  static const String legacyFormatMarker = 'daimao-flashcard-questions';

  /// 解析 JSON 文件 → 返回 (组名 → 题目列表, 错误信息)。
  /// v1.0.2 设计审查修复：错误信息随返回值传递
  /// （此前用静态 lastError 全局变量，并发/重入会被覆盖）
  static Future<(Map<String, List<Question>>, String?)> parseJsonFile(
      String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return (<String, List<Question>>{}, '文件不存在: $filePath');
    }
    final String raw;
    try {
      raw = await file.readAsString();
    } catch (e) {
      return (<String, List<Question>>{}, '读取文件失败: $e');
    }

    final dynamic data;
    try {
      data = jsonDecode(raw);
    } catch (e) {
      // v1.0.2 对齐里程碑：不是有效的 JSON 文件
      return (<String, List<Question>>{}, '不是有效的 JSON 文件: $e');
    }

    final now = DateTime.now().toIso8601String();
    final groups = <String, List<Question>>{};

    if (data is List) {
      // 单题库：数组
      final questions = _parseQuestions(data, now);
      if (questions.isEmpty) {
        return (<String, List<Question>>{}, '文件中没有有效题目');
      }
      final baseName = filePath.split(RegExp(r'[\\/]')).last
          .replaceAll(RegExp(r'\.json$', caseSensitive: false), '');
      groups[baseName] = questions;
    } else if (data is Map) {
      // v1.0.2 对齐里程碑：本软件导出的 .json（format 标记 + questions 数组）→ 单题库；
      // 有 questions 键但缺 format 标记 → 提示缺少 format 标记
      if (data.containsKey('questions')) {
        final marker = data['format'];
        if (marker != formatMarker && marker != legacyFormatMarker) {
          return (<String, List<Question>>{}, '不是猫卷题库文件（缺少 format 标记）');
        }
        if (data['questions'] is List) {
          final questions = _parseQuestions(data['questions'] as List, now);
          if (questions.isNotEmpty) {
            groups[data['name']?.toString() ?? '错题导出'] = questions;
          }
        }
      }
      // 分组：{ 组名: [...] }
      if (groups.isEmpty) {
        for (final entry in data.entries) {
          if (entry.value is! List) continue;
          final questions = _parseQuestions(entry.value as List, now);
          if (questions.isEmpty) continue;
          groups['${entry.key}'] = questions;
        }
      }
      if (groups.isEmpty) {
        return (<String, List<Question>>{}, '文件中没有有效题目分组');
      }
    } else {
      return (<String, List<Question>>{}, 'JSON 顶层应为数组或对象');
    }
    return (groups, null);
  }

  static List<Question> _parseQuestions(List list, String now) {
    final questions = <Question>[];
    for (final item in list) {
      if (item is! Map) continue;
      final q = _parseQuestion(Map<String, dynamic>.from(item), now);
      if (q != null) questions.add(q);
    }
    return questions;
  }

  static Question? _parseQuestion(Map<String, dynamic> m, String now) {
    final title = _first(m, ['title', '题干', 'question']);
    if (title == null || (title as String).trim().isEmpty) return null;

    final rawOptions = m['options'] ?? m['选项'] ?? m['choices'];
    var options = <String>[];
    if (rawOptions is List) {
      options =
          rawOptions.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    } else if (rawOptions is String && rawOptions.trim().isNotEmpty) {
      // "A. xxx\nB. yyy" 或 "A.xxx B.yyy"（同行）拆段：在前缀 "X." 前断开
      options = rawOptions
          .split(RegExp(r'\n'))
          .expand((line) => line.split(RegExp(r'(?=[A-Z][\.、．]\s)')))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    // 逐项剥选项前缀（"A. xxx" → "xxx"；首个无前缀、后续带前缀的情况也处理）
    options = options
        .map((o) => o.replaceFirst(RegExp(r'^[A-Z][\.、．]\s*'), '').trim())
        .where((o) => o.isNotEmpty)
        .toList();

    var correctAnswer =
        (_first(m, ['correct_answer', 'answer', 'correctAnswer', '答案']) ?? '')
            .toString()
            .trim()
            .toUpperCase()
        // 多选归一：A、C → A,C
        .replaceAll(RegExp(r'[、，,;；/\s]+'), ',');
    // 连续字母串归一（外部导出的 "AC"）：仅当纯大写字母且长度>1 时拆为 A,C。
    // 中文/数字答案（填空、判断）不受影响
    if (RegExp(r'^[A-Z]{2,}$').hasMatch(correctAnswer)) {
      correctAnswer = correctAnswer.split('').join(',');
    }

    final typeRaw =
        (_first(m, ['question_type', 'type', '题型']) ?? '').toString().toLowerCase();
    String questionType = 'single_choice';
    if (typeRaw.contains('multi') || typeRaw.contains('多选')) {
      questionType = 'multi_choice';
    } else if (typeRaw.contains('true') || typeRaw.contains('判断')) {
      questionType = 'true_false';
    } else if (typeRaw.contains('fill') || typeRaw.contains('填空')) {
      questionType = 'fill_blank';
    } else if (typeRaw.contains('ming') || typeRaw.contains('名解')) {
      questionType = 'ming_jie';
    } else if (typeRaw.contains('jian') || typeRaw.contains('简答')) {
      questionType = 'jian_da';
    } else if (typeRaw.contains('jie') || typeRaw.contains('问答')) {
      questionType = 'jie_da';
    } else if (correctAnswer.contains(',')) {
      questionType = 'multi_choice';
    }

    final analysis = (_first(m, ['analysis', '解析']) ?? '').toString();
    final kp = (_first(m, ['knowledge_point', 'knowledgePoint', '知识点']) ?? '')
        .toString();

    return Question(
      bankId: 0, // 导入时由调用方设置
      title: title.toString().trim(),
      options: options,
      correctAnswer: correctAnswer,
      analysis: analysis.isEmpty ? null : analysis,
      questionType: questionType,
      knowledgePoint: kp.isEmpty ? null : kp,
      createdAt: now,
    );
  }

  static dynamic _first(Map m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k) && m[k] != null) return m[k];
    }
    return null;
  }

  /// 导入 JSON 文件（分组建库）：返回 (成功组数, 导入题目数, 错误信息, 改名组数)。
  /// [existingNames] 非空时同名组自动加后缀（防重复导入建重复题库）
  static Future<(int, int, String?, int)> importJsonFile(String filePath,
      {Set<String>? existingNames}) async {
    final (groups, err) = await parseJsonFile(filePath);
    if (groups.isEmpty) return (0, 0, err, 0);
    final now = DateTime.now().toIso8601String();
    final taken = existingNames ?? <String>{};
    var bankCount = 0;
    var questionCount = 0;
    var renamedCount = 0;
    for (final entry in groups.entries) {
      var name = entry.key;
      // v1.0.2 七项改进：同名自动改名（X(2)/X(3)...）
      if (taken.contains(name)) {
        var i = 2;
        while (taken.contains('$name($i)')) {
          i++;
        }
        name = '$name($i)';
        renamedCount++;
      }
      taken.add(name);
      final bankId = await _db.insertBank(QuestionBank(
        name: name,
        fileSource: 'json',
        createdAt: now,
      ));
      final questions = entry.value
          .map((q) => q.copyWith(bankId: bankId))
          .toList();
      await _db.insertQuestions(questions);
      await _db.updateBankQuestionCount(bankId, questions.length);
      bankCount++;
      questionCount += questions.length;
    }
    return (bankCount, questionCount, null, renamedCount);
  }

  /// 导出题库为 JSON 文件（v1.0.2 扩展：带 format 标记 + 题库名，
  /// 保留打标签后的 knowledge_point / analysis 等整理后字段，可被导入直接入库）。
  /// 返回文件路径；失败返回 null。
  static Future<String?> exportBank(int bankId, String bankName, String destPath) async {
    final questions = await _db.getQuestionsByBank(bankId);
    if (questions.isEmpty) return null;
    final list = questions.map((q) => {
          'title': q.title,
          'options': q.options,
          'correct_answer': q.correctAnswer,
          'analysis': q.analysis,
          'question_type': q.questionType,
          'knowledge_point': q.knowledgePoint,
        }).toList();
    final json = const JsonEncoder.withIndent('  ').convert({
      'format': formatMarker,
      'name': bankName,
      'count': list.length,
      'questions': list,
    });
    final file = File(destPath);
    await file.writeAsString(json);
    return file.path;
  }
}
