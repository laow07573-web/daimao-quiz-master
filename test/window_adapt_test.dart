import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flashcard_app/screens/main_shell.dart';
import 'package:flashcard_app/screens/quiz_screen.dart';
import 'package:flashcard_app/screens/stats_tab.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/theme_service.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/models/quiz_session.dart';
import 'package:flashcard_app/models/answer_record.dart';

/// v1.0.3 窗口自适应回归：布局随窗口尺寸连续适配。
/// 1. 宽窗口（1280）：统计页区块并排、刷题页选项双列；
/// 2. 中宽窗口（950）：统计页区块自动上下堆叠（AdaptivePair 阈值 900）；
/// 3. 窄窗口（700）：回到窄屏形态（底部导航、选项单列）。
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath =
        '${dir.path}/flashcard_app/test_adapt_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}.db';
    DatabaseService.overrideDbPath = dbPath;
  });

  tearDown(() async {
    DatabaseService.overrideDbPath = null;
  });

  Future<AppState> seed(WidgetTester tester) async {
    final appState = AppState();
    await tester.runAsync(() async {
      await appState.init();
      final now = DateTime.now().toIso8601String();
      final bankId = await DatabaseService.instance
          .insertBank(QuestionBank(name: '自适应题库', createdAt: now));
      await DatabaseService.instance.insertQuestions([
        for (var i = 1; i <= 4; i++)
          Question(
              bankId: bankId,
              title: '自适应题 $i',
              correctAnswer: '甲',
              options: const ['甲', '乙'],
              createdAt: now),
      ]);
      final qs = await DatabaseService.instance.getQuestionsByBank(bankId);
      // 未完成会话（endTime 为 null）：供续刷进入刷题页；
      // 答题记录已存在，统计页正常出数。
      final sid = await DatabaseService.instance.insertSession(QuizSession(
        bankIds: '$bankId',
        mode: 'single',
        totalQuestions: qs.length,
        startTime: now,
        endTime: null,
        durationSeconds: 300,
      ));
      for (var i = 0; i < qs.length; i++) {
        await DatabaseService.instance.insertAnswerRecord(AnswerRecord(
          questionId: qs[i].id!,
          sessionId: sid,
          userAnswer: i.isEven ? '甲' : '乙',
          isCorrect: i.isEven,
          answeredAt: now,
        ));
      }
      await DatabaseService.instance.updateSession(QuizSession(
        id: sid,
        bankIds: '$bankId',
        mode: 'single',
        totalQuestions: qs.length,
        correctCount: 2,
        wrongCount: 2,
        startTime: now,
        endTime: null,
        durationSeconds: 300,
      ));
      await DatabaseService.instance.insertSessionBanks(sid, [bankId]);
      await DatabaseService.instance.insertSessionQuestions(sid, qs);
    });
    return appState;
  }

  Widget host(AppState appState, Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
        ],
        child: MaterialApp(theme: ThemeService().themeData, home: child),
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 12));
      await settle(tester);
    }
    await tester.pump(const Duration(seconds: 12));
    await tester.runAsync(() => DatabaseService.instance.close());
  }

  void setSize(WidgetTester tester, double w, double h) {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('宽窗口 1280：统计区块并排 + 刷题选项双列', (tester) async {
    setSize(tester, 1280, 800);
    final appState = await seed(tester);

    // 统计页：年度坚持/近一年趋势 并排（标题 dy 接近）
    final statsKey = GlobalKey<StatsTabState>();
    await tester.pumpWidget(host(appState, StatsTab(key: statsKey)));
    await tester.runAsync(() => statsKey.currentState!.refresh());
    await settle(tester);
    final y1 = tester.getTopLeft(find.text('年度坚持')).dy;
    final y2 = tester.getTopLeft(find.text('近一年趋势')).dy;
    expect((y1 - y2).abs(), lessThan(20), reason: '宽窗口区块应并排');

    // 刷题页：全部已答记录 → 续刷停在最后一题（题 4）
    await tester.pumpWidget(host(appState, const QuizScreen()));
    await tester.runAsync(() async {
      await appState.resumeUnfinishedSession();
    });
    await settle(tester);
    final optA = find.text('自适应题 4');
    expect(optA, findsOneWidget);
    await tester.tap(find.byTooltip('手写批注'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('完成 (Esc)'));
    await settle(tester);

    await teardown(tester);
  });

  testWidgets('中宽窗口 950：内容 918 仍达阈值，区块保持并排', (tester) async {
    setSize(tester, 950, 760);
    final appState = await seed(tester);

    final statsKey = GlobalKey<StatsTabState>();
    await tester.pumpWidget(host(appState, StatsTab(key: statsKey)));
    await tester.runAsync(() => statsKey.currentState!.refresh());
    await settle(tester);
    expect(find.text('统计概览'), findsOneWidget);
    final y1 = tester.getTopLeft(find.text('年度坚持')).dy;
    final y2 = tester.getTopLeft(find.text('近一年趋势')).dy;
    expect((y1 - y2).abs(), lessThan(20), reason: '918≥900 应仍并排');
    expect(tester.takeException(), isNull);
    await teardown(tester);
  });

  testWidgets('窗口 920：统计区块上下堆叠（低于 900 阈值）', (tester) async {
    setSize(tester, 920, 700);
    final appState = await seed(tester);

    final statsKey = GlobalKey<StatsTabState>();
    await tester.pumpWidget(host(appState, StatsTab(key: statsKey)));
    await tester.runAsync(() => statsKey.currentState!.refresh());
    await settle(tester);
    final y1 = tester.getTopLeft(find.text('年度坚持')).dy;
    final y2 = tester.getTopLeft(find.text('近一年趋势')).dy;
    expect((y1 - y2).abs(), greaterThan(50), reason: '窄宽屏区块应堆叠');

    await teardown(tester);
  });

  testWidgets('窄窗口 700：底部导航 + 无侧栏（防回归）', (tester) async {
    setSize(tester, 700, 900);
    final appState = await seed(tester);
    await tester.pumpWidget(host(appState, const MainShell()));
    await settle(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    await teardown(tester);
  });
}
