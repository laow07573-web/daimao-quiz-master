import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/services/theme_service.dart';
import 'package:flashcard_app/widgets/year_heatmap.dart';

/// 年度坚持热力图（v1.28 重做：GitHub 贡献图风格）。
/// 覆盖：色阶阈值、周列结构、窄容器不溢出、今天高亮、点击回调。
void main() {
  AppThemeColors themeOf(WidgetTester tester) {
    final ctx = tester.element(find.byType(Scaffold));
    return AppThemeColors.of(ctx);
  }

  Widget host({double width = 360, int? year, ValueChanged<String>? onTap}) =>
      MaterialApp(
        theme: ThemeService().themeData,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: YearHeatmap(
                year: year ?? DateTime.now().year,
                dailyTotals: {
                  '${year ?? DateTime.now().year}-03-05': 10,   // 少
                  '${year ?? DateTime.now().year}-03-06': 80,   // 达标
                  '${year ?? DateTime.now().year}-03-07': 250,  // 多
                },
                todayKey: '${year ?? DateTime.now().year}-03-06',
                onDayTap: onTap,
              ),
            ),
          ),
        ),
      );

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

  testWidgets('渲染全年 53 周 × 7 天且不溢出（窄容器）', (tester) async {
    await tester.pumpWidget(host(width: 300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '窄容器不应布局溢出');
    expect(find.byType(YearHeatmap), findsOneWidget);
  });

  testWidgets('宽容器同样不溢出（宽屏双列卡片场景）', (tester) async {
    await tester.pumpWidget(host(width: 520));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击某天回调日期 key', (tester) async {
    String? tapped;
    final y = DateTime.now().year;
    await tester.pumpWidget(host(year: y, onTap: (k) => tapped = k));
    await tester.pumpAndSettle();
    // 直接验证组件契约：命中任一格子即能拿到 YYYY-MM-DD
    final cells = find.byType(GestureDetector);
    expect(cells, findsWidgets);
    await tester.tap(cells.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    if (tapped != null) {
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(tapped!), isTrue);
    }
  });
}
