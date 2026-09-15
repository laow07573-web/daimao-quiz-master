import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:flashcard_app/models/answer_record.dart';
import 'package:flashcard_app/models/app_settings.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/screens/error_book_screen.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/database_service.dart';

/// 「薄弱知识点建议」弹窗必须渲染富文本，不能把 markdown 源码直接摊给用户。
///
/// 这条是用户真机截图反馈的：弹窗里显示的是
/// `## 最优先复习知识点`、`**病理学**: 错题**53道**` —— 而 `generateKpAdvice`
/// 的提示词恰恰就是让 AI「用 ## 分标题、**粗体** 突出知识点名和关键数据」，
/// 也就是说 AI 是按要求输出的，是弹窗漏用了富文本渲染器（AiResponseWidget）。
void main() {
  late Directory tmp;

  setUp(() async {
    await DatabaseService.instance.close();
    tmp = Directory.systemTemp.createTempSync('mj_advice_');
    DatabaseService.overrideDbPath = '${tmp.path}/flashcard.db';
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// AI 返回的建议（模拟真实输出：## 标题 + **加粗** 知识点与数据）
  const advice = '## 最优先复习知识点\n'
      '\n'
      '**病理学**：错题 **53 道**（无正确率记录），错题量居首。\n'
      '\n'
      '**内科学**：错题 **52 道**，与病理学并列高频。';

  Future<void> seedErrorQuestion(String title, String kp) async {
    final db = DatabaseService.instance;
    final bankId = await db.insertBank(QuestionBank(
        name: '题库_$title', createdAt: DateTime.now().toIso8601String()));
    await db.insertQuestions([
      Question(
        bankId: bankId,
        title: title,
        options: const ['A项', 'B项'],
        correctAnswer: 'B',
        knowledgePoint: kp,
        createdAt: DateTime.now().toIso8601String(),
      ),
    ]);
    final qid = (await db.getQuestionsByBank(bankId)).first.id!;
    await db.addToErrorBook(qid);
    await db.insertAnswerRecord(AnswerRecord(
        questionId: qid,
        userAnswer: 'A',
        isCorrect: false,
        answeredAt: DateTime.now().toIso8601String()));
  }

  Future<void> settleUntil(WidgetTester tester, Finder target,
      {String? what}) async {
    for (var i = 0; i < 150; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 10));
      if (target.evaluate().isNotEmpty) return;
    }
    fail('等不到${what ?? '目标控件'}渲染');
  }

  testWidgets('建议弹窗渲染富文本：不出现 ## / ** 源码，标题与加粗都生效', (tester) async {
    final client = MockClient((request) async => http.Response.bytes(
          utf8.encode(jsonEncode({
            'choices': [
              {
                'message': {'content': advice}
              }
            ],
            'usage': {'total_tokens': 42},
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ));

    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late AppState appState;
    await tester.runAsync(() async {
      await seedErrorQuestion('病理题', '病理学');
      await seedErrorQuestion('内科题', '内科学');
      appState = AppState(aiClient: client);
      await appState.init();
      await appState.updateSettings(
          AppSettings(apiKey: 'sk-test', model: 'test-model'));
    });

    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const MaterialApp(home: ErrorBookScreen()),
    ));
    final adviceButton = find.text('生成建议');
    await settleUntil(tester, adviceButton, what: '生成建议按钮');

    await tester.tap(adviceButton);
    await settleUntil(tester, find.text('薄弱知识点建议'), what: '建议弹窗');

    // 断言 1：markdown 源码标记不能出现在界面上
    expect(find.textContaining('##'), findsNothing,
        reason: '「## 最优先复习知识点」应该渲染成标题，而不是把 ## 显示出来');
    expect(find.textContaining('**'), findsNothing,
        reason: '「**病理学**」应该渲染成加粗，而不是把星号显示出来');

    // 断言 2：内容本身要在（标题去掉 ##、加粗词去掉 **）
    expect(find.textContaining('最优先复习知识点'), findsWidgets);
    expect(find.textContaining('病理学'), findsWidgets);
    expect(find.textContaining('53 道'), findsWidgets);
  });
}
