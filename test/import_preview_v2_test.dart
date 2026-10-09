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
class _RetryImportState extends AppState {
  int attempts = 0;
  final selections = <Set<int>>[];

  @override
  Future<void> confirmImport({Set<int> excludedIndices = const {}}) async {
    attempts++;
    selections.add(Set.of(excludedIndices));
    if (attempts == 1) throw StateError('模拟写入失败');
    clearPreview();
  }
}

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

  testWidgets('确认失败保留编辑与删除，留在预览页并可重试成功返回', (tester) async {
    final state = _RetryImportState();
    state.setPreviewQuestionsForTest([
      mk('保留题', answer: 'A'),
      mk('待删除题', answer: 'B'),
    ]);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: state),
        ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
      ],
      child: MaterialApp(
        navigatorKey: navigator,
        theme: ThemeService().themeData,
        home: const Scaffold(body: Text('首页')),
      ),
    ));
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const ImportPreviewScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline).last);
    await settle(tester);
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '已编辑题干');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await settle(tester);
    await tester.tap(find.text('确认导入 1 道题目'));
    await tester.pumpAndSettle();

    expect(find.byType(ImportPreviewScreen), findsOneWidget);
    expect(find.textContaining('模拟写入失败'), findsOneWidget);
    expect(find.text('已编辑题干'), findsOneWidget);
    expect(find.text('待删除题'), findsNothing);
    expect(state.previewQuestions.map((q) => q.title), ['已编辑题干', '待删除题']);
    expect(state.selections.single, {1});
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('重试导入 1 道题目'));
    await tester.pumpAndSettle();
    expect(state.attempts, 2);
    expect(state.selections.last, {1});
    expect(find.byType(ImportPreviewScreen), findsNothing);
    expect(find.text('首页'), findsOneWidget);
  });

  test('数据库写入失败保留全部预览，重试仅写入未删除题', () async {
    final state = AppState();
    await state.init();
    state.setPreviewQuestionsForTest([
      mk('已编辑题干', answer: 'A'),
      mk('删除题', answer: 'B'),
    ]);
    final db = await DatabaseService.instance.database;
    await db.execute('''
      CREATE TRIGGER fail_preview_insert BEFORE INSERT ON questions
      BEGIN SELECT RAISE(ABORT, 'test import failure'); END
    ''');
    await expectLater(
        state.confirmImport(excludedIndices: {1}), throwsA(anything));
    expect(state.previewQuestions.map((q) => q.title), ['已编辑题干', '删除题']);
    expect(await DatabaseService.instance.getAllBanks(), isEmpty);
    await db.execute('DROP TRIGGER fail_preview_insert');
    await state.confirmImport(excludedIndices: {1});
    expect(state.previewQuestions, isEmpty);
    final rows = await db.query('questions');
    expect(rows, hasLength(1));
    expect(rows.single['title'], '已编辑题干');
    expect(await DatabaseService.instance.getAllBanks(), hasLength(1));
    state.dispose();
  });

  testWidgets('全删后禁止空导入，不永久删除预览数据', (tester) async {
    final state = _RetryImportState();
    state.setPreviewQuestionsForTest([mk('保留底稿', answer: 'A')]);
    await tester.pumpWidget(host(state));
    await tester.tap(find.byIcon(Icons.delete_outline));
    await settle(tester);
    final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '确认导入 0 道题目'));
    expect(button.onPressed, isNull);
    expect(state.previewQuestions, hasLength(1));
    expect(state.attempts, 0);
  });

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
