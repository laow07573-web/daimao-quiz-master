import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/screens/quiz_screen.dart';
import 'package:flashcard_app/screens/practice_screen.dart' show PracticeTiming;
import 'package:flashcard_app/widgets/annotation_canvas.dart';
import 'package:flashcard_app/widgets/annotation_controller.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/theme_service.dart';

/// 手写批注刷题页 widget 集成测试（v1.0.3）：
/// 入口可见性（REQ-001/005）、即时/持久批注工具栏配置切换（REQ-014）
///
/// 注意：sqflite ffi 的真实异步在 testWidgets 的 FakeAsync zone 下会
/// 永久挂起——所有被 await 的 DB 操作必须包 tester.runAsync；
/// UI 内 fire-and-forget 的 DB 调用不阻塞帧渲染，无碍。
/// 落库/回读行为由 test/annotation_test.dart（纯逻辑）与模拟器验证覆盖。
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir =
        Directory(Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath =
        '${dir.path}/flashcard_app/test_anno_widget_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}.db';
    DatabaseService.overrideDbPath = dbPath;
    final f = File(dbPath);
    if (await f.exists()) await f.delete();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
  });

  /// 造一个 1 题题库并启动刷题会话（DB 操作走 runAsync 真实 zone）
  Future<AppState> seedAndStart(WidgetTester tester) async {
    final appState = AppState();
    await tester.runAsync(() async {
      final now = DateTime.now().toIso8601String();
      final bankId = await DatabaseService.instance
          .insertBank(QuestionBank(name: '批注题库', createdAt: now));
      await DatabaseService.instance.insertQuestions([
        Question(
            bankId: bankId,
            title: '批注测试题',
            correctAnswer: '甲',
            options: const ['甲', '乙'],
            createdAt: now),
      ]);
      appState.toggleBankSelection(bankId);
      await appState.startQuiz();
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

  /// 推进到动画稳定（不用 pumpAndSettle：练习模式每秒计时
  /// Timer 会让 settle 永不收敛）
  /// 末尾在真实 zone flush 一次：让 UI 内 fire-and-forget 的
  /// ffi DB 异步完成回调落地，避免 close 后才回来报错
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

  /// 收尾：卸载树 + 把 FakeAsync 时钟推过 sqflite 锁警告
  /// Timer 的 10s 周期（pending timer 会让测试失败）
  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settleFrames(tester);
    await tester.pump(const Duration(seconds: 12));
    await settleFrames(tester);
  }

  testWidgets('REQ-001/005：正常模式有批注入口，练习模式无', (tester) async {
    final appState = await seedAndStart(tester);

    // 正常模式：入口存在
    await tester.pumpWidget(host(appState, const QuizScreen()));
    await settleFrames(tester);
    expect(find.byTooltip('手写批注'), findsOneWidget);

    // 练习模式：入口隐藏（计时 Timer 每秒触发，只推有限帧）
    await tester.pumpWidget(host(
        appState,
        const QuizScreen(
            quizMode: QuizMode.practice, practiceTiming: PracticeTiming.untimed)));
    await settleFrames(tester);
    expect(find.byTooltip('手写批注'), findsNothing);

    await teardownTree(tester);
  });

  testWidgets('REQ-002/014：未作答进入即时批注（清草稿），完成收起工具栏',
      (tester) async {
    final appState = await seedAndStart(tester);
    await tester.pumpWidget(host(appState, const QuizScreen()));
    await settleFrames(tester);

    // 进入批注：工具栏出现，即时配置（"清草稿"，无"选择"/"清全部"）
    await tester.tap(find.byTooltip('手写批注'));
    await settleFrames(tester);
    expect(find.text('完成 (Esc)'), findsOneWidget);
    expect(find.byTooltip('清草稿 (Ctrl+Del)'), findsOneWidget);
    expect(find.byTooltip('选择 (S)'), findsNothing);
    expect(find.byTooltip('清全部 (Ctrl+Del)'), findsNothing);

    // 画一笔（题区拖动；页内存在多个 CustomPaint，
    // 定位批注画布本身）
    final canvasFinder = find.byType(AnnotationCanvas);
    expect(canvasFinder, findsOneWidget);
    final center = tester.getCenter(canvasFinder);
    await tester.dragFrom(center - const Offset(60, 20), const Offset(120, 40));
    await settleFrames(tester);

    // 完成 → 工具栏收起（桌面端按钮文本带快捷键标注；精确匹配避免撞「完成刷题」）
    await tester.tap(find.text('完成 (Esc)'));
    await settleFrames(tester);
    expect(find.text('完成 (Esc)'), findsNothing);
    expect(find.byTooltip('清草稿 (Ctrl+Del)'), findsNothing);

    await teardownTree(tester);
  });

  testWidgets('REQ-006~014：已作答进入持久批注（选择/清全部）', (tester) async {
    final appState = await seedAndStart(tester);
    await tester.pumpWidget(host(appState, const QuizScreen()));
    await settleFrames(tester);

    // 造已作答态：runAsync 里直接提交答案（答错留在本题；
    // 不走 UI tap 是为了绕开答题音效的 platform channel）
    await tester.runAsync(() => appState.submitAnswer('乙'));
    await settleFrames(tester);

    // 进入批注：持久配置（"选择"/"清全部"，无"清草稿"）
    await tester.tap(find.byTooltip('手写批注'));
    await settleFrames(tester);
    expect(find.byTooltip('选择 (S)'), findsOneWidget);
    expect(find.byTooltip('清全部 (Ctrl+Del)'), findsOneWidget);
    expect(find.byTooltip('清草稿 (Ctrl+Del)'), findsNothing);

    // 画一笔 + 完成（收起工具栏不崩）
    final canvasFinder = find.byType(AnnotationCanvas);
    final center = tester.getCenter(canvasFinder);
    await tester.dragFrom(center - const Offset(60, 20), const Offset(120, 40));
    await settleFrames(tester);
    await tester.tap(find.text('完成 (Esc)'));
    await settleFrames(tester);
    expect(find.text('完成 (Esc)'), findsNothing);

    await teardownTree(tester);
  });

  testWidgets('REQ-010 回归：选择工具拖动只按事件位移平移（不甩飞）',
      (tester) async {
    // 回归 _onDown select 分支未同步 _lastSelectPos 的 bug：
    // 首个 move 的 delta 若相对 (0,0)，笔迹会被瞬间甩出拖动距离数倍。
    // 独立挂画布（无 DB）：400x400 画布上一笔 (80,100)-(160,100)，
    // 从笔迹中点拖 (30,20)，首点应只偏移 (30/400, 20/400)。
    final controller = AnnotationController();
    controller.beginStroke(const Offset(0.2, 0.25), 1.0);
    controller.extendStroke(const Offset(0.3, 0.25), 1.0);
    controller.extendStroke(const Offset(0.4, 0.25), 1.0);
    controller.endStroke();
    controller.tool = AnnoTool.select;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: AnnotationCanvas(
                controller: controller, interactive: true),
          ),
        ),
      ),
    ));
    await tester.pump();

    final canvas = find.byType(AnnotationCanvas);
    final start = tester.getTopLeft(canvas) + const Offset(120, 100);
    await tester.dragFrom(start, const Offset(30, 20));
    await tester.pump();

    final p0 = controller.strokes.single.pointAt(0);
    // 实际平移 = 拖动量 - touch slop 首段（dragFrom 行为），
    // 应远小于 bug 行为的 ≈ (120,100)+拖动量；用区间断言兼底两种 slop 消耗。
    // 首点增量应落在 [10/400, 30/400] × [≈5/400, 20/400]
    expect(p0.dx, greaterThan(0.21));
    expect(p0.dx, lessThan(0.32));
    expect(p0.dy, greaterThan(0.255));
    expect(p0.dy, lessThan(0.345));
    controller.dispose();
  });
}
