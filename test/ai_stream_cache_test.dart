import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flashcard_app/models/app_settings.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/services/ai_service.dart';
import 'package:flashcard_app/services/database_service.dart';

/// 流式输出的**产品硬约束与缓存行为**回归测试。
///
/// 为什么单独一个文件：`ai_streaming_test.dart` 覆盖的是 SSE 解析与降级分支，
/// 全部靠 `Question(id: null)` 绕过了缓存——也就是说**「已保存的解析不流式」
/// 这条产品第一约束当时并没有测试保护**（对抗审查指出）。这里用真实数据库补上，
/// 顺便锁住「流式成功后写缓存」「回退结果也写缓存」这两条容易在重构中被删掉的行为。
void main() {
  late Directory tmp;

  setUp(() async {
    await DatabaseService.instance.close();
    tmp = Directory.systemTemp.createTempSync('mj_stream_cache_');
    DatabaseService.overrideDbPath = '${tmp.path}/flashcard.db';
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  http.StreamedResponse sse(List<String> pieces) => http.StreamedResponse(
        Stream.value(utf8.encode([
          for (final p in pieces)
            'data: ${jsonEncode({
              'choices': [
                {'delta': {'content': p}}
              ]
            })}',
          '',
          'data: [DONE]',
          '',
        ].join('\n'))),
        200,
        headers: {'content-type': 'text/event-stream'},
      );

  http.StreamedResponse onceJson(Object body) => http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  /// 造一道**已入库**的题（有 id 才会走缓存分支），返回题目
  Future<Question> seedQuestion() async {
    final db = DatabaseService.instance;
    final now = DateTime.now().toIso8601String();
    final bankId =
        await db.insertBank(QuestionBank(name: '流式测试题库', createdAt: now));
    await db.insertQuestions([
      Question(
        bankId: bankId,
        title: '测试题',
        options: const ['A', 'B'],
        correctAnswer: 'A',
        createdAt: now,
      ),
    ]);
    final qs = await db.getQuestionsByBank(bankId);
    return qs.first;
  }

  group('streamAnalysis 的缓存语义', () {
    test('命中缓存 → 整段给出，且**完全不发网络请求**（产品硬约束）', () async {
      var requests = 0;
      final q = await seedQuestion();
      await DatabaseService.instance.cacheAnalysis(q.id!, '【已保存的解析】');

      final svc = AIService(
        AppSettings(apiKey: 'sk-test', model: 'm'),
        client: MockClient.streaming((req, body) async {
          requests++;
          return sse(['不应出现']);
        }),
      );

      final chunks = await svc.streamAnalysis(q).toList();

      expect(chunks, ['【已保存的解析】'], reason: '已保存的解析应原样给出');
      expect(requests, 0,
          reason: '命中缓存时不得发起任何网络请求——这正是「已保存不流式」的含义');
    });

    test('未命中缓存 → 走流式，且**成功后写入缓存**', () async {
      var requests = 0;
      final q = await seedQuestion();

      final svc = AIService(
        AppSettings(apiKey: 'sk-test', model: 'm'),
        client: MockClient.streaming((req, body) async {
          requests++;
          return sse(['第一段', '，第二段']);
        }),
      );

      final chunks = await svc.streamAnalysis(q).toList();

      expect(chunks, ['第一段', '第一段，第二段']);
      expect(requests, 1);
      expect(await DatabaseService.instance.getCachedAnalysis(q.id!),
          '第一段，第二段',
          reason: '流式结果应落缓存，下次点开就不再请求');
    });

    test('流式失败回退一次性时，回退结果同样入缓存', () async {
      var calls = 0;
      final q = await seedQuestion();

      final svc = AIService(
        AppSettings(apiKey: 'sk-test', model: 'm'),
        client: MockClient.streaming((req, body) async {
          calls++;
          final raw = await body.bytesToString();
          if (raw.contains('"stream":true')) {
            // 网关不支持流式
            return http.StreamedResponse(
                Stream.value(utf8.encode('gateway error')), 502);
          }
          return onceJson({
            'choices': [
              {'message': {'content': '回退生成的解析'}}
            ]
          });
        }),
      );

      final chunks = await svc.streamAnalysis(q).toList();

      expect(chunks.last, '回退生成的解析');
      expect(calls, 2, reason: '先试流式（失败），再回退一次性');
      expect(await DatabaseService.instance.getCachedAnalysis(q.id!),
          '回退生成的解析',
          reason: '回退结果也应入缓存，否则每次点开都要重新请求');
    });

    test('缓存写入失败不影响已经展示的解析（不该再发一次请求）', () async {
      var requests = 0;
      final q = await seedQuestion();

      final svc = AIService(
        AppSettings(apiKey: 'sk-test', model: 'm'),
        client: MockClient.streaming((req, body) async {
          requests++;
          return sse(['完整解析']);
        }),
      );

      // 让缓存写入失败：删掉题目行本身。ai_cache.question_id 有外键
      // （REFERENCES questions(id)）且 _onConfigure 开了 PRAGMA foreign_keys=ON，
      // 因此再往里写缓存会抛约束错误——正是这里要模拟的场景。
      final db = await DatabaseService.instance.database;
      await db.delete('questions', where: 'id = ?', whereArgs: [q.id]);

      final chunks = await svc.streamAnalysis(q).toList();

      expect(chunks, ['完整解析'], reason: '缓存写失败不能影响已生成的内容');
      expect(requests, 1,
          reason: '缓存写失败被误当成「流式失败」会导致再发一次请求并覆盖已展示文本');
    });
  });
}
