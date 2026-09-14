import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flashcard_app/models/answer_record.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/models/quiz_session.dart';
import 'package:flashcard_app/screens/home_screen.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/theme_service.dart';
import 'package:flashcard_app/widgets/kit/mj_kit.dart';

/// 首页断点续刷入口的防回归测试。
///
/// 背景：UI 重设计时把续刷入口挪到了「开始」页，首页只剩一行注释，
/// 结果从旧版升级来的用户按肌肉记忆在首页找不到「继续上次刷题」。
/// 首页是回来看的第一屏，这个入口必须在；此测试锁住它。
///
/// DB 注意事项：被 await 的 ffi 操作必须包在 tester.runAsync 内
/// （见 wide_layout_test 的说明）。
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath =
        '${dir.path}/flashcard_app/test_home_resume_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}.db';
    DatabaseService.overrideDbPath = dbPath;
    final f = File(dbPath);
    if (await f.exists()) await f.delete();
  });

  tearDown(() async {
    DatabaseService.overrideDbPath = null;
  });

  Widget host(AppState appState, Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
        ],
        child: MaterialApp(theme: ThemeService().themeData, home: child),
      );

  void setSurface(WidgetTester tester, double width, double height) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  /// 首页加载数据要走 5 个串行 await 的 DB 查询（年度统计→连续天数→本周→
  /// 假期→未完成会话）。在假异步 zone 下，每个 await 都需要「一次 runAsync
  /// 让 ffi 在真实事件循环上跑完 + 一次 pump 派发续体」，所以要交叉推进多轮，
  /// 只做一轮 runAsync 后面跟几个 pump 是不够的（实测第 4 轮才稳定出现）。
  Future<void> settleFrames(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 首页有链式 fire-and-forget DB 查询，收尾需多轮冲刷（同 wide_layout_test）
  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 12));
      await settleFrames(tester);
    }
    await tester.pump(const Duration(seconds: 12));
    await tester.runAsync(() => DatabaseService.instance.close());
  }

  /// 造一个「刷到一半」的会话：3 题，第 1 题已答对。
  Future<void> seedUnfinishedSession() async {
    final db = DatabaseService.instance;
    final now = DateTime.now().toIso8601String();
    final bankId =
        await db.insertBank(QuestionBank(name: '续刷题库', createdAt: now));
    await db.insertQuestions([
      for (var i = 1; i <= 3; i++)
        Question(
            bankId: bankId,
            title: '续刷题$i',
            correctAnswer: 'A',
            options: const ['A', 'B', 'C'],
            createdAt: now),
    ]);
    final qs = await db.getQuestionsByBank(bankId);
    final sid = await db.insertSession(QuizSession(
        bankIds: '$bankId',
        mode: 'single',
        totalQuestions: 3,
        startTime: now));
    await db.insertSessionBanks(sid, [bankId]);
    await db.insertSessionQuestions(sid, qs);
    await db.insertAnswerRecord(AnswerRecord(
        questionId: qs[0].id!,
        sessionId: sid,
        userAnswer: 'A',
        isCorrect: true,
        answeredAt: now));
  }

  testWidgets('有未完成会话时，首页显示「继续上次刷题」入口', (tester) async {
    setSurface(tester, 420, 900);
    final appState = AppState();
    await tester.runAsync(() async {
      await appState.init();
      await seedUnfinishedSession();
    });

    await tester.pumpWidget(host(appState, const HomeScreen()));
    await settleFrames(tester);

    expect(find.text('继续上次刷题'), findsOneWidget,
        reason: '首页是回来看的第一屏，续刷入口必须在这里（不能只在「开始」页）');
    // 进度副标题：3 题已答 1 题
    expect(find.textContaining('已答 1/3'), findsOneWidget);
    // 与「开始」页共用同一个组件，两处外观不会分叉
    expect(find.byType(MJResumeCard), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('没有未完成会话时，首页不显示续刷入口（不占位）', (tester) async {
    setSurface(tester, 420, 900);
    final appState = AppState();
    await tester.runAsync(() => appState.init());

    await tester.pumpWidget(host(appState, const HomeScreen()));
    await settleFrames(tester);

    expect(find.text('继续上次刷题'), findsNothing);
    expect(find.byType(MJResumeCard), findsNothing);

    await teardownTree(tester);
  });

  /// 这一条锁的是「卡片为什么不出现」的真因：首页的续刷卡片与本周战绩都是
  /// 页面私有 state，只在 statsRevision 变化时才重载。暂停会话时本轮作答
  /// 已落库却没走「答题结束」路径，如果 pauseSession 只 notifyListeners，
  /// 首页会一直拿旧值渲染 —— 表现为「暂停退出回首页看不到续刷入口、
  /// 本周刷题还是 0，点一下刷新才出来」。所以这里断言版本号必须自增。
  group('统计口径变化必须让首页重载（statsRevision 契约）', () {
    test('pauseSession 后 statsRevision 自增，且未完成会话可查', () async {
      final db = DatabaseService.instance;
      final appState = AppState();
      await appState.init();
      await seedUnfinishedSession();

      final before = appState.statsRevision;
      await appState.pauseSession();
      expect(appState.statsRevision, greaterThan(before),
          reason: 'pauseSession 必须 bumpStatsRevision，否则首页不重载续刷入口');
      expect(await appState.getUnfinishedSessionInfo(), isNotNull);

      await db.close();
    });

    test('refreshWeeklyStats（切回首页）也会自增，强制首页重新取数', () async {
      final appState = AppState();
      await appState.init();

      final before = appState.statsRevision;
      await appState.refreshWeeklyStats();
      expect(appState.statsRevision, greaterThan(before),
          reason: '切回首页要重载私有统计（含续刷卡片），不能只 notifyListeners');

      await DatabaseService.instance.close();
    });
  });
}
