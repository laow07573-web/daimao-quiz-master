import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flashcard_app/screens/error_book_screen.dart';
import 'package:flashcard_app/screens/quick_start_screen.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/database_service.dart';

/// 2026-10-09 用户反馈：「在没有错题的情况下进入错题本后点击去刷题按钮会出现
/// 快速开始页面的套娃」。
///
/// 根因：空态的「去刷题」原本 `Navigator.pushReplacement` 一份**新的**
/// `QuickStartScreen`，而它本身就是主壳的一级「开始」Tab 页——主壳还留在栈底、
/// 显示的正是同一页，于是栈里出现两份快速开始页，返回时就成了「自己套自己」。
/// 修法：popUntil 回主壳 + 把 Tab 切到「开始」（复用引导那条切 Tab 通道）。
///
/// 这条测试锁住的核心契约：**点「去刷题」不得再产出新的 QuickStartScreen**。
/// 修复前它会失败（findsOneWidget），修复后为 findsNothing。
void main() {
  late Directory tmp;

  setUp(() async {
    await DatabaseService.instance.close();
    tmp = Directory.systemTemp.createTempSync('mj_errbook_cta_');
    DatabaseService.overrideDbPath = '${tmp.path}/flashcard.db';
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> settleUntil(WidgetTester tester, Finder target,
      {String? what}) async {
    for (var i = 0; i < 150; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 10));
      if (target.evaluate().isNotEmpty) return;
    }
    fail('等不到${what ?? '目标控件'}渲染：数据库是真实 I/O，假时钟推不动它');
  }

  testWidgets('空错题态点「去刷题」不再套娃：不会多出一份快速开始页', (tester) async {
    tester.view.physicalSize = const Size(411, 891); // LG G7 竖屏
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late AppState appState;
    await tester.runAsync(() async {
      // 故意不造任何数据 —— 正是用户报告的场景：错题本进入空态
      appState = AppState();
      await appState.init();
    });

    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const MaterialApp(home: ErrorBookScreen()),
    ));
    await settleUntil(tester, find.text('去刷题'), what: '空态的「去刷题」按钮');

    await tester.tap(find.text('去刷题'));
    await tester.pumpAndSettle();

    expect(find.byType(QuickStartScreen), findsNothing,
        reason: '「去刷题」又 push 了一份 QuickStartScreen——它本身就是主壳的一级'
            '「开始」Tab 页，两份叠在一起就是用户看到的「套娃」。'
            '应当是 popUntil 回主壳后 requestTab 切到「开始」。');
    expect(tester.takeException(), isNull);
  });
}
