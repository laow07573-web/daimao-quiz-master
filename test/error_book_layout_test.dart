import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flashcard_app/models/answer_record.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/screens/error_book_screen.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/fsrs_service.dart';

/// 错题本题库卡的**布局回归测试**（真机反馈：元信息行在屏幕右缘被裁断）。
///
/// 为什么必须有这层测试：那条 bug 只在「元信息一行放不下」时出现——窄屏要靠
/// 折行、宽屏网格卡要靠足够的固定行高。纯数据层测试看不见，CI 里的 analyze /
/// flutter test 也抓不到，只能靠人拿真机看。这里用两种屏幕宽度把两条布局分支
/// 都跑一遍，任何一处溢出都会以 FlutterError 的形式被 takeException 抓到。
void main() {
  late Directory tmp;

  setUp(() async {
    await DatabaseService.instance.close();
    tmp = Directory.systemTemp.createTempSync('mj_errbook_layout_');
    DatabaseService.overrideDbPath = '${tmp.path}/flashcard.db';
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 造一个「元信息很长」的题库：题名长、到期/收藏都有、且有已到期的 FSRS 卡
  /// （这三项凑齐才会出现 `173 题到期 · 175 收藏 · 最早到期：已到期179天` 这种宽行）
  Future<void> seedLongMetaBank() async {
    final db = DatabaseService.instance;
    final bankId = await db.insertBank(QuestionBank(
        name: '内科学（呼吸系统与循环系统合并整理版）',
        createdAt: DateTime.now().toIso8601String()));
    await db.insertQuestions([
      for (var i = 0; i < 3; i++)
        Question(
          bankId: bankId,
          title: '题目$i',
          options: const ['A', 'B'],
          correctAnswer: 'A',
          createdAt: DateTime.now().toIso8601String(),
        ),
    ]);
    final qs = await db.getQuestionsByBank(bankId);
    for (final q in qs) {
      await db.addToErrorBook(q.id!);
      // 已到期 179 天：卡片上会出现最长的那段文案
      await db.upsertFSRSCard(FSRSCardState(
        questionId: q.id!,
        stability: 1.0,
        difficulty: 5.0,
        reviewCount: 3,
        lastReviewAt: DateTime.now().subtract(const Duration(days: 200)),
        nextReviewAt: DateTime.now().subtract(const Duration(days: 179)),
      ));
      await db.insertAnswerRecord(AnswerRecord(
          questionId: q.id!,
          userAnswer: 'B',
          isCorrect: false,
          answeredAt: DateTime.now().toIso8601String()));
    }
  }

  /// 造数据 + 起 AppState + 等首页那几条查询：数据库是真实 I/O，
  /// widget 测试的假时钟推不动它，必须借 runAsync 回到真实事件循环。
  Future<void> pumpErrorBook(
    WidgetTester tester, {
    required Size surface,
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late AppState appState;
    await tester.runAsync(() async {
      await seedLongMetaBank();
      appState = AppState();
      await appState.init();
    });

    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const MaterialApp(home: ErrorBookScreen()),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('窄屏（手机竖屏）：元信息折行而不是溢出裁断', (tester) async {
    await pumpErrorBook(tester, surface: const Size(411, 891)); // LG G7 竖屏

    expect(find.textContaining('最早到期'), findsWidgets);
    expect(tester.takeException(), isNull,
        reason: '窄屏放不下时应折行，不能出现 RenderFlex 溢出');
  });

  testWidgets('宽屏（≥840dp 走两列网格）：固定行高要容得下两行元信息', (tester) async {
    await pumpErrorBook(tester, surface: const Size(900, 800));

    expect(find.textContaining('最早到期'), findsWidgets);
    // 宽屏是 GridView（固定 mainAxisExtent），折行后行高不够就会在这里抛溢出
    expect(tester.takeException(), isNull,
        reason: '宽屏网格卡折成两行后不能纵向溢出');
  });
}
