import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/question.dart';
import '../models/app_settings.dart';
import 'database_service.dart';
import 'debug_log_service.dart';

class AIService {
  final AppSettings _settings;
  final DatabaseService _db = DatabaseService.instance;
  final http.Client _client = http.Client();

  // 余额与消耗追踪
  int _totalTokensUsed = 0;
  int get totalTokensUsed => _totalTokensUsed;
  double? _cachedBalance;
  DateTime? _balanceCacheTime;
  double? get cachedBalance => _cachedBalance;
  static const _balanceCacheDuration = Duration(minutes: 5);

  AIService(this._settings);

  /// 使用 AI 从原始文本中批量解析题目
  /// 返回结构化的 Question 列表
  Future<List<Question>> parseQuestionsFromRawText(
    String rawText,
    int bankId,
    void Function(int done, int total) onProgress,
  ) async {
    // 将文本按段落分块，每块控制在合理大小
    final chunks = _splitTextIntoChunks(rawText, maxChars: 3000);
    final allQuestions = <Question>[];
    final now = DateTime.now().toIso8601String();

    for (int i = 0; i < chunks.length; i++) {
      onProgress(i, chunks.length);
      final questions = await _parseChunkWithAI(chunks[i], bankId, now);
      allQuestions.addAll(questions);
    }

    onProgress(chunks.length, chunks.length);
    return allQuestions;
  }

  /// 将文本按大小分块
  List<String> _splitTextIntoChunks(String text, {int maxChars = 3000}) {
    final chunks = <String>[];
    final paragraphs = text.split('\n');
    var current = '';

    for (final p in paragraphs) {
      if (current.length + p.length > maxChars && current.isNotEmpty) {
        chunks.add(current.trim());
        current = p;
      } else {
        current += '\n$p';
      }
    }
    if (current.trim().isNotEmpty) {
      chunks.add(current.trim());
    }
    return chunks;
  }

  /// 用 AI 解析一个文本块中的题目
  Future<List<Question>> _parseChunkWithAI(
    String chunk, int bankId, String now) async {
    final prompt = '''你是一个专业的题目解析器。请从以下文本中提取所有题目，返回严格的 JSON 格式。

文本内容：
$chunk

每道题返回以下 JSON 结构：
{
  "questions": [
    {
      "title": "题目题干（去除题号）",
      "options": ["选项A内容", "选项B内容", ...],
      "correct_answer": "A/B/C/D/对/错/填空答案",
      "question_type": "single_choice/multi_choice/true_false/fill_blank/ming_jie/jian_da/jie_da",
      "analysis": "如果原文有解析则提取，否则留空"
    }
  ]
}

规则：
1. 单选题：question_type="single_choice"，options 至少2个，correct_answer 如 "A"
2. 多选题：question_type="multi_choice"，correct_answer 用逗号分隔如 "A,C"
3. 判断题：question_type="true_false"，options 为空 []，correct_answer 为 "对" 或 "错"
4. 填空题：question_type="fill_blank"，options 为空 []，correct_answer 为正确答案文本（多空用中文分号；分隔）
5. 名词解释：question_type="ming_jie"，options 为空 []，correct_answer 为完整释义段落
6. 简答题：question_type="jian_da"，options 为空 []，correct_answer 为参考答案段落
7. 问答题：question_type="jie_da"，options 为空 []，correct_answer 为参考答案段落
5. 原文中的解析内容请保留到 analysis 字段
6. 只返回 JSON，不要任何其他文字

请直接返回 JSON：''';

    try {
      final response = await _client.post(
        Uri.parse(_settings.apiEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_settings.apiKey}',
        },
        body: jsonEncode({
          'model': _settings.model,
          'messages': [
            {
              'role': 'system',
              'content': '你是一个精确的 JSON 格式题目解析器。只返回合法 JSON，不返回任何其他内容。'
            },
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.1,
          'max_tokens': 4096,
          'response_format': {'type': 'json_object'},
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final logger = DebugLogService.instance;
        final rawBytes = response.bodyBytes;
        logger.logRawResponse(_settings.apiEndpoint, response.statusCode, rawBytes.length);
        final decoded = utf8.decode(rawBytes);
        logger.logUtf8Decode(rawBytes.length, decoded.length, decoded);
        final data = jsonDecode(decoded);
        final content = data['choices']?[0]?['message']?['content'] as String?;
        if (content == null) return [];
        logger.log('PIPE:DECODE', 'contentLen=${content.length}  parsing questions...');
        _trackUsage(data);

        // 解析 JSON 响应
        final parsed = jsonDecode(content);
        final questionsList = parsed['questions'] as List?;
        if (questionsList == null) return [];

        return questionsList.map((q) {
          final opts = (q['options'] as List?)
                  ?.map((o) => o.toString().trim())
                  .where((o) => o.isNotEmpty)
                  .toList() ??
              [];
          return Question(
            bankId: bankId,
            title: (q['title'] ?? '').toString().trim(),
            options: opts,
            correctAnswer: (q['correct_answer'] ?? '').toString().trim().toUpperCase(),
            analysis: _nullIfEmpty(q['analysis']?.toString().trim()),
            questionType: _detectType(q),
            createdAt: now,
          );
        }).toList();
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  String? _nullIfEmpty(String? s) {
    if (s == null || s.isEmpty) return null;
    return s;
  }

  String _detectType(Map q) {
    // 优先使用 AI 返回的 question_type
    final aiType = q['question_type']?.toString() ?? '';
    if (aiType == 'ming_jie' || aiType == 'jian_da' || aiType == 'jie_da') {
      return aiType;
    }
    final answer = (q['correct_answer'] ?? '').toString();
    if (answer.contains(',') && answer.length > 1) return 'multi_choice';
    if (answer == '对' || answer == '错') return 'true_false';
    final opts = q['options'];
    return (opts is List && opts.isNotEmpty) ? 'single_choice' : 'fill_blank';
  }

  /// 获取题目解析（优先使用缓存）
  Future<String> getAnalysis(Question question) async {
    // 先查缓存
    if (question.id != null) {
      final cached = await _db.getCachedAnalysis(question.id!);
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
    }

    // 调用 AI 生成解析
    final analysis = await _callAIForAnalysis(question);

    // 缓存结果
    if (question.id != null && analysis.isNotEmpty) {
      await _db.cacheAnalysis(question.id!, analysis);
    }

    return analysis;
  }

  /// 追问功能：基于原题和解析进行追问
  Future<String> askFollowUp(Question question, String analysis,
      String followUpQuestion) async {
    final prompt = '''你是一个专业的答题解析助手。

原题：${question.title}
选项：
${question.optionsWithLabels.join('\n')}
正确答案：${question.correctAnswer}

之前的解析：$analysis

学生的追问：$followUpQuestion

请针对学生的追问进行详细解答。

禁止使用任何表格。不要输出 | - JSON 等表格相关符号。只输出纯文本段落。''';

    return await _callAI(prompt);
  }

  /// 生成薄弱点分析
  Future<String> generateWeaknessAnalysis(
      List<Map<String, dynamic>> bankStats, double overallAccuracy) async {
    if (bankStats.isEmpty) return '暂无刷题记录，无法生成薄弱点分析。';

    final statsText = bankStats.map((s) {
      final total = s['total'];
      final correct = s['correct'];
      final acc =
          total > 0 ? ((correct / total) * 100).toStringAsFixed(1) : '0';
      return '共$total题，正确$correct题，正确率${acc}%';
    }).join('；');

    final prompt = '''你是一个学习数据分析助手。根据数据诊断薄弱方向，给出具体建议。

整体正确率：${overallAccuracy.toStringAsFixed(1)}%
各科目数据：$statsText

按以下格式回复（不提及题库名称，只说薄弱方向）：

## 🎯 薄弱诊断
根据正确率数据，指出需要加强的方向，如"**基础概念**部分薄弱，正确率仅xx%"、"**案例分析**能力不足"等

## 📋 改进方向
2-3条具体可操作的学习建议（不说题库名，说方向）

## 💪 鼓励
1句话鼓励

控制在150字，用 ## 分标题，**粗体**突出关键数据。''';

    return await _callAI(prompt);
  }

  /// 生成刷题小结
  Future<String> generateSessionSummary(
      int total, int correct, int wrong, int durationSeconds) async {
    final accuracy = total > 0 ? ((correct / total) * 100).toStringAsFixed(1) : '0';
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;

    final prompt = '''你是一个学习助手。为以下刷题结果生成小结：

题量：$total 题 | 正确：$correct | 错误：$wrong | 正确率：${accuracy}% | 用时：${minutes}分${seconds}秒

用下面格式回复（带emoji）：

## 📊 本次表现
一句话总结

## ⚠️ 注意
1条改进建议

控制在80字以内。''';

    return await _callAI(prompt);
  }

  /// 核心 AI 调用方法
  Future<String> _callAIForAnalysis(Question question) async {
    final prompt = '''# 角色
你是一位擅长"题眼破题法"的医学考试辅导老师。你的讲解必须像临床带教老师讲病例一样，直击要害，不说废话。

# 题目
${question.title}
${question.options.isNotEmpty ? '选项：\n${question.optionsWithLabels.join('\n')}' : ''}
正确答案：${question.correctAnswer}

# 解题要求
请严格遵循以下四个步骤拆解这道题，语言务必口语化、逻辑化，杜绝教科书式的背诵列表。

## 第一步：抓题眼，定性
- **动作**：第一句话就点出题干中决定答案的关键数据或特征描述。
- **示例**："看到PaCO₂ 80，直接锁定是呼酸。"
- **示例**："题干出现'支原体'，马上想到它没有细胞壁。"

## 第二步：理逻辑，拆选项
- **动作**：用核心病理生理机制，把正确选项的推理过程讲透，同时把错误选项"毙掉"。
- **要求**：不能只说"A不对"，要说"A为什么错"，尤其是那些因相同机制而被一起排除的选项。
- **要求**：涉及计算的，列出公式并代入数值，给出近似结果。

## 第三步：指坑点，防踩雷
- **动作**：精准指出这道题最容易掉进去的陷阱。
- **示例**："HCO₃⁻ 36看起来高，但这是代偿性升高，不是合并了代碱，千万别被带偏。"

## 第四步：给结论，划重点
- **动作**：用一句顺口溜或一句大白话总结本题的得分要点，方便记忆。

# 输出格式
**答案：** [选项字母]
**题眼：** [一句话点明破题关键]
**解析：**
- **定性/计算**：[简明推理过程]
- **排除法**：[结合机制说明各干扰项错误原因]
**避坑指南：** [直接点出易错陷阱和鉴别点]
**一句话记忆：** [帮助快速记忆的口诀或类比]''';

    return await _callAI(prompt);
  }

  Future<String> _callAI(String userPrompt) async {
    try {
      final response = await _client.post(
        Uri.parse(_settings.apiEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_settings.apiKey}',
        },
        body: jsonEncode({
          'model': _settings.model,
          'messages': [
            {
              'role': 'system',
              'content': '你是一个专业的学习辅导助手，擅长解析题目、分析学习薄弱点，并提供针对性建议。'
            },
            {'role': 'user', 'content': userPrompt},
          ],
          'temperature': 0.3,
          'max_tokens': 4096,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final logger = DebugLogService.instance;
        final rawBytes = response.bodyBytes;
        logger.logRawResponse(_settings.apiEndpoint, response.statusCode, rawBytes.length);
        final decoded = utf8.decode(rawBytes);
        logger.logUtf8Decode(rawBytes.length, decoded.length, decoded);
        final data = jsonDecode(decoded);
        final content = data['choices']?[0]?['message']?['content'] as String?;
        logger.log('PIPE:DECODE', 'contentLen=${content?.length ?? 0}  hasChoices=${data['choices'] != null}');
        _trackUsage(data);
        return content ?? 'AI解析生成失败，请稍后重试。';
      } else {
        return 'AI服务返回错误 (${response.statusCode})，请检查API配置。';
      }
    } catch (e) {
      return 'AI请求失败: ${e.toString()}';
    }
  }

  void _trackUsage(Map<String, dynamic> data) {
    final usage = data['usage'];
    if (usage != null) {
      _totalTokensUsed += (usage['total_tokens'] as int?) ?? 0;
    }
  }

  /// 查询 DeepSeek API 余额（元）
  Future<double?> fetchBalance() async {
    if (_settings.apiKey.isEmpty) return null;
    if (_cachedBalance != null && _balanceCacheTime != null &&
        DateTime.now().difference(_balanceCacheTime!) < _balanceCacheDuration) {
      return _cachedBalance;
    }
    try {
      final response = await _client.get(
        Uri.parse('https://api.deepseek.com/user/balance'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${_settings.apiKey}',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final infos = data['balance_infos'] as List?;
        if (infos != null && infos.isNotEmpty) {
          final total = double.tryParse(infos[0]['total_balance']?.toString() ?? '') ?? 0;
          _cachedBalance = total;
          _balanceCacheTime = DateTime.now();
          return total;
        }
      }
    } catch (_) {}
    return _cachedBalance;
  }

  /// 估算剩余可刷题数
  int getEstimatedRemainingQuestions() {
    final balance = _cachedBalance;
    if (balance == null || _totalTokensUsed == 0) return -1;
    final avgPrice = (_totalTokensUsed / 1000000.0) * 0.002; // ~0.002元/题
    if (avgPrice <= 0) return -1;
    return (balance / avgPrice).round();
  }

  void dispose() {
    _client.close();
  }
}
