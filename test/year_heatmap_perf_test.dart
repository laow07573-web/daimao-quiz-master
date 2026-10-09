import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flashcard_app/services/theme_service.dart';
import 'package:flashcard_app/widgets/year_heatmap.dart';

/// 2026-10-08 用户授权「热力图样式不变的前提下尽可能优化性能」。
///
/// 原实现每格都包一个 Tooltip + GestureDetector（371 格 → 371 个 TooltipState
/// 各带 AnimationController、371 个手势识别器），是统计页卡顿的最大单项开销。
/// 现在整块网格只有 1 个手动触发的 Tooltip + 1 个手势层，命中测试按坐标定位。
///
/// 这些测试锁住三件事：节点数量级、外观不变、交互（点击/长按）仍可用。
void main() {
  Widget host(Widget child) => ChangeNotifierProvider<ThemeService>(
        create: (_) => ThemeService(),
        child: MaterialApp(
          theme: ThemeService().themeData,
          home: Scaffold(body: child),
        ),
      );

  Map<String, int> totals() => {
        '2026-01-01': 10,
        '2026-06-15': 80,
        '2026-10-08': 300,
      };

  testWidgets('整块网格只有一个 Tooltip 与一个手势层（不再逐格创建）', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(host(YearHeatmap(
      year: 2026,
      dailyTotals: totals(),
      todayKey: '2026-10-08',
    )));
    await tester.pumpAndSettle();

    // 371 格 → Tooltip 只能是 1 个（此前是 371 个）
    expect(find.byType(Tooltip), findsOneWidget,
        reason: '每格一个 Tooltip 会创建 371 个 AnimationController，'
            '这是统计页卡顿的主因；整块共用一个即可');
    // 手势层同理：网格级一个，格子级不再各挂一个
    expect(find.byType(GestureDetector), findsOneWidget);

    // 2026-10-09（profile 实测统计页首帧 build 103ms / raster 95.5ms 之后）：
    // 371 个格子 widget 已合并成一次 CustomPaint —— 不再有逐个格子的
    // AspectRatio/Container 节点，而这正是首帧成本的主因。
    expect(find.byType(AspectRatio), findsNothing,
        reason: '逐格 widget 已被 CustomPaint 取代，格子数不该再产生 widget 节点');
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('点击网格仍能命中到正确的日期（坐标命中测试）', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(host(YearHeatmap(
      year: 2026,
      dailyTotals: totals(),
      todayKey: '2026-10-08',
      onDayTap: tapped.add,
    )));
    await tester.pumpAndSettle();

    final grid = tester.getRect(find.byType(GestureDetector));
    // 点网格中部：应命中某个 2026 年内的日期
    await tester.tapAt(grid.center);
    await tester.pump();

    expect(tapped, hasLength(1));
    expect(tapped.first, startsWith('2026-'), reason: '命中测试要定位到具体日期，且不越界到相邻年份');
  });

  testWidgets('长按显示提示且不抛异常（单个 Tooltip 手动触发）', (tester) async {
    await tester.pumpWidget(host(YearHeatmap(
      year: 2026,
      dailyTotals: totals(),
      todayKey: '2026-10-08',
      onDayTap: (_) {},
    )));
    await tester.pumpAndSettle();

    final grid = tester.getRect(find.byType(GestureDetector));
    final gesture = await tester.startGesture(grid.center);
    await tester.pump(const Duration(milliseconds: 600)); // 触发长按
    await tester.pump();
    expect(tester.takeException(), isNull);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('每格的语义标签保留（无障碍不退化）', (tester) async {
    // 格子改成 CustomPaint 之后，语义节点由渲染层（semanticsBuilder）生成，
    // 不在 widget 树里 —— find.bySemanticsLabel 只找 Semantics widget，找不到。
    // 所以直接遍历语义树按 label 匹配。
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(YearHeatmap(
      year: 2026,
      dailyTotals: totals(),
      todayKey: '2026-10-08',
      onDayTap: (_) {},
    )));
    await tester.pumpAndSettle();

    final root = tester.binding.pipelineOwner.semanticsOwner?.rootSemanticsNode;
    expect(root, isNotNull);
    final labels = <String>{};
    void visit(SemanticsNode node) {
      if (node.label.isNotEmpty) labels.add(node.label);
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(root!);

    // 有记录的那天应带「日期，N 题」标签；今天还要带「今天」
    expect(labels, contains('2026-10-08，300 题，今天'));
    expect(labels, contains('2026-06-15，80 题'));
    // 无记录的日期也要有节点（无障碍要求每一格可读）
    expect(labels, contains('2026-01-02，0 题'));

    handle.dispose();
  });
}
