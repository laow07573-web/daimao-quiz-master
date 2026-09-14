import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import '../models/question.dart';
import '../models/app_settings.dart';
import 'api_endpoint.dart';
import 'device_service.dart';
import '../utils/app_constants.dart';
import 'database_service.dart';
import 'debug_log_service.dart';

/// v1.0.2 设计审查修复：分块解析结果显性化。
/// 断网/401/超时/格式错误不再伪装成「解析完成，共 0 道题目」
class AIParseResult {
  final List<Question> questions;
  final int failedChunks;
  final List<String> errors; // 每个失败块一行原因（如「第 3 块：AI服务返回错误 (401)」）

  AIParseResult(this.questions, this.failedChunks, this.errors);
}

class AIService {
  final AppSettings _settings;
  final DatabaseService _db = DatabaseService.instance;

  /// HTTP 客户端。默认自建；**测试可注入**——流式分支要走 `send()` 拿
  /// `StreamedResponse`，用 `package:http/testing.dart` 的 `MockClient.streaming`
  /// 才能覆盖「服务商不支持流式」「非 200」这些兼容分支。
  final http.Client _client;

  // 余额与消耗追踪
  int _totalTokensUsed = 0;
  int get totalTokensUsed => _totalTokensUsed;
  double? _cachedBalance;
  DateTime? _balanceCacheTime;
  double? get cachedBalance => _cachedBalance;
  static const _balanceCacheDuration = Duration(minutes: 5);

  AIService(this._settings, {http.Client? client})
      : _client = client ?? http.Client();

  /// 使用 AI 从原始文本中批量解析题目。
  /// 返回 [AIParseResult]（成功题目 + 失败分块原因），调用方据此显性提示。
  /// v1.27 提速：题目边界感知切块（题干/答案不会被切断）+
  /// [parseConcurrency] 路并发（块间互不依赖，网络等待时间重叠）
  static const int parseConcurrency = 3;
  
  Future<AIParseResult> parseQuestionsFromRawText(
    String rawText,
    int bankId,
    void Function(int done, int total)? onProgress,
  ) async {
    // 题目边界感知切块：每块都是完整的题目集合，不会把题干与答案切开。
    // v1.27 截断修复：块上限 2000 字——此前 7000 字一块时输出 JSON 过长，
    // 撞模型 max_tokens 上限被截断，全块报「响应不是合法 JSON」（日志实证：
    // 失败块输出全部在 ~11000 字符≈ 8K token 处截断）。
    final chunks = splitTextIntoQuestionChunks(rawText);
    final allQuestions = <Question>[];
    final errors = <String>[];
    final now = DateTime.now().toIso8601String();
  
    // 并发受限的 worker 池：结果按块号收集（错误上报顺序稳定）
    final results =
        List<(List<Question>, String?)?>.filled(chunks.length, null);
    var next = 0;
    var done = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= chunks.length) return;
        final r = await _parseChunkWithAI(chunks[i], bankId, now);
        results[i] = r;
        done++;
        onProgress?.call(done, chunks.length);
      }
    }
  
    final workers = min(parseConcurrency, max(1, chunks.length));
    await Future.wait(List.generate(workers, (_) => worker()));
  
    for (var i = 0; i < chunks.length; i++) {
      final r = results[i];
      if (r == null) continue;
      allQuestions.addAll(r.$1);
      if (r.$2 != null) {
        // 内部降级标记不展示给用户。
        errors.add('第 ${i + 1} 块：${r.$2!.replaceAll(_tokenLimitMarker, '')}');
      }
    }
  
    onProgress?.call(chunks.length, chunks.length);
    return AIParseResult(allQuestions, errors.length, errors);
  }

  /// 题目起始行判定（与 DocParserService._isQuestionLine 同口径，
  /// 另兼容【第N题】等括号变体）：边界切块的唯一依据。
  /// 提升为静态公开：便于单测直接验证切块正确性。
  static final RegExp _questionStartPattern = RegExp(
      r'^\s*(?:\d+[\.、．\)）]|第\s*\d+\s*题|[（\(]\s*\d+\s*[）\)]|【\s*第?\s*\d+\s*题\s*】)');
  
  static bool _isQuestionStart(String line) =>
      _questionStartPattern.hasMatch(line);
  
  /// 题目边界感知切块（v1.27 提速 + 防切断）：
  /// 1. 按题目起始行把文本分成完整题目块（题干+选项+答案+解析永不拆散）；
  /// 2. 完整块贪心装箱到 [maxChars] 内，切点永远落在题目与题目之间；
  /// 3. 单个题目块超过 maxChars（大题/长解析）独占一块；
  /// 4. 首个题目之前的文档头（标题/大题说明）并入第一块，保留上下文；
  /// 5. 无任何题目起始行时退回旧的按段切块（兼容无题号文档）。
  @visibleForTesting
  static List<String> splitTextIntoQuestionChunks(String text,
      {int maxChars = 2000}) {
    final lines = text.split('\n');
  
    // 1. 按题目起始行分组为完整题目块；记录首题之前的文档头。
    final blocks = <String>[];
    final header = StringBuffer();
    final cur = StringBuffer();
    for (final line in lines) {
      if (_isQuestionStart(line)) {
        final s = cur.toString().trim();
        if (s.isNotEmpty) blocks.add(s);
        cur.clear();
        cur.writeln(line);
      } else if (cur.isEmpty) {
        header.writeln(line); // 首题之前：文档标题/大题说明等上下文。不单独成块。
      } else {
        cur.writeln(line);
      }
    }
    final tail = cur.toString().trim();
    if (tail.isNotEmpty) blocks.add(tail);
  
    // 无题目起始行：退回按段切块（旧行为，兼容无题号文档）
    if (blocks.isEmpty) {
      return _splitTextIntoChunks(text, maxChars: maxChars);
    }
  
    // 2. 完整块贪心装箱；单块超限也独占一块（不切碎）。
    final chunks = <String>[];
    var buf = '';
    var headerPending = header.toString().trim();
    for (final block in blocks) {
      var candidate = buf.isEmpty ? block : '$buf\n\n$block';
      // 文档头并入第一块（如「三、判断题」之类的大题说明是解析上下文）
      if (headerPending.isNotEmpty && chunks.isEmpty && buf.isEmpty) {
        candidate = '$headerPending\n\n$block';
      }
      if (candidate.length > maxChars && buf.isNotEmpty) {
        chunks.add(buf);
        buf = block;
      } else {
        buf = candidate;
        if (chunks.isEmpty) headerPending = ''; // 文档头已随第一块消耗。
      }
    }
    if (buf.trim().isNotEmpty) chunks.add(buf.trim());
    if (headerPending.isNotEmpty) chunks.insert(0, headerPending);
    return chunks;
  }
  
  /// 将文本按段落分块（无题号文档的退路；题目边界文档请用上面的边界切块）。
  /// v1.27 截断修复：上限同改 2000 字，防输出 JSON 撞模型输出上限被截断。
  static List<String> _splitTextIntoChunks(String text, {int maxChars = 2000}) {
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

  /// v1.27 输出上限逐级降级：不同模型/中转站的输出上限差异很大（
  /// DeepSeek 8K、OpenAI 系 16K、不少中转站只给 4096/2048）——请求带超过模型上限的
  /// max_tokens 会被接口直接 400 拒绝，换模型时逐档降级重试避免撞墙。
  static const List<int> _maxTokensFallbacks = [8192, 4096, 2048];
  
  /// 内部标记：错误属于「超过模型输出上限」（可自动降级重试，不展示给用户）。
  static const String _tokenLimitMarker = '|TOKEN_LIMIT';
  
  /// 用 AI 解析一个文本块中的题目（失败自动重试 1 次；
  /// 输出上限错误按 [​_maxTokensFallbacks] 逐级降级重试）。
  /// 返回 (题目列表, 失败原因)；失败原因非空表示该块解析失败。
  Future<(List<Question>, String?)> _parseChunkWithAI(
      String chunk, int bankId, String now) async {
    for (var i = 0; i < _maxTokensFallbacks.length; i++) {
      final mt = _maxTokensFallbacks[i];
      var result = await _parseChunkOnce(chunk, bankId, now, maxTokens: mt);
      if (result.$2 == null) return result;
      if (result.$2!.contains(_tokenLimitMarker) &&
          i < _maxTokensFallbacks.length - 1) {
        // v1.27：超过模型输出上限——自动降级重试（用户换模型/中转站也兼容）。
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }
      // 其余失败：沿用既有的一次重试（退避 1s）。
      await Future.delayed(const Duration(seconds: 1));
      return _parseChunkOnce(chunk, bankId, now, maxTokens: mt);
    }
    return (<Question>[], 'AI请求失败: 输出上限降级重试全部失败');
  }
  
  /// 判定错误响应是否为「超过模型输出上限」（max_tokens 超出模型支持）：
  /// 兼容 OpenAI 兼容接口常见错误文案，供降级重试判定（单测可直接调用）。
  @visibleForTesting
  static bool isTokenLimitError(String body) {
    final s = body.toLowerCase();
    return s.contains('max_tokens') ||
        (s.contains('maximum') && s.contains('token')) ||
        s.contains('too many tokens') ||
        (s.contains('exceed') && s.contains('token'));
  }

  /// 单次解析一个文本块。失败返回带原因的错误串，不再静默吞掉。
  /// [maxTokens]：本次请求的输出上限（超模型上限会被接口拒绝，
  /// 由调用方按降级序列重试）。
  Future<(List<Question>, String?)> _parseChunkOnce(
      String chunk, int bankId, String now,
      {int maxTokens = 8192}) async {
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
      "analysis": "如果原文有解析则提取，否则留空",
      "knowledge_point": "该题所属的教材章节级知识点，如'解剖学'"
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
8. knowledge_point 命名规范：统一用教材章节式命名（如"解剖学""生理学""病理学"），不要用自由短语或长句，控制在10字以内
9. 原文中的解析内容请保留到 analysis 字段。
10. 只返回 JSON，不要任何其他文字。
11. 控制输出长度：题干/选项/答案如实提取即可，不要添加原文没有的冗余描述

请直接返回 JSON：''';

    try {
      final response = await _client.post(
        ApiEndpoint.resolve(_settings.apiEndpoint),
        headers: await _headers(),
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
          // v1.27 截断修复：默认放宽到 8192；超模型上限时由降级序列重试。
          'max_tokens': maxTokens,
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
        if (content == null) return (<Question>[], 'AI 响应缺少内容');
        logger.log('PIPE:DECODE', 'contentLen=${content.length}  parsing questions...');
        _trackUsage(data);

        // 解析 JSON 响应（容忍 ```json 围栏等常见模型输出格式）；
        // v1.27 截断修复：输出撞 max_tokens 被截断时，抢修到最后一个完整题目对象，
        // 挽救前部完整部分，不再整块作废。
        Map<String, dynamic> parsed;
        try {
          parsed = _extractJson(content);
        } catch (e) {
          final repaired = repairTruncatedJson(content);
          if (repaired == null) {
            return (<Question>[], 'AI 解析生成失败：响应不是合法 JSON（$e）');
          }
          parsed = repaired;
          logger.log('PIPE:DECODE',
              '输出被截断已抢修：挽救前部完整题目（原错：$e）');
        }
        final questionsList = parsed['questions'] as List?;
        if (questionsList == null) {
          return (<Question>[], 'AI 解析生成失败：响应缺少 questions 字段');
        }

        final questions = questionsList.map((q) {
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
            knowledgePoint: _nullIfEmpty(q['knowledge_point']?.toString().trim()),
            createdAt: now,
          );
        }).toList();
        return (questions, null);
      } else {
        // v1.27：识别「输出上限」类错误（用户换模型/中转站上限低时出现），
        // 加内部标记供降级重试；其余错误如实上报。
        final bodyText = utf8.decode(response.bodyBytes, allowMalformed: true);
        final limitSuffix =
            isTokenLimitError(bodyText) ? _tokenLimitMarker : '';
        return (<Question>[], 'AI服务返回错误 (${response.statusCode})$limitSuffix');
      }
    } catch (e) {
      return (<Question>[], 'AI请求失败: $e');
    }
  }

  String? _nullIfEmpty(String? s) {
    if (s == null || s.isEmpty) return null;
    return s;
  }

  /// 解析模型返回的 JSON：剥离 ```json ... ``` 围栏与前后噪音再 decode。
  static Map<String, dynamic> _extractJson(String content) {
    return _extractJsonBody(_stripFence(content));
  }
  
  /// 剥 ```json ``` / ``` ``` 围栏
  static String _stripFence(String content) {
    var s = content.trim();
    final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$', caseSensitive: false);
    final fenceMatch = fence.firstMatch(s);
    if (fenceMatch != null) {
      s = fenceMatch.group(1)!.trim();
    }
    return s;
  }
  
  static Map<String, dynamic> _extractJsonBody(String s) {
    // 剥前后花括号外的散落文本。
    final first = s.indexOf('{');
    final last = s.lastIndexOf('}');
    if (first >= 0 && last > first) {
      s = s.substring(first, last + 1);
    }
    final decoded = jsonDecode(s);
    return decoded is Map<String, dynamic>
        ? decoded
        : (decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{});
  }
  
  /// v1.27 截断抢修：模型输出撞 max_tokens 被截断时，截到最后一个完整题目对象、
  /// 补上数组与外层对象的闭合，挽救前部完整部分（避免整块作废）。
  /// 结构约定：{"questions": [{...}, {...} ...——从后往前逐个 '}' 尝试闭合，
  /// 最多回溯 30 层；全部失败返回 null（调用方如实上报错误）。
  @visibleForTesting
  static Map<String, dynamic>? repairTruncatedJson(String content) {
    var s = _stripFence(content);
    final first = s.indexOf('{');
    if (first < 0) return null;
    s = s.substring(first);
  
    var end = s.length;
    for (var attempt = 0; attempt < 30; attempt++) {
      final idx = s.lastIndexOf('}', end - 1);
      if (idx <= 0) break;
      end = idx + 1;
      // 去掉切点后的尾随逗号/空白（截在题目对象后的 ',' 处时）
      var candidate = s.substring(0, end).replaceFirst(RegExp(r'[\s,]+$'), '');
      try {
        final decoded = jsonDecode('$candidate]}');
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FormatException {
        continue; // 可能截在不完整题目内部：回退到上一个 '}' 再试。
      }
    }
    return null;
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
    // 先查缓存。v1.0.2 设计审查修复：缓存读取失败降级直连 AI，
    // 不再让异常冒泡卡死 loading
    if (question.id != null) {
      try {
        final cached = await _db.getCachedAnalysis(question.id!);
        if (cached != null && cached.isNotEmpty) {
          return cached;
        }
      } catch (e) {
        DebugLogService.instance.log('AI', '解析缓存读取失败，直连 AI: $e');
      }
    }

    return _generateAndCacheAnalysis(question);
  }

  /// 生成解析并缓存（失败串不入缓存，下次点击可重新请求）
  Future<String> _generateAndCacheAnalysis(Question question) async {
    final analysis = await _callAIForAnalysis(question);
    if (question.id != null && analysis.isNotEmpty && !isAiError(analysis)) {
      await _db.cacheAnalysis(question.id!, analysis);
    }
    return analysis;
  }

  // ════════════════════════════════════════════════════════════
  // 流式输出（SSE）
  //
  // 动机：让用户看到 AI 正在生成，而不是对着转圈等十几秒。
  // 三条硬约束（决定了下面前两个方法为什么这么写）：
  //   1. **已保存的解析不流式**——命中 ai_cache 就整段给出，直接展示即可；
  //   2. **不因流式而功能退化**——任何一步失败都要回退到原有的一次性请求，
  //      用户的最终结果与改造前一致，只是少了「边生成边看」；
  //   3. **服务商不可信**——「任意 OpenAI 兼容接口」里有一部分不支持
  //      `stream:true`，或用非标准 SSE（无空格、\r\n、心跳注释、delta 非字符串），
  //      因此解析要宽容、失败要能降级。
  // ════════════════════════════════════════════════════════════

  /// 从一行 SSE 文本里取出增量内容；返回 null 表示这行不含内容
  /// （注释行 / 心跳 / `[DONE]` / 空 delta / 非 JSON）。
  ///
  /// 公开为 `@visibleForTesting`：SSE 的边角情况很多，用纯函数测最划算。
  @visibleForTesting
  static String? deltaFromSseLine(String line) {
    if (!line.startsWith('data:')) return null; // 还含 event:/id:/注释行
    final payload = line.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') return null;
    try {
      final data = jsonDecode(payload);
      if (data is! Map) return null;
      final choices = data['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final first = choices[0];
      if (first is! Map) return null;
      final delta = first['delta'];
      if (delta is! Map) return null;
      final content = delta['content'];
      // 类型保护：某些实现把 content 给成数组/对象
      return (content is String && content.isNotEmpty) ? content : null;
    } catch (_) {
      return null; // 半行或非 JSON 噪音
    }
  }

  /// 是否为 SSE 的结束标记（`data: [DONE]`）
  @visibleForTesting
  static bool isSseDoneLine(String line) =>
      line.startsWith('data:') && line.substring(5).trim() == '[DONE]';

  /// 从一行 SSE 里取 token 用量（流式默认不返回 usage，部分服务商会在末尾补上）。
  /// 取不到就返回 null，不影响主流程。
  @visibleForTesting
  static int? usageFromSseLine(String line) {
    if (!line.startsWith('data:')) return null;
    final payload = line.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') return null;
    try {
      final data = jsonDecode(payload);
      if (data is! Map) return null;
      final usage = data['usage'];
      if (usage is! Map) return null;
      final total = usage['total_tokens'];
      return total is int ? total : null;
    } catch (_) {
      return null;
    }
  }

  /// 从一次性响应体里取正文（兼容分支复用，与 [_callAI] 的取值口径一致）
  static String? _contentFromChatBody(String body) {
    try {
      final data = jsonDecode(body);
      if (data is! Map) return null;
      final choices = data['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final first = choices[0];
      if (first is! Map) return null;
      final message = first['message'];
      if (message is! Map) return null;
      final content = message['content'];
      return content is String ? content : null;
    } catch (_) {
      return null;
    }
  }

  /// 流式对话：产出**累计文本**（每次都给出到目前为止的全文），
  /// 调用方直接赋值即可，不必自己拼接。
  ///
  /// 任一步失败即抛异常，由 [streamAnalysis] / [streamFollowUp] 负责回退。
  Stream<String> _streamChat(String userPrompt) async* {
    final request = http.Request('POST', ApiEndpoint.resolve(_settings.apiEndpoint))
      ..headers.addAll(await _headers())
      ..headers['Accept'] = 'text/event-stream'
      ..body = jsonEncode({
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
        'stream': true,
      });

    // 30s 只覆盖「拿到响应头」；正文的停滞由下面流上的 60s 空闲超时兜底
    final response = await _client.send(request).timeout(const Duration(seconds: 30));
    final contentType = response.headers['content-type'] ?? '';

    // 兼容一：服务商忽略 stream:true，按老格式一次性返回整段 JSON。
    // 这不是错误——照原样给出内容即可，用户完全无感。
    if (response.statusCode == 200 && !contentType.contains('text/event-stream')) {
      final body = await response.stream.bytesToString();
      final content = _contentFromChatBody(body);
      if (content != null && content.isNotEmpty) {
        yield content;
        return;
      }
      throw Exception('AI流式响应格式无法识别');
    }

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      DebugLogService.instance
          .logRawResponse(_settings.apiEndpoint, response.statusCode, body.length);
      throw Exception('AI服务返回错误 (${response.statusCode})');
    }

    final buffer = StringBuffer();
    var received = false;
    // 总时长上限：只有「空闲超时」不够——网关若持续发心跳注释行（`: keep-alive`）
    // 却永不发 [DONE]、也不关连接，空闲计时会被不断重置，流永不结束，
    // 调用方的 loading 就永久卡住。改造前的一次性请求有 30s 硬超时，不会无限等。
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter()) // 自动处理 \n 与 \r\n
        .timeout(const Duration(seconds: 60)); // 流空闲超时

    await for (final line in lines) {
      if (DateTime.now().isAfter(deadline)) {
        throw Exception('AI流式响应超时');
      }
      if (isSseDoneLine(line)) break;
      // token 统计：流式默认不带 usage，但部分服务商会在末尾 chunk 里给出；
      // 有就记，没有就算了（不主动加 stream_options，避免严格网关直接 400）
      final usage = usageFromSseLine(line);
      if (usage != null) _totalTokensUsed += usage;
      final delta = deltaFromSseLine(line);
      if (delta == null) continue;
      received = true;
      buffer.write(delta);
      yield buffer.toString();
    }

    // 兼容二：流开了却一个内容字都没有（例如推理模型只给 reasoning_content，
    // 或网关把流吞了）→ 抛给上层回退一次性请求，而不是把空结果当成功
    if (!received) throw Exception('AI流式响应为空');
  }

  /// 单题讲解的流式版本。
  ///
  /// - 命中缓存：整段给出，**不流式**（已保存的内容没必要重新生成）
  /// - 流式失败：回退到一次性的 [getAnalysis] 路径，结果与改造前一致
  Stream<String> streamAnalysis(Question question) async* {
    if (question.id != null) {
      try {
        final cached = await _db.getCachedAnalysis(question.id!);
        if (cached != null && cached.isNotEmpty) {
          yield cached;
          return;
        }
      } catch (e) {
        DebugLogService.instance.log('AI', '解析缓存读取失败，直连 AI: $e');
      }
    }

    try {
      var last = '';
      await for (final acc in _streamChat(_analysisPrompt(question))) {
        last = acc;
        yield acc;
      }
      if (last.isEmpty || isAiError(last)) {
        yield await _generateAndCacheAnalysis(question);
        return;
      }
      // 写缓存**移出 try**：缓存写失败（磁盘满 / SQLITE_BUSY / 题行被删）不该
      // 被当成「流式失败」，否则会再发一次完整 AI 请求、并用新文本覆盖用户
      // 已经看完的解析（既多花钱又让内容前后不一致）。
      if (question.id != null) {
        try {
          await _db.cacheAnalysis(question.id!, last);
        } catch (e) {
          DebugLogService.instance.log('AI', '解析写缓存失败（不影响展示）: $e');
        }
      }
    } catch (e) {
      DebugLogService.instance.log('AI', '流式讲解失败，回退一次性请求: $e');
      yield await _generateAndCacheAnalysis(question);
    }
  }

  /// 追问的流式版本。追问没有缓存语义，失败同样回退一次性。
  Stream<String> streamFollowUp(
      Question question, String analysis, String followUpQuestion) async* {
    try {
      var last = '';
      await for (final acc
          in _streamChat(_followUpPrompt(question, analysis, followUpQuestion))) {
        last = acc;
        yield acc;
      }
      if (last.isEmpty || isAiError(last)) {
        yield await askFollowUp(question, analysis, followUpQuestion);
      }
    } catch (e) {
      DebugLogService.instance.log('AI', '流式追问失败，回退一次性请求: $e');
      yield await askFollowUp(question, analysis, followUpQuestion);
    }
  }

  /// 判断是否为 AI 失败/错误串（非真实解析内容）
  static bool isAiError(String s) {
    return s.startsWith('AI请求失败') ||
        s.startsWith('AI服务返回错误') ||
        s.startsWith('AI解析生成失败') ||
        s.startsWith('解析生成失败');
  }

  /// 追问功能：基于原题和解析进行追问（聊天式）
  ///
  /// v1.28：篇幅随「AI 解析详细程度」档位浮动；关键词标记沿用同一套约定符号；
  /// 渲染器已支持 Markdown 表格，故不再禁止表格，仅在需要对比/罗列时使用。
  Future<String> askFollowUp(Question question, String analysis,
          String followUpQuestion) async =>
      await _callAI(_followUpPrompt(question, analysis, followUpQuestion));

  /// 追问的提示词（同上：流式与一次性共用同一份）
  String _followUpPrompt(
      Question question, String analysis, String followUpQuestion) {
    final detail = _detailBlock;
    final marking = _markingBlock;

    return '''你是一个专业的答题解析助手，正在以聊天的方式回答学生的追问。

原题：${question.title}
${question.options.isNotEmpty ? '选项：\n${question.optionsWithLabels.join('\n')}' : ''}
正确答案：${question.correctAnswer}

之前的解析：$analysis

学生的追问：$followUpQuestion

请直接回答学生的疑问，不要复述题干，也不要重复之前已讲过的内容。
$detail$marking
# 输出格式
- 用 Markdown 输出，**默认用段落和列表**。
- 只有当「对比多项、罗列多条」时，才用 Markdown 表格（| 表头 | ... | + | --- | 分隔行）；其余情况不要用表格。
- 不要输出 JSON 或代码块包裹正文。''';
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

  // ======================== v1.0.2 对齐里程碑：AI 打标签 / 生成建议 ========================

  /// 为单道题打知识点标签（v1.0.2 对齐里程碑：教材章节分类助手）。
  /// 返回知识点名（≤10字）；失败时返回失败标记：
  /// 'AI请求失败' / 'AI服务返回错误' / 'AI解析生成失败'（与里程碑分组口径一致）
  Future<String> tagKnowledgePoint(Question question) async {
    final prompt = '''请判断下面这道题属于哪个教材章节级知识点。
按以下格式回复（直接说知识点名，不说题库名）：
1. 只输出一个章节级知识点名称（如"解剖学""生理学""病理学"）
2. 控制在10字以内，不要加引号、标点或解释
3. 若无法判断，输出"其他"

题目：${question.title}
${question.options.isNotEmpty ? '选项：\n${question.optionsWithLabels.join('\n')}' : ''}
正确答案：${question.correctAnswer}''';
    try {
      final response = await _client.post(
        ApiEndpoint.resolve(_settings.apiEndpoint),
        headers: await _headers(),
        body: jsonEncode({
          'model': _settings.model,
          'messages': [
            {
              'role': 'system',
              'content': '你是医学教材章节分类助手。请判断下面这道题属于哪个教材章节级知识点。'
            },
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.1,
          'max_tokens': 64,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final content =
            data['choices']?[0]?['message']?['content'] as String?;
        _trackUsage(data);
        final kp = _cleanTag(content ?? '');
        if (kp.isEmpty) return 'AI解析生成失败';
        return kp;
      }
      return 'AI服务返回错误 ($response.statusCode)';
    } catch (_) {
      return 'AI请求失败';
    }
  }

  /// 清洗打标签输出：去引号/标点/前后缀，截断到 20 字
  static String _cleanTag(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'^[【\[\(（]+'), '');
    s = s.replaceAll(RegExp(r'[】\]\)）]+$'), '');
    s = s.replaceAll(RegExp(r'[。，、；：\s]+$'), '');
    s = s.split('\n').first.trim();
    if (s.length > 20) s = s.substring(0, 20);
    return s.trim();
  }

  /// 基于错题知识点统计生成 AI 深度诊断（v1.0.2 对齐里程碑）。
  /// [statsText]：本地精炼后的统计文本（知识点 + 错题数 + 正确率）
  Future<String> generateKpAdvice(String statsText) async {
    if (statsText.trim().isEmpty) return '暂无错题数据，无法精炼。';
    final prompt = '''按优先级从高到低列出 1-3 个最需要复习的知识点，每个点用 **知识点名** 开头，附一句判断依据（如"正确率仅xx%、错题x道"）

基于以下统计：
$statsText

控制在180字，用 ## 分标题，**粗体**突出知识点名和关键数据。''';
    try {
      final response = await _client.post(
        ApiEndpoint.resolve(_settings.apiEndpoint),
        headers: await _headers(),
        body: jsonEncode({
          'model': _settings.model,
          'messages': [
            {
              'role': 'system',
              // v1.0.2 对齐里程碑：根据错题本的知识点分布数据精炼
              'content': '你是一个学习数据分析助手。根据错题本的知识点分布数据，精炼出最需要优先复习的知识点类型，并给出建议。'
            },
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.3,
          'max_tokens': 1024,
        }),
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final content =
            data['choices']?[0]?['message']?['content'] as String?;
        _trackUsage(data);
        return content ?? '解析生成失败，请检查网络或 API 配置后重试。';
      }
      return 'AI服务返回错误 (${response.statusCode})，请检查API配置。';
    } catch (_) {
      return 'AI请求失败';
    }
  }

  /// 篇幅要求：按「AI 解析详细程度」档位拼装（v1.28）
  String get _detailBlock => switch (_settings.analysisDetail) {
        AnalysisDetail.brief => '''
# 篇幅要求（重要）
- 全文控制在 150 字以内。
- 每个小点最多 2 句话，直接给结论，删掉所有铺垫与重复。
- 「排除法」只讲最容易混淆的 1~2 个干扰项，其余用"等"带过。
- 不要复述题干，不要写"综上所述"之类的套话。''',
        AnalysisDetail.standard => '''
# 篇幅要求
- 全文控制在 300 字以内。
- 每个小点 2~3 句话。
- 「排除法」讲主要干扰项即可。''',
        AnalysisDetail.detailed => '',
      };

  /// 关键词标记（可关闭）：让 AI 用约定符号标出决定答案的词，渲染器上色
  String get _markingBlock => _settings.keywordHighlight
      ? '''
# 关键词标记
在正文中用以下符号标出关键词（渲染器会加色显示，务必成对闭合）：
- `==关键词==` 标出「关键依据/决定答案的词」
- `!!关键词!!` 标出「易错陷阱/否定词」（如"最""不是""除外"）
每段最多标 2 处，只标词或短语（不超过 8 字），不要标整句，不要嵌套。'''
      : '';

  /// 核心 AI 调用方法
  Future<String> _callAIForAnalysis(Question question) async =>
      await _callAI(_analysisPrompt(question));

  /// 单题讲解的提示词。抽出来是因为流式与一次性两条路径必须用**完全相同**的
  /// 提示词——否则「流式失败回退一次性」会得到口径不一致的讲解。
  String _analysisPrompt(Question question) {
    final detail = _detailBlock;
    final marking = _markingBlock;

    return '''# 角色
你是一位擅长"题眼破题法"的医学考试辅导老师。你的讲解必须像临床带教老师讲病例一样，直击要害，不说废话。

# 题目
${question.title}
${question.options.isNotEmpty ? '选项：\n${question.optionsWithLabels.join('\n')}' : ''}
正确答案：${question.correctAnswer}
$detail
# 解题要求
请严格遵循以下四个步骤拆解这道题，语言务必口语化、逻辑化，杜绝教科书式的背诵列表。

## 第一步：抓题眼，定性
- **动作**：第一句话就点出题干中决定答案的关键数据或特征描述。
- **示例**："看到PaCO₂ 80，直接锁定是呼酸。"

## 第二步：理逻辑，拆选项
- **动作**：用核心病理生理机制，把正确选项的推理过程讲透，同时把错误选项"毙掉"。
- **要求**：不能只说"A不对"，要说"A为什么错"，尤其是那些因相同机制而被一起排除的选项。
- **要求**：涉及计算的，列出公式并代入数值，给出近似结果。

## 第三步：指坑点，防踩雷
- **动作**：精准指出这道题最容易掉进去的陷阱。

## 第四步：给结论，划重点
- **动作**：用一句顺口溜或一句大白话总结本题的得分要点，方便记忆。
$marking
# 输出格式
**答案：** [选项字母]
**题眼：** [一句话点明破题关键]
**解析：**
- **定性/计算**：[简明推理过程]
- **排除法**：[结合机制说明各干扰项错误原因]
**避坑指南：** [直接点出易错陷阱和鉴别点]
**一句话记忆：** [帮助快速记忆的口诀或类比]''';
  }

  Future<String> _callAI(String userPrompt) async {
    try {
      final response = await _client.post(
        ApiEndpoint.resolve(_settings.apiEndpoint),
        headers: await _headers(),
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
        return content ?? '解析生成失败，请检查网络或 API 配置后重试。';
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

  /// 查询 API 余额（元）：base 从可配置 apiEndpoint 推导（换供应商后余额接口跟随），
  /// 仅当主机为 deepseek.com 时请求其专用余额接口，其余主机按通用 /user/balance 尝试
  Future<double?> fetchBalance() async {
    if (_settings.apiKey.isEmpty) return null;
    if (_cachedBalance != null && _balanceCacheTime != null &&
        DateTime.now().difference(_balanceCacheTime!) < _balanceCacheDuration) {
      return _cachedBalance;
    }
    try {
      // 余额接口为 DeepSeek 专用；换供应商时按配置端点尝试，失败则返回 null
      final balanceUri = ApiEndpoint.balanceUrl(
          ApiEndpoint.resolve(_settings.apiEndpoint));
      final response = await _client.get(
        balanceUri,
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
    final avgPrice = (_totalTokensUsed / 1000000.0) * kAiCostPerQuestionYuan;
    if (avgPrice <= 0) return -1;
    return (balance / avgPrice).round();
  }

  /// 统一的请求头（v1.28）
  ///
  /// 除认证外注入供应商专用头：
  /// - opencode Zen/Go：`x-opencode-session`（必需，否则 400「cannot be
  ///   routed efficiently」）+ client/project 标识
  /// - OpenRouter：来源归因头
  /// - 统一自定义 User-Agent（部分网关拒绝通用 SDK UA）
  Future<Map<String, String>> _headers() async {
    final uri = ApiEndpoint.resolve(_settings.apiEndpoint);
    final sessionId = await DeviceService.instance.deviceId;
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${_settings.apiKey}',
      ...ApiEndpoint.vendorHeaders(uri, sessionId: sessionId),
    };
  }

  /// 拉取可用模型列表（OpenAI 兼容 `GET /models`）。
  ///
  /// 供设置页「选择模型」使用：免去用户手填模型名（第三方网关模型名
  /// 各不相同，填错会 400/422）。返回 (模型 id 列表, 错误说明)。
  Future<(List<String>, String?)> fetchModels() async {
    if (_settings.apiKey.trim().isEmpty) {
      return (<String>[], '请先填写 API Key');
    }
    final uri = ApiEndpoint.modelsUrl(_settings.apiEndpoint);
    try {
      final response = await _client.get(uri, headers: await _headers())
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        return (<String>[],
            ApiEndpoint.explainStatus(response.statusCode,
                utf8.decode(response.bodyBytes)));
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final list = (body is Map ? body['data'] : null) ??
          (body is Map ? body['models'] : null) ??
          (body is List ? body : null);
      if (list is! List) return (<String>[], '返回结构异常，无法解析模型列表');
      final ids = <String>[];
      for (final e in list) {
        final id = e is Map ? (e['id'] ?? e['name'] ?? e['model']) : e;
        if (id != null && id.toString().trim().isNotEmpty) {
          ids.add(id.toString().trim());
        }
      }
      ids.sort();
      if (ids.isEmpty) return (<String>[], '该接口未返回任何模型');
      return (ids, null);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('TimeoutException')) {
        return (<String>[], '拉取模型列表超时（20 秒）');
      }
      return (<String>[], '拉取失败：$msg');
    }
  }

  /// 连通性测试（设置页「测试连接」按钮）
  ///
  /// 发送一次极小的对话请求（1 token 上限），用真实往返验证：
  ///   端点归一化是否正确 → Key 是否有效 → 模型名是否可用。
  /// 返回 (ok, 人类可读说明)；说明里包含实际请求的端点，便于排查第三方兼容。
  Future<(bool, String)> testConnection() async {
    final raw = _settings.apiEndpoint.trim();
    if (_settings.apiKey.trim().isEmpty) {
      return (false, '请先填写 API Key');
    }
    final uri = ApiEndpoint.resolve(raw);
    final normalizedNote =
        uri.toString() == raw ? '' : '（地址已自动补全为 ${uri.toString()}）';
    try {
      final response = await _client.post(
        uri,
        headers: await _headers(),
        body: jsonEncode({
          'model': _settings.model.trim().isEmpty
              ? AppSettings.defaultModel
              : _settings.model.trim(),
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
          'max_tokens': 1,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final content = data['choices']?[0]?['message']?['content'];
        // 200 且结构正确 → 连通；内容为空也视为成功（部分供应商 max_tokens=1 无内容）
        if (data['choices'] != null || content != null) {
          return (true, '连接成功，模型 ${_settings.model} 可用$normalizedNote');
        }
        return (false, '返回结构异常，可能不是 OpenAI 兼容接口$normalizedNote');
      }
      return (false,
          '${ApiEndpoint.explainStatus(response.statusCode, utf8.decode(response.bodyBytes))}$normalizedNote');
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('TimeoutException')) {
        return (false, '连接超时（20 秒），请检查网络或地址$normalizedNote');
      }
      return (false, '连接失败：$msg$normalizedNote');
    }
  }

  void dispose() {
    _client.close();
  }
}
