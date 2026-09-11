import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flashcard_app/screens/main_shell.dart';
import 'package:flashcard_app/screens/session_detail_screen.dart';
import 'package:flashcard_app/screens/stats_tab.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/theme_service.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/models/quiz_session.dart';
import 'package:flashcard_app/models/answer_record.dart';

/// v1.0.3 宽屏统计页交互验证（用户反馈排查）：
/// 侧边导航进入统计页 → 数据加载 → 周期切换（本周/本月/全部）→ 排行维度切换
/// → 历史记录点击进入会话详情。全路径无异常/无白屏。
/// 注：统计页数据加载在测试假异步区会挂起，统一用 runAsync 直驱。
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath =
        '${dir.path}/flashcard_app/test_wide_stats_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}.db';
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

  Future<void> settleFrames(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 12));
      await settleFrames(tester);
    }
    await tester.pump(const Duration(seconds: 12));
    await tester.runAsync(() => DatabaseService.instance.close());
  }

  testWidgets('宽屏主壳：侧边导航可切换到统计页', (tester) async {
    setSurface(tester, 1280, 800);
    final appState = AppState();
    await tester.runAsync(() => appState.init());
    await tester.pumpWidget(host(appState, const MainShell()));
    await settleFrames(tester);

    await tester.tap(find.text('统计'));
    await settleFrames(tester);
    // 统计页挂载即切换成功（内容加载由下个用例覆盖）
    expect(find.byType(StatsTab), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('宽屏统计页：周期切换/排行维度/历史详情全交互路径',
      (tester) async {
    setSurface(tester, 1280, 800);

    // 造数：题库 + 4 题 + 已完成会话（对 2 错 2）
    final appState = AppState();
    final statsKey = GlobalKey<StatsTabState>();
    late int sessionId;
    await tester.runAsync(() async {
      await appState.init();
      final now = DateTime.now().toIso8601String();
      final bankId = await DatabaseService.instance
          .insertBank(QuestionBank(name: '统计测试题库', createdAt: now));
      await DatabaseService.instance.insertQuestions([
        for (var i = 1; i <= 4; i++)
          Question(
              bankId: bankId,
              title: '统计测试题 $i',
              correctAnswer: '甲',
              options: const ['甲', '乙'],
              createdAt: now),
      ]);
      final qs = await DatabaseService.instance.getQuestionsByBank(bankId);
      sessionId = await DatabaseService.instance.insertSession(QuizSession(
        bankIds: '$bankId',
        mode: 'single',
        totalQuestions: qs.length,
        startTime: now,
        endTime: now,
        durationSeconds: 300,
      ));
      var correct = 0;
      var wrong = 0;
      for (var i = 0; i < qs.length; i++) {
        final ok = i.isEven;
        await DatabaseService.instance.insertAnswerRecord(AnswerRecord(
          questionId: qs[i].id!,
          sessionId: sessionId,
          userAnswer: ok ? '甲' : '乙',
          isCorrect: ok,
          answeredAt: now,
        ));
        ok ? correct++ : wrong++;
      }
      await DatabaseService.instance.updateSession(QuizSession(
        id: sessionId,
        bankIds: '$bankId',
        mode: 'single',
        totalQuestions: qs.length,
        correctCount: correct,
        wrongCount: wrong,
        startTime: now,
        endTime: now,
        durationSeconds: 300,
      ));
      await DatabaseService.instance.insertSessionBanks(sessionId, [bankId]);
      await DatabaseService.instance.insertSessionQuestions(sessionId, qs);
    });

    await tester.pumpWidget(host(appState, StatsTab(key: statsKey)));
    await settleFrames(tester);

    // 1. 数据加载（DB 走真实 zone；UI 内 fire-and-forget 在假异步区会挂起）
    await tester.runAsync(() => statsKey.currentState!.refresh());
    await settleFrames(tester);
    expect(find.text('统计概览'), findsOneWidget);
    expect(find.text('年度坚持'), findsOneWidget);
    expect(find.text('近一年趋势'), findsOneWidget);
    expect(find.text('正确率排行'), findsOneWidget);
    expect(find.text('错题统计'), findsOneWidget);

    // 2. 周期切换（本周/本月/全部）无异常（切周期内部查 DB，走 runAsync）
    //    注意：先做顶部交互再滚到底部，否则标签会被滚出视口
    for (final label in ['本月', '全部', '本周']) {
      await tester.ensureVisible(find.text(label));
      await settleFrames(tester);
      await tester.tap(find.text(label));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await settleFrames(tester);
      expect(tester.takeException(), isNull);
    }

    // 3. 排行维度切换（按题库/按知识点）
    await tester.ensureVisible(find.text('按知识点'));
    await settleFrames(tester);
    await tester.tap(find.text('按知识点'));
    await settleFrames(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('按题库'));
    await settleFrames(tester);
    expect(tester.takeException(), isNull);

    // 4. 滚动到底部断言历史记录（v1.28 年度热力图使页面更长）
    await tester.scrollUntilVisible(find.text('历史记录'), 300,
        scrollable: find.byType(Scrollable).first);
    await settleFrames(tester);
    expect(find.text('历史记录'), findsOneWidget);

    // 4. 历史记录点击进入会话详情（题库名在排行/历史两处出现，取历史区末位）
    await tester.tap(find.text('统计测试题库').last);
    await settleFrames(tester);
    expect(find.byType(SessionDetailScreen), findsOneWidget);

    await teardownTree(tester);
  });
}
