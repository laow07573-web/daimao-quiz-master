import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/screens/main_shell.dart';
import 'package:flashcard_app/screens/quiz_screen.dart';
import 'package:flashcard_app/widgets/annotation_canvas.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/theme_service.dart';

/// v1.0.3 宽屏重设计验证：
/// 1. 宽屏（≥840dp，PC/平板横屏）主壳用左侧 NavigationRail，无底部导航栏；
/// 2. 窄屏（手机）保持底部 NavigationBar，无侧边导航（防回归）;
/// 3. 宽屏刷题页选项双列排布，且手写批注全流程在新布局下可用。
///
/// DB 注意事项同 annotation_widget_test：被 await 的 DB 操作必须
/// 包在 tester.runAsync 内（sqflite ffi 真实异步在 FakeAsync zone 会挂起）。
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath =
        '${dir.path}/flashcard_app/test_wide_layout_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}.db';
    DatabaseService.overrideDbPath = dbPath;
    final f = File(dbPath);
    if (await f.exists()) await f.delete();
  });

  tearDown(() async {
    // DB 关闭由收尾助手在测试体内完成（同 annotation_widget_test：
    // 在假异步 zone 内 await ffi 会永久挂起）；这里只清路径覆盖。
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

  /// 有限帧推进（首页有异步数据加载，不用 pumpAndSettle）
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

  /// 收尾：卸载树 + 多轮冲刷。主壳包含首页/统计页多个链式 fire-and-forget
  /// DB 查询，每一环在假异步 zone 会留下 10s 锁警告定时器，而 runAsync 回调又
  /// 会推进下一环——需反复「推 12s + settle」几轮把链耗尽，
  /// 最后在测试体内关闭 DB（同 annotation_widget_test）
  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 12));
      await settleFrames(tester);
    }
    await tester.pump(const Duration(seconds: 12));
    await tester.runAsync(() => DatabaseService.instance.close());
  }

  Future<AppState> initAppState(WidgetTester tester) async {
    final appState = AppState();
    await tester.runAsync(() => appState.init());
    return appState;
  }

  testWidgets('宽屏（1280×800）：主壳用左侧导航，无底部导航栏', (tester) async {
    setSurface(tester, 1280, 800);
    final appState = await initAppState(tester);
    await tester.pumpWidget(host(appState, const MainShell()));
    await settleFrames(tester);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    // 侧边导航底部设置入口
    expect(find.byTooltip('设置'), findsOneWidget);
    // 三目的地齐全
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('窄屏（420×800 手机）：保持底部导航，无侧边导航（防回归）',
      (tester) async {
    setSurface(tester, 420, 800);
    final appState = await initAppState(tester);
    await tester.pumpWidget(host(appState, const MainShell()));
    await settleFrames(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    await teardownTree(tester);
  });

  testWidgets('宽屏刷题页：选项双列排布 + 手写批注全流程可用', (tester) async {
    setSurface(tester, 1280, 800);

    // 造 1 道四选项题并启动会话（走 runAsync 真实 zone）
    final appState = AppState();
    await tester.runAsync(() async {
      await appState.init();
      final now = DateTime.now().toIso8601String();
      final bankId = await DatabaseService.instance
          .insertBank(QuestionBank(name: '宽屏题库', createdAt: now));
      await DatabaseService.instance.insertQuestions([
        Question(
            bankId: bankId,
            title: '宽屏布局测试题',
            correctAnswer: '甲',
            options: const ['甲', '乙', '丙', '丁'],
            createdAt: now),
      ]);
      appState.toggleBankSelection(bankId);
      await appState.startQuiz();
    });

    await tester.pumpWidget(host(appState, const QuizScreen()));
    await settleFrames(tester);

    // 选项双列：甲（左列第 1）与乙（右列第 1）顶部近似同高、横向错开
    final topA = tester.getTopLeft(find.text('甲').last);
    final topB = tester.getTopLeft(find.text('乙').last);
    expect((topA.dy - topB.dy).abs(), lessThan(10));
    expect((topA.dx - topB.dx).abs(), greaterThan(100));

    // 批注全流程：进入 → 画一笔 → 完成收起
    await tester.tap(find.byTooltip('手写批注'));
    await settleFrames(tester);
    expect(find.text('完成 (Esc)'), findsOneWidget);

    final canvasFinder = find.byType(AnnotationCanvas);
    expect(canvasFinder, findsOneWidget);
    final center = tester.getCenter(canvasFinder);
    await tester.dragFrom(
        center - const Offset(80, 20), const Offset(160, 40));
    await settleFrames(tester);

    await tester.tap(find.text('完成 (Esc)'));
    await settleFrames(tester);
    expect(find.text('完成 (Esc)'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 12));
      await settleFrames(tester);
    }
    await tester.pump(const Duration(seconds: 12));
    await tester.runAsync(() => DatabaseService.instance.close());
  });
}
