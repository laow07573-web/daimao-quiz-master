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
  ///
  /// [kp] 用来造出多个知识点标签，把「薄弱知识点」面板撑高——整页滚动那条用例
  /// 需要表头足够高才能验证「表头也跟着滚」。
  Future<void> seedLongMetaBank({String kp = '批量知识点'}) async {
    final db = DatabaseService.instance;
    final bankId = await db.insertBank(QuestionBank(
        name: '内科学（呼吸系统与循环系统合并整理版）$kp',
        createdAt: DateTime.now().toIso8601String()));
    await db.insertQuestions([
      for (var i = 0; i < 3; i++)
        Question(
          bankId: bankId,
          title: '题目$i',
          options: const ['A', 'B'],
          correctAnswer: 'A',
          knowledgePoint: kp,
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

  /// 轮询等到 [target] 渲染出来，而不是固定 pump 若干次：
  /// 数据库在后台 isolate，固定次数在慢 runner 上会不够——同一提交曾出现
  /// 「一次全绿、一次两条用例全红」的抖动，根因就在这里。
  Future<void> settleUntil(WidgetTester tester, Finder target,
      {String? what}) async {
    for (var i = 0; i < 150; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 10));
      if (target.evaluate().isNotEmpty) return;
    }
    fail('等不到${what ?? '目标控件'}渲染：数据没加载出来（不是布局问题，是等待时间不够）');
  }

  /// 造数据 + 起 AppState + 等首页那几条查询：数据库是真实 I/O，
  /// widget 测试的假时钟推不动它，必须借 runAsync 回到真实事件循环。
  Future<void> pumpErrorBook(
    WidgetTester tester, {
    required Size surface,
    /// 自定义造数（默认造一个题库）。注意：造数必须在 runAsync 里跑——
    /// widget 测试的假时钟推不动真实数据库 I/O，写在外面会直接挂住不返回。
    Future<void> Function()? seed,
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late AppState appState;
    await tester.runAsync(() async {
      if (seed != null) {
        await seed();
      } else {
        await seedLongMetaBank();
      }
      appState = AppState();
      await appState.init();
    });

    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const MaterialApp(home: ErrorBookScreen()),
    ));
    await settleUntil(tester, find.textContaining('最早到期'), what: '题库卡');
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
    // 宽屏是网格（固定 mainAxisExtent），折行后行高不够就会在这里抛溢出
    expect(tester.takeException(), isNull,
        reason: '宽屏网格卡折成两行后不能纵向溢出');
  });

  testWidgets('整页上下滑动：表头（薄弱知识点面板）也跟着滚，不只是卡片区在滚', (tester) async {
    // 造 6 个题库 / 6 个知识点：知识点标签一多，面板就高（真机反馈的场景），
    // 内容总高必然超过一屏，才能验证「整页一起滚」。
    await pumpErrorBook(tester,
        surface: const Size(411, 891),
        seed: () async {
          for (var i = 1; i <= 6; i++) {
            await seedLongMetaBank(kp: '知识点$i');
          }
        });

    // 知识点面板是在主统计之后再加载的，要单独等它出现
    final header = find.text('薄弱知识点');
    await settleUntil(tester, header, what: '薄弱知识点面板');
    expect(header, findsOneWidget);
    final beforeScroll = tester.getTopLeft(header).dy;

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -320));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final afterScroll = tester.getTopLeft(header).dy;
    expect(afterScroll, lessThan(beforeScroll),
        reason: '表头在滚动视图之外时位置不会变——那正是用户反馈「翻不动整页」的原因');

    // 底部主按钮不随内容滚走，始终固定在底部
    expect(find.textContaining('全题库重刷'), findsOneWidget);
  });
}
