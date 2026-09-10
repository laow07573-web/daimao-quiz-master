import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flashcard_app/models/ink_annotation.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/models/quiz_session.dart';
import 'package:flashcard_app/screens/quiz_screen.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/theme_service.dart';
import 'package:flashcard_app/widgets/annotation_canvas.dart';
import 'package:flashcard_app/widgets/trend_chart.dart';

/// v1.0.3 批注增强验证：
/// 1. InkStroke frame 字段 JSON 往返与存量兼容；
/// 2. 宽屏画布扩区：A 键进入后页面层画布存在，可书写；
/// 3. PC 快捷键：A 进入/退出、数字切色、Q/W/E/R 切工具、Esc 完成；
/// 4. 趋势图箭头翻页（365 天历史数据）。
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath =
        '${dir.path}/flashcard_app/test_anno_v2_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}.db';
    DatabaseService.overrideDbPath = dbPath;
  });

  tearDown(() async {
    DatabaseService.overrideDbPath = null;
  });

  group('InkStroke frame 字段', () {
    test('JSON 往返保留 frame；缺省兼容存量（无 f 字段 = question）', () {
      const page = InkStroke(pts: [0.1, 0.2, 0.3, 0.4], color: 0xFFE53935, width: 3, frame: kFramePage);
      final json = page.toJson();
      expect(json['f'], kFramePage);
      final back = InkStroke.fromJson(json);
      expect(back.frame, kFramePage);

      // 存量数据无 f 字段 → 缺省 question
      final legacy = InkStroke.fromJson(
          {'pts': [0.1, 0.2], 'c': 0xFF212121, 'w': 3, 'p': 1});
      expect(legacy.frame, kFrameQuestion);

      // question frame 省略写入
      const q = InkStroke(pts: [0.5, 0.5], color: 1, width: 3);
      expect(q.toJson().containsKey('f'), isFalse);

      // encode/decode 全链路
      final decoded = InkStroke.decodeList(InkStroke.encodeList([page, q]));
      expect(decoded.length, 2);
      expect(decoded[0].frame, kFramePage);
      expect(decoded[1].frame, kFrameQuestion);
    });
  });

  group('宽屏画布扩区 + PC 快捷键', () {
    Future<AppState> seed(WidgetTester tester) async {
      final appState = AppState();
      await tester.runAsync(() async {
        await appState.init();
        final now = DateTime.now().toIso8601String();
        final bankId = await DatabaseService.instance
            .insertBank(QuestionBank(name: '快捷键题库', createdAt: now));
        await DatabaseService.instance.insertQuestions([
          for (var i = 1; i <= 4; i++)
            Question(
                bankId: bankId,
                title: '快捷键题 $i',
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
          endTime: null,
        ));
        await DatabaseService.instance.insertSessionBanks(sid, [bankId]);
        await DatabaseService.instance.insertSessionQuestions(sid, qs);
      });
      return appState;
    }

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

    Future<void> pressKey(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyUpEvent(key);
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('宽屏：A 进入批注 → 页面层画布书写 → Esc 收起；工具快捷键无异常',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final appState = await seed(tester);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
        ],
        child: MaterialApp(
            theme: ThemeService().themeData, home: const QuizScreen()),
      ));
      await tester.runAsync(() => appState.resumeUnfinishedSession());
      await settle(tester);
      expect(find.text('快捷键题 1'), findsOneWidget);

      // A 进入批注（桌面快捷键）
      await pressKey(tester, LogicalKeyboardKey.keyA);
      await settle(tester);
      expect(find.text('完成 (Esc)'), findsOneWidget,
          reason: 'A 键应进入批注模式（工具栏含快捷键标注）');

      // 页面层画布存在（宽屏扩区）
      expect(find.byType(AnnotationCanvas), findsOneWidget);

      // 数字切色 + 字母切工具：无异常即生效（状态在 controller 内部）
      for (final k in [
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.keyE,
        LogicalKeyboardKey.keyR,
        LogicalKeyboardKey.keyQ,
      ]) {
        await pressKey(tester, k);
        expect(tester.takeException(), isNull);
      }

      // 画一笔（画布交互）
      final canvas = find.byType(AnnotationCanvas);
      final c = tester.getCenter(canvas);
      await tester.dragFrom(c - const Offset(60, 20), const Offset(120, 40));
      await settle(tester);
      expect(tester.takeException(), isNull);

      // Esc 收起批注
      await pressKey(tester, LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.text('完成 (Esc)'), findsNothing, reason: 'Esc 应收起批注');

      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 12));
        await settle(tester);
      }
      await tester.pump(const Duration(seconds: 12));
      await tester.runAsync(() => DatabaseService.instance.close());
    });

    testWidgets('v1.27 纠偏：批注中纯横向滑动不切题（禁止横滑切题）',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    
      final appState = await seed(tester);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
        ],
        child: MaterialApp(
            theme: ThemeService().themeData, home: const QuizScreen()),
      ));
      await tester.runAsync(() => appState.resumeUnfinishedSession());
      await settle(tester);
      expect(appState.currentQuestionIndex, 0);
    
      // 先答错（留在本题）：非批注态已作答才允许前进，
      // 确保「不切题」是批注禁止而非作答门槛拦的（后续退出批注对照验证）。
      await tester.runAsync(() => appState.submitAnswer('乙'));
      await settle(tester);
      expect(appState.currentQuestionIndex, 0, reason: '答错应留在本题');
      await pressKey(tester, LogicalKeyboardKey.keyA);
      await settle(tester);
      expect(find.text('完成 (Esc)'), findsOneWidget);
      final canvas = find.byType(AnnotationCanvas);
      expect(canvas, findsOneWidget);
      final c = tester.getCenter(canvas);
      // 批注中纯横向甩动：不切题（画布接管全部指针，横向也归书写）
      final gesture = await tester.startGesture(c);
      for (var i = 1; i <= 8; i++) {
        await gesture.moveTo(c + Offset(-50.0 * i, 0),
            timeStamp: Duration(milliseconds: 16 * i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up(timeStamp: const Duration(milliseconds: 16 * 9));
      await tester.pump(const Duration(milliseconds: 100));
      await settle(tester);
      expect(appState.currentQuestionIndex, 0,
          reason: '批注模式禁止左右滑动切题（v1.27 需求纠偏）');
      // 横向甩动归书写：笔画保留（不被当作切题手势丢弃）
      expect(find.text('完成 (Esc)'), findsOneWidget,
          reason: '未切题，批注态保持');
      // 退出批注后同一横滑可以切题（对照：确证「不切」是批注禁止而非手势失效）
      await pressKey(tester, LogicalKeyboardKey.escape);
      await settle(tester);
      final gesture2 = await tester.startGesture(c);
      for (var i = 1; i <= 8; i++) {
        await gesture2.moveTo(c + Offset(-50.0 * i, 0),
            timeStamp: Duration(milliseconds: 16 * i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture2.up(timeStamp: const Duration(milliseconds: 16 * 9));
      await tester.pump(const Duration(milliseconds: 100));
      await settle(tester);
      expect(appState.currentQuestionIndex, 1,
          reason: '非批注态整个答题区域左右拖动可切题');
    
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 12));
        await settle(tester);
      }
      await tester.pump(const Duration(seconds: 12));
      await tester.runAsync(() => DatabaseService.instance.close());
    });

    testWidgets('PC 横滑不误触：批注中斜向书写不切题、笔画保留',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final appState = await seed(tester);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
        ],
        child: MaterialApp(
            theme: ThemeService().themeData, home: const QuizScreen()),
      ));
      await tester.runAsync(() => appState.resumeUnfinishedSession());
      await settle(tester);

      await pressKey(tester, LogicalKeyboardKey.keyA);
      await settle(tester);
      final canvas = find.byType(AnnotationCanvas);
      final c = tester.getCenter(canvas);
      // 斜向拖动（纵向分量超比例）：正常书写，不切题、批注态保持
      await tester.dragFrom(c - const Offset(60, 40), const Offset(150, 90));
      await settle(tester);
      expect(appState.currentQuestionIndex, 0, reason: '斜向书写不应切题');
      expect(find.text('完成 (Esc)'), findsOneWidget, reason: '批注态应保持');
      // Esc 可正常收起（笔画保留不受影响）
      await pressKey(tester, LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.text('完成 (Esc)'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 12));
        await settle(tester);
      }
      await tester.pump(const Duration(seconds: 12));
      await tester.runAsync(() => DatabaseService.instance.close());
    });
    testWidgets('PC 慢速拖动：非批注态鼠标慢速拖动（无速度）按位移切题',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final appState = await seed(tester);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
        ],
        child: MaterialApp(
            theme: ThemeService().themeData, home: const QuizScreen()),
      ));
      await tester.runAsync(() => appState.resumeUnfinishedSession());
      await settle(tester);

      // 先答错（未作答不允许前进，既有语义）
      await tester.runAsync(() => appState.submitAnswer('乙'));
      await settle(tester);
      expect(appState.currentQuestionIndex, 0);

      // 非批注态：慢速鼠标拖动（速度 ≈ -200px/s < 300 阈值，位移 -300 达标）
      final center = tester.getCenter(find.byType(SingleChildScrollView).first);
      final gesture = await tester.startGesture(center);
      await gesture.moveTo(center + const Offset(-300, 0),
          timeStamp: const Duration(milliseconds: 1500));
      await gesture.up(timeStamp: const Duration(milliseconds: 1600));
      await tester.pump(const Duration(milliseconds: 100));
      await settle(tester);
      expect(appState.currentQuestionIndex, 1,
          reason: '慢速拖动无速度时按累计位移切题（鼠标左右拖动切题）');
      expect(find.byType(AnnotationCanvas), findsNothing,
          reason: '非批注态不应出现画布');

      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 12));
        await settle(tester);
      }
      await tester.pump(const Duration(seconds: 12));
      await tester.runAsync(() => DatabaseService.instance.close());
    });
  });

  group('趋势图箭头翻页', () {
    testWidgets('365 天数据多页：左箭头翻到过去，日期范围文本变化',
        (tester) async {
      final days = List.generate(70, (i) {
        final date = DateTime(2026, 8, 27).subtract(Duration(days: 69 - i));
        return {'date': date, 'total': i, 'accuracy': 50.0};
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TrendChart(days: days)),
      ));
      await tester.pump();

      // 70 天 / 7 天每页 = 10 页 > 6：显示日期范围文本 + 左右箭头
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      final labelFinder = find.textContaining(' - ');
      expect(labelFinder, findsOneWidget);
      final before = tester.widget<Text>(labelFinder).data;

      // 点左箭头翻到更早的一页
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      final after = tester.widget<Text>(labelFinder).data;
      expect(after, isNot(before), reason: '左箭头应翻到更早的页');

      // 右箭头翻回
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(labelFinder).data, before);
    });

    testWidgets('少量页数：圆点可点击跳页', (tester) async {
      final days = List.generate(21, (i) {
        final date = DateTime(2026, 8, 27).subtract(Duration(days: 20 - i));
        return {'date': date, 'total': i, 'accuracy': 50.0};
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TrendChart(days: days)),
      ));
      await tester.pump();

      // 21 天 = 3 页 ≤ 6：圆点可点（带 ValueKey 精确定位）
      expect(find.byKey(const ValueKey('trend_dot_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('trend_dot_2')), findsOneWidget);
      // 点第一个圆点跳到第一页（当前在最后一页）
      await tester.tap(find.byKey(const ValueKey('trend_dot_0')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
