import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/screens/import_preview_screen.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/theme_service.dart';

/// v1.27 导入预览页增强验证：
/// 1. 编辑卡支持超过 4 个选项（五选全显示/可改/可增删，保存不丢失）；
/// 2. 五选答案（A,E）不再误报「答案格式异常」；
/// 3. 顶部统计徽章（正常/需检查/有问题）点击筛选题目，再点取消。
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath =
        '${dir.path}/flashcard_app/test_preview_v2_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}.db';
    DatabaseService.overrideDbPath = dbPath;
    final f = File(dbPath);
    if (await f.exists()) await f.delete();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
  });

  Question mk(String title,
          {List<String> options = const [],
          String answer = '',
          String type = 'single_choice'}) =>
      Question(
        bankId: 1,
        title: title,
        options: options,
        correctAnswer: answer,
        questionType: type,
        createdAt: DateTime.now().toIso8601String(),
      );

  Widget host(AppState s) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: s),
          ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
        ],
        child: MaterialApp(
            theme: ThemeService().themeData, home: const ImportPreviewScreen()),
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('编辑卡支持 5 选项：全显示、可修改、可添加，保存不丢失', (tester) async {
    final appState = AppState();
    await tester.runAsync(() => appState.init());
    appState.setPreviewQuestionsForTest([
      mk('五选题干？',
          options: ['选项一', '选项二', '选项三', '选项四', '选项五'],
          answer: 'A,E',
          type: 'multi_choice'),
    ]);
    await tester.pumpWidget(host(appState));
    await settle(tester);

    // 五选答案 A,E 合法：不误报「答案格式异常」
    expect(find.text('答案格式异常'), findsNothing);

    // 进入编辑
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await settle(tester);

    // 题干 + 5 选项 + 答案 = 7 个输入框（第 5 个选项可见可编辑）
    expect(find.byType(TextField), findsNWidgets(7));
    expect(find.byTooltip('删除选项 E'), findsOneWidget);

    // 修改第 5 个选项 + 添加一个空选项行（编辑卡可能超出视口，先滚入视区）
    await tester.ensureVisible(find.byType(TextField).at(5));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(5), '选项五改');
    await tester.ensureVisible(find.text('添加选项'));
    await settle(tester);
    await tester.tap(find.text('添加选项'));
    await settle(tester);
    expect(find.byType(TextField), findsNWidgets(8));
    
    // 保存：新增的空行不入选项，修改保留，全部 5 个选项不丢失。
    await tester.ensureVisible(find.text('保存'));
    await settle(tester);
    await tester.tap(find.text('保存'));
    await settle(tester);
    final saved = appState.previewQuestions.first;
    expect(saved.options.length, 5);
    expect(saved.options[4], '选项五改');
    expect(saved.correctAnswer, 'A,E');
  });

  testWidgets('徽章点击筛选：点「有问题/需检查」只展示对应题目，再点取消', (tester) async {
    final appState = AppState();
    await tester.runAsync(() => appState.init());
    appState.setPreviewQuestionsForTest([
      mk('正常题 1', options: ['甲', '乙'], answer: 'A'),
      mk('正常题 2', options: ['甲', '乙'], answer: 'B'),
      mk('需检查题（答案含非法字符）', options: ['甲', '乙'], answer: 'A!'),
      mk('有问题题（缺答案）', options: ['甲', '乙'], answer: ''),
    ]);
    await tester.pumpWidget(host(appState));
    await settle(tester);

    expect(find.text('2 正常'), findsOneWidget);
    expect(find.text('1 需检查'), findsOneWidget);
    expect(find.text('1 有问题'), findsOneWidget);

    // 点「有问题」→ 只剩缺答案那道题
    await tester.tap(find.text('1 有问题'));
    await settle(tester);
    expect(find.textContaining('有问题题'), findsOneWidget);
    expect(find.textContaining('正常题 1'), findsNothing);
    expect(find.textContaining('需检查题'), findsNothing);
    expect(find.text('已筛出 1 题 · 再点徽章可取消'), findsOneWidget);

    // 再点取消筛选 → 全部恢复
    await tester.tap(find.text('1 有问题'));
    await settle(tester);
    expect(find.textContaining('正常题 1'), findsOneWidget);
    expect(find.textContaining('需检查题'), findsOneWidget);

    // 点「需检查」→ 只剩答案格式异常那道题
    await tester.tap(find.text('1 需检查'));
    await settle(tester);
    expect(find.text('答案格式异常'), findsOneWidget);
    expect(find.textContaining('正常题 2'), findsNothing);
  });
}
