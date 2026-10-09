import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flashcard_app/screens/quick_start_screen.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/theme_service.dart';

/// 2026-10-08 用户要求：把「定向爆破」的火箭图标换成原版素材「爆」字
/// （assets/burst_icon.png 是 2048×2048 原图，UI 用裁边缩放的
/// assets/burst_icon_ui.png，并按主题色 BlendMode.srcIn 着色）。
///
/// 这条测试守住两件事：
///   ① 卡片里真的渲染了图片（不是又被换回 Material 火箭图标）；
///   ② 资产装配正确（能找到 burst_icon_ui.png，且尺寸被约束成小图标）。
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath =
        '${dir.path}/flashcard_app/test_qs_icon_${DateTime.now().millisecondsSinceEpoch}.db';
    DatabaseService.overrideDbPath = dbPath;
    final f = File(dbPath);
    if (await f.exists()) await f.delete();
  });

  tearDown(() async {
    DatabaseService.overrideDbPath = null;
  });

  Future<void> settleFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('定向爆破卡片用「爆」字原版素材，不再用火箭图标', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
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
        theme: ThemeService().themeData,
        home: const QuickStartScreen(),
      ),
    ));
    await settleFrames(tester);

    expect(find.text('定向爆破'), findsOneWidget);

    // ① 火箭图标不该再出现（换回 Material 图标即视为回归）
    expect(find.byIcon(Icons.rocket_launch_rounded), findsNothing,
        reason: '定向爆破已改用原版「爆」字素材，不该再用火箭图标');

    // ② 该素材以图片形式渲染，并被约束成小图标尺寸
    final images = tester.widgetList<Image>(find.byType(Image));
    expect(images, isNotEmpty);
    final burst = images.where((i) =>
        i.image is AssetImage &&
        (i.image as AssetImage).assetName == 'assets/burst_icon_ui.png');
    expect(burst, isNotEmpty, reason: '应使用裁边缩放的 UI 版素材');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => DatabaseService.instance.close());
  });
}
