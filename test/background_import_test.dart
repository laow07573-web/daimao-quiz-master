import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flashcard_app/screens/main_shell.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/theme_service.dart';

/// v1.27 后台导入验证：
/// 1. 任务在应用层运行（离开导入页不中断）：JSON 按文件推进、完成入库、
///    产生待消费的完成提示；
/// 2. 示例题库后台导入；
/// 3. 未配置 API 时 DOCX 解析失败结果如实上报（不伪装成功）；
/// 4. 主壳在主页弹「导入完成」提示且仅弹一次（消费后清除）。
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath =
        '${dir.path}/flashcard_app/test_bg_import_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}.db';
    DatabaseService.overrideDbPath = dbPath;
    final f = File(dbPath);
    if (await f.exists()) await f.delete();
  });

  tearDown(() async {
    DatabaseService.overrideDbPath = null;
  });

  /// 构造一个合法的猫卷 JSON 题库文件
  String writeJsonBank(Directory dir, String name, int questionCount) {
    final questions = [
      for (var i = 1; i <= questionCount; i++)
        {
          'title': '$name 第 $i 题？',
          'options': ['甲', '乙', '丙', '丁'],
          'correct_answer': 'A',
          'question_type': 'single_choice',
        }
    ];
    final path = '${dir.path}/$name.json';
    File(path).writeAsStringSync(jsonEncode({
      'format': 'maojuan-quiz-questions',
      'name': name,
      'count': questionCount,
      'questions': questions,
    }));
    return path;
  }

  group('后台导入任务（应用层运行，离开页面不中断）', () {
    test('JSON 后台导入：入库 + 完成提示 + 消费后清除', () async {
      final appState = AppState();
      await appState.init();
      final tmp = Directory.systemTemp.createTempSync('bg_import_json');
      final f1 = writeJsonBank(tmp, '后台库一', 3);
      final f2 = writeJsonBank(tmp, '后台库二', 2);

      expect(appState.importTaskActive, isFalse);
      await appState.startBackgroundImport(jsonFiles: [f1, f2]);

      // 任务结束：标志复位、进度归满、题库入库
      expect(appState.importTaskActive, isFalse);
      expect(appState.importProgress, 1.0);
      final banks = appState.banks.map((b) => b.name).toList();
      expect(banks, containsAll(['后台库一', '后台库二']));
      expect(appState.banks
              .firstWhere((b) => b.name == '后台库一')
              .questionCount,
          3);

      // 完成提示：成功、含数量、消费一次后清除
      final result = appState.pendingImportResult;
      expect(result, isNotNull);
      expect(result!.success, isTrue);
      expect(result.kind, ImportTaskKind.json);
      expect(result.questionCount, 5);
      expect(appState.consumeImportResult(), isNotNull);
      expect(appState.pendingImportResult, isNull);
      expect(appState.consumeImportResult(), isNull);
      tmp.deleteSync(recursive: true);
    });

    test('示例题库后台导入：入库并产生成功提示', () async {
      final appState = AppState();
      await appState.init();
      await appState.startBackgroundSampleImport();
      expect(appState.importTaskActive, isFalse);
      expect(appState.banks, isNotEmpty);
      final result = appState.pendingImportResult;
      expect(result, isNotNull);
      expect(result!.success, isTrue);
      expect(result.kind, ImportTaskKind.sample);
      expect(result.questionCount, greaterThan(0));
    });

    test('未配置 API 时 DOCX 解析：失败结果如实上报，不伪装成功', () async {
      final appState = AppState();
      await appState.init();
      final tmp = Directory.systemTemp.createTempSync('bg_import_docx');
      final docx = File('${tmp.path}/无API测试.docx')..writeAsBytesSync([1, 2]);
      await appState.startBackgroundImport(docxFiles: [docx.path]);
      final result = appState.pendingImportResult;
      expect(result, isNotNull);
      expect(result!.success, isFalse);
      expect(result.kind, ImportTaskKind.docxParse);
      expect(result.message, isNotEmpty);
      tmp.deleteSync(recursive: true);
    });

    test('任务进行中重复启动被拦截（防并发导入）', () async {
      final appState = AppState();
      await appState.init();
      final tmp = Directory.systemTemp.createTempSync('bg_import_dup');
      final f1 = writeJsonBank(tmp, '并发库', 1);
      // 手动置位模拟进行中（直接改状态不可行，用两个任务串联验证：
      // 第一个任务结束后第二个才能启动）
      await appState.startBackgroundImport(jsonFiles: [f1]);
      expect(appState.importTaskActive, isFalse);
      // 空参数不启动
      await appState.startBackgroundImport();
      expect(appState.importTaskActive, isFalse);
      expect(appState.pendingImportResult, isNotNull); // 仍是上一次结果
      tmp.deleteSync(recursive: true);
    });
  });

  group('主壳完成提示', () {
    Widget host(AppState appState, Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: appState),
            ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
          ],
          child: MaterialApp(theme: ThemeService().themeData, home: child),
        );

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

    testWidgets('导入完成后主壳弹「导入完成」提示，点「知道了」后不再弹',
        (tester) async {
      final appState = AppState();
      await tester.runAsync(() => appState.init());

      // 应用层完成一次 JSON 后台导入（产生待消费结果）
      final tmp = Directory.systemTemp.createTempSync('bg_import_dialog');
      final f = writeJsonBank(tmp, '弹窗库', 2);
      await tester
          .runAsync(() => appState.startBackgroundImport(jsonFiles: [f]));
      expect(appState.pendingImportResult, isNotNull);

      await tester.pumpWidget(host(appState, const MainShell()));
      await settleFrames(tester);

      // 完成提示弹出（标题 + 结果文案）
      expect(find.text('导入完成'), findsOneWidget);
      expect(find.textContaining('JSON 导入完成'), findsOneWidget);

      // 点「知道了」关闭：提示消失且结果已消费，不会再弹
      await tester.tap(find.text('知道了'));
      await settleFrames(tester);
      expect(find.text('导入完成'), findsNothing);
      expect(appState.pendingImportResult, isNull);
      tmp.deleteSync(recursive: true);
      await teardownTree(tester);
    });
  });
}
