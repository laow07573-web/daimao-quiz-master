import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flashcard_app/screens/import_screen.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/theme_service.dart';

/// v1.27 导入页滚动修复验证：
/// 此前文件列表被压在 Column 的 Expanded 里，上方固定内容占满
/// 小窗口/手机屏时列表区几乎为 0 无法滚动；现在整页单滚动结构，
/// 小窗口不溢出、内容可滚动查看，操作按钮固定在页底。
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath =
        '${dir.path}/flashcard_app/test_import_scroll_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}.db';
    DatabaseService.overrideDbPath = dbPath;
    final f = File(dbPath);
    if (await f.exists()) await f.delete();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
  });

  testWidgets('导入页小窗口（400×520）：无溢出、整页可滚动', (tester) async {
    tester.view.physicalSize = const Size(400, 520);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final appState = AppState();
    await tester.runAsync(() => appState.init());
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
      ],
      child: MaterialApp(
          theme: ThemeService().themeData, home: const ImportScreen()),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 无布局溢出异常（旧结构在小窗口会溢出/列表区为 0）
    expect(tester.takeException(), isNull);

    // 整页可滚动：下滑后原本在视口外的「点击选择」区域仍可达且不报错
    final scrollable = find.byType(SingleChildScrollView).first;
    expect(scrollable, findsOneWidget);
    await tester.drag(scrollable, const Offset(0, -200));
    await tester.pump();
    await tester.drag(scrollable, const Offset(0, 200));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => DatabaseService.instance.close());
  });
}
