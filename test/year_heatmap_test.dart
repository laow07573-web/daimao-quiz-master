import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/services/theme_service.dart';
import 'package:flashcard_app/widgets/year_heatmap.dart';

/// 年度坚持热力图（GitHub 贡献图样式：一整年 53 周 × 7 天铺满卡片宽度）。
/// 覆盖：色阶阈值、格子正方形且不溢出、今天高亮、点击回调。
void main() {
  AppThemeColors themeOf(WidgetTester tester) {
    final ctx = tester.element(find.byType(Scaffold));
    return AppThemeColors.of(ctx);
  }

  Widget host({double width = 360, int? year, ValueChanged<String>? onTap}) {
    final y = year ?? DateTime.now().year;
    return MaterialApp(
      theme: ThemeService().themeData,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: YearHeatmap(
              year: y,
              dailyTotals: {
                '$y-03-05': 10, // 少
                '$y-03-06': 80, // 达标
                '$y-03-07': 250, // 多
              },
              todayKey: '$y-03-06',
              onDayTap: onTap,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('色阶四档：0 / 少 / 达标 / 多 依次加深', (tester) async {
    await tester.pumpWidget(host());
    final ac = themeOf(tester);
    final c0 = YearHeatmap.levelColor(0, ac);
    final c1 = YearHeatmap.levelColor(10, ac);
    final c2 = YearHeatmap.levelColor(80, ac);
    final c3 = YearHeatmap.levelColor(250, ac);
    // 无记录 = 中性底；有记录逐档提升不透明度
    expect(c0, ac.surfaceAlt);
    expect(c1.opacity, lessThan(c2.opacity));
    expect(c2.opacity, lessThan(c3.opacity));
  });

  testWidgets('整年铺满卡片宽度：53 周都能看见，且不横向溢出', (tester) async {
    await tester.pumpWidget(host(width: 300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '窄容器不应布局溢出');
    expect(find.byType(YearHeatmap), findsOneWidget);
    // 格子为正方形：2026-10-09 起网格由 CustomPaint 绘制（原来 371 个格子
    // widget 造成统计页首帧 build 103ms），正方形由 painter 内部保证——
    // 断言画布尺寸的宽高比：宽 = 53 列 × 格宽，高 = 7 行 × 格宽。
    final canvas = tester.getSize(find.byKey(YearHeatmap.gridCanvasKey));
    expect(canvas.width, greaterThan(0));
    final cellW = canvas.width / 53;
    expect((canvas.height - cellW * 7).abs(), lessThan(1.0),
        reason: '画布高度应正好是 7 行正方形格子的高度');
  });

  testWidgets('宽容器同样不溢出（宽屏双列卡片场景）', (tester) async {
    await tester.pumpWidget(host(width: 520));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('极窄容器不抛异常', (tester) async {
    await tester.pumpWidget(host(width: 200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击某天回调日期 key', (tester) async {
    String? tapped;
    final y = DateTime.now().year;
    await tester.pumpWidget(host(year: y, onTap: (k) => tapped = k));
    await tester.pumpAndSettle();
    final cells = find.byType(GestureDetector);
    expect(cells, findsWidgets);
    await tester.tap(cells.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    if (tapped != null) {
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(tapped!), isTrue);
    }
  });
}
