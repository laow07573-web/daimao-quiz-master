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

/// 排查用户反馈「最大化窗口统计页交互无反应/历史详情打不开」：
/// 1. 根因修复验证——多实例争抢 SQLite 已由 main.dart 单实例锁解决（此处不再覆盖）；
/// 2. 高 DPI 最大化（1080p@150%/125%）下统计页渲染与核心交互回归。
/// 注：统计页数据加载在测试假异步区会挂起，统一用 runAsync 直驱加载。
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath =
        '${dir.path}/flashcard_app/test_dpi_stats_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}.db';
    DatabaseService.overrideDbPath = dbPath;
  });

  tearDown(() async {
    DatabaseService.overrideDbPath = null;
  });

  testWidgets('高 DPI 最大化：主壳宽屏导航可达统计页', (tester) async {
    final appState = AppState();
    await tester.runAsync(() => appState.init());

    // 1080p@150% 最大化 → 逻辑 1280×720
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
      ],
      child: MaterialApp(theme: ThemeService().themeData, home: const MainShell()),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);

    // 宽屏应为侧边导航（逻辑宽 1280 ≥ 840）
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.tap(find.text('统计'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(StatsTab), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 12));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(() => DatabaseService.instance.close());
  });

  testWidgets('高 DPI 最大化：统计页加载/周期/排行/历史详情全交互', (tester) async {
    final appState = AppState();
    await tester.runAsync(() async {
      await appState.init();
      final now = DateTime.now().toIso8601String();
      final bankId = await DatabaseService.instance
          .insertBank(QuestionBank(name: 'DPI题库', createdAt: now));
      await DatabaseService.instance.insertQuestions([
        for (var i = 1; i <= 4; i++)
          Question(
              bankId: bankId,
              title: 'DPI题 $i',
              correctAnswer: '甲',
              options: const ['甲', '乙'],
              createdAt: now),
      ]);
      final qs = await DatabaseService.instance.getQuestionsByBank(bankId);
      final sid = await DatabaseService.instance.insertSession(QuizSession(
        bankIds: '$bankId',
        mode: 'single',
        totalQuestions: qs.length,
        startTime: now,
        endTime: now,
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
        endTime: now,
        durationSeconds: 300,
      ));
      await DatabaseService.instance.insertSessionBanks(sid, [bankId]);
      await DatabaseService.instance.insertSessionQuestions(sid, qs);
    });

    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // 1080p@150% 最大化 → 逻辑 1280×720
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final statsKey = GlobalKey<StatsTabState>();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
      ],
      child: MaterialApp(
          theme: ThemeService().themeData, home: StatsTab(key: statsKey)),
    ));
    await tester.runAsync(() => statsKey.currentState!.refresh());
    await settle();
    expect(tester.takeException(), isNull);
    expect(find.text('统计概览'), findsOneWidget);

    // 周期切换（顶部区域，先做，避免滚动后 chip 移出视口）
    await tester.tap(find.text('全部'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('本周'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('统计概览'), -300,
        scrollable: find.byType(Scrollable).first);
    await settle();

    // v1.28 年度热力图使页面更长：用 scrollUntilVisible 逐步滚到历史记录区
    await tester.scrollUntilVisible(find.text('历史记录'), 300,
        scrollable: find.byType(Scrollable).first);
    await settle();
    expect(find.text('历史记录'), findsOneWidget);

    // 排行页签
    await tester.ensureVisible(find.text('按知识点'));
    await settle();
    await tester.tap(find.text('按知识点'));
    await settle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('按题库'));
    await settle();
    expect(tester.takeException(), isNull);

    // 历史记录 → 会话详情
    final item = find.text('DPI题库').last;
    await tester.ensureVisible(item);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(item);
    await settle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SessionDetailScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 12));
      await settle();
    }
    await tester.pump(const Duration(seconds: 12));
    await tester.runAsync(() => DatabaseService.instance.close());
  });
}
