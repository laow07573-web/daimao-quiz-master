// AI 调用健壮性回归：空响应重试、402 终态人话、非法 JSON 干净报错。
// 背景：用户导入题库时第 4 块报「响应不是合法 JSON (Unexpected end of input
// at character 1)」——空内容一路走到 jsonDecode('') 炸出异常堆栈；随后实测
// 账户已 402 Insufficient Balance。这里把三类失败的可读性与重试行为钉死。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flashcard_app/models/app_settings.dart';
import 'package:flashcard_app/services/ai_service.dart';

void main() {
  AppSettings settings() => AppSettings.fromMap({
        'api_key': 'sk-test-key',
        'api_endpoint': 'https://api.deepseek.com/v1/chat/completions',
        'model': 'deepseek-chat',
      });

  http.Response chat(int status, {String? content, String? rawBody}) {
    if (rawBody != null) {
      return http.Response(rawBody, status,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }
    // charset=utf-8 不能省：package:http 对无 charset 的响应默认 latin1，
    // 响应体里的中文会直接炸在构造时（真实服务端都带 charset，应用侧走 bodyBytes）
    return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': content}
            }
          ],
          'usage': {'total_tokens': 10},
        }),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }

  test('402 余额不足：人话报错 + 终态不重试（1 次调用即止）', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return chat(402,
          rawBody:
              '{"error":{"message":"Insufficient Balance","type":"unknown_error"}}');
    });
    final res = await AIService(settings(), client: client)
        .parseQuestionsFromRawText('1．测试题干\nA．甲', 0, null);
    expect(res.errors.single, contains('账户余额不足'));
    expect(res.errors.single, contains('402'));
    expect(res.errors.single, isNot(contains('PERMANENT')), reason: '内部标记不出现在用户文案');
    expect(calls, 1, reason: '402 是终态错误，不该浪费重试');
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('空响应：重试 3 次后报「空响应」，绝不抛 FormatException 堆栈', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return chat(200, content: '');
    });
    final res = await AIService(settings(), client: client)
        .parseQuestionsFromRawText('1．测试题干\nA．甲', 0, null);
    expect(res.errors.single, contains('AI 返回了空响应'));
    expect(res.errors.single, isNot(contains('FormatException')));
    expect(calls, 3, reason: '瞬时空响应值得重试');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('只剩围栏的响应也算空响应', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return chat(200, content: '```json\n```');
    });
    final res = await AIService(settings(), client: client)
        .parseQuestionsFromRawText('1．测试题干\nA．甲', 0, null);
    expect(res.errors.single, contains('AI 返回了空响应'));
    expect(calls, greaterThanOrEqualTo(1));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('非法 JSON：报错收敛为人话（不带异常串）', () async {
    final client = MockClient((req) async => chat(200, content: '完全不是 JSON 也没有抢修点'));
    final res = await AIService(settings(), client: client)
        .parseQuestionsFromRawText('1．测试题干\nA．甲', 0, null);
    expect(res.errors.single, contains('响应不是合法 JSON'));
    expect(res.errors.single, isNot(contains('FormatException')));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('正常响应对照：题目照常解析', () async {
    final client = MockClient((req) async => chat(200,
        content: '{"questions":[{"title":"肽键是","options":["甲","乙"],'
            '"correct_answer":"A","question_type":"single_choice"}]}'));
    final res = await AIService(settings(), client: client)
        .parseQuestionsFromRawText('1．肽键是\nA．甲\nB．乙', 0, null);
    expect(res.questions, hasLength(1));
    expect(res.questions.single.title, '肽键是');
  });

  test('isAiError：带空格的「AI 解析生成失败」也要判为错误（漏判回归）', () {
    expect(AIService.isAiError('AI 解析生成失败：响应不是合法 JSON'), isTrue);
    expect(AIService.isAiError('AI返回了空响应（可能是限流或账户余额不足）'), isTrue);
    expect(AIService.isAiError('AI服务返回错误 (402)：账户余额不足'), isTrue);
    expect(AIService.isAiError('肽键是蛋白质的基本结构单位'), isFalse);
  });
}
