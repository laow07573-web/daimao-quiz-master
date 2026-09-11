import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/services/theme_service.dart';
import 'package:flashcard_app/widgets/trend_chart.dart';

List<Map<String, dynamic>> _days(int n, {int Function(int)? totals}) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: n - 1));
  return [
    for (var i = 0; i < n; i++)
      {
        'date': start.add(Duration(days: i)),
        'total': totals?.call(i) ?? 10,
        'accuracy': 70.0,
      }
  ];
}

void main() {
  group('chunkDays 从尾部每7天分页', () {
    test('30 天 → 4 页，每页 7 天，头部碎片丢弃', () {
      final days = _days(30);
      final pages = chunkDays(days);
      expect(pages.length, 4);
      for (final p in pages) {
        expect(p.length, 7);
      }
      // 头部 2 天碎片丢弃（30 % 7 == 2）
      expect(pages.first.first['date'], days[2]['date']);
      // 尾部对齐：最后一页最后一天 = 数据最后一天
      expect(pages.last.last['date'], days.last['date']);
    });

    test('28 天 → 4 页整（无丢弃）', () {
      final days = _days(28);
      final pages = chunkDays(days);
      expect(pages.length, 4);
      expect(pages.first.first['date'], days[0]['date']);
    });

    test('不足 7 天 → 单页保留全部', () {
      final days = _days(5);
      final pages = chunkDays(days);
      expect(pages.length, 1);
      expect(pages.first.length, 5);
    });

    test('空数据 → 空页', () {
      expect(chunkDays([]), isEmpty);
    });
  });

  group('niceStep 整数刻度', () {
    test('1/2/5×10ⁿ 步长', () {
      expect(niceStep(0), 1);
      expect(niceStep(1), 1);
      expect(niceStep(2.5), 5);
      expect(niceStep(7), 10);
      expect(niceStep(100), 100);
      expect(niceStep(101), 200);
      expect(niceStep(1.2), 2);
      expect(niceStep(0.3), 0.5); // max(raw, 1.0) 由调用方保证
    });
  });

  group('accuracyTierColor 三档', () {
    test('>=80 accent 0.75 / >=60 accent 0.45 / <60 danger 0.75', () {
      // v1.28 新设计语言：取色改走 AppThemeColors 语义色
      const ac = AppThemeColors(
        background: Color(0xFFFFFFFF),
        surface: Color(0xFFFFFFFF),
        surfaceAlt: Color(0xFFF0F0F0),
        border: Color(0xFFE0E0E0),
        textPrimary: Color(0xFF000000),
        textSecondary: Color(0xFF666666),
        textTertiary: Color(0xFF999999),
        accent: Color(0xFF000000),
        accentSoft: Color(0xFFEEEEEE),
        onAccent: Color(0xFFFFFFFF),
        navBackground: Color(0xFFFFFFFF),
        navForeground: Color(0xFF000000),
        danger: Color(0xFFEE0000),
      );
      expect(accuracyTierColor(90, ac), const Color(0xFF000000).withOpacity(0.75));
      expect(accuracyTierColor(70, ac), const Color(0xFF000000).withOpacity(0.45));
      expect(accuracyTierColor(50, ac), const Color(0xFFEE0000).withOpacity(0.75));
      expect(accuracyTierColor(0, ac), const Color(0xFFEE0000).withOpacity(0.75));
    });
  });

  group('正确率平滑曲线（Catmull-Rom → 三次贝塞尔）', () {
    test('曲线包含三次贝塞尔段（非直线）', () {
      final path = smoothSegment(
        const Offset(0, 100), const Offset(10, 20),
        const Offset(0, 100), const Offset(20, 30),
      );
      final metrics = path.computeMetrics().toList();
      expect(metrics, isNotEmpty);
      // 贝塞尔段长度 > 直线距离（曲线比直线长），可证明它在弯曲
      final straight = (const Offset(10, 20) - const Offset(0, 100)).distance;
      expect(metrics.first.length, greaterThan(straight));
    });

    test('控制点收在段包围盒内：曲线不过冲', () {
      // 三段起伏数据，中点应落在两端 y 之间，不冲出
      final p1 = const Offset(0, 50);
      final p2 = const Offset(10, 50);
      final p0 = const Offset(-10, 0);   // 上一段在上方 → 会拉高控制点
      final p3 = const Offset(20, 100);  // 下一段在下方
      final path = smoothSegment(p1, p2, p0, p3);
      final bounds = path.getBounds();
      // 包围盒不应超出 p1/p2 的 y 范围（50~50）
      expect(bounds.top, greaterThanOrEqualTo(49.9));
      expect(bounds.bottom, lessThanOrEqualTo(50.1));
    });

    test('平坦数据得到水平直线', () {
      final path = smoothSegment(
        const Offset(0, 30), const Offset(10, 30),
        const Offset(0, 30), const Offset(10, 30),
      );
      final b = path.getBounds();
      expect(b.height, lessThan(0.01));
    });
  });

  group('TrendChart 交互', () {
    testWidgets('渲染 30 天数据无异常，页码指示器存在', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrendChart(days: _days(30)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TrendChart), findsOneWidget);
      // 4 页指示器
      expect(find.byType(PageView), findsOneWidget);
    });

    testWidgets('点击有记录的天触发 onDaySelected（气泡逻辑）', (tester) async {
      Map<String, dynamic>? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrendChart(
              days: _days(14),
              onDaySelected: (d) => selected = d,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 点击 PageView 中心（图表区）
      final pv = tester.getRect(find.byType(PageView));
      await tester.tapAt(pv.center);
      await tester.pump();
      expect(selected, isNotNull);
      expect(selected!['total'], 10);
    });

    testWidgets('点击无记录的天不触发（跳过 total<=0）', (tester) async {
      Map<String, dynamic>? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrendChart(
              days: _days(7, totals: (_) => 0),
              onDaySelected: (d) => selected = d,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 点击 PageView 中心（图表区，全部无记录 → 不触发）
      final pv = tester.getRect(find.byType(PageView));
      await tester.tapAt(pv.center);
      await tester.pump();
      expect(selected, isNull);
    });
  });
}
