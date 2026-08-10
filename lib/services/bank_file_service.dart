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

  /// 解析 JSON 文件 → 按组返回（组名 → 题目列表）
  /// 返回空 Map 表示解析失败（错误信息见 [lastError]）
  static String? lastError;

  static Future<Map<String, List<Question>>> parseJsonFile(String filePath) async {
    lastError = null;
    final file = File(filePath);
    if (!await file.exists()) {
      lastError = '文件不存在: $filePath';
      return {};
    }
    final String raw;
    try {
      raw = await file.readAsString();
    } catch (e) {
      lastError = '读取文件失败: $e';
      return {};
    }

    final dynamic data;
    try {
      data = jsonDecode(raw);
    } catch (e) {
      // v1.0.2 对齐里程碑：不是有效的 JSON 文件
      lastError = '不是有效的 JSON 文件: $e';
      return {};
    }

    final now = DateTime.now().toIso8601String();
    final groups = <String, List<Question>>{};

    if (data is List) {
      // 单题库：数组
      final questions = _parseQuestions(data, now);
      if (questions.isEmpty) {
        lastError = '文件中没有有效题目';
        return {};
      }
      final baseName = filePath.split(RegExp(r'[\\/]')).last
          .replaceAll(RegExp(r'\.json$', caseSensitive: false), '');
      groups[baseName] = questions;
    } else if (data is Map) {
      // v1.0.2 对齐里程碑：本软件导出的 .json（format 标记 + questions 数组）→ 单题库；
      // 有 questions 键但缺 format 标记 → 提示缺少 format 标记
      if (data.containsKey('questions')) {
        if (!data.containsKey('format')) {
          lastError = '不是呆猫刷题宝题库文件（缺少 format 标记）';
          return {};
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
        lastError = '文件中没有有效题目分组';
        return {};
      }
    } else {
      lastError = 'JSON 顶层应为数组或对象';
      return {};
    }
    return groups;
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
      options = rawOptions.map((e) => e.toString()).toList();
    } else if (rawOptions is String && rawOptions.trim().isNotEmpty) {
      // "A. xxx\nB. yyy" 或 "A.xxx B.yyy" 拆行
      options = rawOptions
          .split(RegExp(r'\n'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    // 带标签选项去标签
    if (options.isNotEmpty && RegExp(r'^[A-Z][\.、．]\s*').hasMatch(options.first)) {
      options = options
          .map((o) => o.replaceFirst(RegExp(r'^[A-Z][\.、．]\s*'), '').trim())
          .toList();
    }

    final correctAnswer =
        (_first(m, ['correct_answer', 'answer', 'correctAnswer', '答案']) ?? '')
            .toString()
            .trim()
            .toUpperCase()
        // 多选归一：A、C → A,C
        .replaceAll(RegExp(r'[、，,;；/\s]+'), ',');

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

  /// 导入 JSON 文件（分组建库）：返回 (成功组数, 导入题目数)
  static Future<(int, int)> importJsonFile(String filePath) async {
    final groups = await parseJsonFile(filePath);
    if (groups.isEmpty) return (0, 0);
    final now = DateTime.now().toIso8601String();
    var bankCount = 0;
    var questionCount = 0;
    for (final entry in groups.entries) {
      final bankId = await _db.insertBank(QuestionBank(
        name: entry.key,
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
    return (bankCount, questionCount);
  }

  /// 导出题库为 JSON 文件
  static Future<String?> exportBank(int bankId, String bankName, String destPath) async {
    final questions = await _db.getQuestionsByBank(bankId);
    final list = questions.map((q) => {
          'title': q.title,
          'options': q.options,
          'correct_answer': q.correctAnswer,
          'analysis': q.analysis,
          'question_type': q.questionType,
          'knowledge_point': q.knowledgePoint,
        }).toList();
    final file = File(destPath);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(list));
    return null;
  }
}
