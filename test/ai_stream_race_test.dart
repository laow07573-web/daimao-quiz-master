import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flashcard_app/models/answer_record.dart';
import 'package:flashcard_app/models/app_settings.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/database_service.dart';

/// 流式输出 × 切题竞态：用户看着 AI 生成到一半就翻到下一题时，
/// 这段回答必须**完整落库**，而不是把半截当最终结果存下来。
///
/// 为什么单独一个文件：`ai_streaming_test.dart` 只覆盖 AIService 的 SSE 解析与
/// 降级分支（全部绕过缓存），`ai_stream_cache_test.dart` 只覆盖缓存三态。
/// AppState 层「切题后继续读完」的这处逻辑当时**零覆盖**——而它正是改造时特意
/// 从 `break` 改成 `continue` 的地方，回归了没有任何测试能发现。
void main() {
  late Directory tmp;

  setUp(() async {
    await DatabaseService.instance.close();
    tmp = Directory.systemTemp.createTempSync('mj_stream_race_');
    DatabaseService.overrideDbPath = '${tmp.path}/flashcard.db';
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 轮询等到 [cond] 成立——**不要用固定次数的 pump/delay**：
  /// 数据库在后台 isolate、流的分片要走真实事件循环，固定等待在慢 runner 上
  /// 会不够。这条不是理论风险：CI 上曾因此把「已收到第一段」误判成空串
  /// （同一个提交本地全绿、CI 红），根因就是这里等了固定 80ms。
  Future<void> waitFor(bool Function() cond, {required String what}) async {
    for (var i = 0; i < 300; i++) {
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (cond()) return;
    }
    fail('等不到$what（超过 6s）');
  }

  /// 造一道已入库、已加入错题本、已答错一次的题
  Future<int> seed(int n) async {
    final db = DatabaseService.instance;
    final bankId = await db.insertBank(QuestionBank(
        name: '题库$n', createdAt: DateTime.now().toIso8601String()));
    await db.insertQuestions([
      Question(
        bankId: bankId,
        title: '题目$n',
        options: const ['A', 'B'],
        correctAnswer: 'A',
        createdAt: DateTime.now().toIso8601String(),
      ),
    ]);
    final qid = (await db.getQuestionsByBank(bankId)).first.id!;
    await db.addToErrorBook(qid);
    await db.insertAnswerRecord(AnswerRecord(
        questionId: qid,
        userAnswer: 'B',
        isCorrect: false,
        answeredAt: DateTime.now().toIso8601String()));
    return qid;
  }

  test('切题后仍把完整回答落库，且不污染下一题的对话历史', () async {
    final gate = Completer<void>();
    String sse(String text) =>
        'data: ${jsonEncode({
              'choices': [
                {'delta': {'content': text}}
              ]
            })}\n\n';

    final client = MockClient.streaming((request, bodyStream) async {
      final body = await bodyStream.bytesToString();
      if (body.contains('"stream":true')) {
        return http.StreamedResponse(
          () async* {
            yield utf8.encode(sse('前半'));
            await gate.future; // 卡在中间：等测试切题后再放行后半段
            yield utf8.encode(sse('后半'));
            yield utf8.encode('data: [DONE]\n\n');
          }(),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }
      // 流式成功就不该回退；真回退了这里会给出可辨认的文本
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({
          'choices': [
            {'message': {'content': '不该回退'}}
          ]
        }))),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final appState = AppState(aiClient: client);
    await appState.init();
    await appState.updateSettings(
        AppSettings(apiKey: 'sk-test', model: 'test-model'));

    final q1 = await seed(1);
    await seed(2);
    // 预置解析：showAnalysis 命中缓存（不额外发网络），追问才有前置条件
    await DatabaseService.instance.cacheAnalysis(q1, '已保存的解析');

    await appState.startErrorReview(mode: 'all');
    expect(appState.quizQuestions.length, 2);
    await appState.showAnalysis();
    await waitFor(() => appState.currentAnalysis != null, what: '缓存里的解析');
    expect(appState.currentAnalysis, isNotNull,
        reason: '缓存里的解析要先就位，否则 sendFollowUp 会直接返回');

    final streamedQuestionId = appState.currentQuestion!.id!;
    final send = appState.sendFollowUp('为什么选 A？');
    await waitFor(() => appState.streamingReply.isNotEmpty, what: '第一段流式内容');
    expect(appState.streamingReply, '前半',
        reason: '流式进行中应能拿到半截内容（这正是「边生成边显示」）');

    // 用户中途切到下一题
    appState.nextQuestion();
    expect(appState.currentQuestion!.id, isNot(streamedQuestionId));

    gate.complete();
    await send;

    // 关键断言：落库的是完整回答，不是切题那一刻的半截
    final msgs =
        await DatabaseService.instance.getFollowUpMessages(streamedQuestionId);
    final assistant =
        msgs.where((m) => m['role'] == 'assistant').toList();
    expect(assistant.length, 1);
    expect(assistant.single['content'], '前半后半',
        reason: '切题时中断订阅会把「前半」当最终结果存下来');

    // 第二题的 UI 历史不能被上一题还在飞的流污染
    expect(appState.followUpHistory.where((m) => m.role == 'assistant'), isEmpty);
    expect(appState.streamingReply, '');
  });
}
