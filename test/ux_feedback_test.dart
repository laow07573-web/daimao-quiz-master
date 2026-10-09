import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flashcard_app/screens/profile_tab.dart';
import 'package:flashcard_app/screens/quick_start_screen.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/theme_service.dart';
import 'package:flashcard_app/widgets/kit/mj_kit.dart';

/// 2026-10-08 真机反馈的三条回归：
///   ① 我的页「使用引导」被长副标题挤成竖排（每字一行）
///   ② 弹层顶部有一条能看见下层的透明带（框架拖拽手柄画在透明背景上）
///   ③ 连点「定向爆破」叠出多条提示
void main() {
  Widget harness(Widget home, {ThemeData? theme}) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: AppState()),
          ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
        ],
        child: MaterialApp(
          theme: theme ?? ThemeService().themeData,
          home: home,
        ),
      );

  testWidgets('我的页「使用引导」：标题单行横向显示，长副标题不再把它挤成竖排', (tester) async {
    await tester.pumpWidget(harness(const ProfileTab()));
    await tester.pump();

    expect(find.text('使用引导'), findsOneWidget);
    // 旧文案（含长副标题）应当已经去掉
    expect(find.text('重看使用引导'), findsNothing);
    expect(find.text('导入 → 刷题 → 统计，一步步带你走一遍'), findsNothing);

    final size = tester.getSize(find.text('使用引导'));
    expect(size.width, greaterThan(size.height),
        reason: '标题被挤成竖排时每字一行，高度会明显大于宽度');
    expect(size.height, lessThan(30), reason: '标题应当只占一行');
  });

  testWidgets('MJSheet 顶部不留透明带：容器顶边与弹层顶边对齐（无框架拖拽手柄）', (tester) async {
    final theme = ThemeService().themeData;
    // 前提：主题确实开了框架拖拽手柄——这正是当初透明带的成因。
    // 若哪天主题关掉它，这条测试的前提不再成立，需要同步复核 MJSheet.show。
    expect(theme.bottomSheetTheme.showDragHandle, isTrue,
        reason: '主题 bottomSheetTheme.showDragHandle 应为 true（透明带成因）');

    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold();
      }),
    ));
    await tester.pump();

    MJSheet.show<void>(ctx, title: '测试弹层', child: const SizedBox(height: 120));
    await tester.pumpAndSettle();

    expect(find.text('测试弹层'), findsOneWidget);

    final sheetTop = tester.getTopLeft(find.byType(MJSheet)).dy;
    final routeTop = tester.getTopLeft(find.byType(BottomSheet)).dy;
    expect((sheetTop - routeTop).abs(), lessThan(0.5),
        reason: '两者不对齐说明弹层里插入了别的东西（如拖拽手柄），'
            '而那块区域的背景是透明的，会露出下层页面');
  });

  testWidgets('连点「定向爆破」只留一条提示，不叠不排队', (tester) async {
    await tester.pumpWidget(harness(const QuickStartScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final tile = find.text('定向爆破');
    expect(tile, findsOneWidget);

    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(SnackBar), findsOneWidget, reason: '同一时刻只应有一条提示');

    // 修复前：第二次点击只是把提示排进队列，第一条播完还会再播一条，
    //         提示总时长接近翻倍。
    // 实测（250ms 步进推进）：修复后全部消失；修复前约 9900ms。
    // 2026-10-09 起提示时长改为 MaoMotion.toast = 1500ms（用户要求 2 秒内消散；
    // 1.5s 停留 + 出入场动画约 2s 正好），
    // 所以现在连点两次约 2.5s 就清空，7s 的分界仍能区分「有没有被排队」。
    var elapsed = 100;
    var emptyAt = -1;
    for (var i = 0; i < 40 && emptyAt < 0; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      elapsed += 250;
      if (find.byType(SnackBar).evaluate().isEmpty) emptyAt = elapsed;
    }
    expect(emptyAt, greaterThan(0), reason: '提示最终应当消失');
    expect(emptyAt, lessThanOrEqualTo(7000),
        reason: '提示存活了 ${emptyAt}ms：第二次点击被排进了队列 '
            '（修复后约 2500ms，修复前约 9900ms）');
  });

  testWidgets('轻提示 2 秒内消散（框架默认 4 秒太久，会一直挡着视线）', (tester) async {
    await tester.pumpWidget(harness(const QuickStartScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('定向爆破'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(SnackBar), findsOneWidget);

    // 小步推进：一次大跨度 pump 会跳过退场动画所需的帧边界
    var elapsed = 50;
    var emptyAt = -1;
    for (var i = 0; i < 30 && emptyAt < 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      elapsed += 100;
      if (find.byType(SnackBar).evaluate().isEmpty) emptyAt = elapsed;
    }
    expect(emptyAt, greaterThan(0), reason: '提示最终应当消失');
    expect(emptyAt, lessThanOrEqualTo(2200),
        reason: '提示存活了 ${emptyAt}ms，超出用户要求的「2 秒内消散」——'
            'SnackBar 默认停留 4 秒，必须显式传 duration: MaoMotion.toast');
  });

  testWidgets('无障碍导航开启时，提示依然 2 秒内消散（框架会忽略 duration）', (tester) async {
    // 真机复现：设备开着无障碍服务（accessibility_enabled=1）时，Flutter 会让
    // SnackBar 常驻并忽略 duration——实测点击后 3.8 秒仍在，只有切页才消失。
    // 这里显式打开 accessibleNavigation，锁住「定时器兜底」这条路径。
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: AppState()),
        ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
      ],
      child: MaterialApp(
        theme: ThemeService().themeData,
        home: const MediaQuery(
          data: MediaQueryData(accessibleNavigation: true),
          child: QuickStartScreen(),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('定向爆破'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(SnackBar), findsOneWidget, reason: '前提是提示确实弹出来了');

    var elapsed = 50;
    var emptyAt = -1;
    for (var i = 0; i < 30 && emptyAt < 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      elapsed += 100;
      if (find.byType(SnackBar).evaluate().isEmpty) emptyAt = elapsed;
    }
    expect(emptyAt, greaterThan(0), reason: '提示最终应当消失');
    expect(emptyAt, lessThanOrEqualTo(2200),
        reason: '无障碍导航下提示存活了 ${emptyAt}ms：框架忽略 duration 时会常驻，'
            '必须由 _toast 里的兜底定时器清掉');
  });
}
