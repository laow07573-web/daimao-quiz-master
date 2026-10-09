import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flashcard_app/screens/error_book_screen.dart';
import 'package:flashcard_app/screens/quick_start_screen.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/utils/app_constants.dart';
import 'package:flashcard_app/widgets/guide/guide_anchor.dart';
import 'package:flashcard_app/widgets/guide/guide_controller.dart';

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

  /// 搭一个「壳 → 错题本」的两层栈，并把 GuideScope 接上，这样
  /// popUntil / requestTab 都是**真实生效**的，而不是在这一层空转。
  ///
  /// 2026-10-09 代码审查指出：只写 `home: ErrorBookScreen()` 会让两个动作都
  /// 变成空操作，测试退化成"只验证没有多出一份 QuickStartScreen"，锁不住真正
  /// 的修复路径（Tab 切没切、错题本有没有被弹出都不看）。
  Future<({GuideController guide, List<int> switched})> pumpShellThenErrorBook(
      WidgetTester tester, AppState appState) async {
    final switched = <int>[];
    final guide = GuideController()..attachTabSwitcher(switched.add);
    addTearDown(guide.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: GuideScope(
          controller: guide,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const ErrorBookScreen()),
                    ),
                    child: const Text('打开错题本'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('打开错题本'));
    // 不能用 pumpAndSettle：错题本加载期有骨架屏动画，永远等不到"稳定"，
    // 会直接超时。这里只推到转场结束，具体内容交给调用方的 settleUntil 轮询。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    return (guide: guide, switched: switched);
  }

  testWidgets('空错题态点「去刷题」：不套娃 + 真的回到「开始」Tab', (tester) async {
    tester.view.physicalSize = const Size(411, 891); // LG G7 竖屏
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late AppState appState;
    await tester.runAsync(() async {
      // 故意不造任何数据 —— 正是用户报告的场景：错题本进入空态
      appState = AppState();
      await appState.init();
    });

    final ctx = await pumpShellThenErrorBook(tester, appState);
    await settleUntil(tester, find.text('去刷题'), what: '空态的「去刷题」按钮');
    expect(find.byType(ErrorBookScreen), findsOneWidget,
        reason: '前提：现在确实在错题本这一层');

    await tester.tap(find.text('去刷题'));
    // 同上：不用 pumpAndSettle，只推到路由转场走完
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(QuickStartScreen), findsNothing,
        reason: '「去刷题」又 push 了一份 QuickStartScreen——它本身就是主壳的一级'
            '「开始」Tab 页，两份叠在一起就是用户看到的「套娃」。'
            '应当是 popUntil 回主壳后 requestTab 切到「开始」。');
    expect(find.byType(ErrorBookScreen), findsNothing,
        reason: '点完「去刷题」应当已经离开错题本（popUntil 回主壳）');
    expect(ctx.switched, contains(kQuickStartTabIndex),
        reason: '没有把 Tab 切到「开始」——用户点了「去刷题」却停在原 Tab，'
            '等于什么都没发生（该动作走 GuideController.requestTab → 主壳 _select）');
    expect(tester.takeException(), isNull);
  });
}
