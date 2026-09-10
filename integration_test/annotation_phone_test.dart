// 手机端手写批注抽查（REQ-015）：真机/模拟器进程内驱动，
// 走完整路径：首页 → 选择题库 → 定向爆破 → 正常刷题 → 批注工具栏 → 画一笔。
// 运行：flutter test integration_test -d <device>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:flashcard_app/main.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/theme_service.dart';
import 'package:flashcard_app/widgets/annotation_canvas.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('手机端：批注入口 + 工具栏横向滚动 + 画布书写', (tester) async {
    final appState = AppState();
    await appState.init();
    final themeService = ThemeService();
    await themeService.init();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<ThemeService>.value(value: themeService),
      ],
      child: const FlashcardApp(),
    ));
    // 启动闪屏约 2 秒
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));

    // 确保有题库可选：设备可能已有示例题库；空库则直接写一个测试题库（同进程）
    if (appState.banks.isEmpty) {
      final now = DateTime.now().toIso8601String();
      final bankId = await DatabaseService.instance
          .insertBank(QuestionBank(name: '批注抽查题库', createdAt: now));
      await DatabaseService.instance.insertQuestions([
        for (var i = 1; i <= 3; i++)
          Question(
              bankId: bankId,
              title: '批注抽查题 $i',
              correctAnswer: '甲',
              options: const ['甲', '乙'],
              createdAt: now),
      ]);
      await appState.init(); // 重新加载题库列表
      await tester.pump();
    }
    if (appState.selectedBankIds.isEmpty) {
      appState.toggleBankSelection(appState.banks.first.id!);
      await tester.pump();
    }

    // 首页 → 定向爆破（滚动到可见再点）
    final blitz = find.text('定向爆破');
    await tester.scrollUntilVisible(blitz, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(blitz);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    // 题数选择弹层：点 10 题（题库可能不足 10，选 10 会限到实有题数，无妨）
    final chip = find.text('10 题');
    await tester.tap(chip);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    // 模式弹层：正常刷题
    await tester.tap(find.text('正常刷题'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // 刷题页：批注入口存在（REQ-001）
    final annoBtn = find.byTooltip('手写批注');
    expect(annoBtn, findsOneWidget);
    await tester.tap(annoBtn);
    await tester.pump(const Duration(milliseconds: 600));

    // 工具栏出现（未作答 → 即时批注配置，REQ-002/014）
    expect(find.text('完成'), findsOneWidget);
    expect(find.byTooltip('清草稿'), findsOneWidget);

    // REQ-015 手机窄屏：工具栏横向滚动可用——
    // 末段按钮（完成）无需滚动即可见，验证前段工具也能 ensureVisible
    await tester.ensureVisible(find.byTooltip('清草稿'));
    await tester.pump(const Duration(milliseconds: 300));

    // 画布上画一笔（即时批注可书写，REQ-003）
    final canvas = find.byType(AnnotationCanvas);
    expect(canvas, findsOneWidget);
    final c = tester.getCenter(canvas);
    await tester.dragFrom(c - const Offset(80, 0), const Offset(160, 40));
    await tester.pump(const Duration(milliseconds: 300));

    // 批注态停留窗口：供外部 adb 截图取证（不影响断言）
    await tester.pump(const Duration(seconds: 10));

    // 完成收起工具栏
    await tester.tap(find.text('完成'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('完成'), findsNothing);

    // 截图仅在 flutter drive 下可用，独立运行时容错跳过
    try {
      await binding.takeScreenshot('phone_annotation_done');
    } catch (_) {}
  });
}
